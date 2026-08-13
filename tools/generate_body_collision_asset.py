#!/usr/bin/env python3
"""Build the deterministic, material-free collision proxy and mapping artifacts.

The render candidate is intentionally segmented and high detail.  Its collision
artifact must not be a renamed copy: this script creates a separate low-poly
static triangle mesh, freezes face order, and writes the face ranges consumed by
the iOS hit resolver.  The proxy is a location-expression aid only; it has no
anatomical or medical meaning.
"""

from __future__ import annotations

import hashlib
import json
import math
import re
import shutil
import struct
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
RESOURCE_ROOT = ROOT / "ios/BodyCompanion/AppHost/BodyCompanionInternal/Resources"
RENDER_PATH = RESOURCE_ROOT / "BodyNeutralPrototype.usdz"
COLLISION_PATH = RESOURCE_ROOT / "BodyNeutralPrototypeCollision.usdz"
REGION_PATH = RESOURCE_ROOT / "body-neutral-procedural-v1.region_map.json"
CORRESPONDENCE_PATH = RESOURCE_ROOT / "body-neutral-procedural-v1.surface_correspondence.json"

ASSET_ID = "body-neutral-procedural-v1"
ASSET_VERSION = "1.2.0"
TOPOLOGY_ID = "body-neutral-procedural-topology-v2"
COLLISION_MESH_ID = "body_collision_v1"
COLLISION_ARTIFACT_ID = "body-neutral-procedural-v1-runtime-collision-candidate"
RENDER_ARTIFACT_ID = "body-neutral-procedural-v1-render"
MAPPING_VERSION = "1.2.0"
ONTOLOGY_VERSION = "body-ontology-prototype-v1"
GENERATED_AT = "2026-08-13T05:20:00Z"
FIXED_DOS_TIME = 0
FIXED_DOS_DATE = (2020 - 1980) << 9 | 1 << 5 | 1


@dataclass(frozen=True)
class Component:
    mesh_id: str
    region_id: str
    laterality: str
    surface: str
    kind: str
    values: tuple[float, ...]


def _side_components(side: str, sign: float) -> list[Component]:
    x = sign * 0.24
    return [
        Component(f"body_{side}_shoulder", "body.shoulder.general", side, "lateral", "ellipsoid", (sign * 0.225, 1.47, 0, 0.09, 0.10, 0.095)),
        Component(f"body_{side}_chest", "body.chest.general", side, "anterior", "ellipsoid", (sign * 0.09, 1.34, 0.09, 0.115, 0.13, 0.055)),
        Component(f"body_{side}_upper_back", "body.upper_back.general", side, "posterior", "ellipsoid", (sign * 0.09, 1.34, -0.09, 0.115, 0.13, 0.055)),
        Component(f"body_{side}_hip", "body.hip.general", side, "lateral", "ellipsoid", (sign * 0.105, 0.96, 0, 0.095, 0.11, 0.115)),
        Component(f"body_{side}_upper_arm", "body.upper_arm.general", side, "lateral", "cylinder", (x * 0.84, 1.48, 0, x * 1.03, 1.18, 0, 0.06)),
        Component(f"body_{side}_elbow", "body.elbow.general", side, "lateral", "ellipsoid", (x * 1.03, 1.17, 0, 0.065, 0.065, 0.06)),
        Component(f"body_{side}_forearm", "body.forearm.general", side, "lateral", "cylinder", (x * 1.03, 1.18, 0, x * 1.08, 0.90, 0, 0.048)),
        Component(f"body_{side}_hand", "body.hand.general", side, "lateral", "ellipsoid", (x * 1.08, 0.84, 0, 0.055, 0.08, 0.045)),
        Component(f"body_{side}_thigh", "body.thigh.general", side, "lateral", "cylinder", (x * 0.62, 0.88, 0, x * 0.62, 0.48, 0, 0.09)),
        Component(f"body_{side}_knee", "body.knee.general", side, "lateral", "ellipsoid", (x * 0.62, 0.42, 0, 0.09, 0.075, 0.08)),
        Component(f"body_{side}_calf", "body.calf.general", side, "lateral", "cylinder", (x * 0.62, 0.36, 0, x * 0.62, 0.08, 0, 0.065)),
        Component(f"body_{side}_foot", "body.ankle_foot.general", side, "lateral", "box", (x * 0.62, 0.035, 0.05, 0.075, 0.035, 0.14)),
    ]


