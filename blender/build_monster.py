"""Build the hare: the Soglot, a hunched predatory stalker.

Concept sheet STLK-SOGLOT-01 — dark leathery hide, torn membranes, calcified
plates, scavenged straps, and a corroded back tank with hoses. Authored
headlessly through Blender's Python API. Output is a skinned GLB with Idle /
Walk / Die clips plus a .blend.

The sheet's scale bar puts an upright Soglot near 3 m. Rooms only clear 2.1 m
under the lintel, so this rest pose keeps the hunched back under 2.0 m and
spends the length in the arms, beak, and feet.

Conventions match the other builders:
  * +Z up, feet on z = 0, character faces +Y, +X is the character's right.
  * Export uses export_yup, so +Y in Blender becomes -Z in Godot.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Vector, noise

OUT_DIR = Path("/workspace/godot/assets/characters")
BLEND_OUT = Path("/workspace/blender/enemy_monster.blend")
GLB_OUT = OUT_DIR / "enemy_monster.glb"
PNG_OUT = Path("/opt/cursor/artifacts/soglot_three_quarter.png")

SEGMENTS = 12

# name, parent, head, tail
BONES = [
    ("Hips", None, (0.0, 0.00, 0.82), (0.0, 0.10, 1.06)),
    ("Spine", "Hips", (0.0, 0.10, 1.06), (0.0, 0.18, 1.36)),
    ("Chest", "Spine", (0.0, 0.18, 1.36), (0.0, 0.24, 1.64)),
    ("Neck", "Chest", (0.0, 0.32, 1.52), (0.0, 0.54, 1.40)),
    ("Head", "Neck", (0.0, 0.54, 1.40), (0.0, 0.92, 1.14)),
    ("Jaw", "Head", (0.0, 0.60, 1.26), (0.0, 0.86, 1.08)),
    ("UpperArm_R", "Chest", (0.46, 0.18, 1.50), (0.58, 0.30, 0.86)),
    ("Forearm_R", "UpperArm_R", (0.58, 0.30, 0.86), (0.50, 0.40, 0.34)),
    ("Hand_R", "Forearm_R", (0.50, 0.40, 0.34), (0.48, 0.48, 0.10)),
    ("UpperArm_L", "Chest", (-0.46, 0.18, 1.50), (-0.58, 0.30, 0.86)),
    ("Forearm_L", "UpperArm_L", (-0.58, 0.30, 0.86), (-0.50, 0.40, 0.34)),
    ("Hand_L", "Forearm_L", (-0.50, 0.40, 0.34), (-0.48, 0.48, 0.10)),
    ("Thigh_R", "Hips", (0.15, 0.02, 0.86), (0.20, 0.20, 0.44)),
    ("Shin_R", "Thigh_R", (0.20, 0.20, 0.44), (0.15, 0.04, 0.08)),
    ("Foot_R", "Shin_R", (0.15, 0.04, 0.08), (0.15, 0.32, 0.035)),
    ("Thigh_L", "Hips", (-0.15, 0.02, 0.86), (-0.20, 0.20, 0.44)),
    ("Shin_L", "Thigh_L", (-0.20, 0.20, 0.44), (-0.15, 0.04, 0.08)),
    ("Foot_L", "Shin_L", (-0.15, 0.04, 0.08), (-0.15, 0.32, 0.035)),
]

SPINE = ["Hips", "Spine", "Chest"]


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
        channel = int(hex_color[i : i + 2], 16) / 255.0
        out.append(channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


def mat(
    name: str,
    hex_color: str,
    roughness: float = 0.72,
    metallic: float = 0.0,
    emission: str | None = None,
    emission_strength: float = 0.0,
    double_sided: bool = False,
):
    material = bpy.data.materials.new(name=name)
    material.use_nodes = True
    if double_sided and hasattr(material, "use_backface_culling"):
        material.use_backface_culling = False
    bsdf = material.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = srgb(hex_color)
    bsdf.inputs["Roughness"].default_value = roughness
    if "Metallic" in bsdf.inputs:
        bsdf.inputs["Metallic"].default_value = metallic
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.32
    if emission and "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = srgb(emission)
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emission_strength
    return material


def _profile(angle: float, rx: float, ry: float, power: float) -> tuple[float, float]:
    cosine, sine = math.cos(angle), math.sin(angle)
    return (
        math.copysign(abs(cosine) ** power, cosine) * rx,
        math.copysign(abs(sine) ** power, sine) * ry,
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
    dome_rings: int = 2,
) -> bpy.types.Object:
    u = Vector(axis_u).normalized()
    v = Vector(axis_v).normalized()
    rings: list[tuple[Vector, float, float, float]] = [
        (Vector(section["c"]), section["rx"], section["ry"], section.get("p", 1.0))
        for section in sections
    ]

    def dome_extension(inner, outer):
        centre, rx, ry, power = outer
        direction = (centre - inner[0]).normalized()
        height = 0.85 * (rx + ry) * 0.5
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
        if mode == "none" or not verts:
            return
        if mode == "flat" or pole_location is None:
            pole_location = sum((vert.co for vert in verts), Vector()) / len(verts)
        pole = bm.verts.new(pole_location)
        for i in range(segments):
            j = (i + 1) % segments
            trio = (verts[i], verts[j], pole)
            bm.faces.new(trio[::-1] if flip else trio)

    close(ring_verts[0], start_pole, cap_start, False)
    close(ring_verts[-1], end_pole, cap_end, True)
    return _finish(name, bm, material)


def box(name: str, material, centre, size, power: float = 0.45) -> bpy.types.Object:
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


def curve_tube(name: str, material, points: list, radii: list[float], segments: int = 7) -> bpy.types.Object:
    """Tube following a polyline, with a cross-section normal to the tangent."""
    pts = [Vector(point) for point in points]
    bm = bmesh.new()
    rings = []
    side = None
    for index, point in enumerate(pts):
        if index == 0:
            tangent = pts[1] - pts[0]
        elif index == len(pts) - 1:
            tangent = pts[-1] - pts[-2]
        else:
            tangent = pts[index + 1] - pts[index - 1]
        if tangent.length < 1e-6:
            tangent = Vector((0.0, 0.0, 1.0))
        tangent.normalize()
        if side is None:
            up = Vector((0.0, 0.0, 1.0))
            if abs(tangent.dot(up)) > 0.85:
                up = Vector((1.0, 0.0, 0.0))
            side = tangent.cross(up).normalized()
        else:
            side = side - tangent * side.dot(tangent)
            if side.length < 1e-6:
                side = tangent.cross(Vector((0.0, 0.0, 1.0)))
            side.normalize()
        binormal = tangent.cross(side).normalized()
        radius = radii[min(index, len(radii) - 1)]
        verts = []
        for step in range(segments):
            angle = 2.0 * math.pi * step / segments
            verts.append(bm.verts.new(
                point + side * (math.cos(angle) * radius) + binormal * (math.sin(angle) * radius)
            ))
        rings.append(verts)

    for lower, upper in zip(rings, rings[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((lower[i], lower[j], upper[j], upper[i]))

    for ring, flip in ((rings[0], False), (rings[-1], True)):
        pole = bm.verts.new(sum((vert.co for vert in ring), Vector()) / segments)
        for i in range(segments):
            j = (i + 1) % segments
            trio = (ring[i], ring[j], pole)
            bm.faces.new(trio[::-1] if flip else trio)
    return _finish(name, bm, material)


def ribbon(name: str, material, edge_a: list, edge_b: list, thickness: float = 0.012) -> bpy.types.Object:
    a = [Vector(point) for point in edge_a]
    b = [Vector(point) for point in edge_b]
    normal = Vector((0.0, 0.0, 0.0))
    for index in range(len(a) - 1):
        normal += (a[index + 1] - a[index]).cross(b[index] - a[index])
    if normal.length < 1e-8:
        normal = Vector((0.0, 1.0, 0.0))
    normal = normal.normalized() * (thickness * 0.5)
    bm = bmesh.new()
    top_a = [bm.verts.new(point + normal) for point in a]
    top_b = [bm.verts.new(point + normal) for point in b]
    bot_a = [bm.verts.new(point - normal) for point in a]
    bot_b = [bm.verts.new(point - normal) for point in b]
    count = len(a)
    for index in range(count - 1):
        nxt = index + 1
        bm.faces.new((top_a[index], top_a[nxt], top_b[nxt], top_b[index]))
        bm.faces.new((bot_b[index], bot_b[nxt], bot_a[nxt], bot_a[index]))
        bm.faces.new((top_a[index], bot_a[index], bot_a[nxt], top_a[nxt]))
        bm.faces.new((top_b[nxt], bot_b[nxt], bot_b[index], top_b[index]))
    bm.faces.new((top_a[0], top_b[0], bot_b[0], bot_a[0]))
    bm.faces.new((top_b[-1], top_a[-1], bot_a[-1], bot_b[-1]))
    return _finish(name, bm, material)


def torus(
    name: str,
    material,
    centre,
    major: float,
    minor: float,
    rot: tuple[float, float, float] = (0.0, 0.0, 0.0),
    segments: int = 18,
    sides: int = 6,
) -> bpy.types.Object:
    rotation = Euler(rot).to_matrix()
    origin = Vector(centre)
    bm = bmesh.new()
    rings = []
    for i in range(segments):
        angle = 2.0 * math.pi * i / segments
        ring_centre = Vector((math.cos(angle) * major, math.sin(angle) * major, 0.0))
        radial = Vector((math.cos(angle), math.sin(angle), 0.0))
        up = Vector((0.0, 0.0, 1.0))
        verts = []
        for j in range(sides):
            beta = 2.0 * math.pi * j / sides
            local = ring_centre + radial * (minor * math.cos(beta)) + up * (minor * math.sin(beta))
            verts.append(bm.verts.new(origin + rotation @ local))
        rings.append(verts)
    for i in range(segments):
        nxt = (i + 1) % segments
        for j in range(sides):
            k = (j + 1) % sides
            bm.faces.new((rings[i][j], rings[i][k], rings[nxt][k], rings[nxt][j]))
    return _finish(name, bm, material)


def _smoothstep(edge0: float, edge1: float, value: float) -> float:
    t = min(1.0, max(0.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def add_surface_noise(obj: bpy.types.Object, fold: float, grain: float, seed: float = 0.0) -> None:
    for vert in obj.data.vertices:
        point = vert.co + Vector((seed, seed * 0.37, seed * 0.13))
        offset = fold * noise.noise(point * 6.5) + grain * noise.noise(point * 26.0)
        vert.co = vert.co + vert.normal * offset
    obj.data.update()


def _sx(side: str, x: float) -> float:
    return x if side == "R" else -x


def build_character() -> list[tuple[bpy.types.Object, list[str]]]:
    hide = mat("Hide", "#2c2824", roughness=0.82)
    hide_deep = mat("HideDeep", "#141210", roughness=0.9)
    membrane = mat("Membrane", "#6a5344", roughness=0.7, double_sided=True)
    bone = mat("Calcified", "#cbb892", roughness=0.46, metallic=0.04)
    rust = mat("Rust", "#7a4b36", roughness=0.52, metallic=0.62)
    steel = mat("Steel", "#6a7074", roughness=0.34, metallic=0.88)
    tank_paint = mat("Tank", "#3e4338", roughness=0.58, metallic=0.42)
    hose_mat = mat("Hose", "#1c1a18", roughness=0.92, metallic=0.08)
    claw = mat("Claw", "#e6d7be", roughness=0.3, metallic=0.08)
    eye = mat("EyeGlow", "#3a120e", roughness=0.18, emission="#ff3418", emission_strength=8.0)
    mouth = mat("Mouth", "#0c0909", roughness=0.95)
    strap = mat("Strap", "#2a2118", roughness=0.84)

    parts: list[tuple[bpy.types.Object, list[str]]] = []

    def add(obj: bpy.types.Object, bones: list[str]) -> None:
        parts.append((obj, bones))

    # One continuous hunched volume, so the chest does not float above the hips.
    add(tube("Torso", hide, [
        {"c": (0.0, 0.02, 0.70), "rx": 0.22, "ry": 0.16, "p": 0.82},
        {"c": (0.0, 0.04, 0.86), "rx": 0.27, "ry": 0.19, "p": 0.8},
        {"c": (0.0, 0.16, 1.00), "rx": 0.29, "ry": 0.22, "p": 0.78},
        {"c": (0.0, 0.26, 1.14), "rx": 0.32, "ry": 0.23, "p": 0.76},
        {"c": (0.0, 0.20, 1.30), "rx": 0.38, "ry": 0.24, "p": 0.74},
        {"c": (0.0, 0.14, 1.46), "rx": 0.46, "ry": 0.26, "p": 0.72},
        {"c": (0.0, 0.08, 1.60), "rx": 0.50, "ry": 0.26, "p": 0.7},
        {"c": (0.0, 0.02, 1.72), "rx": 0.30, "ry": 0.16, "p": 0.76},
    ], cap_start="dome", cap_end="dome", segments=16), SPINE)

    add(tube("Belly", hide, [
        {"c": (0.0, 0.34, 0.96), "rx": 0.16, "ry": 0.08, "p": 0.75},
        {"c": (0.0, 0.42, 1.06), "rx": 0.14, "ry": 0.07, "p": 0.72},
        {"c": (0.0, 0.36, 1.16), "rx": 0.10, "ry": 0.05, "p": 0.78},
    ], cap_start="dome", cap_end="dome", segments=12), ["Hips", "Spine"])

    add(tube("Hump", bone, [
        {"c": (0.0, -0.06, 1.62), "rx": 0.14, "ry": 0.06, "p": 0.55},
        {"c": (0.0, -0.10, 1.76), "rx": 0.08, "ry": 0.035, "p": 0.5},
        {"c": (0.0, -0.12, 1.86), "rx": 0.03, "ry": 0.016, "p": 0.6},
    ], cap_start="flat", cap_end="dome", segments=10), ["Chest"])

    add(curve_tube("Neck", hide, [
        (0.0, 0.16, 1.58),
        (0.0, 0.32, 1.50),
        (0.0, 0.46, 1.44),
        (0.0, 0.58, 1.38),
    ], [0.12, 0.095, 0.082, 0.074], segments=10), ["Chest", "Neck", "Head"])

    add(tube("Skull", hide, [
        {"c": (0.0, 0.50, 1.44), "rx": 0.10, "ry": 0.11, "p": 0.72},
        {"c": (0.0, 0.62, 1.40), "rx": 0.135, "ry": 0.12, "p": 0.68},
        {"c": (0.0, 0.74, 1.32), "rx": 0.09, "ry": 0.075, "p": 0.7},
        {"c": (0.0, 0.84, 1.22), "rx": 0.048, "ry": 0.04, "p": 0.62},
        {"c": (0.0, 0.93, 1.12), "rx": 0.020, "ry": 0.016, "p": 0.7},
    ], axis_u=(1, 0, 0), axis_v=(0, 0, 1), cap_start="dome", cap_end="dome", segments=14), ["Neck", "Head"])

    add(tube("Jaw", hide_deep, [
        {"c": (0.0, 0.60, 1.28), "rx": 0.07, "ry": 0.032, "p": 0.6},
        {"c": (0.0, 0.74, 1.18), "rx": 0.045, "ry": 0.020, "p": 0.62},
        {"c": (0.0, 0.86, 1.08), "rx": 0.016, "ry": 0.010, "p": 0.7},
    ], axis_u=(1, 0, 0), axis_v=(0, 0, 1), cap_start="dome", cap_end="dome", segments=10), ["Head", "Jaw"])

    add(box("Mouth", mouth, (0.0, 0.76, 1.20), (0.07, 0.12, 0.035)), ["Head", "Jaw"])

    for index, (y, z, w, h) in enumerate((
        (0.78, 1.24, 0.012, 0.028),
        (0.84, 1.18, 0.010, 0.032),
        (0.88, 1.14, 0.008, 0.026),
    )):
        add(box(f"ToothU_{index}", claw, (0.0, y, z), (w, 0.012, h), power=0.35), ["Head"])
        add(box(f"ToothL_{index}", claw, (0.0, y - 0.01, z - 0.055), (w * 0.9, 0.01, h * 0.8), power=0.35), ["Jaw"])

    for side, sign in (("R", 1.0), ("L", -1.0)):
        socket = (sign * 0.105, 0.66, 1.385)
        add(tube(f"EyeSocket_{side}", hide_deep, [
            {"c": socket, "rx": 0.028, "ry": 0.022},
            {"c": (socket[0] + sign * 0.012, socket[1] + 0.01, socket[2]), "rx": 0.02, "ry": 0.016},
        ], axis_u=(0, 1, 0), axis_v=(0, 0, 1), cap_start="flat", cap_end="dome", segments=8), ["Head"])
        add(tube(f"Eye_{side}", eye, [
            {"c": (socket[0] + sign * 0.010, socket[1] + 0.012, socket[2]), "rx": 0.022, "ry": 0.016},
            {"c": (socket[0] + sign * 0.026, socket[1] + 0.022, socket[2]), "rx": 0.016, "ry": 0.012},
        ], axis_u=(0, 1, 0), axis_v=(0, 0, 1), cap_start="flat", cap_end="dome", segments=8), ["Head"])
        add(box(f"Brow_{side}", bone, (sign * 0.09, 0.70, 1.43), (0.06, 0.03, 0.018), power=0.4), ["Head"])

    # Calcified ridge standing off the back surface of the torso.
    for index, (z, back_y, width) in enumerate((
        (1.04, -0.08, 0.20),
        (1.18, -0.12, 0.24),
        (1.32, -0.16, 0.26),
        (1.46, -0.18, 0.24),
        (1.58, -0.18, 0.18),
    )):
        add(tube(f"Plate_{index}", bone, [
            {"c": (0.0, back_y + 0.02, z), "rx": width * 0.5, "ry": 0.022, "p": 0.48},
            {"c": (0.0, back_y - 0.045, z + 0.045), "rx": width * 0.32, "ry": 0.014, "p": 0.52},
        ], cap_start="flat", cap_end="dome", segments=6), ["Spine", "Chest"])

    # Corroded cylinder strapped to the upper back.
    add(tube("BackTank", tank_paint, [
        {"c": (0.04, -0.24, 1.30), "rx": 0.11, "ry": 0.105, "p": 0.92},
        {"c": (0.02, -0.26, 1.50), "rx": 0.125, "ry": 0.118, "p": 0.94},
        {"c": (0.00, -0.22, 1.68), "rx": 0.095, "ry": 0.09, "p": 0.92},
    ], cap_start="dome", cap_end="dome", segments=14), ["Spine", "Chest"])
    add(torus("TankBandLow", rust, (0.03, -0.25, 1.40), 0.132, 0.013, segments=16, sides=5), ["Chest", "Spine"])
    add(torus("TankBandHigh", steel, (0.01, -0.24, 1.58), 0.118, 0.011, segments=16, sides=5), ["Chest"])
    add(tube("TankValve", steel, [
        {"c": (0.00, -0.22, 1.76), "rx": 0.03, "ry": 0.03},
        {"c": (0.00, -0.22, 1.84), "rx": 0.02, "ry": 0.02},
    ], cap_start="flat", cap_end="dome", segments=8), ["Chest"])
    add(tube("TankLens", eye, [
        {"c": (0.11, -0.18, 1.54), "rx": 0.018, "ry": 0.018},
        {"c": (0.135, -0.16, 1.54), "rx": 0.012, "ry": 0.012},
    ], axis_u=(0, 1, 0), axis_v=(0, 0, 1), cap_start="flat", cap_end="dome", segments=8), ["Chest"])

    add(curve_tube("Hose_R", hose_mat, [
        (0.10, -0.18, 1.50),
        (0.26, -0.04, 1.60),
        (0.32, 0.16, 1.50),
        (0.18, 0.34, 1.42),
        (0.06, 0.46, 1.38),
    ], [0.02, 0.018, 0.017, 0.016, 0.014], segments=6), ["Chest", "Neck"])
    add(curve_tube("Hose_L", hose_mat, [
        (-0.05, -0.20, 1.40),
        (-0.22, -0.04, 1.46),
        (-0.28, 0.16, 1.34),
        (-0.14, 0.34, 1.28),
        (-0.02, 0.44, 1.32),
    ], [0.018, 0.016, 0.015, 0.014, 0.013], segments=6), ["Chest", "Neck", "Spine"])

    add(curve_tube("StrapChest", strap, [
        (-0.26, 0.38, 1.40),
        (0.0, 0.44, 1.36),
        (0.26, 0.38, 1.40),
    ], [0.016, 0.016, 0.016], segments=5), SPINE)
    add(curve_tube("StrapWaist", strap, [
        (-0.20, 0.20, 0.94),
        (0.0, 0.28, 0.88),
        (0.20, 0.20, 0.94),
    ], [0.016, 0.016, 0.016], segments=5), ["Hips", "Spine"])
    add(curve_tube("StrapShoulder", strap, [
        (0.10, 0.40, 1.30),
        (0.24, 0.18, 1.58),
        (0.10, -0.02, 1.64),
        (0.02, -0.16, 1.50),
    ], [0.014, 0.014, 0.013, 0.013], segments=5), ["Chest", "Spine"])

    for side, sign in (("R", 1.0), ("L", -1.0)):
        add(tube(f"Pauldron_{side}", rust if side == "R" else steel, [
            {"c": (sign * 0.36, 0.04, 1.64), "rx": 0.16 if side == "R" else 0.12, "ry": 0.055, "p": 0.48},
            {"c": (sign * 0.46, 0.00, 1.74), "rx": 0.09 if side == "R" else 0.07, "ry": 0.03, "p": 0.5},
        ], cap_start="flat", cap_end="dome", segments=8), ["Chest", f"UpperArm_{side}"])
        add(torus(
            f"ThighStrap_{side}",
            strap,
            (sign * 0.17, 0.10, 0.68),
            0.125,
            0.01,
            segments=14,
            sides=5,
        ), ["Hips", f"Thigh_{side}"])

    add(tube("ThighPlate_R", rust, [
        {"c": (0.22, 0.20, 0.66), "rx": 0.07, "ry": 0.016, "p": 0.4},
        {"c": (0.24, 0.26, 0.52), "rx": 0.08, "ry": 0.014, "p": 0.4},
        {"c": (0.20, 0.22, 0.40), "rx": 0.05, "ry": 0.012, "p": 0.45},
    ], cap_start="dome", cap_end="dome", segments=8), ["Thigh_R", "Shin_R"])

    for side, sign in (("R", 1.0), ("L", -1.0)):
        add(tube(f"KneeCap_{side}", bone, [
            {"c": (sign * 0.20, 0.28, 0.45), "rx": 0.055, "ry": 0.03, "p": 0.55},
            {"c": (sign * 0.20, 0.33, 0.45), "rx": 0.03, "ry": 0.016, "p": 0.6},
        ], axis_u=(1, 0, 0), axis_v=(0, 0, 1), cap_start="flat", cap_end="dome", segments=8), [f"Thigh_{side}", f"Shin_{side}"])

    # Long arms rooted inside the shoulder so the limb does not float.
    for side, sign in (("R", 1.0), ("L", -1.0)):
        add(curve_tube(f"Arm_{side}", hide, [
            (sign * 0.24, 0.12, 1.52),
            (sign * 0.42, 0.16, 1.46),
            (sign * 0.54, 0.22, 1.16),
            (sign * 0.58, 0.28, 0.88),
            (sign * 0.54, 0.34, 0.58),
            (sign * 0.50, 0.40, 0.36),
            (sign * 0.48, 0.44, 0.24),
        ], [0.15, 0.12, 0.105, 0.092, 0.08, 0.072, 0.066], segments=8), ["Chest", f"UpperArm_{side}", f"Forearm_{side}", f"Hand_{side}"])

        for flap, drop in enumerate((0.28, 0.18)):
            z = 1.22 - flap * 0.16
            add(ribbon(f"Web_{side}_{flap}", membrane, [
                (sign * 0.34, 0.16, z),
                (sign * 0.38, 0.18, z - drop * 0.45),
                (sign * 0.32, 0.14, z - drop),
            ], [
                (sign * 0.48, 0.20, z - 0.02),
                (sign * 0.50, 0.22, z - drop * 0.4),
                (sign * 0.44, 0.18, z - drop * 0.75),
            ], thickness=0.008), ["Chest", f"UpperArm_{side}", f"Forearm_{side}"])

        fingers = (
            (-0.045, 0.00),
            (0.00, 0.02),
            (0.045, 0.00),
        )
        for index, (spread, forward) in enumerate(fingers):
            root = (sign * 0.48 + sign * spread, 0.46 + forward, 0.24)
            mid = (sign * 0.48 + sign * spread * 1.5, 0.52 + forward, 0.12)
            tip = (sign * 0.47 + sign * spread * 1.8, 0.55 + forward, 0.045)
            nail = (sign * 0.46 + sign * spread * 2.0, 0.58 + forward, 0.028)
            add(curve_tube(
                f"Finger_{side}_{index}",
                hide,
                [root, mid, tip],
                [0.018, 0.014, 0.010],
                segments=5,
            ), [f"Hand_{side}"])
            add(curve_tube(
                f"Claw_{side}_{index}",
                claw,
                [tip, nail],
                [0.010, 0.004],
                segments=5,
            ), [f"Hand_{side}"])
        thumb_root = (sign * 0.40, 0.42, 0.26)
        thumb_mid = (sign * 0.32, 0.50, 0.16)
        thumb_tip = (sign * 0.30, 0.54, 0.07)
        add(curve_tube(f"Thumb_{side}", hide, [thumb_root, thumb_mid, thumb_tip], [0.02, 0.015, 0.010], segments=5), [f"Hand_{side}"])
        add(curve_tube(f"ThumbClaw_{side}", claw, [thumb_tip, (sign * 0.28, 0.57, 0.045)], [0.010, 0.004], segments=5), [f"Hand_{side}"])

    # Crouched legs continued through the foot so the ankle cannot split in the walk.
    for side, sign in (("R", 1.0), ("L", -1.0)):
        x = sign * 0.16
        add(curve_tube(f"Leg_{side}", hide, [
            (sign * 0.12, 0.02, 0.96),
            (sign * 0.16, 0.06, 0.76),
            (sign * 0.19, 0.14, 0.58),
            (sign * 0.20, 0.22, 0.44),
            (sign * 0.17, 0.10, 0.24),
            (sign * 0.15, 0.02, 0.10),
            (x, 0.16, 0.075),
            (x, 0.32, 0.058),
        ], [0.145, 0.125, 0.115, 0.108, 0.092, 0.078, 0.06, 0.04], segments=8), ["Hips", f"Thigh_{side}", f"Shin_{side}", f"Foot_{side}"])

        for index, spread in enumerate((-0.045, 0.0, 0.05)):
            root = (x + spread, 0.34, 0.05)
            mid = (x + spread * 1.4, 0.46, 0.04)
            tip = (x + spread * 1.7, 0.56, 0.032)
            add(curve_tube(f"Toe_{side}_{index}", hide, [root, mid, tip], [0.02, 0.015, 0.011], segments=5), [f"Foot_{side}"])
            add(curve_tube(
                f"ToeClaw_{side}_{index}",
                claw,
                [tip, (x + spread * 1.9, 0.64, 0.024)],
                [0.011, 0.004],
                segments=5,
            ), [f"Foot_{side}"])

    # Ragged flaps around the hips.
    for index, (x, drop, drift) in enumerate((
        (-0.16, 0.28, 0.06),
        (-0.06, 0.36, 0.10),
        (0.06, 0.32, 0.08),
        (0.16, 0.24, 0.04),
        (0.0, 0.22, -0.08),
    )):
        y = 0.16 if drift > 0 else -0.08
        add(ribbon(f"Tatter_{index}", membrane, [
            (x, y, 0.84),
            (x + 0.04, y + drift * 0.4, 0.84 - drop * 0.45),
            (x + 0.02, y + drift, 0.84 - drop),
        ], [
            (x + 0.07, y + 0.01, 0.82),
            (x + 0.09, y + drift * 0.35, 0.82 - drop * 0.4),
            (x + 0.05, y + drift * 0.8, 0.84 - drop * 0.85),
        ], thickness=0.008), ["Hips"])

    for index, loc in enumerate((
        (0.28, 0.30, 1.48),
        (-0.34, 0.16, 1.46),
        (0.16, 0.34, 1.22),
        (-0.10, 0.08, 0.55),
        (0.0, 0.66, 1.36),
    )):
        add(tube(f"Flake_{index}", bone, [
            {"c": loc, "rx": 0.045, "ry": 0.03, "p": 0.55},
            {"c": (loc[0], loc[1] + 0.012, loc[2] + 0.01), "rx": 0.028, "ry": 0.018, "p": 0.5},
        ], cap_start="flat", cap_end="dome", segments=7), SPINE + ["Head"])

    return parts


def build_armature() -> bpy.types.Object:
    arm = bpy.data.armatures.new("SoglotArmature")
    rig = bpy.data.objects.new("SoglotRig", arm)
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
    if hasattr(action, "slots") and hasattr(rig.animation_data, "action_slot"):
        slot = action.slots.new(id_type="OBJECT", name=rig.name) if len(action.slots) == 0 else action.slots[0]
        rig.animation_data.action_slot = slot
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
    curves = list(action.fcurves) if hasattr(action, "fcurves") else []
    for curve in curves:
        for keyframe in curve.keyframe_points:
            keyframe.interpolation = "BEZIER"
    return action


def idle_pose(rig):
    def poser(t: float):
        q = 2.0 * math.pi * t
        breath = math.sin(2.0 * q)
        shift = math.sin(q)
        pose_offset(rig, "Hips", Vector((0.0, 0.0, 0.012 * breath)))
        pose_rotate(rig, "Spine", rx=1.8 * breath)
        pose_rotate(rig, "Chest", rx=2.6 * breath, rz=-1.4 * shift)
        pose_rotate(rig, "Head", rx=-4.0 + 3.0 * math.sin(q + 0.4), rz=4.0 * shift)
        pose_rotate(rig, "Jaw", rx=6.0 * max(0.0, math.sin(q * 2.0)))
        pose_rotate(rig, "UpperArm_L", rx=1.5 * breath)
        pose_rotate(rig, "UpperArm_R", rx=1.2 * breath)
        return {"Hips", "Spine", "Chest", "Head", "Jaw", "UpperArm_L", "UpperArm_R"}
    return poser


def walk_pose(rig):
    def poser(t: float):
        q = 2.0 * math.pi * t
        pose_offset(rig, "Hips", Vector((0.0, 0.0, -0.028 * (1.0 + math.cos(2.0 * q)))))
        pose_rotate(rig, "Hips", rx=4.0, ry=-6.0 * math.sin(q), rz=8.0 * math.cos(q))
        pose_rotate(rig, "Spine", rx=6.0, rz=-5.0 * math.cos(q))
        pose_rotate(rig, "Chest", rx=4.0, rz=-4.0 * math.cos(q))
        pose_rotate(rig, "Head", rx=-6.0, rz=5.0 * math.cos(q))
        pose_rotate(rig, "Jaw", rx=3.0)
        for side in ("R", "L"):
            leg = q if side == "R" else q + math.pi
            pose_rotate(rig, f"Thigh_{side}", rx=18.0 * math.cos(leg))
            pose_rotate(rig, f"Shin_{side}", rx=-8.0 - 12.0 * max(0.0, math.sin(leg)))
            pose_rotate(rig, f"Foot_{side}", rx=8.0 * math.sin(leg))
            pose_rotate(rig, f"UpperArm_{side}", rx=14.0 * math.cos(leg + math.pi))
            pose_rotate(rig, f"Forearm_{side}", rx=6.0)
            pose_rotate(rig, f"Hand_{side}", rx=-8.0 + 6.0 * math.sin(leg))
        return {
            "Hips", "Spine", "Chest", "Head", "Jaw",
            "Thigh_R", "Thigh_L", "Shin_R", "Shin_L", "Foot_R", "Foot_L",
            "UpperArm_R", "UpperArm_L", "Forearm_R", "Forearm_L", "Hand_R", "Hand_L",
        }
    return poser


def die_pose(rig):
    def poser(t: float):
        buckle = _smoothstep(0.0, 0.4, t)
        fall = _smoothstep(0.18, 0.9, t)
        pose_offset(rig, "Hips", Vector((0.0, 0.35 * fall, -0.62 * fall)))
        pose_rotate(rig, "Hips", rx=72.0 * fall)
        pose_rotate(rig, "Spine", rx=18.0 * buckle + 16.0 * fall)
        pose_rotate(rig, "Chest", rx=12.0 * fall)
        pose_rotate(rig, "Head", rx=24.0 * buckle)
        pose_rotate(rig, "Jaw", rx=18.0 * fall)
        pose_rotate(rig, "Thigh_L", rx=24.0 * buckle)
        pose_rotate(rig, "Thigh_R", rx=18.0 * buckle)
        pose_rotate(rig, "Shin_L", rx=-36.0 * buckle)
        pose_rotate(rig, "Shin_R", rx=-28.0 * buckle)
        pose_rotate(rig, "UpperArm_L", rx=16.0 * fall, ry=22.0 * fall)
        pose_rotate(rig, "UpperArm_R", rx=12.0 * fall, ry=-18.0 * fall)
        return {
            "Hips", "Spine", "Chest", "Head", "Jaw",
            "Thigh_L", "Thigh_R", "Shin_L", "Shin_R", "UpperArm_L", "UpperArm_R",
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
        ("Idle", 48, idle_pose(rig), True),
        ("Walk", 14, walk_pose(rig), True),
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
    objects = [obj for obj, _bones in parts]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    body = objects[0]
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = "Soglot"
    body.data.name = "SoglotBody"
    return body


def sharpen_edges(obj: bpy.types.Object, angle: float = 42.0) -> None:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for face in bm.faces:
        face.smooth = True
    limit = math.radians(angle)
    for edge in bm.edges:
        edge.smooth = not (len(edge.link_faces) == 2 and edge.calc_face_angle() > limit)
    bm.to_mesh(obj.data)
    bm.free()


def mesh_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    xs, ys, zs = [], [], []
    for vert in obj.data.vertices:
        world = obj.matrix_world @ vert.co
        xs.append(world.x)
        ys.append(world.y)
        zs.append(world.z)
    return Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))


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


def _look_at(camera: bpy.types.Object, target: Vector) -> None:
    direction = target - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def render_turnaround(rig: bpy.types.Object, engine: str, names: set[str] | None = None) -> None:
    PNG_OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.mesh.primitive_plane_add(size=8, location=(0.0, 0.2, 0.0))
    ground = bpy.context.active_object
    ground.name = "PreviewGround"
    ground_mat = mat("PreviewGround", "#d7d3cc", roughness=0.9)
    ground.data.materials.append(ground_mat)

    bpy.ops.object.light_add(type="AREA", location=(2.4, -2.2, 3.4))
    key = bpy.context.active_object
    key.data.energy = 650
    key.data.size = 3.2
    bpy.ops.object.light_add(type="AREA", location=(-2.2, 1.6, 2.2))
    fill = bpy.context.active_object
    fill.data.energy = 180
    fill.data.size = 2.6

    scene = bpy.context.scene
    scene.render.resolution_x = 800
    scene.render.resolution_y = 800
    scene.render.film_transparent = False
    if engine == "eevee":
        scene.render.engine = "BLENDER_EEVEE_NEXT"
        if hasattr(scene, "eevee") and hasattr(scene.eevee, "taa_render_samples"):
            scene.eevee.taa_render_samples = 16
    else:
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = 16
        scene.cycles.use_denoising = True
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.78, 0.77, 0.74, 1.0)
        bg.inputs[1].default_value = 0.85

    bpy.ops.object.camera_add(location=(0.0, 4.4, 1.15))
    camera = bpy.context.active_object
    scene.camera = camera
    target = Vector((0.0, 0.15, 0.95))
    views = {
        "soglot_front": Vector((0.0, 4.6, 1.15)),
        "soglot_side": Vector((4.6, 0.25, 1.15)),
        "soglot_back": Vector((0.0, -4.4, 1.25)),
        "soglot_top": Vector((0.0, 0.15, 5.2)),
        "soglot_three_quarter": Vector((3.3, 3.1, 1.7)),
    }
    if names is not None:
        views = {key: value for key, value in views.items() if key in names}
    for name, location in views.items():
        camera.location = location
        _look_at(camera, target if name != "soglot_top" else Vector((0.0, 0.15, 0.4)))
        scene.render.filepath = str(PNG_OUT.parent / f"{name}.png")
        bpy.ops.render.render(write_still=True)
        print(f"Wrote {scene.render.filepath}")

    ground.hide_render = True
    action = bpy.data.actions["Walk"]
    rig.animation_data.action = action
    if hasattr(rig.animation_data, "action_slot") and action.slots:
        rig.animation_data.action_slot = action.slots[0]
    camera.location = Vector((3.6, 2.6, 1.35))
    _look_at(camera, target)
    for label, frame in (("soglot_walk_contact", 1), ("soglot_walk_pass", 6)):
        scene.frame_set(frame)
        scene.render.filepath = str(PNG_OUT.parent / f"{label}.png")
        bpy.ops.render.render(write_still=True)
        print(f"Wrote {scene.render.filepath}")
    rig.animation_data.action = None
    reset_pose(rig)


def _extra_args() -> list[str]:
    if "--" not in sys.argv:
        return []
    return sys.argv[sys.argv.index("--") + 1 :]


def main() -> None:
    bpy.context.scene.render.fps = 24
    clear_scene()
    parts = build_character()
    for obj, _allowed in parts:
        material_name = obj.data.materials[0].name if obj.data.materials else ""
        if material_name in {"Hide", "HideDeep", "Membrane"}:
            add_surface_noise(obj, 0.006, 0.0016, seed=(hash(obj.name) % 19) * 0.17)
        elif material_name == "Calcified":
            add_surface_noise(obj, 0.002, 0.0006, seed=(hash(obj.name) % 11) * 0.2)

    rig = build_armature()
    for obj, allowed in parts:
        skin_part(obj, allowed)

    body = join_parts(parts)
    sharpen_edges(body)
    body.parent = rig
    modifier = body.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig
    build_animations(rig)

    low, high = mesh_bounds(body)
    triangles = sum(len(polygon.vertices) - 2 for polygon in body.data.polygons)
    print(
        f"Soglot: {len(body.data.vertices)} verts, {triangles} tris, "
        f"{len(body.material_slots)} materials, {len(bpy.data.actions)} actions"
    )
    print(f"bounds min {low.x:.3f} {low.y:.3f} {low.z:.3f} max {high.x:.3f} {high.y:.3f} {high.z:.3f}")
    if low.z < -0.02 or high.z > 2.02:
        print("WARNING: silhouette is outside the doorway envelope")

    BLEND_OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
    export(rig, body)

    mode = _extra_args()[0] if _extra_args() else "cycles"
    if mode == "norender":
        return
    try:
        if mode == "eevee":
            render_turnaround(rig, "eevee")
        else:
            render_turnaround(rig, "cycles", names={"soglot_three_quarter"})
    except Exception as exc:
        print(f"Preview render skipped: {exc}")


if __name__ == "__main__":
    main()
