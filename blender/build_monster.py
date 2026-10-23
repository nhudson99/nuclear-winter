"""Build the Soglot (the "hare" enemy): a hunched, plated stalker mutant.

Based on the "Stalker Mutant - Soglot" concept sheet: elongated limbs, a
predatory forward-slung silhouette, dark leathery skin with calcified plates and
torn membranes, and scavenged gear (a corroded gas canister, straps, hoses).

Authored headlessly through Blender's Python API. Output is a skinned GLB with
Idle / Walk / Attack / Hit / Die clips plus a .blend for inspection.

Conventions match the other builders:
  * +Z up, feet on z = 0, character faces +Y, +X is the character's right.
  * Export uses export_yup, so +Y in Blender becomes -Z in Godot.
"""

from __future__ import annotations

import math
import random
import zlib
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Vector, noise

OUT_DIR = Path("/workspace/godot/assets/characters")
BLEND_OUT = Path("/workspace/blender/enemy_monster.blend")
GLB_OUT = OUT_DIR / "enemy_monster.glb"
PNG_OUT = Path("/opt/cursor/artifacts/blender_enemy_monster.png")

SEGMENTS = 14

BONES = [
    ("Hips", None, (0.0, -0.17, 0.98), (0.0, -0.17, 1.12)),
    ("Spine", "Hips", (0.0, -0.17, 1.12), (0.0, -0.09, 1.40)),
    ("Chest", "Spine", (0.0, -0.09, 1.40), (0.0, 0.07, 1.66)),
    ("Neck", "Chest", (0.0, 0.07, 1.66), (0.0, 0.34, 1.60)),
    ("Head", "Neck", (0.0, 0.34, 1.60), (0.0, 0.62, 1.48)),
    ("Jaw", "Head", (0.0, 0.42, 1.46), (0.0, 0.70, 1.34)),
    ("UpperArm_R", "Chest", (0.40, 0.02, 1.56), (0.50, -0.06, 1.04)),
    ("Forearm_R", "UpperArm_R", (0.50, -0.06, 1.04), (0.46, 0.18, 0.52)),
    ("Hand_R", "Forearm_R", (0.46, 0.18, 0.52), (0.46, 0.40, 0.20)),
    ("UpperArm_L", "Chest", (-0.40, 0.02, 1.56), (-0.50, -0.06, 1.04)),
    ("Forearm_L", "UpperArm_L", (-0.50, -0.06, 1.04), (-0.46, 0.18, 0.52)),
    ("Hand_L", "Forearm_L", (-0.46, 0.18, 0.52), (-0.46, 0.40, 0.20)),
    ("Thigh_R", "Hips", (0.21, -0.17, 0.98), (0.27, 0.12, 0.58)),
    ("Shin_R", "Thigh_R", (0.27, 0.12, 0.58), (0.25, -0.12, 0.28)),
    ("Foot_R", "Shin_R", (0.25, -0.12, 0.28), (0.26, 0.14, 0.05)),
    ("Thigh_L", "Hips", (-0.21, -0.17, 0.98), (-0.27, 0.12, 0.58)),
    ("Shin_L", "Thigh_L", (-0.27, 0.12, 0.58), (-0.25, -0.12, 0.28)),
    ("Foot_L", "Shin_L", (-0.25, -0.12, 0.28), (-0.26, 0.14, 0.05)),
]

TORSO_BONES = ["Hips", "Spine", "Chest"]

# Torso cross-sections, bottom to top. c = (x, y) centre, rx = half width,
# ry = half depth. Everything that hugs the body (plates, straps, hoses) is
# placed by interpolating this table so it follows the silhouette exactly.
TORSO = [
    (0.86, (0.0, -0.17), 0.19, 0.16),
    (1.00, (0.0, -0.19), 0.26, 0.21),
    (1.18, (0.0, -0.17), 0.28, 0.25),
    (1.38, (0.0, -0.09), 0.31, 0.27),
    (1.56, (0.0, 0.03), 0.34, 0.25),
    (1.69, (0.0, 0.11), 0.26, 0.20),
    (1.77, (0.0, 0.16), 0.13, 0.11),
]
TORSO_POWER = 0.82

# The upper body is authored upright, then sheared forward above the pelvis so
# the spine arcs into the predatory hunch from the concept art. Bones and mesh
# take the same shear, so skinning and animation stay consistent.
LEAN = 0.27


def lean_offset(z: float) -> float:
    t = min(1.0, max(0.0, (z - 1.0) / 0.75))
    return LEAN * t * t * (3.0 - 2.0 * t)


def lean_point(p) -> tuple[float, float, float]:
    return (p[0], p[1] + lean_offset(p[2]), p[2])