COMPONENTS = sorted(
    [
        Component("body_head", "body.head.general", "midline", "circumferential", "ellipsoid", (0, 1.72, 0, 0.115, 0.14, 0.105)),
        Component("body_neck", "body.neck.general", "midline", "circumferential", "cylinder", (0, 1.56, 0, 0, 1.64, 0, 0.065)),
        Component("body_torso", "body.torso.general", "midline", "circumferential", "ellipsoid", (0, 1.28, 0, 0.22, 0.30, 0.13)),
        Component("body_abdomen", "body.abdomen.general", "midline", "anterior", "ellipsoid", (0, 1.08, 0.005, 0.17, 0.18, 0.125)),
        Component("body_lower_back", "body.lower_back.general", "midline", "posterior", "ellipsoid", (0, 1.08, -0.105, 0.14, 0.16, 0.055)),
        Component("body_pelvis", "body.pelvis.general", "midline", "circumferential", "ellipsoid", (0, 0.92, 0, 0.18, 0.14, 0.13)),
        *_side_components("left", -1.0),
        *_side_components("right", 1.0),
    ],
    key=lambda component: component.mesh_id,
)


def _run_tool(name: str, *arguments: str, capture_output: bool = False) -> str:
    executable = shutil.which(name)
    if executable is None:
        raise RuntimeError(f"required OpenUSD tool is unavailable: {name}")
    result = subprocess.run(
        (executable, *arguments),
        check=True,
        text=True,
        capture_output=capture_output,
    )
    return result.stdout if capture_output else ""


def _normalize_usdz_timestamps(path: Path) -> None:
    payload = bytearray(path.read_bytes())
    eocd = b"PK\x05\x06"
    central = b"PK\x01\x02"
    local = b"PK\x03\x04"
    end = payload.rfind(eocd)
    if end < 0:
        raise RuntimeError("collision USDZ has no end-of-central-directory record")
    _, disk, central_disk, on_disk, count, size, offset, comment = struct.unpack_from("<4sHHHHIIH", payload, end)
    if (disk, central_disk, on_disk) != (0, 0, count) or end + 22 + comment != len(payload):
        raise RuntimeError("collision USDZ has an unsupported ZIP layout")
    if offset + size != end:
        raise RuntimeError("collision USDZ central directory bounds are invalid")
    timestamp_offsets: list[int] = []
    cursor = offset
    for _ in range(count):
        if payload[cursor : cursor + 4] != central:
            raise RuntimeError("collision USDZ central entry is invalid")
        compression = struct.unpack_from("<H", payload, cursor + 10)[0]
        name_len, extra_len, comment_len = struct.unpack_from("<HHH", payload, cursor + 28)
        local_offset = struct.unpack_from("<I", payload, cursor + 42)[0]
        if payload[local_offset : local_offset + 4] != local:
            raise RuntimeError("collision USDZ local entry is invalid")
        local_compression = struct.unpack_from("<H", payload, local_offset + 8)[0]
        local_name_len, local_extra_len = struct.unpack_from("<HH", payload, local_offset + 26)
        data_offset = local_offset + 30 + local_name_len + local_extra_len
        if compression != 0 or local_compression != 0 or data_offset % 64 != 0:
            raise RuntimeError("collision USDZ entries must be stored and 64-byte aligned")
        timestamp_offsets.extend((cursor + 12, local_offset + 10))
        cursor += 46 + name_len + extra_len + comment_len
    if cursor != end:
        raise RuntimeError("collision USDZ central directory count is inconsistent")
    with path.open("r+b") as archive:
        for item in timestamp_offsets:
            archive.seek(item)
            archive.write(struct.pack("<HH", FIXED_DOS_TIME, FIXED_DOS_DATE))


def _add_ellipsoid(component: Component, points: list[tuple[float, float, float]], faces: list[tuple[int, int, int]]) -> None:
    cx, cy, cz, rx, ry, rz = component.values
    segments = 10
    rings = 5
    top = len(points)
    points.append((cx, cy + ry, cz))
    ring_indices: list[list[int]] = []
    for ring in range(1, rings):
        phi = math.pi * ring / rings
        ring_points: list[int] = []
        for segment in range(segments):
            theta = 2 * math.pi * segment / segments
            ring_points.append(len(points))
            points.append((cx + rx * math.sin(phi) * math.cos(theta), cy + ry * math.cos(phi), cz + rz * math.sin(phi) * math.sin(theta)))
        ring_indices.append(ring_points)
    bottom = len(points)
    points.append((cx, cy - ry, cz))
    first = ring_indices[0]
    for segment in range(segments):
        nxt = (segment + 1) % segments
        faces.append((top, first[nxt], first[segment]))
    for upper, lower in zip(ring_indices, ring_indices[1:]):
        for segment in range(segments):
            nxt = (segment + 1) % segments
            faces.extend(((upper[segment], lower[segment], lower[nxt]), (upper[segment], lower[nxt], upper[nxt])))
    last = ring_indices[-1]
    for segment in range(segments):
        nxt = (segment + 1) % segments
        faces.append((last[segment], last[nxt], bottom))


