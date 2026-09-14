"""Build the Widow: pale woman in a black mourning dress and veil.

Dangerous enemy mesh for Nuclear Winter. Authored headlessly through Blender's
Python API. Output is a skinned GLB with Idle / Walk / Die clips plus a .blend.

Conventions match the other builders:
  * +Z up, feet on z = 0, character faces +Y, +X is the character's right.
  * Export uses export_yup, so +Y in Blender becomes -Z in Godot.
"""

from __future__ import annotations

import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Vector

OUT_DIR = Path("/workspace/godot/assets/characters")
BLEND_OUT = Path("/workspace/blender/enemy_widow.blend")
GLB_OUT = OUT_DIR / "enemy_widow.glb"
PNG_OUT = Path("/opt/cursor/artifacts/blender_enemy_widow.png")

SEGMENTS = 14

BONES = [
    ("Hips", None, (0.0, 0.02, 0.90), (0.0, 0.03, 1.08)),
    ("Spine", "Hips", (0.0, 0.03, 1.08), (0.0, 0.04, 1.28)),
    ("Chest", "Spine", (0.0, 0.04, 1.28), (0.0, 0.05, 1.48)),
    ("Neck", "Chest", (0.0, 0.05, 1.48), (0.0, 0.06, 1.58)),
    ("Head", "Neck", (0.0, 0.06, 1.58), (0.0, 0.07, 1.78)),
    ("UpperArm_R", "Chest", (0.16, 0.04, 1.46), (0.22, 0.02, 1.22)),
    ("Forearm_R", "UpperArm_R", (0.22, 0.02, 1.22), (0.24, 0.00, 0.98)),
    ("Hand_R", "Forearm_R", (0.24, 0.00, 0.98), (0.25, 0.01, 0.86)),
    ("UpperArm_L", "Chest", (-0.16, 0.04, 1.46), (-0.22, 0.02, 1.22)),
    ("Forearm_L", "UpperArm_L", (-0.22, 0.02, 1.22), (-0.24, 0.00, 0.98)),
    ("Hand_L", "Forearm_L", (-0.24, 0.00, 0.98), (-0.25, 0.01, 0.86)),
    ("Thigh_R", "Hips", (0.08, 0.02, 0.90), (0.09, 0.03, 0.50)),
    ("Shin_R", "Thigh_R", (0.09, 0.03, 0.50), (0.08, 0.06, 0.12)),
    ("Foot_R", "Shin_R", (0.08, 0.06, 0.12), (0.08, 0.16, 0.03)),
    ("Thigh_L", "Hips", (-0.08, 0.02, 0.90), (-0.09, 0.03, 0.50)),
    ("Shin_L", "Thigh_L", (-0.09, 0.03, 0.50), (-0.08, 0.06, 0.12)),
    ("Foot_L", "Shin_L", (-0.08, 0.06, 0.12), (-0.08, 0.16, 0.03)),
]


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (
        bpy.data.meshes,
        bpy.data.materials,
        bpy.data.armatures,
        bpy.data.actions,
        bpy.data.images,
        bpy.data.objects,
    ):
        for block in list(collection):
            collection.remove(block)


def srgb(hex_color: str) -> tuple[float, float, float, float]:
    hex_color = hex_color.lstrip("#")
    out = []
    for i in range(0, 6, 2):
        c = int(hex_color[i : i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


def mat(
    name: str,
    hex_color: str,
    roughness: float = 0.72,
    specular: float = 0.35,
    alpha: float = 1.0,
    emission: str | None = None,
    emission_strength: float = 0.0,
):
    material = bpy.data.materials.new(name=name)
    material.use_nodes = True
    if alpha < 1.0:
        material.blend_method = "BLEND"
        if hasattr(material, "shadow_method"):
            material.shadow_method = "HASHED"
    bsdf = material.node_tree.nodes["Principled BSDF"]
    color = srgb(hex_color)
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], alpha)
    bsdf.inputs["Roughness"].default_value = roughness
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = specular
    if "Alpha" in bsdf.inputs:
        bsdf.inputs["Alpha"].default_value = alpha
    if emission and "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = srgb(emission)
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emission_strength
    return material


def _profile(angle: float, rx: float, ry: float, power: float) -> tuple[float, float]:
    c, s = math.cos(angle), math.sin(angle)
    return (
        math.copysign(abs(c) ** power, c) * rx,
        math.copysign(abs(s) ** power, s) * ry,
    )


