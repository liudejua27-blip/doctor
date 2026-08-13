"""Generate the original internal neutral body prototype asset.

This is intentionally a low-detail, non-anatomical display model. It is not
derived from RehabMate or any third-party mesh. The generated USDZ remains an
internal candidate until the asset, anatomy, performance and accessibility
gates in FEAT-BODY-MAP-V1 are signed off.
"""

from __future__ import annotations

import hashlib
import re
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

import bpy
from mathutils import Vector


OUTPUT = Path(__file__).resolve().parents[1] / "ios/BodyCompanion/Sources/BodyCompanionIOS/Resources/BodyNeutralPrototype.usdz"
ASSET_ID = "body-neutral-procedural-v1"
ASSET_VERSION = "1.2.0"
TOPOLOGY_ID = "body-neutral-procedural-topology-v2"
FIXED_DOS_TIME = 0
FIXED_DOS_DATE = (2020 - 1980) << 9 | 1 << 5 | 1
CANONICAL_GROUND_Y_METERS = 0.0
CANONICAL_HEIGHT_METERS = 1.86

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


def run_tool(*arguments: str, capture_output: bool = False) -> str:
    executable = shutil.which(arguments[0])
    if executable is None:
        raise RuntimeError(f"required OpenUSD tool is unavailable: {arguments[0]}")
    completed = subprocess.run(
        (executable, *arguments[1:]),
        check=True,
        text=True,
        capture_output=capture_output,
    )
    return completed.stdout if capture_output else ""


def normalize_usdz_timestamps_in_place(path: Path) -> None:
    """Normalize ZIP timestamps without rebuilding or moving USDZ entries.

    USDZ requires uncompressed entries whose payloads begin at 64-byte aligned
    offsets. Repacking with a general ZIP writer can invalidate that contract,
    so usdzip owns layout and this function changes only DOS time/date fields.
    """
    payload = bytearray(path.read_bytes())
    end_signature = b"PK\x05\x06"
    central_signature = b"PK\x01\x02"
    local_signature = b"PK\x03\x04"
    end_offset = payload.rfind(end_signature)
    if end_offset < 0 or end_offset + 22 > len(payload):
        raise RuntimeError("USDZ has no valid end-of-central-directory record")

    (
        _signature,
        disk_number,
        central_disk,
        entries_on_disk,
        entry_count,
        central_size,
        central_offset,
        comment_length,
    ) = struct.unpack_from("<4sHHHHIIH", payload, end_offset)
    if disk_number != 0 or central_disk != 0 or entries_on_disk != entry_count:
        raise RuntimeError("multi-disk ZIP is not valid for this USDZ candidate")
    if end_offset + 22 + comment_length != len(payload):
        raise RuntimeError("unexpected bytes after USDZ central directory")
    if central_offset + central_size != end_offset:
        raise RuntimeError("USDZ central-directory bounds are inconsistent")

    timestamp_offsets: list[int] = []
    cursor = central_offset
    for _ in range(entry_count):
        if payload[cursor : cursor + 4] != central_signature:
            raise RuntimeError("invalid USDZ central-directory entry")
        compression = struct.unpack_from("<H", payload, cursor + 10)[0]
        file_name_length, extra_length, entry_comment_length = struct.unpack_from("<HHH", payload, cursor + 28)
        local_offset = struct.unpack_from("<I", payload, cursor + 42)[0]
        if payload[local_offset : local_offset + 4] != local_signature:
            raise RuntimeError("USDZ central entry does not reference a local entry")
        local_compression = struct.unpack_from("<H", payload, local_offset + 8)[0]
        local_name_length, local_extra_length = struct.unpack_from("<HH", payload, local_offset + 26)
        data_offset = local_offset + 30 + local_name_length + local_extra_length
        if compression != 0 or local_compression != 0:
            raise RuntimeError("USDZ entries must be stored without compression")
        if data_offset % 64 != 0:
            raise RuntimeError(f"USDZ entry payload is not 64-byte aligned: offset={data_offset}")

        timestamp_offsets.extend((cursor + 12, local_offset + 10))
        cursor += 46 + file_name_length + extra_length + entry_comment_length

    if cursor != end_offset:
        raise RuntimeError("USDZ central-directory entry count is inconsistent")
    with path.open("r+b") as archive:
        for offset in timestamp_offsets:
            archive.seek(offset)
            archive.write(struct.pack("<HH", FIXED_DOS_TIME, FIXED_DOS_DATE))