def _add_cylinder(component: Component, points: list[tuple[float, float, float]], faces: list[tuple[int, int, int]]) -> None:
    ax, ay, az, bx, by, bz, radius = component.values
    a = (ax, ay, az)
    b = (bx, by, bz)
    dx, dy, dz = bx - ax, by - ay, bz - az
    length = math.sqrt(dx * dx + dy * dy + dz * dz)
    if length <= 0:
        raise RuntimeError(f"degenerate collision cylinder: {component.mesh_id}")
    d = (dx / length, dy / length, dz / length)
    ref = (0.0, 1.0, 0.0) if abs(d[1]) < 0.9 else (1.0, 0.0, 0.0)
    u = (d[1] * ref[2] - d[2] * ref[1], d[2] * ref[0] - d[0] * ref[2], d[0] * ref[1] - d[1] * ref[0])
    u_len = math.sqrt(sum(value * value for value in u))
    u = tuple(value / u_len for value in u)
    v = (d[1] * u[2] - d[2] * u[1], d[2] * u[0] - d[0] * u[2], d[0] * u[1] - d[1] * u[0])
    segments = 10
    start_ring: list[int] = []
    end_ring: list[int] = []
    for segment in range(segments):
        theta = 2 * math.pi * segment / segments
        c, s = math.cos(theta) * radius, math.sin(theta) * radius
        start_ring.append(len(points))
        points.append((a[0] + u[0] * c + v[0] * s, a[1] + u[1] * c + v[1] * s, a[2] + u[2] * c + v[2] * s))
        end_ring.append(len(points))
        points.append((b[0] + u[0] * c + v[0] * s, b[1] + u[1] * c + v[1] * s, b[2] + u[2] * c + v[2] * s))
    start_center = len(points)
    points.append(a)
    end_center = len(points)
    points.append(b)
    for segment in range(segments):
        nxt = (segment + 1) % segments
        faces.extend(((start_ring[segment], start_ring[nxt], end_ring[nxt]), (start_ring[segment], end_ring[nxt], end_ring[segment])))
        faces.append((start_center, start_ring[nxt], start_ring[segment]))
        faces.append((end_center, end_ring[segment], end_ring[nxt]))


def _add_box(component: Component, points: list[tuple[float, float, float]], faces: list[tuple[int, int, int]]) -> None:
    cx, cy, cz, rx, ry, rz = component.values
    base = len(points)
    points.extend((
        (cx - rx, cy - ry, cz - rz), (cx + rx, cy - ry, cz - rz),
        (cx + rx, cy + ry, cz - rz), (cx - rx, cy + ry, cz - rz),
        (cx - rx, cy - ry, cz + rz), (cx + rx, cy - ry, cz + rz),
        (cx + rx, cy + ry, cz + rz), (cx - rx, cy + ry, cz + rz),
    ))
    faces.extend(
        (base + a, base + b, base + c)
        for a, b, c in (
            (0, 2, 1), (0, 3, 2), (4, 5, 6), (4, 6, 7),
            (0, 1, 5), (0, 5, 4), (3, 7, 6), (3, 6, 2),
            (0, 4, 7), (0, 7, 3), (1, 2, 6), (1, 6, 5),
        )
    )


def _build_geometry() -> tuple[list[tuple[float, float, float]], list[tuple[int, int, int]], list[dict[str, Any]]]:
    points: list[tuple[float, float, float]] = []
    faces: list[tuple[int, int, int]] = []
    ranges: list[dict[str, Any]] = []
    for component in COMPONENTS:
        start = len(faces)
        if component.kind == "ellipsoid":
            _add_ellipsoid(component, points, faces)
        elif component.kind == "cylinder":
            _add_cylinder(component, points, faces)
        elif component.kind == "box":
            _add_box(component, points, faces)
        else:
            raise RuntimeError(f"unknown collision primitive: {component.kind}")
        end = len(faces) - 1
        if end < start:
            raise RuntimeError(f"collision primitive produced no faces: {component.mesh_id}")
        ranges.append({
            "mesh_id": component.mesh_id,
            "region_id": component.region_id,
            "laterality": component.laterality,
            "surface": component.surface,
            "face_start": start,
            "face_end": end,
            "confidence": 0.86,
            "boundary_candidates": [],
        })
    return points, faces, ranges