BONES_LEANED = [
    (name, parent, lean_point(head), lean_point(tail)) for name, parent, head, tail in BONES
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
    roughness: float = 0.78,
    metallic: float = 0.0,
    specular: float = 0.3,
    emission: str | None = None,
    emission_strength: float = 0.0,
    double_sided: bool = False,
):
    material = bpy.data.materials.new(name=name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = srgb(hex_color)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = specular
    if emission and "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = srgb(emission)
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emission_strength
    material.use_backface_culling = not double_sided
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


def _pick_reference(mean_tangent: Vector) -> Vector:
    for axis in ((0, 1, 0), (0, 0, 1), (1, 0, 0)):
        ref = Vector(axis)
        if abs(ref.dot(mean_tangent)) < 0.7:
            return ref
    return Vector((1, 0, 0))


def sweep(
    name: str,
    material,
    sections: list[dict],
    segments: int = SEGMENTS,
    cap_start: str = "dome",
    cap_end: str = "dome",
    dome_rings: int = 3,
    ref: Vector | None = None,
) -> bpy.types.Object:
    """Skin a tube through `sections` ({c, rx, ry, p, n?}) with rings normal to the path.

    A section may carry `n`, a surface normal that fixes the ring's thin axis
    (used for ribbons that lie on the body).
    """
    pts = [Vector(s["c"]) for s in sections]
    tangents = []
    for i in range(len(pts)):
        a = pts[max(0, i - 1)]
        b = pts[min(len(pts) - 1, i + 1)]
        tangents.append((b - a).normalized())
    mean = sum(tangents, Vector()).normalized()
    reference = ref if ref is not None else _pick_reference(mean)

    frames = []
    for s, t in zip(sections, tangents):
        if "n" in s:
            v = Vector(s["n"])
            v = (v - t * v.dot(t)).normalized()
            u = t.cross(v).normalized()
        else:
            u = t.cross(reference).normalized()
            v = u.cross(t).normalized()
        frames.append((u, v, t))

    rings = [
        (pts[i], sections[i]["rx"], sections[i]["ry"], sections[i].get("p", 1.0), frames[i])
        for i in range(len(pts))
    ]

    def dome(inner, outer, sign):
        centre, rx, ry, power, frame = outer
        direction = frame[2] * sign
        height = 0.9 * (rx + ry) * 0.5
        extra = []
        for k in range(1, dome_rings + 1):
            ang = (k / (dome_rings + 1)) * (math.pi / 2)
            extra.append((
                centre + direction * (math.sin(ang) * height),
                rx * math.cos(ang),
                ry * math.cos(ang),
                power,
                frame,
            ))
        return extra, centre + direction * height

    start_pole = end_pole = None
    if cap_start == "dome" and len(rings) > 1:
        extra, start_pole = dome(rings[1], rings[0], -1)
        rings = list(reversed(extra)) + rings
    if cap_end == "dome" and len(rings) > 1:
        extra, end_pole = dome(rings[-2], rings[-1], 1)
        rings = rings + extra

    bm = bmesh.new()
    ring_verts = []
    for centre, rx, ry, power, (u, v, _t) in rings:
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


def spline(points: list[Vector], samples_per_span: int = 6) -> list[Vector]:
    """Catmull-Rom through `points`."""
    if len(points) < 3:
        return list(points)
    pts = [points[0]] + list(points) + [points[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for k in range(samples_per_span):
            t = k / samples_per_span
            t2, t3 = t * t, t * t * t
            out.append(
                0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
            )
    out.append(points[-1])
    return out


def limb(
    name: str,
    material,
    path: list[tuple[float, float, float]],
    radii: list[tuple[float, float]],
    power: float = 0.9,
    samples: int = 4,
    segments: int = 10,
    cap_start: str = "dome",
    cap_end: str = "dome",
) -> bpy.types.Object:
    """Tube along a smoothed path with radii interpolated by position along the path."""
    pts = spline([Vector(p) for p in path], samples)
    n_ctrl = len(radii)
    sections = []
    for i, p in enumerate(pts):
        f = i / (len(pts) - 1) * (n_ctrl - 1)
        lo = min(int(f), n_ctrl - 2)
        t = f - lo
        rx = radii[lo][0] * (1 - t) + radii[lo + 1][0] * t
        ry = radii[lo][1] * (1 - t) + radii[lo + 1][1] * t
        sections.append({"c": p, "rx": rx, "ry": ry, "p": power})
    return sweep(name, material, sections, segments=segments, cap_start=cap_start, cap_end=cap_end, dome_rings=2)


def claw(name: str, material, base, direction, length: float, radius: float, curl: float = 0.5):
    """Curved, pointed claw starting at `base`, pointing along `direction`, curling downward."""
    base = Vector(base)
    d = Vector(direction).normalized()
    down = Vector((0, 0, -1))
    pts = []
    for k in range(5):
        t = k / 4
        bend = down * (curl * length * t * t)
        pts.append(base + d * (length * t) + bend)
    sections = [
        {"c": p, "rx": radius * (1 - 0.92 * (k / 4) ** 0.8), "ry": radius * 0.8 * (1 - 0.92 * (k / 4) ** 0.8)}
        for k, p in enumerate(pts)
    ]
    return sweep(name, material, sections, segments=6, cap_start="flat", cap_end="flat", dome_rings=1)


def cone(name: str, material, base, direction, length: float, radius: float, segments: int = 6):
    base = Vector(base)
    d = Vector(direction).normalized()
    sections = [
        {"c": base, "rx": radius, "ry": radius},
        {"c": base + d * length * 0.55, "rx": radius * 0.5, "ry": radius * 0.5},
        {"c": base + d * length, "rx": radius * 0.04, "ry": radius * 0.04},
    ]
    return sweep(name, material, sections, segments=segments, cap_start="flat", cap_end="flat")


def torso_point(z: float, theta: float, outset: float = 0.0) -> tuple[Vector, Vector]:
    """Point and outward normal on the torso at height z, angle theta (0 = +x, 90deg = front)."""
    lo = TORSO[0]
    hi = TORSO[-1]
    for a, b in zip(TORSO, TORSO[1:]):
        if a[0] <= z <= b[0]:
            lo, hi = a, b
            break
    else:
        if z > TORSO[-1][0]:
            lo = hi = TORSO[-1]
        else:
            lo = hi = TORSO[0]
    span = hi[0] - lo[0]
    t = 0.0 if span <= 1e-6 else (z - lo[0]) / span
    cx = lo[1][0] * (1 - t) + hi[1][0] * t
    cy = lo[1][1] * (1 - t) + hi[1][1] * t
    rx = lo[2] * (1 - t) + hi[2] * t
    ry = lo[3] * (1 - t) + hi[3] * t
    c, s = math.cos(theta), math.sin(theta)
    px = math.copysign(abs(c) ** TORSO_POWER, c) * rx
    py = math.copysign(abs(s) ** TORSO_POWER, s) * ry
    normal = Vector((c / max(rx, 1e-4), s / max(ry, 1e-4), 0.0)).normalized()
    slope = (hi[3] - lo[3]) / span if span > 1e-6 else 0.0
    normal = (normal + Vector((0, 0, -slope * 0.4))).normalized()
    pos = Vector((cx + px, cy + py, z)) + normal * outset
    return pos, normal


def add_surface_noise(obj: bpy.types.Object, fold: float, grain: float, seed: float = 0.0) -> None:
    offset_vec = Vector((seed, seed * 0.37, seed * 0.13))
    for vert in obj.data.vertices:
        point = vert.co + offset_vec
        offset = fold * noise.noise(point * 6.0) + grain * noise.noise(point * 21.0)
        vert.co = vert.co + vert.normal * offset
    obj.data.update()


def plate_into(bm, centre: Vector, normal: Vector, up: Vector, w: float, h: float, thick: float, tilt: float = 0.35):
    """Add one low-poly overlapping scute at `centre`."""
    n = (normal - up * tilt).normalized()
    u = (up - n * up.dot(n)).normalized()
    a = u.cross(n).normalized()
    base, top = [], []
    for i in range(6):
        phi = i * math.pi / 3.0
        local = a * (math.cos(phi) * w) + u * (math.sin(phi) * h)
        base.append(bm.verts.new(centre + local - n * thick * 0.6))
        top.append(bm.verts.new(centre + local * 0.72 + n * thick * (1.0 if math.sin(phi) < -0.1 else 0.7)))
    apex = bm.verts.new(centre + n * thick * 1.4 + u * (h * 0.05))
    for i in range(6):
        j = (i + 1) % 6
        bm.faces.new((base[i], base[j], top[j], top[i]))
        bm.faces.new((top[i], top[j], apex))


def band_into(bm, z: float, half_height: float, outset: float, thickness: float, segments: int = 28):
    """Closed strap wrapped around the torso at height z."""
    rings = []
    for dz, off in ((-half_height, 0.0), (-half_height, thickness), (half_height, thickness), (half_height, 0.0)):
        ring = []
        for i in range(segments):
            theta = 2.0 * math.pi * i / segments
            pos, _n = torso_point(z + dz, theta, outset + off)
            ring.append(bm.verts.new(pos))
        rings.append(ring)
    for r0, r1 in zip(rings, rings[1:] + rings[:1]):
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((r0[i], r0[j], r1[j], r1[i]))


def build_character() -> list[tuple[bpy.types.Object, list[str]]]:
    rng = random.Random(7)
    skin = mat("SoglotSkin", "#2a2524", roughness=0.72, specular=0.38)
    skin_pale = mat("SoglotUnderbelly", "#3c322d", roughness=0.8)
    plate_m = mat("SoglotPlate", "#3d3532", roughness=0.58, specular=0.45)
    calc = mat("SoglotCalcified", "#6b6255", roughness=0.6, specular=0.3)
    rust = mat("SoglotRust", "#5b3b25", roughness=0.58, metallic=0.7, specular=0.5)
    steel = mat("SoglotDarkSteel", "#2b2d2e", roughness=0.5, metallic=0.8, specular=0.5)
    strap = mat("SoglotStrap", "#1b1714", roughness=0.86)
    hose = mat("SoglotHose", "#141312", roughness=0.4, specular=0.5)
    bone_m = mat("SoglotBone", "#b9ab90", roughness=0.45, specular=0.4)
    socket_m = mat("SoglotSocket", "#0b0908", roughness=0.9)
    eye_m = mat("SoglotEye", "#4a2410", roughness=0.25, emission="#ff9a35", emission_strength=2.2)
    membrane = mat("SoglotMembrane", "#352c29", roughness=0.9, double_sided=True)

    parts: list[tuple[bpy.types.Object, list[str]]] = []

    def add(obj, bones):
        parts.append((obj, bones))
        return obj

    torso_sections = [
        {"c": (cx, cy, z), "rx": rx, "ry": ry, "p": TORSO_POWER}
        for z, (cx, cy), rx, ry in TORSO
    ]
    add(sweep("Torso", skin, torso_sections, segments=20, cap_start="dome", cap_end="dome", ref=Vector((0, 1, 0))), TORSO_BONES + ["Neck"])

    # Softer, paler underbelly with a visible rib cage ridge pattern.
    belly_sections = []
    for z, ry_b, rx_b in ((0.96, 0.07, 0.13), (1.16, 0.08, 0.19), (1.36, 0.08, 0.22), (1.54, 0.06, 0.19)):
        c, _n = torso_point(z, math.pi / 2, -0.05)
        belly_sections.append({"c": c, "rx": rx_b, "ry": ry_b, "p": 0.85})
    add(sweep("Belly", skin_pale, belly_sections, segments=14, cap_start="dome", cap_end="dome", ref=Vector((0, 1, 0))), TORSO_BONES)

    for i, z in enumerate((1.12, 1.21, 1.30, 1.39, 1.48)):
        arc = [torso_point(z + 0.02 * math.sin(th), math.radians(th), 0.004)[0] for th in (25, 55, 90, 125, 155)]
        add(limb(f"Rib_{i}", skin_pale, [tuple(p) for p in arc], [(0.014, 0.012)] * 5, power=0.9, samples=3, segments=6,
                 cap_start="dome", cap_end="dome"), ["Spine", "Chest"])

    # Dorsal plating: tight, flat, overlapping scutes shingled down the back and flanks.
    plate_bm = bmesh.new()
    calc_bm = bmesh.new()
    z = 0.91
    row = 0
    while z < 1.76:
        radius_here = torso_point(z, 0.0)[0].x
        circumference_back = max(0.12, radius_here * math.radians(200.0)) * 1.15
        w = 0.050 + 0.014 * min(1.0, (z - 0.9) / 0.6) + rng.uniform(-0.004, 0.006)
        count = max(4, int(circumference_back / (w * 1.5)))
        start = math.radians(190.0 if row % 2 == 0 else 190.0 + 200.0 / count * 0.5)
        for k in range(count):
            theta = start + math.radians(200.0) * (k + 0.5) / count
            theta += rng.uniform(-0.04, 0.04)
            jitter_z = z + rng.uniform(-0.008, 0.008)
            pos, normal = torso_point(jitter_z, theta, 0.006)
            up = Vector((0, 0, 1))
            size = w * rng.uniform(0.9, 1.12)
            target = calc_bm if rng.random() < 0.11 else plate_bm
            plate_into(target, pos, normal, up, size, size * 0.95, 0.014 + rng.uniform(0, 0.008), tilt=0.5)
        z += 0.046
        row += 1
    add(_finish("DorsalPlates", plate_bm, plate_m), TORSO_BONES)
    add(_finish("CalcifiedPatches", calc_bm, calc), TORSO_BONES)

    # Spine ridge: bone spikes down the back centre line.
    for i, zz in enumerate([0.98 + 0.075 * k for k in range(11)]):
        pos, normal = torso_point(zz, math.radians(270.0), 0.02)
        height = 0.05 + 0.05 * math.sin(min(1.0, (zz - 0.95) / 0.8) * math.pi * 0.85)
        direction = (normal + Vector((0, 0, 0.55))).normalized()
        add(cone(f"Spike_{i}", calc, pos, direction, height, 0.02 + 0.004 * (i % 3)), TORSO_BONES)

    # Head: narrow, skull-like, slung forward of the hump.
    head_sections = [
        {"c": (0.0, 0.24, 1.60), "rx": 0.105, "ry": 0.130, "p": 0.85},
        {"c": (0.0, 0.35, 1.60), "rx": 0.125, "ry": 0.145, "p": 0.82},
        {"c": (0.0, 0.46, 1.57), "rx": 0.110, "ry": 0.130, "p": 0.85},
        {"c": (0.0, 0.56, 1.52), "rx": 0.076, "ry": 0.090, "p": 0.9},
        {"c": (0.0, 0.68, 1.46), "rx": 0.046, "ry": 0.056, "p": 0.95},
    ]
    add(sweep("Head", skin, head_sections, segments=16, cap_start="flat", cap_end="dome", ref=Vector((0, 0, 1))), ["Neck", "Head"])
    add(limb("Neck", skin, [(0.0, 0.02, 1.72), (0.0, 0.14, 1.68), (0.0, 0.26, 1.63), (0.0, 0.34, 1.60)],
             [(0.15, 0.14), (0.12, 0.12), (0.10, 0.10), (0.095, 0.095)], segments=14, cap_start="flat", cap_end="flat"), ["Chest", "Neck", "Head"])
    add(limb("Muzzle", skin_pale, [(0.0, 0.56, 1.50), (0.0, 0.66, 1.46), (0.0, 0.74, 1.42)],
             [(0.065, 0.040), (0.042, 0.028), (0.020, 0.016)], segments=8, cap_start="flat", cap_end="dome"), ["Head"])

    for side, sign in (("R", 1.0), ("L", -1.0)):
        add(limb(f"Brow_{side}", calc, [(sign * 0.02, 0.60, 1.575), (sign * 0.06, 0.60, 1.565), (sign * 0.10, 0.54, 1.56)],
                 [(0.012, 0.012), (0.016, 0.016), (0.012, 0.012)], segments=8), ["Head"])
        add(sweep(f"Socket_{side}", socket_m, [
            {"c": (sign * 0.050, 0.585, 1.525), "rx": 0.030, "ry": 0.036},
            {"c": (sign * 0.062, 0.612, 1.515), "rx": 0.026, "ry": 0.032},
        ], segments=10, cap_start="dome", cap_end="dome", ref=Vector((0, 0, 1))), ["Head"])
        add(sweep(f"Eye_{side}", eye_m, [
            {"c": (sign * 0.060, 0.610, 1.518), "rx": 0.015, "ry": 0.020},
            {"c": (sign * 0.064, 0.628, 1.512), "rx": 0.011, "ry": 0.016},
        ], segments=8, cap_start="dome", cap_end="dome", ref=Vector((0, 0, 1))), ["Head"])
        add(sweep(f"Nostril_{side}", socket_m, [
            {"c": (sign * 0.016, 0.71, 1.455), "rx": 0.007, "ry": 0.010},
            {"c": (sign * 0.016, 0.735, 1.445), "rx": 0.006, "ry": 0.008},
        ], segments=6, cap_start="dome", cap_end="dome", ref=Vector((0, 0, 1))), ["Head"])

    jaw_sections = [
        {"c": (0.0, 0.40, 1.47), "rx": 0.085, "ry": 0.050, "p": 0.9},
        {"c": (0.0, 0.52, 1.43), "rx": 0.065, "ry": 0.040, "p": 0.9},
        {"c": (0.0, 0.62, 1.385), "rx": 0.040, "ry": 0.028, "p": 0.92},
        {"c": (0.0, 0.70, 1.345), "rx": 0.020, "ry": 0.016, "p": 0.95},
    ]
    add(sweep("Jaw", skin_pale, jaw_sections, segments=10, cap_start="flat", cap_end="dome", ref=Vector((0, 0, 1))), ["Head", "Jaw"])
    for i in range(4):
        t = i / 3
        for side, sign in (("R", 1.0), ("L", -1.0)):
            y = 0.52 + 0.17 * t
            half = 0.060 - 0.032 * t
            length = 0.026 + 0.012 * (1 - abs(t - 0.5) * 1.6)
            add(cone(f"ToothU_{side}{i}", bone_m, (sign * half, y, 1.47 - 0.055 * t), (0, 0.1, -1.0), length, 0.008), ["Head"])
            add(cone(f"ToothL_{side}{i}", bone_m, (sign * (half - 0.006), y + 0.02, 1.425 - 0.07 * t), (0, -0.05, 1.0), length * 0.9, 0.007), ["Jaw"])
    add(cone("Fang_R", bone_m, (0.04, 0.68, 1.43), (0, 0.1, -1.0), 0.07, 0.011), ["Head"])
    add(cone("Fang_L", bone_m, (-0.04, 0.68, 1.43), (0, 0.1, -1.0), 0.07, 0.011), ["Head"])

    for side, sign in (("R", 1.0), ("L", -1.0)):
        # Arms: heavy shoulder, long forearm, wrist-down claws almost reaching the floor.
        sh = (sign * 0.38, 0.0, 1.55)
        el = (sign * 0.50, -0.06, 1.04)
        wr = (sign * 0.46, 0.18, 0.52)
        add(limb(f"UpperArm_{side}", skin, [sh, (sign * 0.45, -0.03, 1.30), el],
                 [(0.125, 0.12), (0.095, 0.095), (0.075, 0.07)], segments=12), ["Chest", f"UpperArm_{side}"])
        add(limb(f"Forearm_{side}", skin, [el, (sign * 0.49, 0.06, 0.78), wr],
                 [(0.075, 0.07), (0.085, 0.08), (0.05, 0.045)], segments=12), [f"UpperArm_{side}", f"Forearm_{side}", f"Hand_{side}"])
        if side == "R":
            add(limb(f"ShoulderCap_{side}", calc, [(sign * 0.30, -0.02, 1.70), (sign * 0.40, 0.0, 1.64), (sign * 0.47, 0.0, 1.50)],
                     [(0.05, 0.09), (0.06, 0.10), (0.04, 0.07)], segments=10), ["Chest", f"UpperArm_{side}"])
        add(limb(f"ElbowBone_{side}", calc, [(sign * 0.54, -0.14, 1.07), (sign * 0.56, -0.17, 1.03)],
                 [(0.03, 0.03), (0.016, 0.016)], segments=8), [f"UpperArm_{side}", f"Forearm_{side}"])
        add(limb(f"ForearmPlate_{side}", plate_m, [(sign * 0.50, -0.01, 0.90), (sign * 0.53, 0.04, 0.78), (sign * 0.50, 0.11, 0.64)],
                 [(0.045, 0.02), (0.052, 0.022), (0.04, 0.018)], segments=8, power=0.7), [f"Forearm_{side}"])

        add(limb(f"Palm_{side}", skin, [wr, (sign * 0.46, 0.24, 0.41), (sign * 0.46, 0.30, 0.33)],
                 [(0.052, 0.045), (0.058, 0.032), (0.052, 0.026)], segments=10), [f"Forearm_{side}", f"Hand_{side}"])
        knuckle_y, knuckle_z = 0.30, 0.33
        for f_i, dx in enumerate((-0.042, -0.014, 0.014, 0.042)):
            x = sign * 0.46 + dx
            spread = dx * 1.6
            length = (0.17, 0.2, 0.2, 0.15)[f_i]
            mid = (x + spread * 0.5, knuckle_y + length * 0.55, knuckle_z - 0.10)
            tip = (x + spread, knuckle_y + length * 0.9, knuckle_z - 0.16)
            add(limb(f"Finger_{side}{f_i}", skin, [(x, knuckle_y, knuckle_z), mid, tip],
                     [(0.017, 0.016), (0.013, 0.012), (0.009, 0.009)], segments=6, samples=3), [f"Hand_{side}"])
            add(claw(f"Claw_{side}{f_i}", bone_m, tip, (spread * 0.4, 0.55, -0.55), 0.115, 0.011, curl=0.55), [f"Hand_{side}"])
        add(claw(f"Dewclaw_{side}", bone_m, (sign * 0.40, 0.25, 0.40), (-sign * 0.2, 0.55, -0.8), 0.10, 0.012, curl=0.4), [f"Hand_{side}"])

        # Legs: thick thigh, backwards-bent shin, big clawed feet.
        hip = (sign * 0.21, -0.17, 0.98)
        knee = (sign * 0.27, 0.12, 0.58)
        ankle = (sign * 0.25, -0.12, 0.28)
        add(limb(f"Thigh_{side}", skin, [hip, (sign * 0.25, -0.02, 0.80), knee],
                 [(0.17, 0.18), (0.14, 0.15), (0.09, 0.095)], segments=12), ["Hips", f"Thigh_{side}", f"Shin_{side}"])
        add(limb(f"Shin_{side}", skin, [knee, (sign * 0.27, -0.01, 0.44), ankle],
                 [(0.085, 0.09), (0.08, 0.10), (0.05, 0.055)], segments=12), [f"Thigh_{side}", f"Shin_{side}", f"Foot_{side}"])
        add(limb(f"KneePlate_{side}", calc, [(sign * 0.30, 0.16, 0.66), (sign * 0.31, 0.19, 0.58), (sign * 0.30, 0.16, 0.50)],
                 [(0.05, 0.026), (0.062, 0.032), (0.05, 0.026)], segments=8, power=0.7), [f"Thigh_{side}", f"Shin_{side}"])
        add(limb(f"ShinPlate_{side}", plate_m, [(sign * 0.30, -0.06, 0.50), (sign * 0.31, -0.07, 0.40), (sign * 0.29, -0.09, 0.32)],
                 [(0.04, 0.02), (0.046, 0.022), (0.035, 0.018)], segments=8, power=0.7), [f"Shin_{side}"])
        add(limb(f"Foot_{side}", skin, [ankle, (sign * 0.255, 0.00, 0.12), (sign * 0.26, 0.14, 0.06)],
                 [(0.06, 0.06), (0.075, 0.06), (0.09, 0.05)], segments=10), [f"Shin_{side}", f"Foot_{side}"])
        add(limb(f"Heel_{side}", skin, [(sign * 0.25, -0.12, 0.28), (sign * 0.25, -0.20, 0.12), (sign * 0.25, -0.22, 0.05)],
                 [(0.045, 0.04), (0.034, 0.03), (0.018, 0.018)], segments=8), [f"Shin_{side}", f"Foot_{side}"])
        for t_i, dx in enumerate((-0.05, 0.0, 0.05)):
            x = sign * 0.26 + dx
            toe_tip = (x + dx * 0.6, 0.30, 0.025)
            add(limb(f"Toe_{side}{t_i}", skin, [(x, 0.12, 0.05), (x + dx * 0.3, 0.21, 0.045), toe_tip],
                     [(0.032, 0.03), (0.024, 0.022), (0.017, 0.016)], segments=6, samples=3), [f"Foot_{side}"])
            add(claw(f"ToeClaw_{side}{t_i}", bone_m, toe_tip, (dx * 0.5, 1.0, -0.15), 0.12, 0.015, curl=0.3), [f"Foot_{side}"])

    # Scavenged gear: strap loops, bandolier, rusted canister, hoses.
    strap_bm = bmesh.new()
    band_into(strap_bm, 1.08, 0.030, 0.012, 0.012)
    band_into(strap_bm, 1.45, 0.028, 0.012, 0.012)
    add(_finish("Straps", strap_bm, strap), TORSO_BONES)

    bandolier = []
    for k in range(9):
        t = k / 8
        z = 1.60 - 0.50 * t
        theta = math.radians(20.0 + 140.0 * t)
        pos, normal = torso_point(z, theta, 0.026)
        bandolier.append({"c": pos, "rx": 0.034, "ry": 0.011, "p": 0.6, "n": normal})
    add(sweep("Bandolier", strap, bandolier, segments=8, cap_start="flat", cap_end="flat"), TORSO_BONES)
    for k in range(5):
        t = 0.15 + 0.17 * k
        z = 1.60 - 0.50 * t
        theta = math.radians(20.0 + 140.0 * t)
        pos, normal = torso_point(z, theta, 0.04)
        add(sweep(f"Pouch_{k}", rust, [
            {"c": pos, "rx": 0.026, "ry": 0.013, "p": 0.5, "n": normal},
            {"c": pos + normal * 0.012 - Vector((0, 0, 0.04)), "rx": 0.026, "ry": 0.013, "p": 0.5, "n": normal},
        ], segments=8, cap_start="flat", cap_end="flat"), ["Spine", "Chest"])

    tank_bottom = Vector((0.17, -0.50, 1.04))
    tank_top = Vector((0.14, -0.40, 1.62))
    tank_axis = (tank_top - tank_bottom).normalized()
    tank_sections = []
    for t, r in ((0.0, 0.050), (0.04, 0.082), (0.5, 0.092), (0.96, 0.084), (1.0, 0.050)):
        tank_sections.append({"c": tank_bottom + (tank_top - tank_bottom) * t, "rx": r, "ry": r, "p": 1.0})
    add(sweep("Canister", rust, tank_sections, segments=16, cap_start="dome", cap_end="dome"), ["Chest", "Spine"])
    for t in (0.2, 0.78):
        c = tank_bottom + (tank_top - tank_bottom) * t
        add(sweep(f"CanisterBand_{t}", steel, [
            {"c": c - tank_axis * 0.022, "rx": 0.099, "ry": 0.099},
            {"c": c + tank_axis * 0.022, "rx": 0.099, "ry": 0.099},
        ], segments=16, cap_start="none", cap_end="none"), ["Chest", "Spine"])
        for sx in (-1, 1):
            pos, normal = torso_point(c.z, math.radians(270.0 + sx * 38.0), 0.0)
            add(sweep(f"CanisterStrap_{t}_{sx}", strap, [
                {"c": c + Vector((0.0, 0.03, 0.0)) + Vector((sx * 0.04, 0, 0)), "rx": 0.02, "ry": 0.008, "p": 0.6, "n": Vector((0, -1, 0))},
                {"c": pos + normal * 0.03, "rx": 0.02, "ry": 0.008, "p": 0.6, "n": normal},
            ], segments=6, cap_start="flat", cap_end="flat"), ["Chest", "Spine"])
    valve_base = tank_top + tank_axis * 0.05
    add(sweep("CanisterValve", steel, [
        {"c": valve_base, "rx": 0.034, "ry": 0.034},
        {"c": valve_base + tank_axis * 0.05, "rx": 0.024, "ry": 0.024},
        {"c": valve_base + tank_axis * 0.075, "rx": 0.030, "ry": 0.030},
    ], segments=10, cap_start="flat", cap_end="dome"), ["Chest"])
    add(sweep("ValveWheel", rust, [
        {"c": valve_base + tank_axis * 0.075 + Vector((-0.045, 0, 0)), "rx": 0.01, "ry": 0.01},
        {"c": valve_base + tank_axis * 0.075 + Vector((0.045, 0, 0)), "rx": 0.01, "ry": 0.01},
    ], segments=6, cap_start="dome", cap_end="dome"), ["Chest"])

    def hose_path(points):
        return [tuple(p) for p in points]

    hose_a = [
        tank_top + tank_axis * 0.10,
        Vector((0.20, -0.34, 1.84)),
        Vector((0.26, -0.12, 1.84)),
        torso_point(1.62, math.radians(35.0), 0.10)[0],
        torso_point(1.30, math.radians(30.0), 0.07)[0],
        torso_point(1.08, math.radians(15.0), 0.08)[0] + Vector((0.0, 0.0, -0.02)),
    ]
    add(limb("HoseA", hose, hose_path(hose_a), [(0.017, 0.017)] * 6, power=1.0, samples=6, segments=8), ["Chest", "Spine"])
    hose_b = [
        tank_bottom + Vector((0.0, -0.02, 0.0)),
        Vector((0.30, -0.55, 0.96)),
        Vector((0.34, -0.40, 0.82)),
        Vector((0.30, -0.18, 0.80)),
        Vector((0.24, -0.04, 0.88)),
    ]
    add(limb("HoseB", hose, hose_path(hose_b), [(0.019, 0.019)] * 5, power=1.0, samples=6, segments=8), ["Hips", "Spine"])
    hose_c = [
        tank_top + tank_axis * 0.06 + Vector((-0.02, 0, 0)),
        Vector((0.02, -0.38, 1.72)),
        Vector((-0.16, -0.30, 1.62)),
        torso_point(1.40, math.radians(235.0), 0.06)[0],
        torso_point(1.16, math.radians(215.0), 0.06)[0],
        torso_point(1.00, math.radians(200.0), 0.05)[0] + Vector((-0.04, 0.0, -0.12)),
    ]
    add(limb("HoseC", hose, hose_path(hose_c), [(0.014, 0.014)] * 6, power=1.0, samples=6, segments=8), ["Chest", "Spine", "Hips"])

    # Left shoulder: scrap-metal pauldron riveted over the plates.
    add(sweep("Pauldron", rust, [
        {"c": (-0.30, -0.01, 1.76), "rx": 0.030, "ry": 0.12, "p": 0.7},
        {"c": (-0.42, 0.0, 1.72), "rx": 0.034, "ry": 0.15, "p": 0.7},
        {"c": (-0.52, 0.01, 1.58), "rx": 0.030, "ry": 0.13, "p": 0.7},
    ], segments=14, cap_start="dome", cap_end="dome", ref=Vector((0, 1, 0))), ["Chest", "UpperArm_L"])
    for k, (px, py, pz) in enumerate((
        (-0.33, -0.06, 1.775), (-0.33, 0.06, 1.775), (-0.43, -0.08, 1.745),
        (-0.43, 0.08, 1.745), (-0.51, -0.06, 1.615), (-0.51, 0.07, 1.615),
    )):
        add(sweep(f"Rivet_{k}", steel, [
            {"c": (px, py, pz), "rx": 0.014, "ry": 0.014},
            {"c": (px, py, pz + 0.014), "rx": 0.010, "ry": 0.010},
        ], segments=6, cap_start="flat", cap_end="dome", ref=Vector((0, 1, 0))), ["Chest", "UpperArm_L"])
    # Right forearm brace (corroded steel cuff).
    add(sweep("ForearmBrace", steel, [
        {"c": (0.49, 0.03, 0.80), "rx": 0.092, "ry": 0.088},
        {"c": (0.485, 0.07, 0.72), "rx": 0.088, "ry": 0.085},
    ], segments=14, cap_start="none", cap_end="none"), ["Forearm_R"])
    add(sweep("BeltBuckle", rust, [
        {"c": (0.0, 0.07, 1.07), "rx": 0.05, "ry": 0.015, "p": 0.5, "n": Vector((0, 1, 0))},
        {"c": (0.0, 0.075, 1.07), "rx": 0.05, "ry": 0.015, "p": 0.5, "n": Vector((0, 1, 0))},
    ], segments=8, cap_start="flat", cap_end="flat"), ["Spine", "Hips"])

    # Torn membranes hanging from the waist and under the arms.
    mem_bm = bmesh.new()
    for k in range(11):
        theta = 2.0 * math.pi * (k + rng.uniform(-0.2, 0.2)) / 11
        pos, normal = torso_point(0.93, theta, 0.025)
        length = rng.uniform(0.18, 0.40)
        width = rng.uniform(0.07, 0.10)
        side_axis = Vector((-normal.y, normal.x, 0.0)).normalized()
        drift = normal * rng.uniform(0.02, 0.07)
        rows = []
        for row_i, (frac, wscale) in enumerate(((0.0, 1.0), (0.45, 0.85), (0.8, 0.55), (1.0, 0.0))):
            centre = pos + Vector((0, 0, -length * frac)) + drift * frac + side_axis * rng.uniform(-0.012, 0.012) * frac
            if wscale == 0.0:
                rows.append([mem_bm.verts.new(centre + side_axis * rng.uniform(-0.01, 0.01))])
            else:
                rows.append([
                    mem_bm.verts.new(centre - side_axis * width * wscale),
                    mem_bm.verts.new(centre + side_axis * width * wscale),
                ])
        for r0, r1 in zip(rows, rows[1:]):
            if len(r1) == 1:
                mem_bm.faces.new((r0[0], r0[1], r1[0]))
            else:
                mem_bm.faces.new((r0[0], r0[1], r1[1], r1[0]))
    for sign in (1.0, -1.0):
        for k in range(4):
            top = Vector((sign * (0.36 + 0.03 * k), -0.10 - 0.02 * k, 1.42 - 0.07 * k))
            length = rng.uniform(0.2, 0.36)
            width = 0.04
            axis = Vector((0, 1, 0))
            rows = []
            for frac, wscale in ((0.0, 1.0), (0.5, 0.8), (1.0, 0.0)):
                centre = top + Vector((sign * 0.03 * frac, -0.02 * frac, -length * frac))
                if wscale == 0.0:
                    rows.append([mem_bm.verts.new(centre)])
                else:
                    rows.append([mem_bm.verts.new(centre - axis * width * wscale), mem_bm.verts.new(centre + axis * width * wscale)])
            for r0, r1 in zip(rows, rows[1:]):
                if len(r1) == 1:
                    mem_bm.faces.new((r0[0], r0[1], r1[0]))
                else:
                    mem_bm.faces.new((r0[0], r0[1], r1[1], r1[0]))
    add(_finish("Membranes", mem_bm, membrane), ["Hips", "Spine", "Chest", "Thigh_R", "Thigh_L"])

    return parts


def build_armature() -> bpy.types.Object:
    arm = bpy.data.armatures.new("SoglotArmature")
    rig = bpy.data.objects.new("SoglotRig", arm)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    created = {}
    for name, parent, head, tail in BONES_LEANED:
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
    bone_table = {name: (Vector(head), Vector(tail)) for name, _, head, tail in BONES_LEANED}
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


def _smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = min(1.0, max(0.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def _pulse(t: float, rise0: float, rise1: float, fall0: float, fall1: float) -> float:
    return _smoothstep(rise0, rise1, t) * (1.0 - _smoothstep(fall0, fall1, t))


ALL_BONES = {name for name, *_ in BONES}


def idle_pose(rig):
    def poser(t: float):
        q = 2.0 * math.pi * t
        breath = math.sin(q)
        pose_offset(rig, "Hips", Vector((0.0, 0.0, -0.012 + 0.012 * breath)))
        pose_rotate(rig, "Spine", rx=1.5 * breath)
        pose_rotate(rig, "Chest", rx=2.5 * breath, rz=2.0 * math.sin(q + 0.8))
        pose_rotate(rig, "Neck", rx=3.0 * math.sin(q + 0.5), rz=4.0 * math.sin(q + 1.6))
        pose_rotate(rig, "Head", rx=2.0 * math.sin(q + 1.0), rz=5.0 * math.sin(q * 2.0))
        pose_rotate(rig, "Jaw", rx=5.0 + 7.0 * max(0.0, math.sin(q + 2.0)))
        for side, sign in (("R", 1.0), ("L", -1.0)):
            phase = q + (0.0 if side == "R" else 1.2)
            pose_rotate(rig, f"UpperArm_{side}", rx=3.0 * math.sin(phase), rz=sign * (3.0 + 2.0 * breath))
            pose_rotate(rig, f"Forearm_{side}", rx=4.0 * math.sin(phase + 0.7))
            pose_rotate(rig, f"Hand_{side}", rx=5.0 * math.sin(phase + 1.4))
        return {"Hips", "Spine", "Chest", "Neck", "Head", "Jaw",
                "UpperArm_R", "UpperArm_L", "Forearm_R", "Forearm_L", "Hand_R", "Hand_L"}
    return poser


_BONE_POINTS = {name: (Vector(head), Vector(tail)) for name, _, head, tail in BONES_LEANED}


def _pitch(a: Vector, b: Vector) -> float:
    """Angle of a->b in the sagittal plane: 0 = straight down, positive = forward."""
    return math.atan2(b.y - a.y, -(b.z - a.z))


class Chain:
    """Two-bone limb in the sagittal plane, solved analytically."""

    def __init__(self, upper: str, lower: str, bend: float):
        self.root = _BONE_POINTS[upper][0]
        mid = _BONE_POINTS[upper][1]
        self.end = _BONE_POINTS[lower][1]
        self.l1 = math.hypot(mid.y - self.root.y, mid.z - self.root.z)
        self.l2 = math.hypot(self.end.y - mid.y, self.end.z - mid.z)
        self.phi1_rest = _pitch(self.root, mid)
        self.phi2_rest = _pitch(mid, self.end)
        self.bend = bend

    def solve(self, target_y: float, target_z: float, root_dz: float) -> tuple[float, float]:
        """Return (upper, lower) pose rx in degrees that put the end point on the target."""
        hy, hz = self.root.y, self.root.z + root_dz
        dy, dz = target_y - hy, target_z - hz
        reach = min(max(math.hypot(dy, dz), abs(self.l1 - self.l2) + 1e-3), self.l1 + self.l2 - 1e-3)
        to_end = math.atan2(dy, -dz)
        cos_a = (self.l1 * self.l1 + reach * reach - self.l2 * self.l2) / (2.0 * self.l1 * reach)
        phi1 = to_end + self.bend * math.acos(max(-1.0, min(1.0, cos_a)))
        mid_y = hy + self.l1 * math.sin(phi1)
        mid_z = hz - self.l1 * math.cos(phi1)
        end_y = hy + reach * math.sin(to_end)
        end_z = hz - reach * math.cos(to_end)
        phi2 = math.atan2(end_y - mid_y, -(end_z - mid_z))
        upper = phi1 - self.phi1_rest
        lower = (phi2 - self.phi2_rest) - upper
        return math.degrees(upper), math.degrees(lower)


LEG = Chain("Thigh_R", "Shin_R", bend=1.0)
ARM = Chain("UpperArm_R", "Forearm_R", bend=-1.0)
_ANKLE = LEG.end
STRIDE = 0.42
STANCE_DUTY = 0.55
FOOT_LIFT = 0.15


def foot_track(u: float) -> tuple[float, float, float]:
    """Ankle offset (y, z) and foot pitch for gait phase u in [0, 1)."""
    u %= 1.0
    if u < STANCE_DUTY:
        return STRIDE - 2.0 * STRIDE * (u / STANCE_DUTY), 0.0, 0.0
    v = (u - STANCE_DUTY) / (1.0 - STANCE_DUTY)
    eased = v * v * (3.0 - 2.0 * v)
    return -STRIDE + 2.0 * STRIDE * eased, FOOT_LIFT * math.sin(math.pi * v), 14.0 * math.sin(math.pi * v)


def walk_pose(rig):
    def poser(t: float):
        q = 2.0 * math.pi * t
        crouch = -0.08 + 0.03 * abs(math.sin(q))
        pose_offset(rig, "Hips", Vector((0.0, 0.0, crouch)))
        pose_rotate(rig, "Hips", rx=3.0 * math.sin(2.0 * q + 0.6), ry=3.0 * math.sin(q))
        pose_rotate(rig, "Spine", rx=3.0 * math.sin(2.0 * q), rz=-4.0 * math.sin(q))
        pose_rotate(rig, "Chest", rx=-2.0 + 3.0 * math.sin(2.0 * q + 0.5), rz=-6.0 * math.sin(q))
        pose_rotate(rig, "Neck", rx=6.0 * math.sin(2.0 * q + 1.0), rz=7.0 * math.sin(q))
        pose_rotate(rig, "Head", rx=-3.0 * math.sin(2.0 * q + 1.0), rz=-4.0 * math.sin(q))
        pose_rotate(rig, "Jaw", rx=7.0 + 5.0 * math.sin(2.0 * q + 2.0))
        for side in ("R", "L"):
            gait = t if side == "R" else t + 0.5
            dy, dz, pitch = foot_track(gait)
            thigh, shin = LEG.solve(_ANKLE.y + dy, _ANKLE.z + dz, crouch)
            pose_rotate(rig, f"Thigh_{side}", rx=thigh)
            pose_rotate(rig, f"Shin_{side}", rx=shin)
            pose_rotate(rig, f"Foot_{side}", rx=pitch - thigh - shin)
            arm = 2.0 * math.pi * (gait + 0.5)
            reach_y = ARM.end.y + 0.20 * math.cos(arm)
            reach_z = ARM.end.z + 0.04 + 0.07 * max(0.0, -math.sin(arm))
            upper, lower = ARM.solve(reach_y, reach_z, crouch)
            pose_rotate(rig, f"UpperArm_{side}", rx=upper, rz=(3.0 if side == "R" else -3.0))
            pose_rotate(rig, f"Forearm_{side}", rx=lower)
            pose_rotate(rig, f"Hand_{side}", rx=-upper - lower + 6.0 * math.sin(arm + 0.5))
        return ALL_BONES
    return poser


def attack_pose(rig):
    def poser(t: float):
        wind = _pulse(t, 0.0, 0.30, 0.34, 0.36)
        strike_r = _pulse(t, 0.30, 0.46, 0.55, 0.78)
        strike_l = _pulse(t, 0.52, 0.66, 0.72, 0.92)
        lunge = _pulse(t, 0.26, 0.46, 0.60, 0.95)
        pose_offset(rig, "Hips", Vector((0.0, 0.24 * lunge - 0.05 * wind, -0.08 * lunge)))
        pose_rotate(rig, "Spine", rx=-6.0 * wind + 14.0 * lunge)
        pose_rotate(rig, "Chest", rx=-10.0 * wind + 20.0 * lunge, rz=-12.0 * strike_r + 12.0 * strike_l)
        pose_rotate(rig, "Neck", rx=-6.0 * wind + 14.0 * lunge)
        pose_rotate(rig, "Head", rx=-8.0 * wind + 10.0 * lunge)
        pose_rotate(rig, "Jaw", rx=6.0 + 46.0 * lunge)
        pose_rotate(rig, "UpperArm_R", rx=40.0 * wind + 55.0 * strike_r, rz=-18.0 * strike_r)
        pose_rotate(rig, "Forearm_R", rx=-30.0 * wind - 30.0 * strike_r)
        pose_rotate(rig, "Hand_R", rx=-20.0 * strike_r)
        pose_rotate(rig, "UpperArm_L", rx=10.0 * wind + 62.0 * strike_l, rz=18.0 * strike_l)
        pose_rotate(rig, "Forearm_L", rx=-26.0 * strike_l)
        pose_rotate(rig, "Hand_L", rx=-20.0 * strike_l)
        for side, sign in (("R", 1.0), ("L", -1.0)):
            pose_rotate(rig, f"Thigh_{side}", rx=-14.0 * lunge + (10.0 if side == "R" else -10.0) * lunge)
            pose_rotate(rig, f"Shin_{side}", rx=-18.0 * lunge)
        return ALL_BONES
    return poser


def hit_pose(rig):
    def poser(t: float):
        e = math.sin(math.pi * min(1.0, t * 1.15)) * (1.0 - t * 0.2)
        pose_offset(rig, "Hips", Vector((0.0, -0.10 * e, -0.03 * e)))
        pose_rotate(rig, "Spine", rx=-8.0 * e)
        pose_rotate(rig, "Chest", rx=-12.0 * e, rz=8.0 * e)
        pose_rotate(rig, "Neck", rx=-10.0 * e)
        pose_rotate(rig, "Head", rx=-12.0 * e, rz=-10.0 * e)
        pose_rotate(rig, "Jaw", rx=6.0 + 30.0 * e)
        pose_rotate(rig, "UpperArm_R", rx=-12.0 * e, rz=10.0 * e)
        pose_rotate(rig, "UpperArm_L", rx=-12.0 * e, rz=-10.0 * e)
        return {"Hips", "Spine", "Chest", "Neck", "Head", "Jaw", "UpperArm_R", "UpperArm_L"}
    return poser


def die_pose(rig):
    def poser(t: float):
        buckle = _smoothstep(0.0, 0.4, t)
        fall = _smoothstep(0.3, 0.92, t)
        pose_offset(rig, "Hips", Vector((0.05 * fall, 0.04 * buckle, -0.18 * buckle - 0.52 * fall)))
        pose_rotate(rig, "Hips", rx=14.0 * buckle, ry=84.0 * fall)
        pose_rotate(rig, "Spine", rx=10.0 * buckle)
        pose_rotate(rig, "Chest", rx=12.0 * buckle, rz=-6.0 * fall)
        pose_rotate(rig, "Neck", rx=-8.0 * fall)
        pose_rotate(rig, "Head", rx=-14.0 * fall, rz=14.0 * fall)
        pose_rotate(rig, "Jaw", rx=6.0 + 36.0 * fall)
        pose_rotate(rig, "UpperArm_R", rx=24.0 * buckle, rz=-28.0 * fall)
        pose_rotate(rig, "UpperArm_L", rx=30.0 * buckle, rz=14.0 * fall)
        pose_rotate(rig, "Forearm_R", rx=-20.0 * fall)
        pose_rotate(rig, "Forearm_L", rx=-30.0 * fall)
        for side in ("R", "L"):
            pose_rotate(rig, f"Thigh_{side}", rx=(36.0 if side == "R" else 22.0) * buckle)
            pose_rotate(rig, f"Shin_{side}", rx=-44.0 * buckle)
        return ALL_BONES
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
        ("Walk", 20, walk_pose(rig), True),
        ("Attack", 26, attack_pose(rig), False),
        ("Hit", 14, hit_pose(rig), False),
        ("Die", 40, die_pose(rig), False),
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
    body.name = "Soglot"
    body.data.name = "SoglotBody"
    return body


def sharpen_edges(obj: bpy.types.Object, angle: float = 52.0) -> None:
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
    bpy.ops.object.camera_add(location=(2.6, 3.0, 1.8))
    cam = bpy.context.active_object
    direction = Vector((0.0, 0.05, 0.95)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    bpy.ops.object.light_add(type="AREA", location=(-2.2, 2.4, 3.8))
    light = bpy.context.active_object
    light.data.energy = 650
    light.data.size = 3
    bpy.ops.object.light_add(type="AREA", location=(2.6, -2.0, 2.4))
    fill = bpy.context.active_object
    fill.data.energy = 220
    fill.data.size = 3
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
        bg.inputs[0].default_value = (0.86, 0.86, 0.86, 1.0)
        bg.inputs[1].default_value = 0.9
    try:
        bpy.ops.render.render(write_still=True)
        print(f"Wrote {PNG_OUT}")
    except Exception as exc:
        print(f"Preview render skipped: {exc}")


def main() -> None:
    clear_scene()
    parts = build_character()
    for obj, _allowed in parts:
        if obj.name.startswith(("Torso", "Head", "Thigh", "UpperArm", "Forearm", "Shin", "Neck", "Belly")):
            add_surface_noise(obj, 0.008, 0.0035, seed=zlib.crc32(obj.name.encode()) % 17)
    for obj, _allowed in parts:
        for vert in obj.data.vertices:
            vert.co.y += lean_offset(vert.co.z)
        obj.data.update()
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
        f"Soglot: {len(body.data.vertices)} verts, {triangles} tris, "
        f"{len(body.material_slots)} materials, {len(bpy.data.actions)} actions"
    )
    BLEND_OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
    export(rig, body)
    render_preview()


if __name__ == "__main__":
    main()