def _finish(name: str, bm: bmesh.types.BMesh, material) -> bpy.types.Object:
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    obj.data.materials.append(material)
    bpy.context.collection.objects.link(obj)
    return obj


def tube(
    name: str,
    material,
    sections: list[dict],
    axis_u: tuple[float, float, float] = (1, 0, 0),
    axis_v: tuple[float, float, float] = (0, 1, 0),
    segments: int = SEGMENTS,
    cap_start: str = "dome",
    cap_end: str = "dome",
    dome_rings: int = 3,
) -> bpy.types.Object:
    u = Vector(axis_u).normalized()
    v = Vector(axis_v).normalized()
    rings: list[tuple[Vector, float, float, float]] = [
        (Vector(s["c"]), s["rx"], s["ry"], s.get("p", 1.0)) for s in sections
    ]

    def dome_extension(inner, outer):
        centre, rx, ry, power = outer
        direction = (centre - inner[0]).normalized()
        height = 0.9 * (rx + ry) * 0.5
        extra = []
        for k in range(1, dome_rings + 1):
            t = (k / (dome_rings + 1)) * (math.pi / 2)
            extra.append((
                centre + direction * (math.sin(t) * height),
                rx * math.cos(t),
                ry * math.cos(t),
                power,
            ))
        return extra, centre + direction * height

    start_pole = end_pole = None
    if cap_start == "dome" and len(rings) > 1:
        extra, start_pole = dome_extension(rings[1], rings[0])
        rings = list(reversed(extra)) + rings
    if cap_end == "dome" and len(rings) > 1:
        extra, end_pole = dome_extension(rings[-2], rings[-1])
        rings = rings + extra

    bm = bmesh.new()
    ring_verts = []
    for centre, rx, ry, power in rings:
        verts = []
        for i in range(segments):
            px, py = _profile(2.0 * math.pi * i / segments, rx, ry, power)
            verts.append(bm.verts.new(centre + u * px + v * py))
        ring_verts.append(verts)

    for lower, upper in zip(ring_verts, ring_verts[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((lower[i], lower[j], upper[j], upper[i]))

    def close(verts, pole_location, mode, flip):
        if mode == "none":
            return
        if mode == "flat":
            pole_location = sum((vert.co for vert in verts), Vector()) / segments
        pole = bm.verts.new(pole_location)
        for i in range(segments):
            j = (i + 1) % segments
            trio = (verts[i], verts[j], pole)
            bm.faces.new(trio[::-1] if flip else trio)

    close(ring_verts[0], start_pole, cap_start, False)
    close(ring_verts[-1], end_pole, cap_end, True)
    return _finish(name, bm, material)


def box(name: str, material, centre, size, power: float = 0.55) -> bpy.types.Object:
    cx, cy, cz = centre
    sx, sy, sz = size
    return tube(
        name,
        material,
        [
            {"c": (cx, cy, cz - sz * 0.5), "rx": sx * 0.5, "ry": sy * 0.5, "p": power},
            {"c": (cx, cy, cz + sz * 0.5), "rx": sx * 0.5, "ry": sy * 0.5, "p": power},
        ],
        cap_start="flat",
        cap_end="flat",
        segments=10,
    )


def _smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = min(1.0, max(0.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def build_character() -> list[tuple[bpy.types.Object, list[str]]]:
    skin = mat("WidowSkin", "#f4efe8", roughness=0.48, emission="#fff6ee", emission_strength=0.12)
    dress = mat("WidowDress", "#0b0b0d", roughness=0.82, specular=0.18)
    dress_sheen = mat("WidowDressSheen", "#16161a", roughness=0.55, specular=0.28)
    veil = mat("WidowVeil", "#0e0e10", roughness=0.35, specular=0.15, alpha=0.42)
    hair = mat("WidowHair", "#0a0a0c", roughness=0.88)
    boot = mat("WidowBoot", "#0c0c0e", roughness=0.55)
    eye = mat("WidowEye", "#1a1a1c", roughness=0.2)
    lip = mat("WidowLip", "#c4b4aa", roughness=0.4)

    parts: list[tuple[bpy.types.Object, list[str]]] = []
    spine = ["Hips", "Spine", "Chest"]

    parts.append((tube("DressSkirt", dress, [
        {"c": (0.0, 0.04, 0.04), "rx": 0.32, "ry": 0.30, "p": 0.78},
        {"c": (0.0, 0.03, 0.22), "rx": 0.28, "ry": 0.26, "p": 0.76},
        {"c": (0.0, 0.02, 0.46), "rx": 0.22, "ry": 0.20, "p": 0.74},
        {"c": (0.0, 0.02, 0.70), "rx": 0.18, "ry": 0.16, "p": 0.72},
        {"c": (0.0, 0.03, 0.90), "rx": 0.16, "ry": 0.14, "p": 0.70},
    ], cap_start="flat", cap_end="flat", segments=16), ["Hips", "Thigh_R", "Thigh_L", "Shin_R", "Shin_L"]))

    parts.append((tube("DressBodice", dress_sheen, [
        {"c": (0.0, 0.03, 0.90), "rx": 0.15, "ry": 0.13, "p": 0.72},
        {"c": (0.0, 0.04, 1.10), "rx": 0.14, "ry": 0.12, "p": 0.70},
        {"c": (0.0, 0.05, 1.28), "rx": 0.15, "ry": 0.12, "p": 0.68},
        {"c": (0.0, 0.05, 1.44), "rx": 0.16, "ry": 0.11, "p": 0.66},
        {"c": (0.0, 0.04, 1.50), "rx": 0.10, "ry": 0.08, "p": 0.80},
    ], cap_start="flat", cap_end="flat", segments=14), spine + ["Chest"]))

    parts.append((tube("Neck", skin, [
        {"c": (0.0, 0.05, 1.48), "rx": 0.045, "ry": 0.048, "p": 0.95},
        {"c": (0.0, 0.06, 1.56), "rx": 0.042, "ry": 0.045, "p": 0.95},
        {"c": (0.0, 0.065, 1.62), "rx": 0.048, "ry": 0.050, "p": 0.92},
    ], cap_start="flat", cap_end="flat", segments=12), ["Chest", "Neck", "Head"]))

    parts.append((tube("Head", skin, [
        {"c": (0.0, 0.06, 1.62), "rx": 0.072, "ry": 0.074, "p": 0.88},
        {"c": (0.0, 0.07, 1.70), "rx": 0.086, "ry": 0.090, "p": 0.82},
        {"c": (0.0, 0.07, 1.78), "rx": 0.082, "ry": 0.086, "p": 0.84},
        {"c": (0.0, 0.06, 1.86), "rx": 0.062, "ry": 0.066, "p": 0.90},
    ], cap_start="flat", cap_end="dome", segments=16), ["Neck", "Head"]))

    parts.append((tube("HairBun", hair, [
        {"c": (0.0, -0.01, 1.80), "rx": 0.055, "ry": 0.050, "p": 0.9},
        {"c": (0.0, -0.06, 1.82), "rx": 0.070, "ry": 0.062, "p": 0.88},
        {"c": (0.0, -0.08, 1.84), "rx": 0.040, "ry": 0.038, "p": 0.92},
    ], cap_start="flat", cap_end="dome", segments=12), ["Head"]))

    parts.append((tube("HairCrown", hair, [
        {"c": (0.0, 0.04, 1.82), "rx": 0.078, "ry": 0.080, "p": 0.9},
        {"c": (0.0, 0.03, 1.88), "rx": 0.070, "ry": 0.072, "p": 0.9},
        {"c": (0.0, 0.02, 1.92), "rx": 0.030, "ry": 0.032, "p": 0.95},
    ], cap_start="flat", cap_end="dome", segments=12), ["Head"]))

    parts.append((box("Brow_L", hair, (-0.028, 0.145, 1.76), (0.036, 0.012, 0.010)), ["Head"]))
    parts.append((box("Brow_R", hair, (0.028, 0.145, 1.76), (0.036, 0.012, 0.010)), ["Head"]))
    parts.append((tube("Nose", skin, [
        {"c": (0.0, 0.13, 1.72), "rx": 0.012, "ry": 0.010, "p": 0.85},
        {"c": (0.0, 0.155, 1.695), "rx": 0.014, "ry": 0.012, "p": 0.8},
        {"c": (0.0, 0.16, 1.678), "rx": 0.010, "ry": 0.009, "p": 0.85},
    ], cap_start="flat", cap_end="dome", segments=8), ["Head"]))
    parts.append((box("Lip", lip, (0.0, 0.148, 1.655), (0.042, 0.016, 0.012)), ["Head"]))
    for side, sign in (("R", 1.0), ("L", -1.0)):
        parts.append((tube(f"Eye_{side}", eye, [
            {"c": (sign * 0.030, 0.148, 1.735), "rx": 0.012, "ry": 0.008},
            {"c": (sign * 0.030, 0.158, 1.735), "rx": 0.010, "ry": 0.007},
        ], cap_start="dome", cap_end="dome", segments=8), ["Head"]))
        parts.append((box(f"Ear_{side}", skin, (sign * 0.086, 0.05, 1.72), (0.018, 0.028, 0.040)), ["Head"]))

    parts.append((tube("VeilCrown", veil, [
        {"c": (0.0, 0.02, 1.90), "rx": 0.090, "ry": 0.092, "p": 0.9},
        {"c": (0.0, 0.04, 1.86), "rx": 0.12, "ry": 0.13, "p": 0.88},
        {"c": (0.0, 0.10, 1.72), "rx": 0.14, "ry": 0.12, "p": 0.86},
        {"c": (0.0, 0.16, 1.52), "rx": 0.16, "ry": 0.10, "p": 0.84},
        {"c": (0.0, 0.10, 1.38), "rx": 0.18, "ry": 0.12, "p": 0.82},
    ], cap_start="dome", cap_end="flat", segments=16), ["Head", "Neck", "Chest"]))

    for side, sign in (("R", 1.0), ("L", -1.0)):
        x = sign * 0.16
        parts.append((tube(f"Sleeve_{side}", dress, [
            {"c": (sign * 0.14, 0.04, 1.46), "rx": 0.055, "ry": 0.050, "p": 0.8},
            {"c": (sign * 0.20, 0.02, 1.28), "rx": 0.048, "ry": 0.045, "p": 0.82},
            {"c": (sign * 0.23, 0.01, 1.10), "rx": 0.042, "ry": 0.040, "p": 0.84},
            {"c": (sign * 0.24, 0.00, 0.98), "rx": 0.036, "ry": 0.034, "p": 0.86},
        ], cap_start="flat", cap_end="flat", segments=10), ["Chest", f"UpperArm_{side}", f"Forearm_{side}"]))
        parts.append((tube(f"Hand_{side}", skin, [
            {"c": (sign * 0.24, 0.00, 0.96), "rx": 0.028, "ry": 0.022, "p": 0.8},
            {"c": (sign * 0.25, 0.01, 0.88), "rx": 0.030, "ry": 0.020, "p": 0.75},
            {"c": (sign * 0.255, 0.02, 0.84), "rx": 0.018, "ry": 0.014, "p": 0.8},
        ], cap_start="flat", cap_end="dome", segments=8), [f"Forearm_{side}", f"Hand_{side}"]))
        parts.append((tube(f"Boot_{side}", boot, [
            {"c": (sign * 0.08, 0.06, 0.10), "rx": 0.045, "ry": 0.050, "p": 0.8},
            {"c": (sign * 0.08, 0.12, 0.04), "rx": 0.050, "ry": 0.080, "p": 0.7},
            {"c": (sign * 0.08, 0.16, 0.02), "rx": 0.042, "ry": 0.090, "p": 0.75},
        ], cap_start="flat", cap_end="flat", segments=8), [f"Shin_{side}", f"Foot_{side}"]))

    return parts


def build_armature() -> bpy.types.Object:
    arm = bpy.data.armatures.new("WidowArmature")
    rig = bpy.data.objects.new("WidowRig", arm)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    created = {}
    for name, parent, head, tail in BONES:
        bone = arm.edit_bones.new(name)
        bone.head = Vector(head)
        bone.tail = Vector(tail)
        bone.use_connect = False
        created[name] = bone
        if parent:
            bone.parent = created[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def _distance_to_bone(point: Vector, head: Vector, tail: Vector) -> float:
    span = tail - head
    length_sq = span.length_squared
    if length_sq <= 1e-8:
        return (point - head).length
    t = max(0.0, min(1.0, (point - head).dot(span) / length_sq))
    return (point - (head + span * t)).length


def skin_part(obj: bpy.types.Object, allowed: list[str], falloff: float = 3.6) -> None:
    bone_table = {name: (Vector(head), Vector(tail)) for name, _, head, tail in BONES}
    bones = [(name, *bone_table[name]) for name in allowed if name in bone_table]
    groups = {name: obj.vertex_groups.new(name=name) for name, _, _ in bones}
    for vert in obj.data.vertices:
        point = vert.co
        weights = []
        for name, head, tail in bones:
            distance = max(1e-4, _distance_to_bone(point, head, tail))
            weights.append((name, 1.0 / distance ** falloff))
        weights.sort(key=lambda item: item[1], reverse=True)
        weights = weights[:3]
        total = sum(weight for _, weight in weights) or 1.0
        for name, weight in weights:
            groups[name].add([vert.index], weight / total, "REPLACE")


def pose_rotate(rig: bpy.types.Object, bone: str, rx: float = 0.0, ry: float = 0.0, rz: float = 0.0) -> None:
    pose_bone = rig.pose.bones[bone]
    rest = rig.data.bones[bone].matrix_local.to_3x3()
    world = Euler((math.radians(rx), math.radians(ry), math.radians(rz)), "XYZ").to_matrix()
    pose_bone.rotation_mode = "QUATERNION"
    pose_bone.rotation_quaternion = (rest.inverted() @ world @ rest).to_quaternion()


def pose_offset(rig: bpy.types.Object, bone: str, offset: Vector) -> None:
    pose_bone = rig.pose.bones[bone]
    rest = rig.data.bones[bone].matrix_local.to_3x3()
    pose_bone.location = rest.inverted() @ offset


def _key(rig: bpy.types.Object, bones: set[str], frame: int) -> None:
    for name in bones:
        pose_bone = rig.pose.bones[name]
        pose_bone.keyframe_insert("rotation_quaternion", frame=frame)
        pose_bone.keyframe_insert("location", frame=frame)


def make_action(rig: bpy.types.Object, name: str, frames: int, poser, loop: bool) -> bpy.types.Action:
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    if rig.animation_data is None:
        rig.animation_data_create()
    rig.animation_data.action = action
    touched: set[str] = set()
    last = frames if loop else frames - 1
    for frame in range(last + 1):
        for pose_bone in rig.pose.bones:
            pose_bone.rotation_mode = "QUATERNION"
            pose_bone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
            pose_bone.location = (0.0, 0.0, 0.0)
        phase = (frame % frames) / frames if loop else frame / max(1, frames - 1)
        touched |= set(poser(phase))
        _key(rig, touched, frame + 1)
    for curve in action.fcurves:
        for keyframe in curve.keyframe_points:
            keyframe.interpolation = "BEZIER"
    return action


def idle_pose(rig):
    def poser(t: float):
        q = 2.0 * math.pi * t
        breath = math.sin(q)
        pose_offset(rig, "Hips", Vector((0.0, 0.0, 0.008 * breath)))
        pose_rotate(rig, "Spine", rx=1.4 * breath)
        pose_rotate(rig, "Chest", rx=1.8 * breath, rz=1.2 * math.sin(q + 0.4))
        pose_rotate(rig, "Head", rx=3.0 * math.sin(q + 0.8), rz=4.0 * math.sin(q))
        pose_rotate(rig, "UpperArm_L", rx=2.0 * breath, rz=3.0)
        pose_rotate(rig, "UpperArm_R", rx=2.0 * breath, rz=-3.0)
        return {"Hips", "Spine", "Chest", "Head", "UpperArm_L", "UpperArm_R"}
    return poser


def walk_pose(rig):
    def poser(t: float):
        q = 2.0 * math.pi * t
        pose_offset(rig, "Hips", Vector((0.0, 0.0, -0.018 * (1.0 + math.cos(2.0 * q)))))
        pose_rotate(rig, "Hips", ry=-4.0 * math.sin(q), rz=6.0 * math.cos(q))
        pose_rotate(rig, "Spine", rx=4.0, rz=-5.0 * math.cos(q))
        pose_rotate(rig, "Chest", rx=3.0, rz=-4.0 * math.cos(q))
        pose_rotate(rig, "Head", rx=-2.0, rz=3.0 * math.cos(q))
        for side, sign in (("R", 1.0), ("L", -1.0)):
            leg = q if side == "R" else q + math.pi
            pose_rotate(rig, f"Thigh_{side}", rx=18.0 * math.cos(leg))
            pose_rotate(rig, f"Shin_{side}", rx=-12.0 - 16.0 * max(0.0, math.sin(leg)))
            pose_rotate(rig, f"Foot_{side}", rx=6.0 * math.sin(leg))
            pose_rotate(rig, f"UpperArm_{side}", rx=8.0 * math.cos(leg + math.pi), rz=-sign * 6.0)
            pose_rotate(rig, f"Forearm_{side}", rx=8.0)
        return {
            "Hips", "Spine", "Chest", "Head",
            "Thigh_R", "Thigh_L", "Shin_R", "Shin_L", "Foot_R", "Foot_L",
            "UpperArm_R", "UpperArm_L", "Forearm_R", "Forearm_L",
        }
    return poser


def die_pose(rig):
    def poser(t: float):
        buckle = _smoothstep(0.0, 0.35, t)
        fall = _smoothstep(0.25, 0.95, t)
        pose_offset(rig, "Hips", Vector((0.12 * fall, 0.08 * fall, -0.55 * fall)))
        pose_rotate(rig, "Hips", rx=12.0 * buckle, rz=70.0 * fall)
        pose_rotate(rig, "Spine", rx=18.0 * buckle + 10.0 * fall)
        pose_rotate(rig, "Chest", rx=8.0 * fall)
        pose_rotate(rig, "Head", rx=16.0 * buckle - 20.0 * fall, rz=12.0 * fall)
        pose_rotate(rig, "Thigh_L", rx=22.0 * buckle)
        pose_rotate(rig, "Thigh_R", rx=10.0 * buckle)
        pose_rotate(rig, "UpperArm_L", rx=20.0 * fall, rz=24.0 * fall)
        pose_rotate(rig, "UpperArm_R", rx=8.0 * fall, rz=-18.0 * fall)
        return {
            "Hips", "Spine", "Chest", "Head", "Thigh_L", "Thigh_R",
            "UpperArm_L", "UpperArm_R",
        }
    return poser


def reset_pose(rig: bpy.types.Object) -> None:
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"
        pose_bone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pose_bone.location = (0.0, 0.0, 0.0)
        pose_bone.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()


def build_animations(rig: bpy.types.Object) -> None:
    specs = [
        ("Idle", 72, idle_pose(rig), True),
        ("Walk", 26, walk_pose(rig), True),
        ("Die", 32, die_pose(rig), False),
    ]
    actions = [make_action(rig, name, frames, poser, loop) for name, frames, poser, loop in specs]
    rig.animation_data.action = None
    for action in actions:
        track = rig.animation_data.nla_tracks.new()
        track.name = action.name
        strip = track.strips.new(action.name, 1, action)
        strip.name = action.name
        track.mute = True
    reset_pose(rig)


def join_parts(parts: list[tuple[bpy.types.Object, list[str]]]) -> bpy.types.Object:
    objects = [obj for obj, _ in parts]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    body = objects[0]
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = "Widow"
    body.data.name = "WidowBody"
    return body


def sharpen_edges(obj: bpy.types.Object, angle: float = 44.0) -> None:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for face in bm.faces:
        face.smooth = True
    limit = math.radians(angle)
    for edge in bm.edges:
        edge.smooth = not (len(edge.link_faces) == 2 and edge.calc_face_angle() > limit)
    bm.to_mesh(obj.data)
    bm.free()


def export(rig: bpy.types.Object, body: bpy.types.Object) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_OUT),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_yup=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_frame_range=False,
        export_current_frame=False,
        export_bake_animation=True,
        export_optimize_animation_size=False,
        export_anim_slide_to_zero=True,
    )
    print(f"Wrote {GLB_OUT}")


def render_preview() -> None:
    PNG_OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.camera_add(location=(2.2, 3.4, 1.45))
    cam = bpy.context.active_object
    direction = Vector((0.0, 0.08, 1.05)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    bpy.ops.object.light_add(type="AREA", location=(1.8, -1.8, 3.2))
    light = bpy.context.active_object
    light.data.energy = 520
    light.data.size = 2.8
    bpy.ops.object.light_add(type="AREA", location=(-1.4, 1.6, 2.2))
    fill = bpy.context.active_object
    fill.data.energy = 160
    fill.data.size = 2.0
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    scene.render.film_transparent = True
    scene.render.filepath = str(PNG_OUT)
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.12, 0.12, 0.14, 1.0)
        bg.inputs[1].default_value = 0.35
    try:
        bpy.ops.render.render(write_still=True)
        print(f"Wrote {PNG_OUT}")
    except Exception as exc:
        print(f"Preview render skipped: {exc}")


def main() -> None:
    clear_scene()
    parts = build_character()
    rig = build_armature()
    for obj, allowed in parts:
        skin_part(obj, allowed)
    body = join_parts(parts)
    sharpen_edges(body)
    body.parent = rig
    modifier = body.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig
    build_animations(rig)
    triangles = sum(len(polygon.vertices) - 2 for polygon in body.data.polygons)
    print(
        f"Widow: {len(body.data.vertices)} verts, {triangles} tris, "
        f"{len(body.material_slots)} materials, {len(bpy.data.actions)} actions"
    )
    BLEND_OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
    export(rig, body)
    render_preview()


if __name__ == "__main__":
    main()
