"""
Build a simple low-poly humanoid (gulag-scavenger style) in Blender and export GLB.
Root at feet, +Y up for Godot.
"""

from __future__ import annotations

from pathlib import Path

import bpy

OUT_DIR = Path("/workspace/godot/assets/characters")
BLEND_OUT = Path("/workspace/blender/humanoid_scavenger.blend")
GLB_OUT = OUT_DIR / "humanoid_scavenger.glb"
PNG_OUT = Path("/opt/cursor/artifacts/blender_humanoid.png")


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in list(bpy.data.meshes):
        bpy.data.meshes.remove(block)
    for block in list(bpy.data.materials):
        bpy.data.materials.remove(block)
    for block in list(bpy.data.armatures):
        bpy.data.armatures.remove(block)
    for block in list(bpy.data.actions):
        bpy.data.actions.remove(block)


def mat(name: str, color: tuple[float, float, float, float]):
    m = bpy.data.materials.new(name=name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = 0.65
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


def add_uv_sphere(name: str, loc, radius: float, material, parent=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=radius, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    if obj.data.materials:
        obj.data.materials[0] = material
    else:
        obj.data.materials.append(material)
    if parent is not None:
        obj.parent = parent
    return obj


def build_humanoid():
    skin = mat("Skin", (0.72, 0.55, 0.42, 1.0))
    tunic = mat("Tunic", (0.42, 0.34, 0.24, 1.0))
    pants = mat("Pants", (0.28, 0.26, 0.22, 1.0))
    boots = mat("Boots", (0.16, 0.12, 0.10, 1.0))
    scarf = mat("Scarf", (0.35, 0.35, 0.32, 1.0))

    # Root empty at feet (world origin). Godot CharacterBody origin at feet.
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 0, 0))
    root = bpy.context.active_object
    root.name = "HumanoidRoot"

    # Proportions ~1.8m tall
    pelvis = add_cube("Pelvis", (0, 0, 0.95), (0.38, 0.22, 0.18), pants, root)
    torso = add_cube("Torso", (0, 0, 1.35), (0.42, 0.24, 0.55), tunic, root)
    add_cube("Scarf", (0, 0.02, 1.62), (0.34, 0.28, 0.12), scarf, root)

    head = add_uv_sphere("Head", (0, 0, 1.88), 0.18, skin, root)
    # Bald look: slight flatten
    head.scale = (1.0, 0.95, 1.05)
    bpy.context.view_layer.objects.active = head
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    # Arms (pivots near shoulders; mesh centered on limb)
    l_arm = add_cylinder("Arm_L", (-0.34, 0, 1.35), 0.07, 0.55, tunic, root)
    r_arm = add_cylinder("Arm_R", (0.34, 0, 1.35), 0.07, 0.55, tunic, root)
    # Hands
    add_uv_sphere("Hand_L", (-0.34, 0, 1.05), 0.07, skin, root)
    add_uv_sphere("Hand_R", (0.34, 0, 1.05), 0.07, skin, root)

    # Legs
    l_leg = add_cylinder("Leg_L", (-0.14, 0, 0.55), 0.09, 0.7, pants, root)
    r_leg = add_cylinder("Leg_R", (0.14, 0, 0.55), 0.09, 0.7, pants, root)
    add_cube("Boot_L", (-0.14, 0.04, 0.12), (0.16, 0.28, 0.14), boots, root)
    add_cube("Boot_R", (0.14, 0.04, 0.12), (0.16, 0.28, 0.14), boots, root)

    # Mark limb pivots via custom empty parents for clearer animation targets
    # Re-parent arms/legs under pivot empties at joints.
    def make_pivot(name: str, loc, child_objs):
        bpy.ops.object.empty_add(type="PLAIN_AXES", location=loc)
        pivot = bpy.context.active_object
        pivot.name = name
        pivot.parent = root
        for child in child_objs:
            # Keep world transform while reparenting
            mw = child.matrix_world.copy()
            child.parent = pivot
            child.matrix_world = mw
        return pivot

    make_pivot("Pivot_Arm_L", (-0.34, 0, 1.55), [l_arm])
    make_pivot("Pivot_Arm_R", (0.34, 0, 1.55), [r_arm])
    make_pivot("Pivot_Leg_L", (-0.14, 0, 0.9), [l_leg])
    make_pivot("Pivot_Leg_R", (0.14, 0, 0.9), [r_leg])

    # Face +Y forward in Blender (export Y-up -> Godot -Z forward typically with glTF).
    # Small nose marker so facing is obvious.
    add_cube("Nose", (0, 0.16, 1.88), (0.05, 0.08, 0.05), skin, root)

    return root


def export_assets(root) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    BLEND_OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))

    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for obj in root.children_recursive:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root

    bpy.ops.export_scene.gltf(
        filepath=str(GLB_OUT),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )

    # Preview render
    bpy.ops.object.camera_add(location=(2.4, -3.2, 2.2))
    cam = bpy.context.active_object
    cam.rotation_euler = (1.1, 0.0, 0.6)
    bpy.context.scene.camera = cam
    bpy.ops.object.light_add(type="AREA", location=(1.5, -2.0, 3.5))
    light = bpy.context.active_object
    light.data.energy = 400
    light.data.size = 3

    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except Exception:
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    scene.render.filepath = str(PNG_OUT)
    # Soft blue backdrop
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.45, 0.62, 0.82, 1.0)
        bg.inputs[1].default_value = 0.8
    bpy.ops.render.render(write_still=True)
    print(f"Wrote {GLB_OUT}")
    print(f"Wrote {PNG_OUT}")


def main() -> None:
    clear_scene()
    root = build_humanoid()
    export_assets(root)


if __name__ == "__main__":
    main()
