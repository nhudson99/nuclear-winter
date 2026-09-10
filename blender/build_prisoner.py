"""
Build the player character: a bald prisoner in a worn jumpsuit and work boots.

Authored headlessly through Blender's Python API (Blender MCP is unavailable in
the cloud environment), so every shape is generated from lofted rings rather
than hand-modelled. Output is a skinned GLB with Idle / Walk / Run / Die
animations plus the .blend for further editing.

Conventions (shared with the other builders in this folder):
  * +Z up, feet on z = 0, character faces +Y, +X is the character's right.
  * Export uses export_yup, so +Y in Blender becomes -Z in Godot -- the
    standard glTF forward axis.

Usage:
    blender --background --python blender/build_prisoner.py
    blender --background --python blender/build_prisoner.py -- --skip-bake
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Vector, noise

OUT_DIR = Path("/workspace/godot/assets/characters")
BLEND_OUT = Path("/workspace/blender/player_prisoner.blend")
GLB_OUT = OUT_DIR / "player_prisoner.glb"
TEX_OUT = Path("/workspace/blender/player_prisoner_baked.png")

BAKE_SIZE = 1024
SEGMENTS = 16

# Surface groups. Everything is baked into one colour atlas, but the model keeps
# one material per group so fabric, leather and skin can differ in roughness.
GROUP_FABRIC = "fabric"
GROUP_LEATHER = "leather"
GROUP_SKIN = "skin"


# --------------------------------------------------------------------------- #
# Scene helpers
# --------------------------------------------------------------------------- #

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
    """sRGB hex to the linear values Blender's colour sockets expect."""
    hex_color = hex_color.lstrip("#")
    out = []
    for i in range(0, 6, 2):
        c = int(hex_color[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


def worn_material(
    name: str,
    group: str,
    base: str,
    grime: str,
    stain: str,
    roughness: float = 0.85,
    grime_mix: float = 0.45,
    stain_mix: float = 0.35,
    grain_scale: float = 26.0,
    stain_scale: float = 3.2,
    ground_dirt: float = 1.0,
):
    """A base colour worn down by fabric grain, blotchy stains and ground dirt.

    The procedural noise is baked to an image later on -- glTF cannot carry
    shader nodes -- so this only has to look right at bake time. `ground_dirt`
    weights the stain layer towards the floor, which is where a jumpsuit
    actually gets filthy: clean shoulders, grubby knees, caked boots.
    """
    mat = bpy.data.materials.new(name=name)
    mat["surface_group"] = group
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = roughness

    coords = nt.nodes.new("ShaderNodeTexCoord")

    def math(operation: str, socket_a, value_b: float):
        node = nt.nodes.new("ShaderNodeMath")
        node.operation = operation
        node.inputs[1].default_value = value_b
        nt.links.new(socket_a, node.inputs[0])
        return node.outputs[0]

    def noise(scale: float, detail: float, lo: float, hi: float, amount: float):
        tex = nt.nodes.new("ShaderNodeTexNoise")
        tex.inputs["Scale"].default_value = scale
        tex.inputs["Detail"].default_value = detail
        tex.inputs["Roughness"].default_value = 0.62
        nt.links.new(coords.outputs["Object"], tex.inputs["Vector"])
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = lo
        ramp.color_ramp.elements[1].position = hi
        nt.links.new(tex.outputs["Fac"], ramp.inputs["Fac"])
        return math("MULTIPLY", ramp.outputs["Color"], amount)

    def mix(factor_socket, color_a, color_b):
        node = nt.nodes.new("ShaderNodeMix")
        node.data_type = "RGBA"
        node.blend_type = "MIX"
        # Indices avoid the duplicated A/B socket names on ShaderNodeMix.
        node.inputs[6].default_value = color_a if isinstance(color_a, tuple) else (0, 0, 0, 1)
        node.inputs[7].default_value = color_b
        nt.links.new(factor_socket, node.inputs[0])
        if not isinstance(color_a, tuple):
            nt.links.new(color_a, node.inputs[6])
        return node.outputs[2]

    # Height ramp in object space: 0 at the shoulders, 1 at the soles.
    split = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(coords.outputs["Object"], split.inputs["Vector"])
    height = nt.nodes.new("ShaderNodeMapRange")
    height.clamp = True
    height.inputs["From Min"].default_value = 1.35
    height.inputs["From Max"].default_value = 0.10
    nt.links.new(split.outputs["Z"], height.inputs["Value"])
    dirt_weight = math("MULTIPLY", height.outputs["Result"], ground_dirt)
    dirt_weight = math("ADD", dirt_weight, 1.0 - ground_dirt)

    grain = noise(grain_scale, 10.0, 0.44, 0.60, grime_mix)
    blotch = nt.nodes.new("ShaderNodeMath")
    blotch.operation = "MULTIPLY"
    nt.links.new(noise(stain_scale, 6.0, 0.46, 0.68, stain_mix), blotch.inputs[0])
    nt.links.new(dirt_weight, blotch.inputs[1])

    weathered = mix(grain, srgb(base), srgb(grime))
    stained = mix(blotch.outputs[0], weathered, srgb(stain))
    nt.links.new(stained, bsdf.inputs["Base Color"])
    return mat


# --------------------------------------------------------------------------- #
# Mesh construction
# --------------------------------------------------------------------------- #

def _profile(angle: float, rx: float, ry: float, power: float) -> tuple[float, float]:
    """Superellipse sample. power=1 is a circle, lower values square it off."""
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
    """Loft a closed surface through a list of rings.

    Each section is {"c": centre, "rx": .., "ry": .., "p": superellipse power}.
    Rings lie in the plane spanned by axis_u / axis_v; caps are "dome", "flat"
    or "none" (left open, for shapes that end inside another part).
    """
    u = Vector(axis_u).normalized()
    v = Vector(axis_v).normalized()
    rings: list[tuple[Vector, float, float, float]] = [
        (Vector(s["c"]), s["rx"], s["ry"], s.get("p", 1.0)) for s in sections
    ]

    def dome_extension(inner, outer):
        """Extra rings sweeping from `outer` towards a pole, sphere-like."""
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


def box(name: str, material, centre, size, power: float = 0.35) -> bpy.types.Object:
    """A softened box -- squared-off superellipse rings, so edges read as seams."""
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
    )


# Per-material (coarse fold, fine grain) displacement, in metres.
WRINKLES = {
    "Jumpsuit": (0.0042, 0.0014),
    "JumpsuitTrim": (0.0024, 0.0010),
    "BootLeather": (0.0018, 0.0009),
}


def add_wrinkles(obj: bpy.types.Object) -> None:
    """Nudge cloth surfaces along their normals with two octaves of noise.

    Lofted rings are perfectly regular, which is what makes untextured game
    characters look shrink-wrapped; a few millimetres of noise reads as fabric.
    """
    settings = WRINKLES.get(obj.data.materials[0].name)
    if settings is None:
        return
    fold, grain = settings
    for vert in obj.data.vertices:
        point = vert.co
        offset = fold * noise.noise(point * 7.0) + grain * noise.noise(point * 34.0)
        vert.co = point + vert.normal * offset


# Crown 1.800, eye line 1.700, chin 1.585 -- so the eyes sit halfway up the
# head, which is what separates a head from an egg.
HEAD_CENTRE = Vector((0.0, 0.0, 1.6925))
HEAD_RADII = Vector((0.081, 0.099, 0.1075))

# Half-width / half-depth of the skull as a fraction of HEAD_RADII, sampled by
# normalised height (+1 crown, 0 eye line, -1 under the chin).
SKULL_WIDTH = [
    (-1.00, 0.17), (-0.85, 0.46), (-0.70, 0.69), (-0.50, 0.86), (-0.25, 0.97),
    (0.00, 1.00), (0.30, 0.955), (0.55, 0.855), (0.75, 0.685), (0.88, 0.49),
    (0.95, 0.32), (1.00, 0.0),
]
SKULL_DEPTH = [
    (-1.00, 0.30), (-0.85, 0.60), (-0.70, 0.79), (-0.50, 0.90), (-0.25, 0.97),
    (0.00, 1.00), (0.30, 0.975), (0.55, 0.875), (0.75, 0.705), (0.88, 0.51),
    (0.95, 0.33), (1.00, 0.0),
]


def _curve(table: list[tuple[float, float]], x: float) -> float:
    if x <= table[0][0]:
        return table[0][1]
    for (x0, y0), (x1, y1) in zip(table, table[1:]):
        if x <= x1:
            t = (x - x0) / (x1 - x0)
            return y0 + (y1 - y0) * (t * t * (3.0 - 2.0 * t))
    return table[-1][1]


def skull_point(u: float, v: float, offset: float = 0.0) -> Vector:
    """Head surface. u wraps the azimuth, v runs crown (0) to under-chin (1).

    `offset` lifts the point radially, which is how the stubble shell floats
    over the scalp -- a proportional swell would collapse at the crown and
    z-fight with the skull.
    """
    theta = 2.0 * math.pi * u
    height = math.cos(math.pi * v)
    front = max(0.0, math.sin(theta))

    width = HEAD_RADII.x * _curve(SKULL_WIDTH, height)
    depth = HEAD_RADII.y * _curve(SKULL_DEPTH, height)
    x = width * math.cos(theta)
    y = depth * math.sin(theta)
    z = HEAD_RADII.z * height

    # Flat-backed occiput and a forehead that is not a bulge.
    if y < 0.0:
        y *= 0.94 + 0.06 * max(0.0, -height)
    elif height > 0.25:
        y *= 1.0 - 0.07 * _smoothstep(0.25, 0.9, height)
    # Brow ridge, the socket beneath it, cheekbone, then the hollow under it.
    y += 0.005 * _bump(height, 0.33, 0.11) * front
    y -= 0.008 * _bump(height, 0.06, 0.10) * max(0.0, front - 0.45) / 0.55
    y += 0.004 * _bump(height, -0.25, 0.14) * front
    y -= 0.004 * _bump(height, -0.55, 0.13) * front
    # A chin, rather than the front of the jaw simply running out.
    y += 0.010 * _bump(height, -0.86, 0.13) * max(0.0, front - 0.55) / 0.45

    local = Vector((x, y, z))
    if offset:
        local += local.normalized() * offset
    return local + HEAD_CENTRE


def front_surface(x: float, z: float) -> float:
    """The y of the face at (x, z) -- for planting features on the surface."""
    best_y, best_error = 0.0, float("inf")
    for i in range(160):
        u = 0.001 + 0.498 * i / 159
        for j in range(1, 200):
            point = skull_point(u, j / 200)
            error = (point.x - x) ** 2 + (point.z - z) ** 2
            if error < best_error:
                best_error, best_y = error, point.y
    return best_y


def side_surface(z: float) -> float:
    """The half-width of the head at height z."""
    best_x, best_error = 0.0, float("inf")
    for j in range(1, 200):
        point = skull_point(0.0, j / 200)
        error = (point.z - z) ** 2
        if error < best_error:
            best_error, best_x = error, point.x
    return best_x


def _smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = min(1.0, max(0.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def _bump(x: float, centre: float, width: float) -> float:
    return math.exp(-((x - centre) / width) ** 2)


def build_head(material) -> bpy.types.Object:
    segments = 28
    v_values = [i / 22 for i in range(23)]
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
    # Underside is hidden inside the neck; close it so the mesh stays solid.
    centre = bm.verts.new(sum((vert.co for vert in rings[-1]), Vector()) / segments)
    for i in range(segments):
        j = (i + 1) % segments
        bm.faces.new((rings[-1][j], rings[-1][i], centre))
    return _finish("Head", bm, material)


def build_stubble(material) -> bpy.types.Object:
    """Shaved-scalp shell: the buzzed shadow from the reference, receding at the front."""
    segments = 32
    steps = 11
    bm = bmesh.new()

    def hairline(u: float) -> float:
        # Receding at the front (z 1.765), lower at the temples, and down to
        # the nape at the back.
        theta = 2.0 * math.pi * u
        return 0.386 - 0.118 * math.sin(theta) + 0.022 * abs(math.cos(theta))

    rings = [[bm.verts.new(skull_point(0.0, 0.0, 0.0018))] * segments]
    for step in range(1, steps + 1):
        t = step / steps
        ring = []
        for i in range(segments):
            u = i / segments
            # Thins out over the last two rings so the rim fades into skin.
            offset = 0.0018 if step < steps - 1 else (0.0009 if step < steps else 0.0)
            ring.append(bm.verts.new(skull_point(u, t * hairline(u), offset)))
        rings.append(ring)

    for lower, upper in zip(rings, rings[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            if lower[i] is lower[j]:
                bm.faces.new((upper[i], upper[j], lower[i]))
            else:
                bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
    return _finish("Stubble", bm, material)


# --------------------------------------------------------------------------- #
# Character parts
# --------------------------------------------------------------------------- #

def build_character() -> list[tuple[bpy.types.Object, list[str]]]:
    """Return every part paired with the bones it may be weighted to."""
    jumpsuit = worn_material("Jumpsuit", GROUP_FABRIC, "#6a717a", "#565d66", "#3f4550",
                             roughness=0.9, grime_mix=0.55, stain_mix=0.55, stain_scale=2.6)
    trim = worn_material("JumpsuitTrim", GROUP_FABRIC, "#585f68", "#474d55", "#383d46",
                         roughness=0.92, grain_scale=48.0, stain_mix=0.4)
    zipper = worn_material("Zipper", GROUP_LEATHER, "#3d4046", "#2a2c30", "#4e5157",
                           roughness=0.45, grain_scale=60.0, stain_mix=0.25, ground_dirt=0.3)
    leather = worn_material("BootLeather", GROUP_LEATHER, "#8d6b3b", "#6a5029", "#4a3a22",
                            roughness=0.55, grime_mix=0.6, stain_mix=0.6, stain_scale=7.0)
    rubber = worn_material("BootSole", GROUP_LEATHER, "#2c2a27", "#1b1a18", "#3a352f",
                           roughness=0.75, grain_scale=45.0)
    skin = worn_material("Skin", GROUP_SKIN, "#c1997c", "#ab8265", "#8e6a4e",
                         roughness=0.68, grime_mix=0.3, stain_mix=0.35, stain_scale=9.0)
    stubble_mat = worn_material("Stubble", GROUP_SKIN, "#8f7a66", "#6f5d4d", "#9c8873",
                                roughness=0.85, grain_scale=90.0, grime_mix=0.4,
                                ground_dirt=0.0)
    dark = worn_material("Eye", GROUP_LEATHER, "#3a2f28", "#241d18", "#4a3c31",
                         roughness=0.25, grime_mix=0.15, stain_mix=0.1, ground_dirt=0.0)
    brow_mat = worn_material("Brow", GROUP_SKIN, "#5c4c3e", "#43372c", "#6a5949",
                             roughness=0.9, grain_scale=110.0, ground_dirt=0.0)

    spine_bones = ["Hips", "Spine", "Chest", "Neck"]
    parts: list[tuple[bpy.types.Object, list[str]]] = []

    # ---- torso: baggy coverall, waist gathered by an elastic band ---------- #
    # The lowest rings pinch in between the thighs so the closing cap hides in
    # the crotch instead of leaving a visible hem across the hips.
    parts.append((tube("Torso", jumpsuit, [
        {"c": (0, 0.002, 0.790), "rx": 0.045, "ry": 0.070, "p": 0.90},
        {"c": (0, 0.002, 0.830), "rx": 0.098, "ry": 0.088, "p": 0.90},
        {"c": (0, 0.004, 0.890), "rx": 0.145, "ry": 0.106, "p": 0.90},
        {"c": (0, 0.004, 0.950), "rx": 0.168, "ry": 0.117, "p": 0.90},
        {"c": (0, 0.004, 1.020), "rx": 0.157, "ry": 0.110, "p": 0.92},
        {"c": (0, 0.004, 1.075), "rx": 0.161, "ry": 0.112, "p": 0.92},
        {"c": (0, 0.006, 1.160), "rx": 0.177, "ry": 0.118, "p": 0.94},
        {"c": (0, 0.006, 1.265), "rx": 0.190, "ry": 0.123, "p": 0.94},
        {"c": (0, 0.004, 1.360), "rx": 0.191, "ry": 0.120, "p": 0.94},
        {"c": (0, 0.002, 1.425), "rx": 0.176, "ry": 0.113, "p": 0.94},
        {"c": (0, 0.000, 1.462), "rx": 0.142, "ry": 0.101, "p": 0.95},
        {"c": (0, 0.000, 1.500), "rx": 0.094, "ry": 0.084, "p": 0.96},
        {"c": (0, 0.000, 1.520), "rx": 0.072, "ry": 0.070, "p": 0.96},
    ], cap_start="flat", cap_end="flat"), spine_bones))

    parts.append((tube("WaistBand", trim, [
        {"c": (0, 0.004, 1.020), "rx": 0.158, "ry": 0.112, "p": 0.92},
        {"c": (0, 0.004, 1.040), "rx": 0.161, "ry": 0.115, "p": 0.92},
        {"c": (0, 0.004, 1.058), "rx": 0.158, "ry": 0.112, "p": 0.92},
    ], cap_start="flat", cap_end="flat"), spine_bones))

    # Front zip runs from the waist to the collar, following the chest curve.
    parts.append((tube("Zip", zipper, [
        {"c": (0, 0.104, 1.030), "rx": 0.011, "ry": 0.012, "p": 0.6},
        {"c": (0, 0.116, 1.160), "rx": 0.012, "ry": 0.012, "p": 0.6},
        {"c": (0, 0.123, 1.265), "rx": 0.012, "ry": 0.012, "p": 0.6},
        {"c": (0, 0.119, 1.370), "rx": 0.011, "ry": 0.012, "p": 0.6},
        {"c": (0, 0.106, 1.430), "rx": 0.010, "ry": 0.011, "p": 0.6},
    ], cap_start="flat", cap_end="flat"), spine_bones))
    parts.append((box("ZipPull", zipper, (0.0, 0.110, 1.048), (0.016, 0.012, 0.026)),
                  spine_bones))

    for side, sign in (("R", 1.0), ("L", -1.0)):
        # Welt seams rather than patch pockets: nearly flush with the hip.
        parts.append((box(f"HipPocket_{side}", trim,
                          (sign * 0.112, 0.078, 0.958), (0.086, 0.010, 0.014)),
                      spine_bones))

    # ---- standing collar: folded so it has thickness from every angle ----- #
    # The inner wall drops back down close to the neck, otherwise the collar
    # reads as an open funnel with a hole around the throat.
    parts.append((tube("Collar", jumpsuit, [
        {"c": (0, 0.004, 1.408), "rx": 0.094, "ry": 0.089, "p": 0.95},
        {"c": (0, 0.006, 1.505), "rx": 0.097, "ry": 0.092, "p": 0.95},
        {"c": (0, 0.008, 1.548), "rx": 0.096, "ry": 0.091, "p": 0.95},
        {"c": (0, 0.008, 1.552), "rx": 0.086, "ry": 0.081, "p": 0.95},
        {"c": (0, 0.006, 1.500), "rx": 0.072, "ry": 0.070, "p": 0.95},
        {"c": (0, 0.004, 1.450), "rx": 0.068, "ry": 0.068, "p": 0.95},
    ], cap_start="flat", cap_end="flat"), ["Chest", "Neck", "Head"]))

    parts.append((tube("Neck", skin, [
        {"c": (0, 0.004, 1.380), "rx": 0.068, "ry": 0.070},
        {"c": (0, 0.004, 1.480), "rx": 0.063, "ry": 0.066},
        {"c": (0, 0.002, 1.560), "rx": 0.060, "ry": 0.064},
        {"c": (0, 0.000, 1.600), "rx": 0.058, "ry": 0.062},
    ], cap_start="flat", cap_end="flat"), ["Chest", "Neck", "Head"]))

    # ---- head ------------------------------------------------------------- #
    parts.append((build_head(skin), ["Neck", "Head"]))
    parts.append((build_stubble(stubble_mat), ["Head"]))
    # Features are planted on the measured skull surface so reshaping the head
    # cannot bury the nose or leave the ears floating.
    nose_root, nose_tip, nose_base = 1.742, 1.678, 1.655
    parts.append((tube("Nose", skin, [
        {"c": (0, front_surface(0.0, nose_root) - 0.004, nose_root), "rx": 0.007, "ry": 0.006},
        {"c": (0, front_surface(0.0, 1.712) + 0.006, 1.712), "rx": 0.010, "ry": 0.011},
        {"c": (0, front_surface(0.0, nose_tip) + 0.011, nose_tip), "rx": 0.014, "ry": 0.013},
        {"c": (0, front_surface(0.0, 1.664) + 0.008, 1.664), "rx": 0.016, "ry": 0.011},
        {"c": (0, front_surface(0.0, nose_base) - 0.002, nose_base), "rx": 0.013, "ry": 0.008},
    ], cap_start="flat", cap_end="flat"), ["Head"]))
    parts.append((box("Mouth", dark,
                      (0.0, front_surface(0.0, 1.626) - 0.002, 1.626),
                      (0.030, 0.008, 0.004)), ["Head"]))
    ear_x = side_surface(1.700)
    for side, sign in (("R", 1.0), ("L", -1.0)):
        # Ears / eyes / brows stack along their own axis, so each needs its own
        # ring plane -- a ring plane containing the stacking axis is degenerate.
        parts.append((tube(f"Ear_{side}", skin, [
            {"c": (sign * (ear_x - 0.016), -0.014, 1.700), "rx": 0.016, "ry": 0.029, "p": 0.9},
            {"c": (sign * (ear_x - 0.002), -0.018, 1.698), "rx": 0.014, "ry": 0.026, "p": 0.9},
            {"c": (sign * (ear_x + 0.005), -0.021, 1.694), "rx": 0.010, "ry": 0.020, "p": 0.9},
        ], axis_u=(0, 1, 0), axis_v=(0, 0, 1), cap_start="none", cap_end="dome"), ["Head"]))
        eye_y = front_surface(0.032, 1.706)
        parts.append((tube(f"Eye_{side}", dark, [
            {"c": (sign * 0.032, eye_y - 0.012, 1.706), "rx": 0.012, "ry": 0.008},
            {"c": (sign * 0.032, eye_y - 0.001, 1.706), "rx": 0.009, "ry": 0.006},
        ], axis_u=(1, 0, 0), axis_v=(0, 0, 1), cap_start="none", cap_end="dome"), ["Head"]))
        parts.append((tube(f"Brow_{side}", brow_mat, [
            {"c": (sign * 0.008, front_surface(0.008, 1.726) + 0.001, 1.726),
             "rx": 0.007, "ry": 0.0035, "p": 0.7},
            {"c": (sign * 0.032, front_surface(0.032, 1.730) + 0.001, 1.730),
             "rx": 0.007, "ry": 0.0035, "p": 0.7},
            {"c": (sign * 0.055, front_surface(0.055, 1.724), 1.724),
             "rx": 0.005, "ry": 0.003, "p": 0.7},
        ], axis_u=(0, 1, 0), axis_v=(0, 0, 1), cap_start="flat", cap_end="flat"), ["Head"]))

    # ---- arms ------------------------------------------------------------- #
    for side, sign in (("R", 1.0), ("L", -1.0)):
        arm_bones = [f"UpperArm_{side}", f"Forearm_{side}", "Chest"]
        parts.append((tube(f"Arm_{side}", jumpsuit, [
            {"c": (sign * 0.158, 0.004, 1.378), "rx": 0.075, "ry": 0.078},
            {"c": (sign * 0.176, 0.004, 1.330), "rx": 0.071, "ry": 0.074},
            {"c": (sign * 0.194, 0.008, 1.230), "rx": 0.062, "ry": 0.065},
            {"c": (sign * 0.204, 0.012, 1.140), "rx": 0.057, "ry": 0.060},
            {"c": (sign * 0.216, 0.022, 1.010), "rx": 0.050, "ry": 0.053},
            {"c": (sign * 0.222, 0.028, 0.940), "rx": 0.046, "ry": 0.048},
        ], cap_start="dome", cap_end="flat"), arm_bones))
        parts.append((tube(f"Cuff_{side}", trim, [
            {"c": (sign * 0.221, 0.027, 0.946), "rx": 0.048, "ry": 0.050},
            {"c": (sign * 0.223, 0.029, 0.918), "rx": 0.044, "ry": 0.046},
            {"c": (sign * 0.224, 0.030, 0.906), "rx": 0.040, "ry": 0.042},
        ], cap_start="flat", cap_end="flat"), [f"Forearm_{side}", f"Hand_{side}"]))
        parts.append((tube(f"Hand_{side}", skin, [
            {"c": (sign * 0.224, 0.030, 0.912), "rx": 0.037, "ry": 0.029},
            {"c": (sign * 0.226, 0.032, 0.865), "rx": 0.040, "ry": 0.031},
            {"c": (sign * 0.228, 0.034, 0.810), "rx": 0.038, "ry": 0.030},
            {"c": (sign * 0.229, 0.036, 0.772), "rx": 0.030, "ry": 0.025},
        ], cap_start="none", cap_end="dome"), [f"Forearm_{side}", f"Hand_{side}"]))
        parts.append((tube(f"Thumb_{side}", skin, [
            {"c": (sign * 0.196, 0.038, 0.880), "rx": 0.014, "ry": 0.014},
            {"c": (sign * 0.190, 0.048, 0.845), "rx": 0.012, "ry": 0.012},
        ], cap_start="flat", cap_end="dome"), [f"Hand_{side}"]))

    # ---- legs and boots --------------------------------------------------- #
    for side, sign in (("R", 1.0), ("L", -1.0)):
        leg_bones = ["Hips", f"Thigh_{side}", f"Shin_{side}"]
        parts.append((tube(f"Leg_{side}", jumpsuit, [
            {"c": (sign * 0.098, 0.004, 0.975), "rx": 0.088, "ry": 0.102, "p": 0.95},
            {"c": (sign * 0.098, 0.004, 0.850), "rx": 0.088, "ry": 0.100, "p": 0.95},
            {"c": (sign * 0.098, 0.002, 0.680), "rx": 0.083, "ry": 0.094, "p": 0.95},
            {"c": (sign * 0.098, 0.000, 0.520), "rx": 0.078, "ry": 0.087, "p": 0.95},
            {"c": (sign * 0.098, 0.002, 0.380), "rx": 0.074, "ry": 0.083, "p": 0.95},
            {"c": (sign * 0.098, 0.004, 0.265), "rx": 0.070, "ry": 0.079, "p": 0.95},
            # The hem has to finish below the boot collar, or the trouser leg
            # floats above the boot.
            {"c": (sign * 0.098, 0.006, 0.180), "rx": 0.078, "ry": 0.087, "p": 0.95},
        ], cap_start="flat", cap_end="flat"), leg_bones))

        boot_bones = [f"Shin_{side}", f"Foot_{side}"]
        boot_sections = [
            {"y": -0.082, "rx": 0.044, "rz": 0.046},
            {"y": -0.058, "rx": 0.054, "rz": 0.082},
            {"y": -0.018, "rx": 0.060, "rz": 0.100},
            {"y": 0.022, "rx": 0.062, "rz": 0.096},
            {"y": 0.060, "rx": 0.061, "rz": 0.062},
            {"y": 0.110, "rx": 0.057, "rz": 0.049},
            {"y": 0.160, "rx": 0.050, "rz": 0.042},
            {"y": 0.198, "rx": 0.034, "rz": 0.035},
        ]
        parts.append((tube(f"Boot_{side}", leather, [
            {"c": (sign * 0.098, s["y"], s["rz"]), "rx": s["rx"], "ry": s["rz"], "p": 0.62}
            for s in boot_sections
        ], axis_u=(1, 0, 0), axis_v=(0, 0, 1), cap_start="flat", cap_end="dome"), boot_bones))
        parts.append((tube(f"Sole_{side}", rubber, [
            {"c": (sign * 0.098, s["y"], 0.016), "rx": s["rx"] * 1.07, "ry": 0.016, "p": 0.5}
            for s in boot_sections
        ], axis_u=(1, 0, 0), axis_v=(0, 0, 1), cap_start="flat", cap_end="flat"), boot_bones))
        for index, y in enumerate((0.058, 0.092, 0.126)):
            parts.append((tube(f"Lace_{side}{index}", rubber, [
                {"c": (sign * 0.098 - 0.036, y, 0.056 - index * 0.006), "rx": 0.007, "ry": 0.005},
                {"c": (sign * 0.098 + 0.036, y, 0.056 - index * 0.006), "rx": 0.007, "ry": 0.005},
            ], axis_u=(0, 1, 0), axis_v=(0, 0, 1), cap_start="flat", cap_end="flat"), boot_bones))

    return parts


# --------------------------------------------------------------------------- #
# Armature and skinning
# --------------------------------------------------------------------------- #

BONES: list[tuple[str, str | None, tuple[float, float, float], tuple[float, float, float]]] = [
    ("Hips", None, (0, 0, 0.930), (0, 0, 1.070)),
    ("Spine", "Hips", (0, 0, 1.070), (0, 0, 1.230)),
    ("Chest", "Spine", (0, 0, 1.230), (0, 0, 1.420)),
    ("Neck", "Chest", (0, 0, 1.420), (0, 0, 1.560)),
    ("Head", "Neck", (0, 0, 1.560), (0, 0, 1.800)),
]
for _side, _sign in (("R", 1.0), ("L", -1.0)):
    BONES += [
        (f"UpperArm_{_side}", "Chest", (_sign * 0.166, 0.004, 1.412), (_sign * 0.204, 0.012, 1.140)),
        (f"Forearm_{_side}", f"UpperArm_{_side}", (_sign * 0.204, 0.012, 1.140), (_sign * 0.223, 0.029, 0.916)),
        (f"Hand_{_side}", f"Forearm_{_side}", (_sign * 0.223, 0.029, 0.916), (_sign * 0.229, 0.036, 0.772)),
        (f"Thigh_{_side}", "Hips", (_sign * 0.096, 0.004, 0.945), (_sign * 0.098, 0.000, 0.520)),
        (f"Shin_{_side}", f"Thigh_{_side}", (_sign * 0.098, 0.000, 0.520), (_sign * 0.098, 0.004, 0.150)),
        (f"Foot_{_side}", f"Shin_{_side}", (_sign * 0.098, 0.004, 0.150), (_sign * 0.098, 0.150, 0.035)),
    ]


def build_armature() -> bpy.types.Object:
    armature = bpy.data.armatures.new("PrisonerRig")
    obj = bpy.data.objects.new("PrisonerRig", armature)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    for name, parent, head, tail in BONES:
        bone = armature.edit_bones.new(name)
        bone.head = Vector(head)
        bone.tail = Vector(tail)
        if parent:
            bone.parent = armature.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def _distance_to_bone(point: Vector, head: Vector, tail: Vector) -> float:
    segment = tail - head
    length_sq = segment.length_squared
    if length_sq < 1e-9:
        return (point - head).length
    t = min(1.0, max(0.0, (point - head).dot(segment) / length_sq))
    return (point - (head + segment * t)).length


def skin_part(obj: bpy.types.Object, allowed: list[str], falloff: float = 4.0) -> None:
    """Weight a part by inverse distance to its whitelisted bones.

    Automatic (bone heat) weighting is unreliable on a body assembled from
    overlapping lofts, and a whitelist keeps a hanging hand from grabbing
    weight off the nearby thigh.
    """
    bone_table = {name: (Vector(head), Vector(tail)) for name, _, head, tail in BONES}
    bones = [(name, *bone_table[name]) for name in allowed]
    groups = {name: obj.vertex_groups.new(name=name) for name, _, _ in bones}
    for vert in obj.data.vertices:
        point = vert.co
        weights = []
        for name, head, tail in bones:
            distance = max(1e-4, _distance_to_bone(point, head, tail))
            weights.append((name, 1.0 / distance ** falloff))
        weights.sort(key=lambda item: item[1], reverse=True)
        weights = weights[:3]
        total = sum(weight for _, weight in weights)
        for name, weight in weights:
            groups[name].add([vert.index], weight / total, "REPLACE")


# --------------------------------------------------------------------------- #
# Animation
# --------------------------------------------------------------------------- #

def pose_rotate(rig: bpy.types.Object, bone: str, rx: float = 0.0, ry: float = 0.0, rz: float = 0.0) -> None:
    """Rotate a bone by armature-space degrees, about its own head.

    Working in armature space keeps the animation readable: X swings a limb
    forward, Y tilts it sideways, Z twists it -- no bone-roll bookkeeping.
    """
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
        # A looping cycle repeats its first pose on the last frame.
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
        pose_rotate(rig, "Spine", rx=0.9 * breath)
        pose_rotate(rig, "Chest", rx=1.6 + 1.4 * breath, rz=1.2 * math.sin(q * 0.5))
        pose_rotate(rig, "Neck", rx=-2.0 - 1.0 * breath)
        pose_rotate(rig, "Head", rx=-4.0 + 1.6 * math.sin(q * 0.5 + 0.7),
                    rz=2.5 * math.sin(q * 0.37))
        pose_offset(rig, "Hips", Vector((0.0, 0.0, 0.005 * breath)))
        pose_rotate(rig, "Hips", ry=1.2 * math.sin(q * 0.5))
        for side, sign in (("R", 1.0), ("L", -1.0)):
            pose_rotate(rig, f"UpperArm_{side}", rx=1.8 * breath, ry=-sign * 1.5 * breath)
            pose_rotate(rig, f"Forearm_{side}", rx=6.0 + 2.0 * breath)
            pose_rotate(rig, f"Hand_{side}", rx=4.0)
        return {"Spine", "Chest", "Neck", "Head", "Hips",
                "UpperArm_R", "UpperArm_L", "Forearm_R", "Forearm_L", "Hand_R", "Hand_L"}
    return poser


def _gait(rig, thigh_swing: float, knee_flex: float, arm_swing: float,
          elbow: float, lean: float, bob: float, lift: float):
    """Shared walk/run cycle. t=0 is right-foot contact."""
    def poser(t: float):
        q = 2.0 * math.pi * t
        pose_offset(rig, "Hips", Vector((0.0, 0.0, -bob + bob * math.cos(2.0 * q))))
        pose_rotate(rig, "Hips", rx=lean * 0.35, rz=-4.0 * math.sin(q), ry=2.5 * math.sin(q))
        pose_rotate(rig, "Spine", rx=lean * 0.35, rz=2.0 * math.sin(q))
        pose_rotate(rig, "Chest", rx=lean * 0.3, rz=5.0 * math.sin(q + math.pi))
        pose_rotate(rig, "Neck", rx=-lean * 0.5)
        pose_rotate(rig, "Head", rx=-lean * 0.45 - 2.0)
        for side, sign in (("R", 1.0), ("L", -1.0)):
            # Right leg leads; the left is half a cycle behind.
            leg = q if side == "R" else q + math.pi
            swing = math.sin(leg)
            pose_rotate(rig, f"Thigh_{side}", rx=thigh_swing * swing + lean * 0.2,
                        ry=-sign * 1.5)
            # Knee stays straight through stance, folds during the swing.
            flex = -(6.0 + knee_flex * max(0.0, math.sin(leg - 0.6)) ** 1.4)
            pose_rotate(rig, f"Shin_{side}", rx=flex)
            heel = lift * max(0.0, math.sin(leg + math.pi * 0.55))
            pose_rotate(rig, f"Foot_{side}", rx=-0.45 * (thigh_swing * swing + flex) + heel)
            arm = leg + math.pi
            pose_rotate(rig, f"UpperArm_{side}", rx=arm_swing * math.sin(arm),
                        ry=-sign * 3.0)
            pose_rotate(rig, f"Forearm_{side}", rx=elbow + 0.35 * elbow * math.sin(arm))
            pose_rotate(rig, f"Hand_{side}", rx=6.0)
        return {"Hips", "Spine", "Chest", "Neck", "Head",
                "Thigh_R", "Thigh_L", "Shin_R", "Shin_L", "Foot_R", "Foot_L",
                "UpperArm_R", "UpperArm_L", "Forearm_R", "Forearm_L", "Hand_R", "Hand_L"}
    return poser


def die_pose(rig):
    def poser(t: float):
        # Buckle at the knees first, then topple onto the back.
        fall = _smoothstep(0.15, 0.95, t)
        buckle = _smoothstep(0.0, 0.45, t)
        settle = _smoothstep(0.75, 1.0, t)
        pose_offset(rig, "Hips", Vector((0.0, -0.10 * fall, -0.62 * fall - 0.06 * buckle)))
        pose_rotate(rig, "Hips", rx=-86.0 * fall)
        pose_rotate(rig, "Spine", rx=6.0 * buckle - 8.0 * settle)
        pose_rotate(rig, "Chest", rx=10.0 * buckle - 6.0 * settle)
        pose_rotate(rig, "Neck", rx=14.0 * buckle - 4.0 * settle)
        pose_rotate(rig, "Head", rx=18.0 * buckle + 8.0 * settle, rz=-10.0 * settle)
        for side, sign in (("R", 1.0), ("L", -1.0)):
            pose_rotate(rig, f"Thigh_{side}", rx=74.0 * fall + 10.0 * buckle, ry=-sign * 6.0 * fall)
            pose_rotate(rig, f"Shin_{side}", rx=-42.0 * buckle - 18.0 * settle)
            pose_rotate(rig, f"Foot_{side}", rx=18.0 * fall)
            pose_rotate(rig, f"UpperArm_{side}", rx=-28.0 * fall, ry=-sign * 34.0 * fall)
            pose_rotate(rig, f"Forearm_{side}", rx=26.0 * fall)
            pose_rotate(rig, f"Hand_{side}", rx=8.0)
        return {"Hips", "Spine", "Chest", "Neck", "Head",
                "Thigh_R", "Thigh_L", "Shin_R", "Shin_L", "Foot_R", "Foot_L",
                "UpperArm_R", "UpperArm_L", "Forearm_R", "Forearm_L", "Hand_R", "Hand_L"}
    return poser


def build_animations(rig: bpy.types.Object) -> list[bpy.types.Action]:
    specs = [
        ("Idle", 96, idle_pose(rig), True),
        ("Walk", 24, _gait(rig, thigh_swing=26.0, knee_flex=46.0, arm_swing=-19.0,
                           elbow=14.0, lean=4.0, bob=0.012, lift=16.0), True),
        ("Run", 16, _gait(rig, thigh_swing=42.0, knee_flex=78.0, arm_swing=-34.0,
                          elbow=52.0, lean=13.0, bob=0.026, lift=28.0), True),
        ("Die", 34, die_pose(rig), False),
    ]
    actions = [make_action(rig, name, frames, poser, loop) for name, frames, poser, loop in specs]

    # Actions on NLA tracks are what the glTF exporter reliably picks up.
    rig.animation_data.action = None
    for action in actions:
        track = rig.animation_data.nla_tracks.new()
        track.name = action.name
        strip = track.strips.new(action.name, 1, action)
        strip.name = action.name
        track.mute = True
    reset_pose(rig)
    return actions


def reset_pose(rig: bpy.types.Object) -> None:
    """Drop back to rest. Bones keep their last posed values once the action is
    unassigned, and glTF writes the live pose as each joint's default transform."""
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"
        pose_bone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pose_bone.location = (0.0, 0.0, 0.0)
        pose_bone.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()


# --------------------------------------------------------------------------- #
# Assembly
# --------------------------------------------------------------------------- #

def sharpen_edges(obj: bpy.types.Object, angle: float = 42.0) -> None:
    """Smooth shading everywhere except across real creases."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for face in bm.faces:
        face.smooth = True
    limit = math.radians(angle)
    for edge in bm.edges:
        edge.smooth = not (len(edge.link_faces) == 2 and edge.calc_face_angle() > limit)
    bm.to_mesh(obj.data)
    bm.free()


def join_parts(parts: list[tuple[bpy.types.Object, list[str]]]) -> bpy.types.Object:
    objects = [obj for obj, _ in parts]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    body = objects[0]
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = "Prisoner"
    body.data.name = "PrisonerBody"
    return body


def unwrap(obj: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.006)
    bpy.ops.object.mode_set(mode="OBJECT")


def bake_colour(obj: bpy.types.Object) -> bpy.types.Image:
    """Bake every part's procedural grime into one colour atlas for glTF."""
    image = bpy.data.images.new("PrisonerColour", BAKE_SIZE, BAKE_SIZE)
    image.generated_color = (0.5, 0.5, 0.5, 1.0)
    for slot in obj.material_slots:
        nt = slot.material.node_tree
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = image
        node.location = (-900, 500)
        nt.nodes.active = node

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 1
    scene.render.bake.use_pass_direct = False
    scene.render.bake.use_pass_indirect = False
    scene.render.bake.margin = 6

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, use_clear=True)

    TEX_OUT.parent.mkdir(parents=True, exist_ok=True)
    image.filepath_raw = str(TEX_OUT)
    image.file_format = "PNG"
    image.save()
    return image


def apply_baked_materials(obj: bpy.types.Object, image: bpy.types.Image | None) -> None:
    """Collapse the authoring materials down to one per surface group."""
    settings = {
        GROUP_FABRIC: ("PrisonerFabric", 0.92, "#6d747c"),
        GROUP_LEATHER: ("PrisonerLeather", 0.52, "#7a5f36"),
        GROUP_SKIN: ("PrisonerSkin", 0.68, "#c39a7c"),
    }
    order = [GROUP_FABRIC, GROUP_LEATHER, GROUP_SKIN]
    finals = {}
    for group, (name, roughness, fallback) in settings.items():
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = 0.0
        if image is not None:
            tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
            tex.image = image
            tex.location = (-400, 300)
            mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        else:
            bsdf.inputs["Base Color"].default_value = srgb(fallback)
        finals[group] = mat

    # One slot per group, so the export is three primitives instead of one per part.
    remap = [order.index(slot.material.get("surface_group", GROUP_FABRIC))
             for slot in obj.material_slots]
    for polygon in obj.data.polygons:
        polygon.material_index = remap[polygon.material_index]
    obj.data.materials.clear()
    for group in order:
        obj.data.materials.append(finals[group])


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


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    skip_bake = "--skip-bake" in argv

    clear_scene()
    parts = build_character()
    rig = build_armature()
    for obj, allowed in parts:
        add_wrinkles(obj)
        skin_part(obj, allowed)

    body = join_parts(parts)
    sharpen_edges(body)
    unwrap(body)
    image = None if skip_bake else bake_colour(body)
    apply_baked_materials(body, image)

    body.parent = rig
    modifier = body.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig

    build_animations(rig)

    triangles = sum(len(polygon.vertices) - 2 for polygon in body.data.polygons)
    print(f"Prisoner: {len(body.data.vertices)} verts, {triangles} tris, "
          f"{len(body.material_slots)} materials, {len(bpy.data.actions)} actions")

    BLEND_OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
    export(rig, body)


if __name__ == "__main__":
    main()
