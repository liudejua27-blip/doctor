#!/usr/bin/env python3
"""Fail-closed readback for the checked-in RealityKit body candidate.

This verifier deliberately does not approve the asset. It binds the current
candidate's manifest, Swift constants and packaged USD facts so that any one
of those layers drifting makes the macOS CI job fail.
"""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import struct
import subprocess
import sys
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "docs/assets/body-neutral-procedural-v1.manifest.json"
SWIFT_PATH = ROOT / "ios/BodyCompanion/Sources/BodyCompanionCore/BodyAssetManifest.swift"
RESOURCE_ROOT = ROOT / "ios/BodyCompanion/Sources/BodyCompanionIOS/Resources"

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
    for artifact in bundle_artifacts:
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

    entry_count = verify_archive_layout(resource_path)
    if len(manifest["lods"]) != 1:
        fail("current candidate must have exactly one frozen LOD")
    verify_usd(
        resource_path,
        asset_id=manifest["asset_id"],
        asset_version=manifest["asset_version"],
        topology_id=manifest["topology_id"],
        triangle_count=int(manifest["lods"][0]["triangle_count"]),
        canonical_ground=swift_float(swift_source, "canonicalGroundYMeters"),
        canonical_height=swift_float(swift_source, "canonicalHeightMeters"),
    )
    print(
        "body_asset_release_checks=passed "
        f"asset={manifest['asset_id']}@{manifest['asset_version']} "
        f"sha256={digest} meshes={len(EXPECTED_MESH_NAMES)} "
        f"triangles={manifest['lods'][0]['triangle_count']} zip_entries={entry_count}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, RuntimeError, zipfile.BadZipFile) as exc:
        print(f"body_asset_release_checks=failed error={exc}", file=sys.stderr)
        raise SystemExit(1) from exc
