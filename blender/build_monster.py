"""
Build a simple low-poly nuclear-winter monster in Blender and export GLB.
Root at feet, +Y up for Godot. Hunched biped with long arms and glowing eyes.
"""

from __future__ import annotations

from pathlib import Path

import bpy

OUT_DIR = Path("/workspace/godot/assets/characters")
BLEND_OUT = Path("/workspace/blender/enemy_monster.blend")
GLB_OUT = OUT_DIR / "enemy_monster.glb"
PNG_OUT = Path("/opt/cursor/artifacts/blender_enemy_monster.png")


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


def mat(name: str, color: tuple[float, float, float, float], emission=None):
    m = bpy.data.materials.new(name=name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = 0.72
        if emission is not None:
            if "Emission Color" in bsdf.inputs:
                bsdf.inputs["Emission Color"].default_value = emission
            elif "Emission" in bsdf.inputs:
                bsdf.inputs["Emission"].default_value = emission
            if "Emission Strength" in bsdf.inputs:
                bsdf.inputs["Emission Strength"].default_value = 4.0
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


def add_cylinder(name: str, loc, radius: float, depth: float, material, parent=None, vertices: int = 10):
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
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=radius, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    if obj.data.materials:
        obj.data.materials[0] = material
    else:
        obj.data.materials.append(material)
    if parent is not None:
        obj.parent = parent
    return obj


def build_monster():
    hide = mat("Hide", (0.28, 0.34, 0.22, 1.0))
    belly = mat("Belly", (0.38, 0.32, 0.24, 1.0))
    claw = mat("Claw", (0.55, 0.52, 0.45, 1.0))
    eye = mat("EyeGlow", (0.15, 0.05, 0.02, 1.0), emission=(1.0, 0.25, 0.05, 1.0))
    horn = mat("Horn", (0.18, 0.16, 0.14, 1.0))

    bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 0, 0))
    root = bpy.context.active_object
    root.name = "MonsterRoot"

    # Hunched ~2.1m silhouette, leaning slightly forward (+Y).
    add_cube("Pelvis", (0, 0.05, 0.85), (0.48, 0.32, 0.28), hide, root)
    add_cube("Torso", (0, 0.12, 1.35), (0.55, 0.38, 0.62), hide, root)
    add_cube("Belly", (0, 0.22, 1.15), (0.42, 0.28, 0.35), belly, root)
    add_cube("Shoulders", (0, 0.08, 1.62), (0.72, 0.28, 0.22), hide, root)

    head = add_uv_sphere("Head", (0, 0.28, 1.95), 0.26, hide, root)
    head.scale = (1.05, 1.15, 0.95)
    bpy.context.view_layer.objects.active = head
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    add_cube("Jaw", (0, 0.42, 1.82), (0.28, 0.22, 0.12), hide, root)
    add_cube("Snout", (0, 0.48, 1.92), (0.18, 0.16, 0.12), hide, root)
    add_uv_sphere("Eye_L", (-0.12, 0.46, 2.02), 0.055, eye, root)
    add_uv_sphere("Eye_R", (0.12, 0.46, 2.02), 0.055, eye, root)
    add_cylinder("Horn_L", (-0.18, 0.18, 2.22), 0.04, 0.28, horn, root)
    add_cylinder("Horn_R", (0.18, 0.18, 2.22), 0.04, 0.28, horn, root)

    # Long dangling arms
    l_arm = add_cylinder("Arm_L", (-0.48, 0.05, 1.15), 0.09, 0.95, hide, root)
    r_arm = add_cylinder("Arm_R", (0.48, 0.05, 1.15), 0.09, 0.95, hide, root)
    add_cube("Claw_L", (-0.48, 0.12, 0.58), (0.18, 0.22, 0.10), claw, root)
    add_cube("Claw_R", (0.48, 0.12, 0.58), (0.18, 0.22, 0.10), claw, root)

    l_leg = add_cylinder("Leg_L", (-0.16, 0.0, 0.45), 0.11, 0.72, hide, root)
    r_leg = add_cylinder("Leg_R", (0.16, 0.0, 0.45), 0.11, 0.72, hide, root)
    add_cube("Foot_L", (-0.16, 0.1, 0.1), (0.18, 0.32, 0.12), claw, root)
    add_cube("Foot_R", (0.16, 0.1, 0.1), (0.18, 0.32, 0.12), claw, root)

    def make_pivot(name: str, loc, child_objs):
        bpy.ops.object.empty_add(type="PLAIN_AXES", location=loc)
        pivot = bpy.context.active_object
        pivot.name = name
        pivot.parent = root
        for child in child_objs:
            mw = child.matrix_world.copy()
            child.parent = pivot
            child.matrix_world = mw
        return pivot

    make_pivot("Pivot_Arm_L", (-0.48, 0.05, 1.62), [l_arm])
    make_pivot("Pivot_Arm_R", (0.48, 0.05, 1.62), [r_arm])
    make_pivot("Pivot_Leg_L", (-0.16, 0.0, 0.82), [l_leg])
    make_pivot("Pivot_Leg_R", (0.16, 0.0, 0.82), [r_leg])

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

    bpy.ops.object.camera_add(location=(3.0, -3.6, 2.4))
    cam = bpy.context.active_object
    cam.rotation_euler = (1.1, 0.0, 0.7)
    bpy.context.scene.camera = cam
    bpy.ops.object.light_add(type="AREA", location=(1.8, -2.2, 3.8))
    light = bpy.context.active_object
    light.data.energy = 450
    light.data.size = 3

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 32
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    scene.render.filepath = str(PNG_OUT)
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.18, 0.22, 0.28, 1.0)
        bg.inputs[1].default_value = 0.55
    try:
        bpy.ops.render.render(write_still=True)
        print(f"Wrote {PNG_OUT}")
    except Exception as exc:
        print(f"Preview render skipped: {exc}")
    print(f"Wrote {GLB_OUT}")


def main() -> None:
    clear_scene()
    root = build_monster()
    export_assets(root)


if __name__ == "__main__":
    main()