def prim_own_properties(layer_text: str, declaration: str) -> str:
    start = layer_text.find(declaration)
    if start < 0:
        raise RuntimeError(f"missing USD prim declaration: {declaration}")
    opening = layer_text.find("{", start)
    if opening < 0:
        raise RuntimeError(f"malformed USD prim declaration: {declaration}")
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
    raise RuntimeError("unterminated USDA prim block")


def sort_direct_child_prims(layer_text: str, declaration: str, materials_last: bool = False) -> str:
    """Sort direct child prim specs to remove exporter scheduling variance."""
    parent_start = layer_text.find(declaration)
    if parent_start < 0:
        raise RuntimeError(f"missing USDA prim declaration: {declaration}")
    parent_opening = layer_text.find("{", parent_start)
    parent_closing = matching_brace(layer_text, parent_opening)

    child_pattern = re.compile(r'\n(?P<indent>[ \t]+)def\s+\w+\s+"(?P<name>[^"]+)"')
    children: list[tuple[str, int, int, str]] = []
    cursor = parent_opening + 1
    while cursor < parent_closing:
        match = child_pattern.search(layer_text, cursor, parent_closing)
        if match is None:
            break
        depth = layer_text.count("{", parent_opening + 1, match.start()) - layer_text.count(
            "}", parent_opening + 1, match.start()
        )
        if depth != 0:
            cursor = match.end()
            continue
        child_start = match.start() + 1
        child_opening = layer_text.find("{", match.end(), parent_closing)
        if child_opening < 0:
            raise RuntimeError(f"malformed USDA child prim: {match.group('name')}")
        child_closing = matching_brace(layer_text, child_opening)
        children.append(
            (
                match.group("name"),
                child_start,
                child_closing + 1,
                layer_text[child_start : child_closing + 1],
            )
        )
        cursor = child_closing + 1

    if len(children) < 2:
        return layer_text
    key = (lambda child: (child[0] == "_materials", child[0])) if materials_last else (lambda child: child[0])
    ordered_blocks = [child[3] for child in sorted(children, key=key)]
    replacement = (
        layer_text[parent_opening + 1 : children[0][1]]
        + "\n\n".join(ordered_blocks)
        + layer_text[children[-1][2] : parent_closing]
    )
    return layer_text[: parent_opening + 1] + replacement + layer_text[parent_closing:]


