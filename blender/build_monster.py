"""
Build a monstrous green hare (Level 1 enemy) in Blender and export GLB.

Root at the feet, +Y forward / +Z up in Blender. glTF export is Y-up for Godot.
Hunched biped with long ears, red eyes, an open maw, spindly arms and
digitigrade legs — the same silhouette as the reference creature.
"""

from __future__ import annotations

from pathlib import Path

import bpy
from mathutils import Vector

OUT_DIR = Path("/workspace/godot/assets/characters")
BLEND_OUT = Path("/workspace/blender/enemy_monster.blend")
GLB_OUT = OUT_DIR / "enemy_monster.glb"
PNG_OUT = Path("/opt/cursor/artifacts/level1_hare_monster_blender.png")


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


def mat(
    name: str,
    color: tuple[float, float, float, float],
    *,
    roughness: float = 0.78,
    emission=None,
    emission_strength: float = 5.0,
    sheen: float = 0.0,
):
    m = bpy.data.materials.new(name=name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = roughness
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = 0.0
        if emission is not None:
            if "Emission Color" in bsdf.inputs:
                bsdf.inputs["Emission Color"].default_value = emission
            elif "Emission" in bsdf.inputs:
                bsdf.inputs["Emission"].default_value = emission
            if "Emission Strength" in bsdf.inputs:
                bsdf.inputs["Emission Strength"].default_value = emission_strength
        if sheen > 0.0 and "Sheen Weight" in bsdf.inputs:
            bsdf.inputs["Sheen Weight"].default_value = sheen
            if "Sheen Roughness" in bsdf.inputs:
                bsdf.inputs["Sheen Roughness"].default_value = 0.72
            if "Sheen Color" in bsdf.inputs:
                bsdf.inputs["Sheen Color"].default_value = color
    return m


def _select(obj) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply_rot_scale(obj) -> None:
    _select(obj)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def shade_smooth(obj) -> None:
    mesh = getattr(obj, "data", None)
    if mesh is None or not hasattr(mesh, "polygons"):
        return
    for poly in mesh.polygons:
        poly.use_smooth = True


def assign_mat(obj, material) -> None:
    if obj.data.materials:
        obj.data.materials[0] = material
    else:
        obj.data.materials.append(material)


def parent_keep(obj, parent) -> None:
    if parent is None:
        return
    mw = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = mw


def add_cube(name: str, loc, scale, material, parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    apply_rot_scale(obj)
    assign_mat(obj, material)
    parent_keep(obj, parent)
    return obj


def add_sphere(name: str, loc, radius: float, material, parent=None, segments: int = 16):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments, ring_count=max(8, segments // 2), radius=radius, location=loc
    )
    obj = bpy.context.active_object
    obj.name = name
    assign_mat(obj, material)
    shade_smooth(obj)
    parent_keep(obj, parent)
    return obj


def add_ico(name: str, loc, radius: float, material, parent=None, subdivisions: int = 2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=radius, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    assign_mat(obj, material)
    shade_smooth(obj)
    parent_keep(obj, parent)
    return obj


def add_taper(name: str, p0, p1, r0: float, r1: float, material, parent=None, vertices: int = 10):
    """Cone along p0→p1. radius r0 at p0, r1 at p1."""
    head = Vector(p0)
    tail = Vector(p1)
    mid = (head + tail) * 0.5
    length = (tail - head).length
    if length < 1e-5:
        length = 1e-5
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=r0,
        radius2=r1,
        depth=length,
        location=mid,
    )
    obj = bpy.context.active_object
    obj.name = name
    direction = (tail - head).normalized()
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    apply_rot_scale(obj)
    assign_mat(obj, material)
    shade_smooth(obj)
    parent_keep(obj, parent)
    return obj


def add_limb(name: str, p0, p1, radius: float, material, parent=None, vertices: int = 10):
    return add_taper(name, p0, p1, radius, radius, material, parent, vertices=vertices)


def make_pivot(name: str, loc, child_objs, root):
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=loc)
    pivot = bpy.context.active_object
    pivot.name = name
    pivot.parent = root
    for child in child_objs:
        parent_keep(child, pivot)
    return pivot


def _add_hand(prefix: str, wrist, hide, claw, parent, x_sign: float):
    """Spindly four-fingered claw reaching forward and down from the wrist."""
    wrist = Vector(wrist)
    palm = wrist + Vector((0.02 * x_sign, 0.08, -0.03))
    add_sphere(f"{prefix}_Palm", palm, 0.065, hide, parent, segments=12)
    spreads = (-0.07, -0.025, 0.025, 0.075)
    for i, spread in enumerate(spreads):
        base = palm + Vector((spread, 0.03, -0.01))
        tip = base + Vector((spread * 0.45 + 0.01 * x_sign, 0.14, -0.09))
        add_taper(f"{prefix}_Finger{i}", base, tip, 0.02, 0.009, hide, parent, vertices=7)
        claw_tip = tip + Vector((0.0, 0.055, -0.025))
        add_taper(f"{prefix}_Claw{i}", tip, claw_tip, 0.01, 0.0015, claw, parent, vertices=5)
    thumb_base = palm + Vector((0.06 * x_sign, 0.0, 0.01))
    thumb_tip = thumb_base + Vector((0.05 * x_sign, 0.08, -0.04))
    add_taper(f"{prefix}_Thumb", thumb_base, thumb_tip, 0.018, 0.008, hide, parent, vertices=7)
    add_taper(
        f"{prefix}_ThumbClaw",
        thumb_tip,
        thumb_tip + Vector((0.02 * x_sign, 0.04, -0.02)),
        0.008,
        0.0015,
        claw,
        parent,
        vertices=5,
    )


def _add_foot(prefix: str, ankle, hide, claw, parent, x_sign: float):
    """Long rabbit foot with toenail claws, pointing +Y."""
    ankle = Vector(ankle)
    instep = ankle + Vector((0.02 * x_sign, 0.08, -0.04))
    toe = ankle + Vector((0.03 * x_sign, 0.30, -0.10))
    add_taper(f"{prefix}_Foot", instep, toe, 0.055, 0.032, hide, parent, vertices=8)
    add_sphere(f"{prefix}_Heel", ankle + Vector((0.0, -0.02, -0.02)), 0.05, hide, parent, segments=10)
    for i, spread in enumerate((-0.035, 0.0, 0.035)):
        t0 = toe + Vector((spread, -0.02, 0.0))
        t1 = t0 + Vector((spread * 0.4, 0.07, -0.02))
        add_taper(f"{prefix}_Toe{i}", t0, t1, 0.014, 0.006, hide, parent, vertices=6)
        add_taper(
            f"{prefix}_ToeClaw{i}",
            t1,
            t1 + Vector((0.0, 0.04, -0.01)),
            0.007,
            0.0015,
            claw,
            parent,
            vertices=5,
        )


def _add_teeth(root, tooth, gum) -> None:
    # Open maw: dark cavity, gums, two rows of jagged teeth, long canines.
    add_sphere("MouthCavity", (0.0, 0.76, 1.54), 0.12, gum, root, segments=12)
    add_cube("GumUpper", (0.0, 0.80, 1.60), (0.14, 0.11, 0.035), gum, root)
    add_cube("GumLower", (0.0, 0.74, 1.43), (0.13, 0.12, 0.03), gum, root)

    xs = (-0.09, -0.064, -0.038, -0.013, 0.013, 0.038, 0.064, 0.09)
    for i, x in enumerate(xs):
        length = 0.06 if i in (0, 7) else 0.046
        add_taper(
            f"Tooth_U{i}",
            (x, 0.84, 1.58),
            (x, 0.86, 1.58 - length),
            0.013,
            0.002,
            tooth,
            root,
            vertices=5,
        )
        add_taper(
            f"Tooth_L{i}",
            (x, 0.78, 1.44),
            (x, 0.81, 1.44 + length * 0.85),
            0.012,
            0.002,
            tooth,
            root,
            vertices=5,
        )
    add_taper("Fang_L", (-0.095, 0.82, 1.59), (-0.085, 0.88, 1.46), 0.017, 0.002, tooth, root, vertices=5)
    add_taper("Fang_R", (0.095, 0.82, 1.59), (0.085, 0.88, 1.46), 0.017, 0.002, tooth, root, vertices=5)


def build_monster():
    hide = mat("Hide", (0.18, 0.28, 0.08, 1.0), roughness=0.9, sheen=0.22)
    hide_dark = mat("HideDark", (0.10, 0.16, 0.05, 1.0), roughness=0.92, sheen=0.15)
    belly = mat("Belly", (0.24, 0.20, 0.10, 1.0), roughness=0.86, sheen=0.08)
    inner_ear = mat("InnerEar", (0.62, 0.24, 0.14, 1.0), roughness=0.5)
    claw = mat("Claw", (0.72, 0.64, 0.48, 1.0), roughness=0.42)
    tooth = mat("Tooth", (0.86, 0.80, 0.58, 1.0), roughness=0.35)
    gum = mat("Gum", (0.12, 0.04, 0.04, 1.0), roughness=0.55)
    wound = mat("Wound", (0.28, 0.05, 0.04, 1.0), roughness=0.48)
    nose = mat("Nose", (0.12, 0.08, 0.07, 1.0), roughness=0.45)
    eye = mat(
        "EyeGlow",
        (0.18, 0.02, 0.02, 1.0),
        roughness=0.25,
        emission=(1.0, 0.08, 0.02, 1.0),
        emission_strength=7.0,
    )

    bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 0, 0))
    root = bpy.context.active_object
    root.name = "MonsterRoot"

    # Hunched ~1.8 m body, ears to ~2.75 m. Lean is +Y (forward).
    add_sphere("Pelvis", (0.0, 0.08, 0.86), 0.22, hide_dark, root, segments=14)
    hips = add_sphere("Hips", (0.0, 0.06, 0.82), 0.20, hide_dark, root, segments=12)
    hips.scale = (1.35, 0.95, 0.7)
    apply_rot_scale(hips)
    add_sphere("Belly", (0.0, 0.20, 1.08), 0.20, belly, root, segments=14)
    add_sphere("Torso", (0.0, 0.24, 1.30), 0.26, hide, root, segments=16)
    torso = bpy.data.objects["Torso"]
    torso.scale = (1.15, 0.95, 1.05)
    apply_rot_scale(torso)
    add_sphere("Chest", (0.0, 0.32, 1.42), 0.18, hide, root, segments=14)
    add_sphere("ChestWound", (0.0, 0.46, 1.24), 0.09, wound, root, segments=10)
    add_sphere("WoundClot_A", (0.08, 0.40, 1.10), 0.045, wound, root, segments=8)
    add_sphere("WoundClot_B", (-0.06, 0.38, 1.32), 0.035, wound, root, segments=8)

    add_taper("Neck", (0.0, 0.28, 1.52), (0.0, 0.44, 1.66), 0.10, 0.09, hide, root, vertices=10)

    head = add_sphere("Head", (0.0, 0.52, 1.72), 0.22, hide, root, segments=18)
    head.scale = (1.08, 1.18, 1.0)
    apply_rot_scale(head)
    snout = add_sphere("Snout", (0.0, 0.74, 1.62), 0.145, hide, root, segments=14)
    snout.scale = (0.82, 1.35, 0.78)
    apply_rot_scale(snout)
    add_ico("Nose", (0.0, 0.94, 1.60), 0.028, nose, root, subdivisions=1)
    jaw = add_sphere("Jaw", (0.0, 0.72, 1.44), 0.11, hide, root, segments=12)
    jaw.scale = (0.9, 1.28, 0.52)
    apply_rot_scale(jaw)

    add_sphere("Cheek_L", (-0.17, 0.56, 1.68), 0.08, hide, root, segments=10)
    add_sphere("Cheek_R", (0.17, 0.56, 1.68), 0.08, hide, root, segments=10)
    add_sphere("Brow", (0.0, 0.58, 1.84), 0.09, hide_dark, root, segments=10)

    add_sphere("EyeSocket_L", (-0.09, 0.70, 1.76), 0.05, nose, root, segments=10)
    add_sphere("EyeSocket_R", (0.09, 0.70, 1.76), 0.05, nose, root, segments=10)
    add_sphere("Eye_L", (-0.09, 0.735, 1.76), 0.034, eye, root, segments=12)
    add_sphere("Eye_R", (0.09, 0.735, 1.76), 0.034, eye, root, segments=12)

    _add_teeth(root, tooth, gum)

    # Asymmetric hare ears planted in the skull — left swept back, right upright.
    ear_l_base = Vector((-0.09, 0.48, 1.88))
    ear_l_tip = Vector((-0.20, 0.18, 2.68))
    add_taper("Ear_L", ear_l_base, ear_l_tip, 0.12, 0.03, hide, root, vertices=8)
    add_taper(
        "InnerEar_L",
        ear_l_base.lerp(ear_l_tip, 0.12) + Vector((0.0, 0.03, 0.0)),
        ear_l_base.lerp(ear_l_tip, 0.92) + Vector((0.0, 0.035, 0.0)),
        0.07,
        0.012,
        inner_ear,
        root,
        vertices=8,
    )
    ear_r_base = Vector((0.09, 0.50, 1.88))
    ear_r_tip = Vector((0.16, 0.38, 2.76))
    add_taper("Ear_R", ear_r_base, ear_r_tip, 0.12, 0.028, hide, root, vertices=8)
    add_taper(
        "InnerEar_R",
        ear_r_base.lerp(ear_r_tip, 0.12) + Vector((0.0, 0.03, 0.0)),
        ear_r_base.lerp(ear_r_tip, 0.92) + Vector((0.0, 0.035, 0.0)),
        0.07,
        0.012,
        inner_ear,
        root,
        vertices=8,
    )

    # Tiny cottontail so the hare reads from behind.
    add_sphere("Tail", (0.0, -0.12, 0.88), 0.07, hide, root, segments=10)

    # Arms: long, thin, hanging forward. Pivots at the shoulders.
    sh_l = Vector((-0.38, 0.20, 1.50))
    el_l = Vector((-0.50, 0.32, 1.02))
    wr_l = Vector((-0.42, 0.46, 0.58))
    sh_r = Vector((0.38, 0.20, 1.50))
    el_r = Vector((0.50, 0.30, 1.04))
    wr_r = Vector((0.44, 0.44, 0.60))

    arm_l = add_taper("Arm_L", sh_l, el_l, 0.07, 0.055, hide, root, vertices=10)
    forearm_l = add_taper("Forearm_L", el_l, wr_l, 0.05, 0.038, hide, root, vertices=10)
    add_sphere("Elbow_L", el_l, 0.055, hide, root, segments=10)
    add_sphere("Shoulder_L", sh_l, 0.08, hide, root, segments=10)
    add_sphere("WoundArm_L", el_l + Vector((0.0, 0.02, -0.08)), 0.03, wound, root, segments=8)

    arm_r = add_taper("Arm_R", sh_r, el_r, 0.07, 0.055, hide, root, vertices=10)
    forearm_r = add_taper("Forearm_R", el_r, wr_r, 0.05, 0.038, hide, root, vertices=10)
    add_sphere("Elbow_R", el_r, 0.055, hide, root, segments=10)
    add_sphere("Shoulder_R", sh_r, 0.08, hide, root, segments=10)
    add_sphere("WoundArm_R", wr_r + Vector((0.02, 0.0, 0.06)), 0.028, wound, root, segments=8)

    before = set(bpy.data.objects)
    _add_hand("HandL", wr_l, hide, claw, root, -1.0)
    _add_hand("HandR", wr_r, hide, claw, root, 1.0)
    after = set(bpy.data.objects)
    new_objs = after - before
    hand_l_parts = [o for o in new_objs if o.name.startswith("HandL_")]
    hand_r_parts = [o for o in new_objs if o.name.startswith("HandR_")]

    # Digitigrade hare legs. Pivots at the hips.
    hip_l = Vector((-0.16, 0.04, 0.84))
    knee_l = Vector((-0.20, -0.14, 0.50))
    ankle_l = Vector((-0.18, 0.12, 0.16))
    hip_r = Vector((0.16, 0.04, 0.84))
    knee_r = Vector((0.20, -0.14, 0.50))
    ankle_r = Vector((0.18, 0.12, 0.16))

    thigh_l = add_taper("Thigh_L", hip_l, knee_l, 0.13, 0.075, hide, root, vertices=10)
    shin_l = add_taper("Shin_L", knee_l, ankle_l, 0.06, 0.045, hide_dark, root, vertices=10)
    add_sphere("HipJoint_L", hip_l, 0.09, hide, root, segments=10)
    add_sphere("Knee_L", knee_l, 0.065, hide, root, segments=10)

    thigh_r = add_taper("Thigh_R", hip_r, knee_r, 0.13, 0.075, hide, root, vertices=10)
    shin_r = add_taper("Shin_R", knee_r, ankle_r, 0.06, 0.045, hide_dark, root, vertices=10)
    add_sphere("HipJoint_R", hip_r, 0.09, hide, root, segments=10)
    add_sphere("Knee_R", knee_r, 0.065, hide, root, segments=10)

    before_feet = set(bpy.data.objects)
    _add_foot("FootL", ankle_l, hide, claw, root, -1.0)
    _add_foot("FootR", ankle_r, hide, claw, root, 1.0)
    new_feet = set(bpy.data.objects) - before_feet
    foot_l_parts = [o for o in new_feet if o.name.startswith("FootL_")]
    foot_r_parts = [o for o in new_feet if o.name.startswith("FootR_")]

    make_pivot(
        "Pivot_Arm_L",
        sh_l,
        [arm_l, forearm_l, bpy.data.objects["Elbow_L"], bpy.data.objects["WoundArm_L"], *hand_l_parts],
        root,
    )
    make_pivot(
        "Pivot_Arm_R",
        sh_r,
        [arm_r, forearm_r, bpy.data.objects["Elbow_R"], bpy.data.objects["WoundArm_R"], *hand_r_parts],
        root,
    )
    make_pivot(
        "Pivot_Leg_L",
        hip_l,
        [thigh_l, shin_l, bpy.data.objects["Knee_L"], *foot_l_parts],
        root,
    )
    make_pivot(
        "Pivot_Leg_R",
        hip_r,
        [thigh_r, shin_r, bpy.data.objects["Knee_R"], *foot_r_parts],
        root,
    )

    return root


def _aim_camera(cam, target: Vector) -> None:
    direction = target - Vector(cam.location)
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


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

    dirt = mat("Dirt", (0.07, 0.06, 0.04, 1.0), roughness=0.95)
    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0.0, 0.2, 0.0))
    ground = bpy.context.active_object
    ground.name = "PreviewGround"
    assign_mat(ground, dirt)

    bpy.ops.object.camera_add(location=(-2.45, 3.95, 1.55))
    cam = bpy.context.active_object
    _aim_camera(cam, Vector((0.0, 0.32, 1.40)))
    bpy.context.scene.camera = cam

    bpy.ops.object.light_add(type="AREA", location=(-1.6, 3.0, 3.2))
    key = bpy.context.active_object
    key.data.energy = 280
    key.data.size = 3.2
    key.data.color = (0.82, 0.90, 1.0)

    bpy.ops.object.light_add(type="AREA", location=(2.4, 0.6, 2.2))
    fill = bpy.context.active_object
    fill.data.energy = 70
    fill.data.size = 4.0
    fill.data.color = (0.40, 0.55, 0.42)

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    scene.render.filepath = str(PNG_OUT)
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.06, 0.08, 0.07, 1.0)
        bg.inputs[1].default_value = 0.35
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