def _fmt_float(value: float) -> str:
    if abs(value) < 0.0000000005:
        value = 0.0
    return format(value, ".9g")


def _format_values(values: list[Any], per_line: int = 12) -> str:
    lines: list[str] = []
    for offset in range(0, len(values), per_line):
        lines.append(", ".join(str(item) for item in values[offset : offset + per_line]))
    return ",\n                ".join(lines)


def _write_usda(path: Path, points: list[tuple[float, float, float]], faces: list[tuple[int, int, int]], ranges: list[dict[str, Any]]) -> None:
    points_text = _format_values([f"({_fmt_float(x)}, {_fmt_float(y)}, {_fmt_float(z)})" for x, y, z in points], per_line=6)
    indices = [index for face in faces for index in face]
    index_text = _format_values(indices, per_line=18)
    counts_text = _format_values([3] * len(faces), per_line=24)
    min_x = min(point[0] for point in points)
    min_y = min(point[1] for point in points)
    min_z = min(point[2] for point in points)
    max_x = max(point[0] for point in points)
    max_y = max(point[1] for point in points)
    max_z = max(point[2] for point in points)
    text = f'''#usda 1.0
(
    defaultPrim = "BodyCompanionCollision"
    doc = "Body Companion deterministic static collision proxy"
    metersPerUnit = 1
    upAxis = "Y"
)

def Xform "BodyCompanionCollision"
{{
    def Xform "body_collision_root"
    {{
        custom string userProperties:asset_id = "{ASSET_ID}"
        custom string userProperties:asset_version = "{ASSET_VERSION}"
        custom string userProperties:topology_id = "{TOPOLOGY_ID}"
        custom string userProperties:coordinate_convention = "realitykit_y_up_right_handed"
        custom string userProperties:collision_mesh_id = "{COLLISION_MESH_ID}"
        custom string userProperties:collision_kind = "static_triangle_proxy"
        custom string userProperties:source = "original project-generated low-poly collision proxy"
        custom string userProperties:medical_meaning = "none; visual location expression only"

        def Mesh "{COLLISION_MESH_ID}"
        {{
            uniform bool doubleSided = 1
            uniform token subdivisionScheme = "none"
            float3[] extent = [({_fmt_float(min_x)}, {_fmt_float(min_y)}, {_fmt_float(min_z)}), ({_fmt_float(max_x)}, {_fmt_float(max_y)}, {_fmt_float(max_z)})]
            int[] faceVertexCounts = [{counts_text}]
            int[] faceVertexIndices = [{index_text}]
            point3f[] points = [{points_text}]
        }}
    }}
}}
'''
    path.write_text(text, encoding="utf-8")


def _render_mesh_stats() -> dict[str, dict[str, int]]:
    temporary = Path(tempfile.mkdtemp(prefix="body-render-readback-"))
    try:
        usdc = temporary / "render.usdc"
        usda = temporary / "render.usda"
        with subprocess.Popen(("unzip", "-p", str(RENDER_PATH), "*.usdc"), stdout=usdc.open("wb")) as process:
            if process.wait() != 0:
                raise RuntimeError("unable to extract render USDC")
        usda.write_text(_run_tool("usdcat", str(usdc), capture_output=True), encoding="utf-8")
        text = usda.read_text(encoding="utf-8")
    finally:
        shutil.rmtree(temporary, ignore_errors=True)
    stats: dict[str, dict[str, int]] = {}
    for match in re.finditer(r'def Mesh "([^"]+)"', text):
        opening = text.find("{", match.end())
        depth = 0
        closing = None
        for index in range(opening, len(text)):
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    closing = index + 1
                    break
        if closing is None:
            raise RuntimeError(f"unterminated render mesh: {match.group(1)}")
        block = text[match.start() : closing]
        faces_match = re.search(r"int\[\] faceVertexCounts = \[(.*?)\]", block, re.DOTALL)
        points_match = re.search(r"point3f\[\] points = \[(.*?)\]", block, re.DOTALL)
        if faces_match is None or points_match is None:
            raise RuntimeError(f"render mesh missing topology arrays: {match.group(1)}")
        stats[match.group(1)] = {
            "triangle_count": len(re.findall(r"\d+", faces_match.group(1))),
            "vertex_count": len(re.findall(r"\([^)]*\)", points_match.group(1))),
        }
    return stats