def verify_packaged_asset(path: Path, expected_triangle_count: int) -> str:
    run_tool("usdchecker", "--arkit", str(path))
    layer_text = run_tool("usdcat", str(path), capture_output=True)

    required_metadata = (
        'defaultPrim = "BodyCompanion"',
        "metersPerUnit = 1",
        'upAxis = "Y"',
        f'userProperties:asset_id = "{ASSET_ID}"',
        f'userProperties:asset_version = "{ASSET_VERSION}"',
        f'userProperties:topology_id = "{TOPOLOGY_ID}"',
    )
    for value in required_metadata:
        if value not in layer_text:
            raise RuntimeError(f"packaged USD is missing canonical metadata: {value}")

    for declaration in ('def Xform "BodyCompanion"', 'def Xform "body_root"'):
        own_properties = prim_own_properties(layer_text, declaration)
        if "xformOp:" in own_properties or "xformOpOrder" in own_properties:
            raise RuntimeError(f"canonical root must use an identity transform: {declaration}")

    mesh_names = set(re.findall(r'\bdef Mesh "([^"]+)"', layer_text))
    if mesh_names != EXPECTED_MESH_NAMES:
        missing = sorted(EXPECTED_MESH_NAMES - mesh_names)
        unexpected = sorted(mesh_names - EXPECTED_MESH_NAMES)
        raise RuntimeError(f"unstable Mesh prim names; missing={missing}, unexpected={unexpected}")
    for mesh_name in EXPECTED_MESH_NAMES:
        if f'def Xform "{mesh_name}"' in layer_text:
            raise RuntimeError(f"body entity is an Xform wrapper instead of an actual Mesh prim: {mesh_name}")

    y_extents: list[float] = []
    for lower, upper in re.findall(
        r"float3\[\] extent = \[\([^,]+, ([^,]+), [^)]+\), \([^,]+, ([^,]+), [^)]+\)\]",
        layer_text,
    ):
        y_extents.extend((float(lower), float(upper)))
    y_translations = [
        float(value)
        for value in re.findall(r"double3 xformOp:translate = \([^,]+, ([^,]+), [^)]+\)", layer_text)
    ]
    if not y_extents or not y_translations:
        raise RuntimeError("packaged USD is missing canonical Y bounds")
    # Each Mesh extent is local and each display Mesh carries one Y translation.
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
            raise RuntimeError("packaged Mesh is missing local extent or canonical translation")
        translation_y = float(translation_match.group(1))
        world_y_bounds.extend((translation_y + float(extent_match.group(1)), translation_y + float(extent_match.group(2))))
    if abs(min(world_y_bounds) - CANONICAL_GROUND_Y_METERS) > 1e-5:
        raise RuntimeError(f"canonical ground changed: {min(world_y_bounds)}")
    if abs(max(world_y_bounds) - CANONICAL_HEIGHT_METERS) > 1e-5:
        raise RuntimeError(f"canonical height changed: {max(world_y_bounds)}")

    face_count_arrays = re.findall(r"int\[\] faceVertexCounts = \[(.*?)\]", layer_text, flags=re.DOTALL)
    triangle_count = 0
    for values in face_count_arrays:
        counts = [int(value) for value in re.findall(r"\d+", values)]
        if any(count != 3 for count in counts):
            raise RuntimeError("packaged USD contains a non-triangulated Mesh")
        triangle_count += len(counts)
    if triangle_count != expected_triangle_count:
        raise RuntimeError(
            f"packaged triangle count changed: expected {expected_triangle_count}, read {triangle_count}"
        )

    return hashlib.sha256(path.read_bytes()).hexdigest()


def material(name: str, color: tuple[float, float, float, float]) -> bpy.types.Material:
    value = bpy.data.materials.new(name)
    value.diffuse_color = color
    value.use_nodes = True
    principled = value.node_tree.nodes.get("Principled BSDF")
    if principled is not None:
        principled.inputs["Base Color"].default_value = color
        principled.inputs["Roughness"].default_value = 0.7
    return value


def smooth(obj: bpy.types.Object) -> None:
    if obj.type == "MESH":
        for polygon in obj.data.polygons:
            polygon.use_smooth = True


def triangulate(obj: bpy.types.Object) -> None:
    """Replace polygons with a deterministic fan triangulation.

    Blender's USD triangulation and Triangulate modifier may schedule faces in
    different orders between processes. Rebuilding the Mesh from sorted face
    records fixes the triangle index contract while retaining the active UV map.
    """
    source_mesh = obj.data
    source_vertices = [tuple(vertex.co) for vertex in source_mesh.vertices]
    source_uv_layer = source_mesh.uv_layers.active
    records: list[tuple[tuple[int, int, int], tuple[tuple[float, float], ...] | None, int, bool]] = []

    for polygon in source_mesh.polygons:
        vertices = list(polygon.vertices)
        loop_indices = list(polygon.loop_indices)
        if len(vertices) < 3:
            continue
        for offset in range(1, len(vertices) - 1):
            triangle = (vertices[0], vertices[offset], vertices[offset + 1])
            uv_values = None
            if source_uv_layer is not None:
                selected_loops = (loop_indices[0], loop_indices[offset], loop_indices[offset + 1])
                uv_values = tuple(
                    tuple(round(float(component), 6) for component in source_uv_layer.data[index].uv)
                    for index in selected_loops
                )

            rotations = (
                (triangle, uv_values),
                ((triangle[1], triangle[2], triangle[0]), None if uv_values is None else (uv_values[1], uv_values[2], uv_values[0])),
                ((triangle[2], triangle[0], triangle[1]), None if uv_values is None else (uv_values[2], uv_values[0], uv_values[1])),
            )
            stable_triangle, stable_uv_values = min(rotations, key=lambda value: value[0])
            records.append((stable_triangle, stable_uv_values, polygon.material_index, polygon.use_smooth))

    records.sort(key=lambda value: value[0])
    rebuilt_mesh = bpy.data.meshes.new(source_mesh.name)
    rebuilt_mesh.from_pydata(source_vertices, [], [record[0] for record in records])
    rebuilt_mesh.update()
    if source_uv_layer is not None:
        rebuilt_uv_layer = rebuilt_mesh.uv_layers.new(name=source_uv_layer.name)
        for polygon, record in zip(rebuilt_mesh.polygons, records, strict=True):
            uv_values = record[1]
            if uv_values is None:
                continue
            for loop_index, uv_value in zip(polygon.loop_indices, uv_values, strict=True):
                rebuilt_uv_layer.data[loop_index].uv = uv_value
    for polygon, record in zip(rebuilt_mesh.polygons, records, strict=True):
        polygon.material_index = record[2]
        polygon.use_smooth = record[3]

    obj.data = rebuilt_mesh
    if source_mesh.users == 0:
        bpy.data.meshes.remove(source_mesh)
    rebuilt_mesh.name = obj.name


