"""Build the Toad: a squat, warty amphibian that hunts the mission item.

Easy, passive enemy mesh for Nuclear Winter. Authored headlessly through
Blender's Python API. Output is a skinned GLB with Idle / Walk / Die clips
plus a .blend.

Conventions match the other builders:
  * +Z up, feet on z = 0, character faces +Y, +X is the character's right.
  * Export uses export_yup, so +Y in Blender becomes -Z in Godot.
"""

from __future__ import annotations

import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Vector, noise

OUT_DIR = Path("/workspace/godot/assets/characters")
BLEND_OUT = Path("/workspace/blender/enemy_toad.blend")
GLB_OUT = OUT_DIR / "enemy_toad.glb"
PNG_OUT = Path("/opt/cursor/artifacts/blender_enemy_toad.png")

SEGMENTS = 14

BONES = [
    ("Body", None, (0.0, 0.02, 0.28), (0.0, 0.08, 0.42)),
    ("Head", "Body", (0.0, 0.16, 0.42), (0.0, 0.32, 0.50)),
    ("Jaw", "Head", (0.0, 0.22, 0.34), (0.0, 0.34, 0.30)),
    ("Thigh_R", "Body", (0.14, -0.02, 0.28), (0.20, -0.08, 0.16)),
    ("Shin_R", "Thigh_R", (0.20, -0.08, 0.16), (0.18, 0.04, 0.04)),
    ("Foot_R", "Shin_R", (0.18, 0.04, 0.04), (0.18, 0.16, 0.02)),
    ("Thigh_L", "Body", (-0.14, -0.02, 0.28), (-0.20, -0.08, 0.16)),
    ("Shin_L", "Thigh_L", (-0.20, -0.08, 0.16), (-0.18, 0.04, 0.04)),
    ("Foot_L", "Shin_L", (-0.18, 0.04, 0.04), (-0.18, 0.16, 0.02)),
    ("Arm_R", "Body", (0.16, 0.10, 0.30), (0.22, 0.18, 0.12)),
    ("Hand_R", "Arm_R", (0.22, 0.18, 0.12), (0.24, 0.26, 0.04)),
    ("Arm_L", "Body", (-0.16, 0.10, 0.30), (-0.22, 0.18, 0.12)),
    ("Hand_L", "Arm_L", (-0.22, 0.18, 0.12), (-0.24, 0.26, 0.04)),
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


def mat(name: str, hex_color: str, roughness: float = 0.72, emission=None, emission_strength: float = 0.0):
    material = bpy.data.materials.new(name=name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = srgb(hex_color)
    bsdf.inputs["Roughness"].default_value = roughness
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.28
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


def box(name: str, material, centre, size, power: float = 0.7) -> bpy.types.Object:
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
        segments=8,
    )


def add_surface_noise(obj: bpy.types.Object, fold: float, grain: float, seed: float = 0.0) -> None:
    for vert in obj.data.vertices:
        point = vert.co + Vector((seed, seed * 0.37, seed * 0.13))
        offset = fold * noise.noise(point * 7.5) + grain * noise.noise(point * 22.0)
        vert.co = point - Vector((seed, seed * 0.37, seed * 0.13)) + vert.normal * offset
    obj.data.update()


def _smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = min(1.0, max(0.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def build_character() -> list[tuple[bpy.types.Object, list[str]]]:
    hide = mat("ToadHide", "#4a6a32", roughness=0.82)
    belly = mat("ToadBelly", "#c4b06a", roughness=0.55)
    wart = mat("ToadWart", "#2e441c", roughness=0.9)
    eye_w = mat("ToadEyeWhite", "#f0ead8", roughness=0.22)
    iris = mat("ToadIris", "#1a2a10", roughness=0.16, emission="#304818", emission_strength=0.25)
    mouth = mat("ToadMouth", "#6a3030", roughness=0.5)

    parts: list[tuple[bpy.types.Object, list[str]]] = []
    parts.append((tube("Body", hide, [
        {"c": (0.0, -0.02, 0.16), "rx": 0.22, "ry": 0.20, "p": 0.72},
        {"c": (0.0, 0.02, 0.30), "rx": 0.28, "ry": 0.24, "p": 0.68},
        {"c": (0.0, 0.06, 0.42), "rx": 0.24, "ry": 0.20, "p": 0.70},
        {"c": (0.0, 0.10, 0.50), "rx": 0.16, "ry": 0.14, "p": 0.76},
    ], cap_start="dome", cap_end="flat", segments=16), ["Body"]))

    parts.append((tube("Belly", belly, [
        {"c": (0.0, 0.12, 0.18), "rx": 0.16, "ry": 0.10, "p": 0.8},
        {"c": (0.0, 0.16, 0.30), "rx": 0.18, "ry": 0.12, "p": 0.76},
        {"c": (0.0, 0.14, 0.40), "rx": 0.12, "ry": 0.08, "p": 0.82},
    ], cap_start="dome", cap_end="flat", segments=12), ["Body"]))

    parts.append((tube("Head", hide, [
        {"c": (0.0, 0.14, 0.46), "rx": 0.16, "ry": 0.14, "p": 0.74},
        {"c": (0.0, 0.24, 0.50), "rx": 0.18, "ry": 0.16, "p": 0.70},
        {"c": (0.0, 0.32, 0.48), "rx": 0.14, "ry": 0.13, "p": 0.76},
        {"c": (0.0, 0.36, 0.42), "rx": 0.10, "ry": 0.10, "p": 0.82},
    ], cap_start="flat", cap_end="dome", segments=14), ["Body", "Head"]))

    parts.append((box("Mouth", mouth, (0.0, 0.32, 0.36), (0.16, 0.10, 0.08)), ["Head", "Jaw"]))
    parts.append((tube("Jaw", hide, [
        {"c": (0.0, 0.22, 0.34), "rx": 0.12, "ry": 0.08, "p": 0.8},
        {"c": (0.0, 0.32, 0.30), "rx": 0.11, "ry": 0.07, "p": 0.82},
        {"c": (0.0, 0.36, 0.28), "rx": 0.06, "ry": 0.04, "p": 0.88},
    ], cap_start="flat", cap_end="dome", segments=10), ["Jaw"]))

    for i, (x, y, z, r) in enumerate((
        (0.12, 0.00, 0.40, 0.035), (-0.14, 0.04, 0.38, 0.03),
        (0.08, -0.10, 0.34, 0.028), (-0.06, -0.12, 0.36, 0.032),
        (0.16, 0.08, 0.32, 0.026),
    )):
        parts.append((tube(f"Wart_{i}", wart, [
            {"c": (x, y, z), "rx": r, "ry": r * 0.9},
            {"c": (x, y + 0.01, z + 0.01), "rx": r * 0.7, "ry": r * 0.65},
        ], cap_start="dome", cap_end="dome", segments=8), ["Body"]))

    for side, sign in (("R", 1.0), ("L", -1.0)):
        parts.append((tube(f"EyeBulge_{side}", hide, [
            {"c": (sign * 0.10, 0.26, 0.54), "rx": 0.055, "ry": 0.050, "p": 0.85},
            {"c": (sign * 0.12, 0.30, 0.58), "rx": 0.048, "ry": 0.044, "p": 0.86},
        ], cap_start="dome", cap_end="dome", segments=10), ["Head"]))
        parts.append((tube(f"EyeWhite_{side}", eye_w, [
            {"c": (sign * 0.12, 0.31, 0.575), "rx": 0.032, "ry": 0.028},
            {"c": (sign * 0.13, 0.335, 0.58), "rx": 0.028, "ry": 0.024},
        ], cap_start="dome", cap_end="dome", segments=8), ["Head"]))
        parts.append((tube(f"Iris_{side}", iris, [
            {"c": (sign * 0.13, 0.33, 0.578), "rx": 0.016, "ry": 0.014},
            {"c": (sign * 0.135, 0.348, 0.58), "rx": 0.012, "ry": 0.011},
        ], cap_start="flat", cap_end="dome", segments=8), ["Head"]))
        parts.append((tube(f"Thigh_{side}", hide, [
            {"c": (sign * 0.14, -0.02, 0.28), "rx": 0.08, "ry": 0.07, "p": 0.75},
            {"c": (sign * 0.18, -0.08, 0.18), "rx": 0.07, "ry": 0.06, "p": 0.78},
            {"c": (sign * 0.20, -0.06, 0.12), "rx": 0.05, "ry": 0.045, "p": 0.82},
        ], cap_start="dome", cap_end="flat", segments=10), ["Body", f"Thigh_{side}"]))
        parts.append((tube(f"Shin_{side}", hide, [
            {"c": (sign * 0.20, -0.06, 0.12), "rx": 0.045, "ry": 0.04, "p": 0.84},
            {"c": (sign * 0.18, 0.00, 0.06), "rx": 0.04, "ry": 0.035, "p": 0.86},
            {"c": (sign * 0.18, 0.06, 0.03), "rx": 0.035, "ry": 0.04, "p": 0.8},
        ], cap_start="flat", cap_end="flat", segments=8), [f"Thigh_{side}", f"Shin_{side}"]))
        parts.append((tube(f"Foot_{side}", wart, [
            {"c": (sign * 0.18, 0.06, 0.03), "rx": 0.05, "ry": 0.04, "p": 0.75},
            {"c": (sign * 0.18, 0.14, 0.02), "rx": 0.07, "ry": 0.05, "p": 0.7},
            {"c": (sign * 0.18, 0.20, 0.015), "rx": 0.04, "ry": 0.03, "p": 0.8},
        ], cap_start="flat", cap_end="dome", segments=8), [f"Shin_{side}", f"Foot_{side}"]))
        parts.append((tube(f"Arm_{side}", hide, [
            {"c": (sign * 0.16, 0.10, 0.30), "rx": 0.045, "ry": 0.04, "p": 0.8},
            {"c": (sign * 0.20, 0.16, 0.18), "rx": 0.04, "ry": 0.035, "p": 0.82},
            {"c": (sign * 0.22, 0.20, 0.10), "rx": 0.035, "ry": 0.03, "p": 0.84},
        ], cap_start="dome", cap_end="flat", segments=8), ["Body", f"Arm_{side}"]))
        parts.append((tube(f"Hand_{side}", belly, [
            {"c": (sign * 0.22, 0.20, 0.10), "rx": 0.04, "ry": 0.032, "p": 0.75},
            {"c": (sign * 0.24, 0.26, 0.04), "rx": 0.05, "ry": 0.04, "p": 0.7},
        ], cap_start="flat", cap_end="dome", segments=8), [f"Arm_{side}", f"Hand_{side}"]))

    return parts


def build_armature() -> bpy.types.Object:
    arm = bpy.data.armatures.new("ToadArmature")
    rig = bpy.data.objects.new("ToadRig", arm)
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


def skin_part(obj: bpy.types.Object, allowed: list[str], falloff: float = 3.4) -> None:
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
        pose_offset(rig, "Body", Vector((0.0, 0.0, 0.012 * breath)))
        pose_rotate(rig, "Head", rx=4.0 * math.sin(q + 0.4), rz=3.0 * math.sin(q))
        pose_rotate(rig, "Jaw", rx=3.0 + 4.0 * max(0.0, math.sin(q)))
        return {"Body", "Head", "Jaw"}
    return poser


def walk_pose(rig):
    def poser(t: float):
        q = 2.0 * math.pi * t
        hop = max(0.0, math.sin(q))
        pose_offset(rig, "Body", Vector((0.0, 0.04 * hop, 0.08 * hop)))
        pose_rotate(rig, "Body", rx=-8.0 * hop)
        pose_rotate(rig, "Head", rx=6.0 * hop)
        for side, sign in (("R", 1.0), ("L", -1.0)):
            leg = q if side == "R" else q + math.pi
            pose_rotate(rig, f"Thigh_{side}", rx=28.0 * math.cos(leg))
            pose_rotate(rig, f"Shin_{side}", rx=-20.0 - 18.0 * max(0.0, math.sin(leg)))
            pose_rotate(rig, f"Foot_{side}", rx=10.0 * math.sin(leg))
            pose_rotate(rig, f"Arm_{side}", rx=12.0 * math.cos(leg + math.pi), rz=-sign * 8.0)
        return {
            "Body", "Head",
            "Thigh_R", "Thigh_L", "Shin_R", "Shin_L", "Foot_R", "Foot_L",
            "Arm_R", "Arm_L",
        }
    return poser


def die_pose(rig):
    def poser(t: float):
        flop = _smoothstep(0.0, 0.85, t)
        pose_offset(rig, "Body", Vector((0.0, 0.06 * flop, -0.08 * flop)))
        pose_rotate(rig, "Body", rx=-12.0 * flop, rz=70.0 * flop)
        pose_rotate(rig, "Head", rx=-18.0 * flop)
        pose_rotate(rig, "Jaw", rx=22.0 * flop)
        pose_rotate(rig, "Thigh_L", rx=24.0 * flop)
        pose_rotate(rig, "Thigh_R", rx=10.0 * flop)
        return {"Body", "Head", "Jaw", "Thigh_L", "Thigh_R"}
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
        ("Idle", 64, idle_pose(rig), True),
        ("Walk", 22, walk_pose(rig), True),
        ("Die", 28, die_pose(rig), False),
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
    body.name = "Toad"
    body.data.name = "ToadBody"
    return body


def sharpen_edges(obj: bpy.types.Object, angle: float = 48.0) -> None:
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
    bpy.ops.object.camera_add(location=(1.4, 1.9, 0.95))
    cam = bpy.context.active_object
    direction = Vector((0.0, 0.08, 0.28)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    bpy.ops.object.light_add(type="AREA", location=(1.2, -1.0, 2.0))
    light = bpy.context.active_object
    light.data.energy = 420
    light.data.size = 2.0
    bpy.ops.object.light_add(type="AREA", location=(-0.8, 1.0, 1.4))
    fill = bpy.context.active_object
    fill.data.energy = 140
    fill.data.size = 1.6
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
        bg.inputs[0].default_value = (0.16, 0.18, 0.14, 1.0)
        bg.inputs[1].default_value = 0.4
    try:
        bpy.ops.render.render(write_still=True)
        print(f"Wrote {PNG_OUT}")
    except Exception as exc:
        print(f"Preview render skipped: {exc}")


def main() -> None:
    clear_scene()
    parts = build_character()
    for obj, _allowed in parts:
        if obj.name.startswith(("Body", "Head", "Thigh")):
            add_surface_noise(obj, 0.005, 0.0018, seed=hash(obj.name) % 17)
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
        f"Toad: {len(body.data.vertices)} verts, {triangles} tris, "
        f"{len(body.material_slots)} materials, {len(bpy.data.actions)} actions"
    )
    BLEND_OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
    export(rig, body)
    render_preview()


if __name__ == "__main__":
    main()
