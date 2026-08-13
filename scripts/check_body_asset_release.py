#!/usr/bin/env python3
"""Fail-closed readback for the checked-in RealityKit body candidate.

This verifier deliberately does not approve the asset. It binds the current
candidate's manifest, Swift constants and packaged USD facts so that any one
of those layers drifting makes the macOS CI job fail.
"""

from __future__ import annotations

import hashlib
import json
import base64
import re
import shutil
import struct
import subprocess
import sys
import zipfile
import tempfile
from datetime import datetime, timezone
from copy import deepcopy
from typing import Any
from pathlib import Path

from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "docs/assets/body-neutral-procedural-v1.manifest.json"
SWIFT_PATH = ROOT / "ios/BodyCompanion/Sources/BodyCompanionCore/BodyAssetManifest.swift"
# Candidate resources are copied only by the internal AppHost. Keeping this
# root outside the reusable Swift package prevents a production package link
# from silently shipping a candidate asset.
RESOURCE_ROOT = ROOT / "ios/BodyCompanion/AppHost/BodyCompanionInternal/Resources"
ASSET_REGISTRY_ROOT = ROOT / "docs/assets"
SIGNING_ROOT = ASSET_REGISTRY_ROOT / "signing"
REGION_MAP_SCHEMA_PATH = ROOT / "docs/contracts/body-region-map.schema.json"
SURFACE_CORRESPONDENCE_SCHEMA_PATH = ROOT / "docs/contracts/body-surface-correspondence.schema.json"

EXPECTED_MESH_NAMES = {
    "body_head",
    "body_neck",
    "body_torso",
    "body_abdomen",
    "body_lower_back",
    "body_pelvis",
    *(f"body_{side}_{region}" for side in ("left", "right") for region in (
        "shoulder",
        "chest",
        "upper_back",
        "hip",
        "upper_arm",
        "elbow",
        "forearm",
        "hand",
        "thigh",
        "knee",
        "calf",
        "foot",
    )),
}


def fail(message: str) -> None:
    raise RuntimeError(message)


def swift_string(source: str, name: str) -> str:
    match = re.search(rf'public static let {re.escape(name)} = "([^"]+)"', source)
    if match is None:
        fail(f"missing Swift candidate constant: {name}")
    return match.group(1)


def swift_float(source: str, name: str) -> float:
    match = re.search(
        rf"public static let {re.escape(name)}: Float = (-?(?:\d+(?:\.\d+)?|\.\d+))",
        source,
    )
    if match is None:
        fail(f"missing Swift candidate constant: {name}")
    return float(match.group(1))


def run_tool(name: str, *arguments: str) -> str:
    executable = shutil.which(name)
    if executable is None:
        fail(f"required OpenUSD tool is unavailable: {name}")
    completed = subprocess.run(
        (executable, *arguments),
        text=True,
        capture_output=True,
        check=False,
    )
    output = completed.stdout + completed.stderr
    if completed.returncode != 0:
        fail(f"{name} failed with exit {completed.returncode}: {output[-2000:]}")
    return output