def _write_mapping_artifacts(ranges: list[dict[str, Any]], collision_triangle_count: int) -> None:
    render_stats = _render_mesh_stats()
    expected_mesh_ids = {component.mesh_id for component in COMPONENTS}
    if set(render_stats) != expected_mesh_ids:
        raise RuntimeError(f"render/collision mesh set mismatch: render={sorted(render_stats)}")

    region_payload = {
        "schema_version": "1.0",
        "asset_id": ASSET_ID,
        "asset_version": ASSET_VERSION,
        "topology_id": TOPOLOGY_ID,
        "collision_mesh_id": COLLISION_MESH_ID,
        "collision_triangle_count": collision_triangle_count,
        "entries": [
            {
                "entry_id": f"{index:03d}",
                "mesh_id": item["mesh_id"],
                "collision_mesh_id": COLLISION_MESH_ID,
                "face_start": item["face_start"],
                "face_end": item["face_end"],
                "region_id": item["region_id"],
                "laterality": item["laterality"],
                "surface": item["surface"],
                "confidence": item["confidence"],
                "boundary_candidates": item["boundary_candidates"],
            }
            for index, item in enumerate(ranges)
        ],
        "generated_at": GENERATED_AT,
        "mapping_kind": "collision_triangle_region_map",
        "mapping_version": MAPPING_VERSION,
    }
    correspondence_payload = {
        "schema_version": "1.0",
        "asset_id": ASSET_ID,
        "asset_version": ASSET_VERSION,
        "topology_id": TOPOLOGY_ID,
        "render_artifact_id": RENDER_ARTIFACT_ID,
        "collision_artifact_id": COLLISION_ARTIFACT_ID,
        "collision_mesh_id": COLLISION_MESH_ID,
        "entries": [
            {
                "entry_id": f"{index:03d}",
                "render_mesh_id": item["mesh_id"],
                "collision_mesh_id": COLLISION_MESH_ID,
                "render_triangle_range": {
                    "start": 0,
                    "end": render_stats[item["mesh_id"]]["triangle_count"] - 1,
                },
                "render_triangle_count": render_stats[item["mesh_id"]]["triangle_count"],
                "render_vertex_count": render_stats[item["mesh_id"]]["vertex_count"],
                "collision_face_ranges": [
                    {"start": item["face_start"], "end": item["face_end"]}
                ],
                "method": "semantic_mesh_to_static_proxy",
                "confidence": item["confidence"],
                "quality_status": "candidate_proxy_unmeasured",
                "boundary_candidates": item["boundary_candidates"],
            }
            for index, item in enumerate(ranges)
        ],
        "generated_at": GENERATED_AT,
        "mapping_kind": "render_mesh_to_collision_face_ranges",
        "mapping_version": MAPPING_VERSION,
    }
    for path, payload in ((REGION_PATH, region_payload), (CORRESPONDENCE_PATH, correspondence_payload)):
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    if not RENDER_PATH.is_file():
        raise RuntimeError(f"render asset is missing: {RENDER_PATH}")
    points, faces, ranges = _build_geometry()
    if len({item["face_start"] for item in ranges}) != len(ranges):
        raise RuntimeError("collision face ranges are not unique")
    with tempfile.TemporaryDirectory(prefix="body-collision-asset-") as temporary_directory:
        staging = Path(temporary_directory)
        source = staging / "BodyNeutralPrototypeCollision.usda"
        staged = staging / COLLISION_PATH.name
        _write_usda(source, points, faces, ranges)
        _run_tool("usdzip", "--arkitAsset", str(source), str(staged))
        _normalize_usdz_timestamps(staged)
        checker = _run_tool("usdchecker", "--arkit", str(staged), capture_output=True)
        if "Success!" not in checker:
            raise RuntimeError("usdchecker --arkit did not report Success for collision asset")
        shutil.copyfile(staged, COLLISION_PATH)
    _write_mapping_artifacts(ranges, len(faces))
    print(
        f"generated collision={COLLISION_PATH} sha256={hashlib.sha256(COLLISION_PATH.read_bytes()).hexdigest()} "
        f"triangles={len(faces)} vertices={len(points)} ranges={len(ranges)}"
    )


if __name__ == "__main__":
    main()
