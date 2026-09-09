"""
Build low-poly environment props for Nuclear Winter: crate, wardrobe, couch.
Exports individual GLBs for Godot and a combined preview blend/render.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy

OUT_DIR = Path("/workspace/godot/assets/props")
BLEND_OUT = Path("/workspace/blender/furniture_props.blend")
PNG_OUT = Path("/opt/cursor/artifacts/blender_furniture_props.png")

PROP_NAMES = ("crate", "wardrobe", "couch")


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in list(bpy.data.meshes):
        bpy.data.meshes.remove(block)
    for block in list(bpy.data.materials):
        bpy.data.materials.remove(block)
    for block in list(bpy.data.collections):
        if block.name != "Collection":
            bpy.data.collections.remove(block)


def mat(name: str, color: tuple[float, float, float, float], roughness: float = 0.65):
    m = bpy.data.materials.new(name=name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = roughness
    return m


def add_cube(name: str, loc, scale, material, parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if obj.data.materials:
        obj.data.materials[0] = material
    else:
        obj.data.materials.append(material)
    if parent is not None:
        obj.parent = parent
    return obj


def add_cylinder(name: str, loc, radius: float, depth: float, material, parent=None, vertices: int = 12):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    if obj.data.materials:
        obj.data.materials[0] = material
    else:
        obj.data.materials.append(material)
    if parent is not None:
        obj.parent = parent
    return obj


def make_root(name: str):
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 0, 0))
    root = bpy.context.active_object
    root.name = name
    return root


def build_crate(wood, metal):
    root = make_root("Crate")
    # Main box ~0.9m cube, sitting on floor
    add_cube("CrateBody", (0, 0, 0.45), (0.9, 0.9, 0.9), wood, root)
    # Corner posts
    for sx, sy in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
        add_cube(
            f"Post_{sx}_{sy}",
            (sx * 0.42, sy * 0.42, 0.45),
            (0.08, 0.08, 0.92),
            wood,
            root,
        )
    # Horizontal straps
    for z in (0.18, 0.72):
        add_cube(f"StrapX_a_{z}", (0, -0.42, z), (0.86, 0.06, 0.08), metal, root)
        add_cube(f"StrapX_b_{z}", (0, 0.42, z), (0.86, 0.06, 0.08), metal, root)
        add_cube(f"StrapY_a_{z}", (-0.42, 0, z), (0.06, 0.86, 0.08), metal, root)
        add_cube(f"StrapY_b_{z}", (0.42, 0, z), (0.06, 0.86, 0.08), metal, root)
    # Lid seam
    add_cube("Lid", (0, 0, 0.92), (0.88, 0.88, 0.06), wood, root)
    return root


def build_wardrobe(wood, paint, metal):
    root = make_root("Wardrobe")
    # Tall cabinet ~2.1m
    add_cube("Cabinet", (0, 0, 1.05), (1.1, 0.55, 2.1), paint, root)
    # Back panel slightly darker wood
    add_cube("Back", (0, 0.26, 1.05), (1.05, 0.04, 2.05), wood, root)
    # Twin doors
    add_cube("Door_L", (-0.28, -0.28, 1.05), (0.48, 0.04, 1.9), wood, root)
    add_cube("Door_R", (0.28, -0.28, 1.05), (0.48, 0.04, 1.9), wood, root)
    # Door trim / center stile
    add_cube("Stile", (0, -0.3, 1.05), (0.05, 0.03, 1.92), wood, root)
    # Handles
    add_cube("Handle_L", (-0.08, -0.34, 1.05), (0.04, 0.05, 0.14), metal, root)
    add_cube("Handle_R", (0.08, -0.34, 1.05), (0.04, 0.05, 0.14), metal, root)
    # Base plinth
    add_cube("Plinth", (0, 0, 0.06), (1.14, 0.58, 0.12), wood, root)
    # Crown molding
    add_cube("Crown", (0, 0, 2.12), (1.16, 0.58, 0.08), wood, root)
    return root


def build_couch(fabric, wood, cushion):
    root = make_root("Couch")
    # Seat base
    add_cube("SeatBase", (0, 0, 0.28), (2.0, 0.9, 0.36), fabric, root)
    # Seat cushions
    add_cube("Cushion_L", (-0.5, -0.05, 0.52), (0.9, 0.78, 0.16), cushion, root)
    add_cube("Cushion_R", (0.5, -0.05, 0.52), (0.9, 0.78, 0.16), cushion, root)
    # Backrest
    add_cube("Backrest", (0, 0.38, 0.85), (2.0, 0.22, 0.9), fabric, root)
    # Arms
    add_cube("Arm_L", (-1.05, 0, 0.55), (0.18, 0.9, 0.7), fabric, root)
    add_cube("Arm_R", (1.05, 0, 0.55), (0.18, 0.9, 0.7), fabric, root)
    # Wooden legs
    for sx, sy, name in (
        (-0.85, -0.35, "Leg_FL"),
        (0.85, -0.35, "Leg_FR"),
        (-0.85, 0.35, "Leg_BL"),
        (0.85, 0.35, "Leg_BR"),
    ):
        add_cylinder(name, (sx, sy, 0.08), 0.05, 0.16, wood, root, vertices=8)
    # Throw pillows
    add_cube("Pillow_L", (-0.7, 0.15, 0.95), (0.35, 0.18, 0.35), cushion, root)
    add_cube("Pillow_R", (0.7, 0.15, 0.95), (0.35, 0.18, 0.35), cushion, root)
    return root


def export_prop(root, glb_path: Path) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for obj in root.children_recursive:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )


def layout_for_preview(crate, wardrobe, couch) -> None:
    crate.location = (-2.4, 0, 0)
    wardrobe.location = (0, 0, 0)
    couch.location = (2.6, 0, 0)

    bpy.ops.object.camera_add(location=(5.5, -7.5, 3.8))
    cam = bpy.context.active_object
    cam.name = "PreviewCam"
    cam.rotation_euler = (math.radians(68), 0, math.radians(35))
    bpy.context.scene.camera = cam

    bpy.ops.object.light_add(type="AREA", location=(1.5, -3.0, 5.0))
    light = bpy.context.active_object
    light.name = "KeyLight"
    light.data.energy = 800
    light.data.size = 5

    bpy.ops.object.light_add(type="SUN", location=(4, -6, 8))
    sun = bpy.context.active_object
    sun.name = "Sun"
    sun.data.energy = 1.5
    sun.rotation_euler = (math.radians(45), math.radians(10), math.radians(25))

    # Ground plane for preview
    wood_floor = mat("PreviewFloor", (0.55, 0.78, 0.62, 1.0), 0.8)
    add_cube("PreviewFloor", (0, 0, -0.02), (10, 6, 0.04), wood_floor)


def render_preview() -> None:
    scene = bpy.context.scene
    # Prefer Cycles CPU for headless cloud agents without EGL/GPU.
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 32
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.filepath = str(PNG_OUT)
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.45, 0.62, 0.82, 1.0)
        bg.inputs[1].default_value = 0.85
    bpy.ops.render.render(write_still=True)


def main() -> None:
    clear_scene()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    BLEND_OUT.parent.mkdir(parents=True, exist_ok=True)
    PNG_OUT.parent.mkdir(parents=True, exist_ok=True)

    wood = mat("Wood", (0.42, 0.28, 0.16, 1.0), 0.7)
    metal = mat("Metal", (0.35, 0.36, 0.38, 1.0), 0.35)
    paint = mat("CabinetPaint", (0.62, 0.58, 0.48, 1.0), 0.55)
    fabric = mat("CouchFabric", (0.28, 0.32, 0.38, 1.0), 0.85)
    cushion = mat("Cushion", (0.45, 0.40, 0.34, 1.0), 0.9)
    wardrobe_wood = mat("WardrobeWood", (0.38, 0.24, 0.14, 1.0), 0.6)

    crate = build_crate(wood, metal)
    wardrobe = build_wardrobe(wardrobe_wood, paint, metal)
    couch = build_couch(fabric, wood, cushion)

    # Export each prop at origin before preview layout offset.
    export_prop(crate, OUT_DIR / "crate.glb")
    export_prop(wardrobe, OUT_DIR / "wardrobe.glb")
    export_prop(couch, OUT_DIR / "couch.glb")

    layout_for_preview(crate, wardrobe, couch)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
    render_preview()

    for name in PROP_NAMES:
        print(f"Wrote {OUT_DIR / (name + '.glb')}")
    print(f"Wrote {BLEND_OUT}")
    print(f"Wrote {PNG_OUT}")


if __name__ == "__main__":
    main()
