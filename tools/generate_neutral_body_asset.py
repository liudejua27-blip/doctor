"""Generate the original internal neutral body prototype asset.

This is intentionally a low-detail, non-anatomical display model. It is not
derived from RehabMate or any third-party mesh. The generated USDZ remains an
internal candidate until the asset, anatomy, performance and accessibility
gates in FEAT-BODY-MAP-V1 are signed off.
"""

from __future__ import annotations

import math
import zipfile
from pathlib import Path

import bpy
from mathutils import Vector


OUTPUT = Path(__file__).resolve().parents[1] / "ios/BodyCompanion/Sources/BodyCompanionIOS/Resources/BodyNeutralPrototype.usdz"


def canonicalize_usdz(path: Path) -> None:
    """Rewrite USDZ container metadata with fixed timestamps and mode bits."""
    temporary = path.with_suffix(".canonical.usdz")
    with zipfile.ZipFile(path, "r") as source:
        entries = [(info.filename, source.read(info)) for info in source.infolist()]
    with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_STORED) as destination:
        for name, payload in sorted(entries):
            info = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_STORED
            info.create_system = 3
            info.external_attr = 0o644 << 16
            destination.writestr(info, payload)
    temporary.replace(path)


def material(name: str, color: tuple[float, float, float, float]) -> bpy.types.Material:
    value = bpy.data.materials.new(name)
    value.diffuse_color = color
    value.use_nodes = True
    principled = value.node_tree.nodes.get("Principled BSDF")
    if principled is not None:
        principled.inputs["Base Color"].default_value = color
        principled.inputs["Roughness"].default_value = 0.7
    return value


def add_sphere(name: str, location: tuple[float, float, float], scale: tuple[float, float, float], mat: bpy.types.Material) -> None:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)


def add_box(name: str, location: tuple[float, float, float], scale: tuple[float, float, float], mat: bpy.types.Material) -> None:
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bevel = obj.modifiers.new("soft_edges", "BEVEL")
    bevel.width = min(scale) * 0.35
    bevel.segments = 3
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    obj.data.materials.append(mat)


def add_limb(name: str, start: tuple[float, float, float], end: tuple[float, float, float], radius: float, mat: bpy.types.Material) -> None:
    a = Vector(start)
    b = Vector(end)
    direction = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=radius, depth=direction.length, location=(a + b) / 2)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(direction.normalized())
    obj.data.materials.append(mat)


def main() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)

    skin = material("neutral_body_surface", (0.68, 0.78, 0.84, 1.0))
    accent = material("neutral_body_accent", (0.35, 0.55, 0.68, 1.0))

    # Blender uses Z-up; the USD export converts to the documented RealityKit
    # Y-up convention. Dimensions are metres, with the feet on z=0.
    add_sphere("body_head", (0, 0, 1.72), (0.105, 0.105, 0.13), skin)
    add_limb("body_neck", (0, 0, 1.56), (0, 0, 1.64), 0.065, skin)
    add_box("body_torso", (0, 0, 1.28), (0.20, 0.12, 0.28), skin)
    add_box("body_pelvis", (0, 0, 0.92), (0.17, 0.11, 0.12), accent)

    for side, x in (("left", -1), ("right", 1)):
        x = x * 0.24
        add_limb(f"body_{side}_upper_arm", (x * 0.84, 0, 1.48), (x * 1.03, 0, 1.18), 0.055, skin)
        add_limb(f"body_{side}_forearm", (x * 1.03, 0, 1.18), (x * 1.08, 0, 0.90), 0.045, skin)
        add_sphere(f"body_{side}_hand", (x * 1.08, 0, 0.84), (0.055, 0.045, 0.08), skin)
        add_limb(f"body_{side}_thigh", (x * 0.62, 0, 0.88), (x * 0.62, 0, 0.48), 0.085, skin)
        add_sphere(f"body_{side}_knee", (x * 0.62, 0, 0.42), (0.09, 0.08, 0.07), accent)
        add_limb(f"body_{side}_calf", (x * 0.62, 0, 0.36), (x * 0.62, 0, 0.08), 0.06, skin)
        add_box(f"body_{side}_foot", (x * 0.62, -0.05, 0.035), (0.075, 0.14, 0.035), skin)

    # A root makes the coordinate contract explicit and keeps child IDs stable.
    root = bpy.data.objects.new("body_root", None)
    bpy.context.collection.objects.link(root)
    for obj in list(bpy.context.scene.objects):
        if obj != root:
            obj.parent = root
    root["asset_id"] = "body-neutral-procedural-v1"
    root["asset_version"] = "1.0.0"
    root["ontology_version"] = "body-ontology-prototype-v1"
    root["coordinate_convention"] = "realitykit_y_up_right_handed"
    root["source"] = "original project-generated low-detail prototype"
    root["medical_meaning"] = "none; visual location expression only"

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.usd_export(
        filepath=str(OUTPUT),
        selected_objects_only=False,
        export_animation=False,
        export_uvmaps=True,
        export_normals=True,
        export_materials=True,
        convert_orientation=True,
        export_global_forward_selection="NEGATIVE_Z",
        export_global_up_selection="Y",
        root_prim_path="/BodyCompanion",
        generate_preview_surface=True,
        convert_scene_units="METERS",
        meters_per_unit=1.0,
        triangulate_meshes=True,
    )
    canonicalize_usdz(OUTPUT)
    print(f"generated {OUTPUT}")


if __name__ == "__main__":
    main()