def add_sphere(name: str, location: tuple[float, float, float], scale: tuple[float, float, float], mat: bpy.types.Material) -> None:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=20, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    triangulate(obj)
    obj.data.materials.append(mat)
    smooth(obj)


def add_box(name: str, location: tuple[float, float, float], scale: tuple[float, float, float], mat: bpy.types.Material) -> None:
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bevel = obj.modifiers.new("soft_edges", "BEVEL")
    bevel.width = min(scale) * 0.35
    bevel.segments = 3
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    triangulate(obj)
    obj.data.materials.append(mat)
    smooth(obj)


def add_limb(name: str, start: tuple[float, float, float], end: tuple[float, float, float], radius: float, mat: bpy.types.Material) -> None:
    a = Vector(start)
    b = Vector(end)
    direction = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=radius, depth=direction.length, location=(a + b) / 2)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(direction.normalized())
    triangulate(obj)
    obj.data.materials.append(mat)
    smooth(obj)


def main() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)

    skin = material("neutral_body_surface", (0.68, 0.78, 0.84, 1.0))
    skin_shadow = material("neutral_body_shadow", (0.48, 0.63, 0.72, 1.0))
    accent = material("neutral_body_accent", (0.35, 0.55, 0.68, 1.0))
    joint = material("neutral_body_joint", (0.30, 0.46, 0.58, 1.0))

    # Geometry is authored directly in the documented canonical coordinates:
    # +Y up, +Z anterior, +X user's right, metres, feet on y=0. Blender's
    # stage metadata is patched to Y-up after export; no compensating root
    # rotation is allowed.
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0
    add_sphere("body_head", (0, 1.72, 0), (0.115, 0.14, 0.105), skin)
    add_limb("body_neck", (0, 1.56, 0), (0, 1.64, 0), 0.065, skin)
    add_sphere("body_torso", (0, 1.28, 0), (0.22, 0.30, 0.13), skin)
    add_sphere("body_abdomen", (0, 1.08, 0.005), (0.17, 0.18, 0.125), skin_shadow)
    add_sphere("body_lower_back", (0, 1.08, -0.105), (0.14, 0.16, 0.055), skin_shadow)
    add_sphere("body_pelvis", (0, 0.92, 0), (0.18, 0.14, 0.13), accent)

    # Segmented display volumes make the map readable without claiming
    # clinically precise muscle boundaries. The names are stable UI entities.
    for side, x in (("left", -1), ("right", 1)):
        sign = float(x)
        add_sphere(f"body_{side}_shoulder", (sign * 0.225, 1.47, 0), (0.09, 0.10, 0.095), skin)
        add_sphere(f"body_{side}_chest", (sign * 0.09, 1.34, 0.09), (0.115, 0.13, 0.055), skin)
        add_sphere(f"body_{side}_upper_back", (sign * 0.09, 1.34, -0.09), (0.115, 0.13, 0.055), skin_shadow)
        add_sphere(f"body_{side}_hip", (sign * 0.105, 0.96, 0), (0.095, 0.11, 0.115), accent)

    for side, x in (("left", -1), ("right", 1)):
        x = x * 0.24
        add_limb(f"body_{side}_upper_arm", (x * 0.84, 1.48, 0), (x * 1.03, 1.18, 0), 0.06, skin)
        add_sphere(f"body_{side}_elbow", (x * 1.03, 1.17, 0), (0.065, 0.065, 0.06), joint)
        add_limb(f"body_{side}_forearm", (x * 1.03, 1.18, 0), (x * 1.08, 0.90, 0), 0.048, skin)
        add_sphere(f"body_{side}_hand", (x * 1.08, 0.84, 0), (0.055, 0.08, 0.045), skin)
        add_limb(f"body_{side}_thigh", (x * 0.62, 0.88, 0), (x * 0.62, 0.48, 0), 0.09, skin)
        add_sphere(f"body_{side}_knee", (x * 0.62, 0.42, 0), (0.09, 0.075, 0.08), joint)
        add_limb(f"body_{side}_calf", (x * 0.62, 0.36, 0), (x * 0.62, 0.08, 0), 0.065, skin)
        add_box(f"body_{side}_foot", (x * 0.62, 0.035, 0.05), (0.075, 0.035, 0.14), skin)

    # A root makes the coordinate contract explicit and keeps child IDs stable.
    root = bpy.data.objects.new("body_root", None)
    bpy.context.collection.objects.link(root)
    for obj in list(bpy.context.scene.objects):
        if obj != root:
            obj.parent = root
    root["asset_id"] = ASSET_ID
    root["asset_version"] = ASSET_VERSION
    root["topology_id"] = TOPOLOGY_ID
    root["ontology_version"] = "body-ontology-prototype-v1"
    root["coordinate_convention"] = "realitykit_y_up_right_handed"
    root["source"] = "original project-generated segmented neutral prototype"
    root["medical_meaning"] = "none; visual location expression only"

    triangle_count = sum(
        max(len(polygon.vertices) - 2, 0)
        for obj in bpy.context.scene.objects
        if obj.type == "MESH"
        for polygon in obj.data.polygons
    )
    print(f"candidate triangle_count={triangle_count}")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="body-neutral-procedural-") as temporary_directory:
        staging_directory = Path(temporary_directory)
        source_usda = staging_directory / "BodyNeutralPrototype.usda"
        staged_usdz = staging_directory / OUTPUT.name
        bpy.ops.wm.usd_export(
            filepath=str(source_usda),
            selected_objects_only=False,
            export_animation=False,
            export_uvmaps=True,
            export_normals=True,
            export_materials=True,
            export_custom_properties=True,
            author_blender_name=False,
            convert_orientation=False,
            root_prim_path="/BodyCompanion",
            generate_preview_surface=True,
            convert_scene_units="METERS",
            meters_per_unit=1.0,
            triangulate_meshes=False,
            merge_parent_xform=True,
            relative_paths=True,
        )

        source_text = source_usda.read_text(encoding="utf-8")
        if source_text.count('upAxis = "Z"') != 1:
            raise RuntimeError("Blender USDA did not contain the expected Z-up stage metadata")
        source_text = source_text.replace('upAxis = "Z"', 'upAxis = "Y"')
        source_text = sort_direct_child_prims(source_text, 'def Xform "body_root"')
        source_text = sort_direct_child_prims(source_text, 'def Scope "_materials"')
        source_text = sort_direct_child_prims(source_text, 'def Xform "BodyCompanion"', materials_last=True)
        source_usda.write_text(source_text, encoding="utf-8")

        # usdzip owns USDZ entry ordering, storage and 64-byte payload alignment.
        run_tool("usdzip", "--arkitAsset", str(source_usda), str(staged_usdz))
        normalize_usdz_timestamps_in_place(staged_usdz)
        digest = verify_packaged_asset(staged_usdz, triangle_count)
        shutil.copyfile(staged_usdz, OUTPUT)

    print(f"generated {OUTPUT}")
    print(f"candidate sha256={digest}")


if __name__ == "__main__":
    main()