def manifest_body_digest(path: Path) -> str:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    normalized = deepcopy(manifest)
    integrity = normalized.setdefault("integrity", {})
    if not isinstance(integrity, dict):
        fail("manifest integrity section is malformed")
    integrity["manifest_sha256"] = "sha256:" + "0" * 64
    canonical = json.dumps(normalized, ensure_ascii=False, indent=2) + "\n"
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def verify_manifest_signature(path: Path, manifest: dict[str, Any]) -> None:
    integrity = manifest.get("integrity", {})
    if integrity.get("signature_status") != "verified":
        return
    key_id = integrity.get("signing_key_id")
    if not isinstance(key_id, str) or not re.fullmatch(r"[A-Za-z0-9._-]{1,120}", key_id):
        fail(f"manifest signature key is missing or malformed: {integrity.get('signing_key_id')}")
    public_key = SIGNING_ROOT / f"{key_id}.pub.pem"
    if not public_key.is_file():
        fail(f"manifest signing key public artifact is missing: {public_key.relative_to(ROOT)}")

    signature_path = ASSET_REGISTRY_ROOT / f"{path.stem}.signature"
    if not signature_path.is_file():
        fail(f"manifest signature artifact is missing: {signature_path.relative_to(ROOT)}")
    try:
        signature = base64.b64decode(signature_path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        fail(f"manifest signature artifact decode failed: {exc}")

    if shutil.which("openssl") is None:
        fail("openssl not found, cannot verify manifest signature chain")

    with tempfile.NamedTemporaryFile(delete=False) as tmp_sig:
        tmp_sig.write(signature)
        tmp_sig_path = Path(tmp_sig.name)
    with tempfile.NamedTemporaryFile(suffix=".manifest", mode="wb", delete=False) as tmp_manifest:
        tmp_manifest.write(path.read_bytes())
        tmp_manifest_path = Path(tmp_manifest.name)

    try:
        completed = subprocess.run(
            (
                "openssl",
                "pkeyutl",
                "-verify",
                "-inkey",
                str(public_key),
                "-pubin",
                "-rawin",
                "-sigfile",
                str(tmp_sig_path),
                "-in",
                str(tmp_manifest_path),
            ),
            text=True,
            capture_output=True,
            check=False,
        )
        if completed.returncode != 0:
            fail(f"manifest signature verification failed: {completed.stdout}{completed.stderr}")
    finally:
        tmp_sig_path.unlink(missing_ok=True)
        tmp_manifest_path.unlink(missing_ok=True)


def verify_archive_layout(path: Path) -> int:
    payload = path.read_bytes()
    entry_count = 0
    with zipfile.ZipFile(path) as archive:
        for info in archive.infolist():
            entry_count += 1
            if info.compress_type != zipfile.ZIP_STORED:
                fail(f"USDZ entry is compressed: {info.filename}")
            if payload[info.header_offset : info.header_offset + 4] != b"PK\x03\x04":
                fail(f"invalid local ZIP header: {info.filename}")
            name_length, extra_length = struct.unpack_from("<HH", payload, info.header_offset + 26)
            data_offset = info.header_offset + 30 + name_length + extra_length
            if data_offset % 64 != 0:
                fail(f"USDZ entry is not 64-byte aligned: {info.filename} offset={data_offset}")
    if entry_count == 0:
        fail("USDZ archive is empty")
    return entry_count


def archive_payload_digests(path: Path) -> dict[str, str]:
    with zipfile.ZipFile(path) as archive:
        return {info.filename: hashlib.sha256(archive.read(info)).hexdigest() for info in archive.infolist()}


def usd_text_from_archive(path: Path) -> str:
    with zipfile.ZipFile(path) as archive:
        usdc_names = [info.filename for info in archive.infolist() if info.filename.lower().endswith((".usdc", ".usd"))]
        if len(usdc_names) != 1:
            fail(f"USDZ must contain exactly one USDC/USD payload: {path.name} => {usdc_names}")
        with tempfile.NamedTemporaryFile(suffix=Path(usdc_names[0]).suffix, delete=False) as extracted:
            extracted.write(archive.read(usdc_names[0]))
            extracted_path = Path(extracted.name)
    try:
        return run_tool("usdcat", str(extracted_path))
    finally:
        extracted_path.unlink(missing_ok=True)


def usd_geometry_digest(layer_text: str) -> tuple[str, int, int]:
    """Hash only mesh topology/points, excluding ZIP and USD metadata."""
    records: list[tuple[str, str, str, str]] = []
    for match in re.finditer(r'\bdef Mesh "([^"]+)"', layer_text):
        start = match.start()
        opening = layer_text.find("{", match.end())
        closing = matching_brace(layer_text, opening)
        block = layer_text[start : closing + 1]
        counts = re.search(r"int\[\] faceVertexCounts = \[(.*?)\]", block, re.DOTALL)
        indices = re.search(r"int\[\] faceVertexIndices = \[(.*?)\]", block, re.DOTALL)
        points = re.search(r"point3f\[\] points = \[(.*?)\]", block, re.DOTALL)
        if counts is None or indices is None or points is None:
            fail(f"mesh lacks topology arrays: {match.group(1)}")
        records.append((match.group(1), counts.group(1), indices.group(1), points.group(1)))
    if not records:
        fail("USD has no Mesh prim")
    canonical = json.dumps(records, ensure_ascii=True, separators=(",", ":"))
    triangles = sum(len(re.findall(r"\d+", record[1])) for record in records)
    vertices = sum(len(re.findall(r"\([^)]*\)", record[3])) for record in records)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest(), triangles, vertices


def verify_collision_usd(path: Path, expected_triangle_count: int, expected_mesh_id: str) -> str:
    checker_output = run_tool("usdchecker", "--arkit", str(path))
    if "Success!" not in checker_output:
        fail("collision usdchecker --arkit did not report Success")
    layer_text = usd_text_from_archive(path)
    for value in (
        'defaultPrim = "BodyCompanionCollision"',
        "metersPerUnit = 1",
        'upAxis = "Y"',
        f'def Mesh "{expected_mesh_id}"',
        'subdivisionScheme = "none"',
        'userProperties:collision_kind = "static_triangle_proxy"',
    ):
        if value not in layer_text:
            fail(f"collision USD missing canonical metadata: {value}")
    mesh_names = set(re.findall(r'\bdef Mesh "([^"]+)"', layer_text))
    if mesh_names != {expected_mesh_id}:
        fail(f"collision USD must expose one canonical Mesh: {sorted(mesh_names)}")
    geometry_digest, triangles, vertices = usd_geometry_digest(layer_text)
    if triangles != expected_triangle_count:
        fail(f"collision triangle count mismatch: manifest={expected_triangle_count} usd={triangles}")
    if vertices <= 0:
        fail("collision USD has no vertices")
    return geometry_digest


def _validate_schema(path: Path, payload: dict[str, Any]) -> None:
    try:
        schema = json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        fail(f"mapping schema missing: {path.relative_to(ROOT)}: {exc}")
    errors = sorted(Draft202012Validator(schema).iter_errors(payload), key=lambda error: list(error.absolute_path))
    if errors:
        location = ".".join(str(item) for item in errors[0].absolute_path)
        fail(f"{path.relative_to(ROOT)} invalid at {location}: {errors[0].message}")


def _parse_iso8601(value: str) -> datetime:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        fail(f"invalid ISO-8601 mapping timestamp: {value}: {exc}")
    return parsed.astimezone(timezone.utc)


def verify_mapping_artifacts(
    manifest: dict[str, Any],
    *,
    collision_triangle_count: int,
    collision_mesh_id: str,
    render_mesh_ids: set[str],
) -> tuple[dict[str, Any], dict[str, Any]]:
    region_artifact = next((item for item in manifest["artifacts"] if item["role"] == "region_map"), None)
    correspondence_artifact = next((item for item in manifest["artifacts"] if item["role"] == "surface_correspondence"), None)
    if region_artifact is None or correspondence_artifact is None:
        fail("region_map and surface_correspondence artifacts are required")
    region_path = RESOURCE_ROOT / region_artifact["uri"].removeprefix("bundle://")
    correspondence_path = RESOURCE_ROOT / correspondence_artifact["uri"].removeprefix("bundle://")
    region = json.loads(region_path.read_text(encoding="utf-8"))
    correspondence = json.loads(correspondence_path.read_text(encoding="utf-8"))
    _validate_schema(REGION_MAP_SCHEMA_PATH, region)
    _validate_schema(SURFACE_CORRESPONDENCE_SCHEMA_PATH, correspondence)
    for payload, kind in ((region, "region_map"), (correspondence, "surface_correspondence")):
        for key in ("asset_id", "asset_version", "topology_id"):
            if payload[key] != manifest[key]:
                fail(f"{kind} identity mismatch for {key}: {payload[key]} != {manifest[key]}")
        if _parse_iso8601(payload["generated_at"]) < _parse_iso8601(manifest["updated_at"]):
            fail(f"{kind} generated_at predates manifest updated_at")
    if region["collision_mesh_id"] != collision_mesh_id:
        fail("region_map collision mesh ID does not match collision artifact")
    if region["collision_triangle_count"] != collision_triangle_count:
        fail("region_map collision triangle count does not match collision artifact")
    ranges = sorted(region["entries"], key=lambda item: item["face_start"])
    expected_start = 0
    for entry in ranges:
        if entry["collision_mesh_id"] != collision_mesh_id:
            fail(f"region_map entry uses unexpected collision mesh: {entry['entry_id']}")
        if entry["face_start"] != expected_start or entry["face_end"] < entry["face_start"]:
            fail(f"region_map face ranges are not contiguous at {entry['entry_id']}")
        expected_start = entry["face_end"] + 1
    if expected_start != collision_triangle_count:
        fail(f"region_map does not cover every collision face: end={expected_start - 1} count={collision_triangle_count}")

    if correspondence["render_artifact_id"] != next(item["artifact_id"] for item in manifest["artifacts"] if item["role"] == "render"):
        fail("surface correspondence render artifact ID is not bound to manifest")
    if correspondence["collision_artifact_id"] != next(item["artifact_id"] for item in manifest["artifacts"] if item["role"] == "collision"):
        fail("surface correspondence collision artifact ID is not bound to manifest")
    correspondence_meshes = {item["render_mesh_id"] for item in correspondence["entries"]}
    if correspondence_meshes != render_mesh_ids:
        fail(f"surface correspondence mesh set mismatch: {sorted(correspondence_meshes ^ render_mesh_ids)}")
    region_by_mesh = {item["region_id"] + "|" + item["laterality"]: item for item in ranges}
    for entry in correspondence["entries"]:
        if entry["collision_mesh_id"] != collision_mesh_id:
            fail(f"surface correspondence entry uses unexpected collision mesh: {entry['entry_id']}")
        for face_range in entry["collision_face_ranges"]:
            if face_range["start"] < 0 or face_range["end"] < face_range["start"] or face_range["end"] >= collision_triangle_count:
                fail(f"surface correspondence collision range is out of bounds: {entry['entry_id']}")
        mapped = [item for item in ranges if any(
            face_range["start"] == item["face_start"] and face_range["end"] == item["face_end"]
            for face_range in entry["collision_face_ranges"]
        )]
        if len(mapped) != 1:
            fail(f"surface correspondence must reference exactly one region face range: {entry['entry_id']}")
    return region, correspondence


def prim_own_properties(layer_text: str, declaration: str) -> str:
    start = layer_text.find(declaration)
    if start < 0:
        fail(f"missing USD prim declaration: {declaration}")
    opening = layer_text.find("{", start)
    if opening < 0:
        fail(f"malformed USD prim declaration: {declaration}")
    child = re.search(r"\n\s+def\s+", layer_text[opening + 1 :])
    end = opening + 1 + child.start() if child else len(layer_text)
    return layer_text[opening + 1 : end]


def matching_brace(text: str, opening: int) -> int:
    depth = 0
    for index in range(opening, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    fail("unterminated USD prim block")


def verify_usd(
    path: Path,
    *,
    asset_id: str,
    asset_version: str,
    topology_id: str,
    triangle_count: int,
    canonical_ground: float,
    canonical_height: float,
) -> None:
    checker_output = run_tool("usdchecker", "--arkit", str(path))
    if "Success!" not in checker_output:
        fail("usdchecker --arkit did not report Success")
    layer_text = run_tool("usdcat", str(path))

    required_metadata = (
        'defaultPrim = "BodyCompanion"',
        "metersPerUnit = 1",
        'upAxis = "Y"',
        f'userProperties:asset_id = "{asset_id}"',
        f'userProperties:asset_version = "{asset_version}"',
        f'userProperties:topology_id = "{topology_id}"',
    )
    for value in required_metadata:
        if value not in layer_text:
            fail(f"packaged USD is missing canonical metadata: {value}")

    for declaration in ('def Xform "BodyCompanion"', 'def Xform "body_root"'):
        own_properties = prim_own_properties(layer_text, declaration)
        if "xformOp:" in own_properties or "xformOpOrder" in own_properties:
            fail(f"canonical root must be identity: {declaration}")

    mesh_names = set(re.findall(r'\bdef Mesh "([^"]+)"', layer_text))
    if mesh_names != EXPECTED_MESH_NAMES:
        missing = sorted(EXPECTED_MESH_NAMES - mesh_names)
        unexpected = sorted(mesh_names - EXPECTED_MESH_NAMES)
        fail(f"unstable Mesh prim names; missing={missing} unexpected={unexpected}")
    for mesh_name in EXPECTED_MESH_NAMES:
        if f'def Xform "{mesh_name}"' in layer_text:
            fail(f"body entity is an Xform wrapper: {mesh_name}")

    face_count_arrays = re.findall(r"int\[\] faceVertexCounts = \[(.*?)\]", layer_text, flags=re.DOTALL)
    actual_triangle_count = 0
    for values in face_count_arrays:
        counts = [int(value) for value in re.findall(r"\d+", values)]
        if any(count != 3 for count in counts):
            fail("packaged USD contains a non-triangulated Mesh")
        actual_triangle_count += len(counts)
    if actual_triangle_count != triangle_count:
        fail(f"triangle count mismatch: manifest={triangle_count} usd={actual_triangle_count}")

    mesh_blocks = [
        layer_text[start : matching_brace(layer_text, layer_text.find("{", start)) + 1]
        for start in (match.start() for match in re.finditer(r'\bdef Mesh "', layer_text))
    ]
    world_y_bounds: list[float] = []
    for block in mesh_blocks:
        extent_match = re.search(
            r"float3\[\] extent = \[\([^,]+, ([^,]+), [^)]+\), \([^,]+, ([^,]+), [^)]+\)\]",
            block,
        )
        translation_match = re.search(r"double3 xformOp:translate = \([^,]+, ([^,]+), [^)]+\)", block)
        if extent_match is None or translation_match is None:
            fail("packaged Mesh is missing local extent or canonical translation")
        translation_y = float(translation_match.group(1))
        world_y_bounds.extend(
            (
                translation_y + float(extent_match.group(1)),
                translation_y + float(extent_match.group(2)),
            )
        )
    if abs(min(world_y_bounds) - canonical_ground) > 1e-5:
        fail(f"canonical ground mismatch: swift={canonical_ground} usd={min(world_y_bounds)}")
    if abs(max(world_y_bounds) - canonical_height) > 1e-5:
        fail(f"canonical height mismatch: swift={canonical_height} usd={max(world_y_bounds)}")


def main() -> int:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    expected_digest = f"sha256:{manifest_body_digest(MANIFEST_PATH)}"
    actual_digest = manifest.get("integrity", {}).get("manifest_sha256", "")
    if actual_digest != expected_digest:
        fail(f"manifest self-hash mismatch: manifest={actual_digest} expected={expected_digest}")
    verify_manifest_signature(MANIFEST_PATH, manifest)

    swift_source = SWIFT_PATH.read_text(encoding="utf-8")
    swift_values = {
        "asset_id": swift_string(swift_source, "assetID"),
        "asset_version": swift_string(swift_source, "assetVersion"),
        "topology_id": swift_string(swift_source, "topologyID"),
    }
    for key, value in swift_values.items():
        if manifest[key] != value:
            fail(f"manifest/Swift identity mismatch for {key}: {manifest[key]} != {value}")

    resource_name = swift_string(swift_source, "modelResourceName")
    resource_extension = swift_string(swift_source, "modelResourceExtension")
    resource_path = RESOURCE_ROOT / f"{resource_name}.{resource_extension}"
    if not resource_path.is_file():
        fail(f"Swift candidate resource is missing: {resource_path.relative_to(ROOT)}")

    digest = hashlib.sha256(resource_path.read_bytes()).hexdigest()
    bundle_artifacts = [
        artifact for artifact in manifest["artifacts"]
        if artifact["uri"].startswith("bundle://")
    ]
    if not bundle_artifacts:
        fail("candidate manifest has no bundle artifact")

    required_roles = {
        "render",
        "collision",
        "region_map",
        "surface_correspondence",
        "camera_preset",
    }
    present_roles = {artifact["role"] for artifact in bundle_artifacts if artifact.get("role") in required_roles}
    missing_roles = sorted(required_roles - present_roles)
    if missing_roles:
        fail(f"candidate manifest missing required artifact roles: {missing_roles}")
    for artifact in bundle_artifacts:
        if artifact.get("role") in {"render", "collision", "region_map", "surface_correspondence", "camera_preset"} and artifact.get("required") is not True:
            fail(f"required artifact role is not marked required: {artifact['role']} => {artifact.get('artifact_id')}")
        artifact_path = RESOURCE_ROOT / artifact["uri"].removeprefix("bundle://")
        if not artifact_path.is_file():
            fail(f"bundle artifact is missing: {artifact['uri']}")
        artifact_digest = hashlib.sha256(artifact_path.read_bytes()).hexdigest()
        if artifact["sha256"] != f"sha256:{artifact_digest}":
            fail(f"bundle artifact hash mismatch: {artifact['uri']}")
    render_artifacts = [artifact for artifact in bundle_artifacts if artifact["role"] == "render"]
    if len(render_artifacts) != 1 or render_artifacts[0]["uri"] != f"bundle://{resource_path.name}":
        fail("Swift resource does not match the single candidate render artifact")
    if render_artifacts[0]["sha256"] != f"sha256:{digest}":
        fail("Swift candidate resource digest does not match manifest render artifact")

    collision_artifacts = [artifact for artifact in bundle_artifacts if artifact["role"] == "collision"]
    if len(collision_artifacts) != 1:
        fail("candidate manifest must have exactly one required collision artifact")
    if (
        collision_artifacts[0]["uri"] == render_artifacts[0]["uri"]
        or collision_artifacts[0]["sha256"] == render_artifacts[0]["sha256"]
    ):
        fail("candidate manifest collision artifact must be independent from render")

    entry_count = verify_archive_layout(resource_path)
    if len(manifest["lods"]) != 1:
        fail("current candidate must have exactly one frozen LOD")
    render_layer_text = usd_text_from_archive(resource_path)
    render_geometry_digest, render_triangle_count, _ = usd_geometry_digest(render_layer_text)
    verify_usd(
        resource_path,
        asset_id=manifest["asset_id"],
        asset_version=manifest["asset_version"],
        topology_id=manifest["topology_id"],
        triangle_count=int(manifest["lods"][0]["triangle_count"]),
        canonical_ground=swift_float(swift_source, "canonicalGroundYMeters"),
        canonical_height=swift_float(swift_source, "canonicalHeightMeters"),
    )
    collision_path = RESOURCE_ROOT / collision_artifacts[0]["uri"].removeprefix("bundle://")
    collision_layer_text = usd_text_from_archive(collision_path)
    collision_geometry_digest, collision_triangle_count, _ = usd_geometry_digest(collision_layer_text)
    collision_mesh_id = "body_collision_v1"
    if collision_artifacts[0].get("geometry_sha256") != f"sha256:{collision_geometry_digest}":
        fail("collision artifact geometry_sha256 does not match USD topology/points")
    if collision_artifacts[0].get("triangle_count") != collision_triangle_count:
        fail("collision artifact triangle_count does not match USD")
    if collision_artifacts[0].get("mesh_id") != collision_mesh_id:
        fail("collision artifact mesh_id is not the canonical collision mesh")
    verify_collision_usd(collision_path, collision_triangle_count, collision_mesh_id)
    render_payloads = archive_payload_digests(resource_path)
    collision_payloads = archive_payload_digests(collision_path)
    if render_payloads.get("BodyNeutralPrototype.usdc") == collision_payloads.get("BodyNeutralPrototypeCollision.usdc"):
        fail("render and collision internal USDC payloads are identical")
    if render_geometry_digest == collision_geometry_digest:
        fail("render and collision geometry/topology digests are identical")
    verify_mapping_artifacts(
        manifest,
        collision_triangle_count=collision_triangle_count,
        collision_mesh_id=collision_mesh_id,
        render_mesh_ids=set(re.findall(r'\bdef Mesh "([^"]+)"', render_layer_text)),
    )
    print(
        "body_asset_release_checks=passed "
        f"asset={manifest['asset_id']}@{manifest['asset_version']} "
        f"sha256={digest} meshes={len(EXPECTED_MESH_NAMES)} "
        f"render_triangles={render_triangle_count} collision_triangles={collision_triangle_count} "
        f"zip_entries={entry_count}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, RuntimeError, zipfile.BadZipFile) as exc:
        print(f"body_asset_release_checks=failed error={exc}", file=sys.stderr)
        raise SystemExit(1) from exc
