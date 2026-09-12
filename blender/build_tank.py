"""Build a Left 4 Dead-style Tank: hulking mutant in jeans, knuckle-draggers.

Authored headlessly through Blender's Python API. Output is a skinned GLB with
Idle / Walk / Die clips plus a .blend for inspection. The silhouette is hunched
under the 2.1 m door lintel so the creature can patrol the generated rooms.

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
BLEND_OUT = Path("/workspace/blender/enemy_tank.blend")
GLB_OUT = OUT_DIR / "enemy_tank.glb"
PNG_OUT = Path("/opt/cursor/artifacts/blender_enemy_tank.png")

SEGMENTS = 14


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


def mat(name: str, hex_color: str, roughness: float = 0.72, specular: float = 0.35):
    material = bpy.data.materials.new(name=name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = srgb(hex_color)
    bsdf.inputs["Roughness"].default_value = roughness
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = specular
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


def box(name: str, material, centre, size, power: float = 0.42) -> bpy.types.Object:
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


def _bump(x: float, centre: float, width: float) -> float:
    return math.exp(-((x - centre) / width) ** 2)


def add_surface_noise(obj: bpy.types.Object, fold: float, grain: float, seed: float = 0.0) -> None:
    for vert in obj.data.vertices:
        point = vert.co + Vector((seed, seed * 0.37, seed * 0.13))
        offset = fold * noise.noise(point * 6.2) + grain * noise.noise(point * 28.0)
        vert.co = point - Vector((seed, seed * 0.37, seed * 0.13)) + vert.normal * offset
    obj.data.update()


# --------------------------------------------------------------------------- #
# Head
# --------------------------------------------------------------------------- #

HEAD_CENTRE = Vector((0.0, 0.22, 1.78))
HEAD_RADII = Vector((0.112, 0.128, 0.132))

SKULL_WIDTH = [
    (-1.00, 0.22), (-0.85, 0.52), (-0.70, 0.74), (-0.50, 0.90), (-0.25, 0.99),
    (0.00, 1.00), (0.30, 0.94), (0.55, 0.82), (0.75, 0.64), (0.88, 0.42),
    (0.96, 0.22), (1.00, 0.0),
]
SKULL_DEPTH = [
    (-1.00, 0.34), (-0.85, 0.62), (-0.70, 0.80), (-0.50, 0.92), (-0.25, 0.99),
    (0.00, 1.00), (0.30, 0.96), (0.55, 0.84), (0.75, 0.66), (0.88, 0.44),
    (0.96, 0.24), (1.00, 0.0),
]


def _curve(table: list[tuple[float, float]], x: float) -> float:
    if x <= table[0][0]:
        return table[0][1]
    for (x0, y0), (x1, y1) in zip(table, table[1:]):
        if x <= x1:
            t = (x - x0) / (x1 - x0)
            return y0 + (y1 - y0) * (t * t * (3.0 - 2.0 * t))
    return table[-1][1]


def skull_point(u: float, v: float) -> Vector:
    theta = 2.0 * math.pi * u
    height = math.cos(math.pi * v)
    front = max(0.0, math.sin(theta))
    width = HEAD_RADII.x * _curve(SKULL_WIDTH, height)
    depth = HEAD_RADII.y * _curve(SKULL_DEPTH, height)
    x = width * math.cos(theta)
    y = depth * math.sin(theta)
    z = HEAD_RADII.z * height
    if y < 0.0:
        y *= 0.92
    y += 0.010 * _bump(height, 0.28, 0.12) * front
    y -= 0.012 * _bump(height, 0.02, 0.10) * max(0.0, front - 0.4)
    y += 0.008 * _bump(height, -0.82, 0.14) * max(0.0, front - 0.5)
    return Vector((x, y, z)) + HEAD_CENTRE


def build_head(skin) -> bpy.types.Object:
    segments = 24
    v_values = [i / 18 for i in range(19)]
    bm = bmesh.new()
    rings = []
    for v in v_values:
        if v <= 0.0:
            rings.append([bm.verts.new(skull_point(0.0, 0.0))] * segments)
            continue
        rings.append([bm.verts.new(skull_point(i / segments, v)) for i in range(segments)])
    for lower, upper in zip(rings, rings[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            if lower[i] is lower[j]:
                bm.faces.new((upper[i], upper[j], lower[i]))
            else:
                bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
    centre = bm.verts.new(sum((vert.co for vert in rings[-1]), Vector()) / segments)
    for i in range(segments):
        j = (i + 1) % segments
        bm.faces.new((rings[-1][j], rings[-1][i], centre))
    return _finish("Head", bm, skin)


def front_y(x: float, z: float) -> float:
    best_y, best_error = 0.0, float("inf")
    for i in range(90):
        u = 0.002 + 0.496 * i / 89
        for j in range(1, 120):
            point = skull_point(u, j / 120)
            error = (point.x - x) ** 2 + (point.z - z) ** 2
            if error < best_error:
                best_error, best_y = error, point.y
    return best_y


# --------------------------------------------------------------------------- #
# Body
# --------------------------------------------------------------------------- #

BONES = [
    # name, parent, head, tail
    ("Hips", None, (0.0, 0.05, 0.78), (0.0, 0.07, 1.00)),
    ("Spine", "Hips", (0.0, 0.07, 1.00), (0.0, 0.12, 1.26)),
    ("Chest", "Spine", (0.0, 0.12, 1.26), (0.0, 0.18, 1.52)),
    ("Neck", "Chest", (0.0, 0.18, 1.52), (0.0, 0.21, 1.66)),
    ("Head", "Neck", (0.0, 0.21, 1.66), (0.0, 0.24, 1.90)),
    ("UpperArm_R", "Chest", (0.40, 0.14, 1.48), (0.52, 0.18, 1.05)),
    ("Forearm_R", "UpperArm_R", (0.52, 0.18, 1.05), (0.58, 0.26, 0.52)),
    ("Hand_R", "Forearm_R", (0.58, 0.26, 0.52), (0.62, 0.34, 0.12)),
    ("UpperArm_L", "Chest", (-0.44, 0.16, 1.48), (-0.60, 0.24, 0.98)),
    ("Forearm_L", "UpperArm_L", (-0.60, 0.24, 0.98), (-0.70, 0.34, 0.42)),
    ("Hand_L", "Forearm_L", (-0.70, 0.34, 0.42), (-0.74, 0.44, 0.08)),
    ("Thigh_R", "Hips", (0.16, 0.02, 0.78), (0.18, 0.04, 0.42)),
    ("Shin_R", "Thigh_R", (0.18, 0.04, 0.42), (0.16, 0.08, 0.12)),
    ("Foot_R", "Shin_R", (0.16, 0.08, 0.12), (0.16, 0.22, 0.04)),
    ("Thigh_L", "Hips", (-0.16, 0.02, 0.78), (-0.18, 0.04, 0.42)),
    ("Shin_L", "Thigh_L", (-0.18, 0.04, 0.42), (-0.16, 0.08, 0.12)),
    ("Foot_L", "Shin_L", (-0.16, 0.08, 0.12), (-0.16, 0.22, 0.04)),
]


def build_character() -> list[tuple[bpy.types.Object, list[str]]]:
    skin = mat("TankSkin", "#c6b6ac", roughness=0.66)
    blood = mat("TankBlood", "#7a241c", roughness=0.52)
    jeans = mat("TankJeans", "#3a4550", roughness=0.88)
    jeans_dark = mat("TankJeansDark", "#2a333c", roughness=0.9)
    boot = mat("TankBoot", "#1a1816", roughness=0.48)
    sole = mat("TankSole", "#11100e", roughness=0.7)
    tooth = mat("TankTooth", "#e8dfd0", roughness=0.28)
    gum = mat("TankGum", "#8a3a3a", roughness=0.55)
    eye_w = mat("TankEyeWhite", "#e6dcd0", roughness=0.22)
    iris = mat("TankIris", "#2a221c", roughness=0.18)
    hair = mat("TankHair", "#2c241c", roughness=0.9)
    nail = mat("TankNail", "#8a7468", roughness=0.4)

    spine = ["Hips", "Spine", "Chest"]
    parts: list[tuple[bpy.types.Object, list[str]]] = []

    # Hunched torso: rings drift +Y as they rise so the creature leans forward.
    parts.append((tube("Pelvis", jeans, [
        {"c": (0.0, 0.04, 0.70), "rx": 0.24, "ry": 0.17, "p": 0.76},
        {"c": (0.0, 0.06, 0.84), "rx": 0.27, "ry": 0.19, "p": 0.72},
        {"c": (0.0, 0.08, 0.96), "rx": 0.25, "ry": 0.18, "p": 0.76},
    ], cap_start="flat", cap_end="flat"), ["Hips", "Spine"]))

    parts.append((tube("Belly", skin, [
        {"c": (0.0, 0.10, 0.94), "rx": 0.24, "ry": 0.19, "p": 0.80},
        {"c": (0.0, 0.16, 1.12), "rx": 0.30, "ry": 0.24, "p": 0.74},
        {"c": (0.0, 0.20, 1.28), "rx": 0.34, "ry": 0.26, "p": 0.70},
    ], cap_start="flat", cap_end="flat"), ["Hips", "Spine", "Chest"]))

    parts.append((tube("Chest", skin, [
        {"c": (0.0, 0.18, 1.24), "rx": 0.36, "ry": 0.26, "p": 0.68},
        {"c": (0.0, 0.24, 1.40), "rx": 0.48, "ry": 0.30, "p": 0.60},
        {"c": (0.0, 0.26, 1.52), "rx": 0.52, "ry": 0.28, "p": 0.58},
        {"c": (0.0, 0.22, 1.60), "rx": 0.34, "ry": 0.20, "p": 0.70},
    ], cap_start="flat", cap_end="flat"), ["Spine", "Chest"]))

    parts.append((tube("Pecs", skin, [
        {"c": (0.0, 0.36, 1.32), "rx": 0.28, "ry": 0.11, "p": 0.78},
        {"c": (0.0, 0.42, 1.44), "rx": 0.32, "ry": 0.13, "p": 0.74},
        {"c": (0.0, 0.38, 1.54), "rx": 0.24, "ry": 0.10, "p": 0.80},
    ], cap_start="dome", cap_end="flat"), ["Chest"]))

    parts.append((box("WoundChest", blood, (0.12, 0.48, 1.44), (0.18, 0.05, 0.14)), ["Chest"]))
    parts.append((box("WoundShoulder", blood, (-0.38, 0.30, 1.54), (0.20, 0.10, 0.12)), ["Chest", "UpperArm_L"]))

    parts.append((tube("Neck", skin, [
        {"c": (0.0, 0.16, 1.54), "rx": 0.10, "ry": 0.11, "p": 0.92},
        {"c": (0.0, 0.20, 1.64), "rx": 0.09, "ry": 0.10, "p": 0.94},
        {"c": (0.0, 0.22, 1.70), "rx": 0.085, "ry": 0.095, "p": 0.95},
    ], cap_start="flat", cap_end="flat"), ["Chest", "Neck", "Head"]))

    parts.append((build_head(skin), ["Neck", "Head"]))
    parts.append((tube("Hair", hair, [
        {"c": (0.0, 0.16, 1.86), "rx": 0.09, "ry": 0.10, "p": 0.92},
        {"c": (0.0, 0.12, 1.90), "rx": 0.07, "ry": 0.08, "p": 0.92},
        {"c": (0.0, 0.10, 1.925), "rx": 0.03, "ry": 0.04, "p": 0.95},
    ], cap_start="flat", cap_end="dome", segments=12), ["Head"]))

    # Brow, nose, snarling mouth, teeth, eyes.
    brow_y = front_y(0.0, 1.84) + 0.008
    parts.append((box("Brow_L", hair, (-0.045, brow_y, 1.842), (0.055, 0.03, 0.022)), ["Head"]))
    parts.append((box("Brow_R", hair, (0.045, brow_y, 1.842), (0.055, 0.03, 0.022)), ["Head"]))
    nose_y = front_y(0.0, 1.76) + 0.02
    parts.append((tube("Nose", skin, [
        {"c": (0.0, nose_y - 0.01, 1.78), "rx": 0.018, "ry": 0.016, "p": 0.8},
        {"c": (0.0, nose_y + 0.03, 1.755), "rx": 0.022, "ry": 0.020, "p": 0.75},
        {"c": (0.0, nose_y + 0.05, 1.735), "rx": 0.016, "ry": 0.014, "p": 0.8},
    ], cap_start="flat", cap_end="dome", segments=10), ["Head"]))

    mouth_y = front_y(0.0, 1.70) + 0.01
    parts.append((box("MouthCavity", gum, (0.0, mouth_y, 1.695), (0.10, 0.06, 0.055)), ["Head"]))
    parts.append((box("Jaw", skin, (0.0, mouth_y + 0.01, 1.655), (0.12, 0.08, 0.05)), ["Head"]))
    for i, x in enumerate((-0.032, -0.012, 0.012, 0.032)):
        parts.append((box(f"ToothUpper_{i}", tooth, (x, mouth_y + 0.028, 1.712), (0.014, 0.012, 0.022)), ["Head"]))
        parts.append((box(f"ToothLower_{i}", tooth, (x, mouth_y + 0.024, 1.678), (0.013, 0.011, 0.018)), ["Head"]))

    for side, sign in (("R", 1.0), ("L", -1.0)):
        eye_x = sign * 0.042
        eye_z = 1.805
        eye_y = front_y(eye_x, eye_z) + 0.006
        parts.append((tube(f"EyeWhite_{side}", eye_w, [
            {"c": (eye_x, eye_y, eye_z), "rx": 0.016, "ry": 0.012},
            {"c": (eye_x, eye_y + 0.012, eye_z), "rx": 0.015, "ry": 0.011},
        ], cap_start="dome", cap_end="dome", segments=10), ["Head"]))
        parts.append((tube(f"Iris_{side}", iris, [
            {"c": (eye_x, eye_y + 0.010, eye_z), "rx": 0.008, "ry": 0.007},
            {"c": (eye_x, eye_y + 0.016, eye_z), "rx": 0.006, "ry": 0.005},
        ], cap_start="flat", cap_end="dome", segments=8), ["Head"]))
        parts.append((box(f"Ear_{side}", skin, (sign * 0.112, 0.18, 1.78), (0.03, 0.05, 0.07)), ["Head"]))

    # Legs: one jeans tube per side so the knee does not split, then a boot.
    for side, sign in (("R", 1.0), ("L", -1.0)):
        x = sign * 0.16
        parts.append((tube(f"Leg_{side}", jeans, [
            {"c": (x, 0.04, 0.78), "rx": 0.135, "ry": 0.125, "p": 0.76},
            {"c": (x, 0.05, 0.62), "rx": 0.125, "ry": 0.115, "p": 0.78},
            {"c": (x, 0.06, 0.46), "rx": 0.115, "ry": 0.105, "p": 0.80},
            {"c": (x, 0.07, 0.32), "rx": 0.100, "ry": 0.095, "p": 0.84},
            {"c": (x, 0.08, 0.16), "rx": 0.090, "ry": 0.085, "p": 0.88},
        ], cap_start="flat", cap_end="flat"), ["Hips", f"Thigh_{side}", f"Shin_{side}"]))
        parts.append((tube(f"Boot_{side}", boot, [
            {"c": (x, 0.09, 0.15), "rx": 0.088, "ry": 0.090, "p": 0.7},
            {"c": (x, 0.14, 0.08), "rx": 0.092, "ry": 0.125, "p": 0.64},
            {"c": (x, 0.22, 0.045), "rx": 0.080, "ry": 0.140, "p": 0.7},
        ], cap_start="flat", cap_end="flat"), [f"Shin_{side}", f"Foot_{side}"]))
        parts.append((box(f"Sole_{side}", sole, (x, 0.18, 0.02), (0.16, 0.30, 0.035)), [f"Foot_{side}"]))

    # Continuous hanging arms. The left is the dragging hammer fist.
    arm_specs = {
        "R": {
            "sign": 1.0,
            "rings": [
                {"c": (0.28, 0.16, 1.52), "rx": 0.20, "ry": 0.16, "p": 0.70},
                {"c": (0.40, 0.14, 1.48), "rx": 0.17, "ry": 0.15, "p": 0.72},
                {"c": (0.48, 0.16, 1.22), "rx": 0.15, "ry": 0.14, "p": 0.74},
                {"c": (0.52, 0.18, 1.05), "rx": 0.13, "ry": 0.13, "p": 0.76},
                {"c": (0.56, 0.22, 0.78), "rx": 0.145, "ry": 0.14, "p": 0.70},
                {"c": (0.58, 0.26, 0.52), "rx": 0.12, "ry": 0.12, "p": 0.74},
                {"c": (0.60, 0.32, 0.22), "rx": 0.13, "ry": 0.12, "p": 0.70},
                {"c": (0.62, 0.36, 0.10), "rx": 0.15, "ry": 0.13, "p": 0.65},
            ],
            "blood": (0.54, 0.20, 1.16),
        },
        "L": {
            "sign": -1.0,
            "rings": [
                {"c": (-0.30, 0.18, 1.52), "rx": 0.24, "ry": 0.18, "p": 0.66},
                {"c": (-0.44, 0.16, 1.48), "rx": 0.21, "ry": 0.18, "p": 0.68},
                {"c": (-0.54, 0.20, 1.18), "rx": 0.19, "ry": 0.17, "p": 0.70},
                {"c": (-0.60, 0.24, 0.98), "rx": 0.17, "ry": 0.16, "p": 0.72},
                {"c": (-0.66, 0.30, 0.68), "rx": 0.19, "ry": 0.18, "p": 0.66},
                {"c": (-0.70, 0.34, 0.42), "rx": 0.16, "ry": 0.15, "p": 0.70},
                {"c": (-0.73, 0.40, 0.18), "rx": 0.17, "ry": 0.16, "p": 0.64},
                {"c": (-0.74, 0.46, 0.07), "rx": 0.19, "ry": 0.17, "p": 0.60},
            ],
            "blood": (-0.68, 0.32, 0.55),
        },
    }
    for side, spec in arm_specs.items():
        parts.append((tube(
            f"Arm_{side}",
            skin,
            spec["rings"],
            cap_start="dome",
            cap_end="dome",
            segments=16,
        ), ["Chest", f"UpperArm_{side}", f"Forearm_{side}", f"Hand_{side}"]))
        fist = spec["rings"][-1]["c"]
        parts.append((box(
            f"KnuckleBlood_{side}",
            blood,
            (fist[0], fist[1] + 0.04, fist[2] + 0.02),
            (0.16, 0.08, 0.10),
        ), [f"Hand_{side}"]))
        parts.append((box(
            f"BloodArm_{side}",
            blood,
            spec["blood"],
            (0.12, 0.10, 0.22),
        ), [f"UpperArm_{side}", f"Forearm_{side}"]))
        for i, dx in enumerate((-0.05, -0.015, 0.02, 0.055)):
            parts.append((box(
                f"Knuckle_{side}_{i}",
                nail,
                (fist[0] + dx, fist[1] + 0.08, fist[2] + 0.05),
                (0.04, 0.05, 0.045),
            ), [f"Hand_{side}"]))

    return parts


def build_armature() -> bpy.types.Object:
    arm = bpy.data.armatures.new("TankArmature")
    rig = bpy.data.objects.new("TankRig", arm)
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
        breath = math.sin(2.0 * q)
        shift = math.sin(q)
        pose_offset(rig, "Hips", Vector((0.0, 0.0, 0.012 * breath)))
        pose_rotate(rig, "Spine", rx=1.6 * breath)
        pose_rotate(rig, "Chest", rx=2.4 * breath, rz=-1.2 * shift)
        pose_rotate(rig, "Head", rx=-4.0 + 2.2 * math.sin(q + 0.4), rz=3.0 * shift)
        pose_rotate(rig, "UpperArm_L", rx=2.0 * breath, ry=1.6 * shift)
        pose_rotate(rig, "UpperArm_R", rx=1.6 * breath, ry=-1.2 * shift)
        return {"Hips", "Spine", "Chest", "Head", "UpperArm_L", "UpperArm_R"}
    return poser


def walk_pose(rig):
    def poser(t: float):
        q = 2.0 * math.pi * t
        pose_offset(rig, "Hips", Vector((0.0, 0.0, -0.03 * (1.0 + math.cos(2.0 * q)))))
        pose_rotate(rig, "Hips", rx=6.0, ry=-5.0 * math.sin(q), rz=8.0 * math.cos(q))
        pose_rotate(rig, "Spine", rx=8.0, rz=-4.0 * math.cos(q))
        pose_rotate(rig, "Chest", rx=6.0, rz=-6.0 * math.cos(q))
        pose_rotate(rig, "Head", rx=-8.0, rz=4.0 * math.cos(q))
        for side, sign in (("R", 1.0), ("L", -1.0)):
            leg = q if side == "R" else q + math.pi
            pose_rotate(rig, f"Thigh_{side}", rx=22.0 * math.cos(leg))
            pose_rotate(rig, f"Shin_{side}", rx=-18.0 - 20.0 * max(0.0, math.sin(leg)))
            pose_rotate(rig, f"Foot_{side}", rx=8.0 * math.sin(leg))
            pose_rotate(rig, f"UpperArm_{side}", rx=10.0 * math.cos(leg + math.pi), ry=-sign * 4.0)
            pose_rotate(rig, f"Forearm_{side}", rx=6.0)
        return {"Hips", "Spine", "Chest", "Head",
                "Thigh_R", "Thigh_L", "Shin_R", "Shin_L", "Foot_R", "Foot_L",
                "UpperArm_R", "UpperArm_L", "Forearm_R", "Forearm_L"}
    return poser


def die_pose(rig):
    def poser(t: float):
        buckle = _smoothstep(0.0, 0.4, t)
        fall = _smoothstep(0.2, 0.9, t)
        pose_offset(rig, "Hips", Vector((0.0, 0.18 * fall, -0.22 * buckle - 0.42 * fall)))
        pose_rotate(rig, "Hips", rx=38.0 * fall)
        pose_rotate(rig, "Spine", rx=16.0 * buckle + 22.0 * fall)
        pose_rotate(rig, "Chest", rx=12.0 * fall)
        pose_rotate(rig, "Head", rx=18.0 * buckle - 10.0 * fall)
        pose_rotate(rig, "Thigh_L", rx=28.0 * buckle)
        pose_rotate(rig, "Thigh_R", rx=20.0 * buckle)
        pose_rotate(rig, "Shin_L", rx=-40.0 * buckle)
        pose_rotate(rig, "Shin_R", rx=-32.0 * buckle)
        pose_rotate(rig, "UpperArm_L", rx=12.0 * fall, ry=18.0 * fall)
        pose_rotate(rig, "UpperArm_R", rx=8.0 * fall, ry=-14.0 * fall)
        return {"Hips", "Spine", "Chest", "Head", "Thigh_L", "Thigh_R",
                "Shin_L", "Shin_R", "UpperArm_L", "UpperArm_R"}
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
        ("Walk", 28, walk_pose(rig), True),
        ("Die", 30, die_pose(rig), False),
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
    body.name = "Tank"
    body.data.name = "TankBody"
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
    bpy.ops.object.camera_add(location=(2.8, 3.9, 1.55))
    cam = bpy.context.active_object
    direction = Vector((0.0, 0.20, 1.05)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    bpy.ops.object.light_add(type="AREA", location=(2.2, -2.4, 3.6))
    light = bpy.context.active_object
    light.data.energy = 700
    light.data.size = 3.4
    bpy.ops.object.light_add(type="AREA", location=(-1.6, 2.0, 2.4))
    fill = bpy.context.active_object
    fill.data.energy = 180
    fill.data.size = 2.4
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
        bg.inputs[0].default_value = (0.16, 0.18, 0.20, 1.0)
        bg.inputs[1].default_value = 0.45
    try:
        bpy.ops.render.render(write_still=True)
        print(f"Wrote {PNG_OUT}")
    except Exception as exc:
        print(f"Preview render skipped: {exc}")


def main() -> None:
    clear_scene()
    parts = build_character()
    for obj, _allowed in parts:
        if obj.name.startswith(("Leg", "Belly", "Chest", "Arm", "Head", "Pecs")):
            add_surface_noise(obj, 0.004, 0.0014, seed=hash(obj.name) % 17)
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
        f"Tank: {len(body.data.vertices)} verts, {triangles} tris, "
        f"{len(body.material_slots)} materials, {len(bpy.data.actions)} actions"
    )
    BLEND_OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
    export(rig, body)
    render_preview()


if __name__ == "__main__":
    main()
