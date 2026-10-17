"""
Build tileable room modules for Nuclear Winter's procedural maps:
bedroom, living room, office, storage, up/down stairwells, a boiler
room (steam valve) and a pipe gallery.

Every room shares one square footprint with a doorway centred on each of the
four walls, so the Godot map generator can butt any two rooms together on a
grid. Each doorway ships with a `Plug_<side>` filler block: the generator
deletes the plug where two rooms meet and keeps it where a room faces the
outside, which seals the map edge without needing per-room wall variants.

Naming contract consumed by godot/scripts/MapGenerator.gd:
  Floor              - room floor slab
  Wall_<side>_A/_B   - wall runs either side of the doorway
  Wall_<side>_L      - lintel above the doorway
  Plug_<side>        - removable doorway filler (side is N/S/E/W in Godot space)
  NoCol_*            - decoration the generator must not build a collider for

Blender +Y maps to Godot -Z on glTF export, so the +Y wall is named `N` to
match the generator's north.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy

OUT_DIR = Path("/workspace/godot/assets/rooms")
BLEND_OUT = Path("/workspace/blender/procedural_rooms.blend")
PNG_OUT = Path("/opt/cursor/artifacts/blender_procedural_rooms.png")
PNG_STEAM = Path("/opt/cursor/artifacts/blender_steam_rooms.png")

TILE = 12.0  # grid pitch; must match MapGenerator.TILE
HALF = TILE * 0.5
WALL_H = 2.4
WALL_T = 0.28
DOOR_W = 2.6
DOOR_H = 2.1
SIDES = ("N", "S", "E", "W")

# Keeping props out of the middle cross of the tile leaves every doorway
# reachable no matter which neighbours the generator attaches.
CLEAR = DOOR_W * 0.5 + 0.6


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for material in list(bpy.data.materials):
        bpy.data.materials.remove(material)
    for light in list(bpy.data.lights):
        bpy.data.lights.remove(light)
    for camera in list(bpy.data.cameras):
        bpy.data.cameras.remove(camera)


def srgb_to_linear(channel: float) -> float:
    if channel <= 0.04045:
        return channel / 12.92
    return ((channel + 0.055) / 1.055) ** 2.4


def mat(name: str, color: tuple[float, float, float], roughness: float = 0.7):
    """`color` is sRGB — the space the palette is picked in. Blender base colours
    and glTF baseColorFactor are linear, so skipping this conversion makes
    everything read about twice as bright as intended once Godot lights it."""
    material = bpy.data.materials.new(name=name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    linear = tuple(srgb_to_linear(channel) for channel in color)
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*linear, 1.0)
        bsdf.inputs["Roughness"].default_value = roughness
    return material


def emissive(name: str, color: tuple[float, float, float], strength: float = 2.0):
    material = mat(name, color, 0.4)
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    linear = tuple(srgb_to_linear(channel) for channel in color)
    if bsdf:
        bsdf.inputs["Emission Color"].default_value = (*linear, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    return material


def cube(name: str, loc, size, material, parent=None, yaw: float = 0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if yaw:
        obj.rotation_euler[2] = math.radians(yaw)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    obj.data.materials.append(material)
    if parent is not None:
        obj.parent = parent
    return obj


def cylinder(name: str, loc, radius: float, depth: float, material, parent=None, verts: int = 12):
    return cylinder_along(name, loc, radius, depth, material, parent, axis="Z", verts=verts)


def cylinder_along(
    name: str,
    loc,
    radius: float,
    depth: float,
    material,
    parent=None,
    axis: str = "Z",
    verts: int = 12,
):
    """Cylinder whose axis is X, Y or Z in Blender space. Axis Z stays vertical in Godot."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    if axis == "X":
        obj.rotation_euler = (0.0, math.radians(90.0), 0.0)
    elif axis == "Y":
        obj.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    if axis != "Z":
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    obj.data.materials.append(material)
    if parent is not None:
        obj.parent = parent
    return obj


def attach(obj, parent) -> None:
    """Parent `obj` without sliding it. Props parented to the origin empty can
    skip this; a wheel is not at the origin, so a bare `.parent =` would treat
    world coordinates as local and throw the mesh across the room."""
    obj.parent = parent
    obj.matrix_parent_inverse = parent.matrix_world.inverted()


def pipe_seg(name: str, start, end, radius: float, material, parent, collide: bool = False):
    """Axis-aligned pipe. Thin runs are decoration so they never fill a doorway."""
    loc = tuple((start[i] + end[i]) * 0.5 for i in range(3))
    size = tuple(max(abs(end[i] - start[i]), radius * 2.0) for i in range(3))
    full = name if collide else f"NoCol_{name}"
    return cube(full, loc, size, material, parent)


def make_root(name: str):
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 0, 0))
    root = bpy.context.active_object
    root.name = name
    return root


# --------------------------------------------------------------------------- #
# Shared room shell
# --------------------------------------------------------------------------- #


def build_wall(root, side: str, wall_mat, plug_mat) -> None:
    """Two wall runs, a lintel, and a removable plug for one side of the tile."""
    # N/S walls span the whole tile; E/W walls stop short so no two boxes end
    # on the same plane at the corners (which would z-fight).
    span = HALF if side in ("N", "S") else HALF - WALL_T
    run = span - DOOR_W * 0.5
    offset = (span + DOOR_W * 0.5) * 0.5
    lintel_h = WALL_H - DOOR_H
    sign = 1.0 if side in ("N", "E") else -1.0
    face = (HALF - WALL_T * 0.5) * sign

    if side in ("N", "S"):
        cube(f"Wall_{side}_A", (-offset, face, WALL_H * 0.5), (run, WALL_T, WALL_H), wall_mat, root)
        cube(f"Wall_{side}_B", (offset, face, WALL_H * 0.5), (run, WALL_T, WALL_H), wall_mat, root)
        cube(
            f"Wall_{side}_L",
            (0.0, face, DOOR_H + lintel_h * 0.5),
            (DOOR_W, WALL_T, lintel_h),
            wall_mat,
            root,
        )
        cube(f"Plug_{side}", (0.0, face, DOOR_H * 0.5), (DOOR_W, WALL_T, DOOR_H), plug_mat, root)
    else:
        cube(f"Wall_{side}_A", (face, -offset, WALL_H * 0.5), (WALL_T, run, WALL_H), wall_mat, root)
        cube(f"Wall_{side}_B", (face, offset, WALL_H * 0.5), (WALL_T, run, WALL_H), wall_mat, root)
        cube(
            f"Wall_{side}_L",
            (face, 0.0, DOOR_H + lintel_h * 0.5),
            (WALL_T, DOOR_W, lintel_h),
            wall_mat,
            root,
        )
        cube(f"Plug_{side}", (face, 0.0, DOOR_H * 0.5), (WALL_T, DOOR_W, DOOR_H), plug_mat, root)


def build_shell(name: str, floor_mat, wall_mat, plug_mat):
    root = make_root(name)
    cube("Floor", (0, 0, -0.05), (TILE, TILE, 0.1), floor_mat, root)
    for side in SIDES:
        build_wall(root, side, wall_mat, plug_mat)
    return root


def add_wall_grime(root, grime_mat, patches) -> None:
    """Flat decals floated just off the plaster to suggest damp and fallout burn."""
    inset = HALF - WALL_T - 0.02
    for index, (side, along, height, width, tall) in enumerate(patches):
        if side in ("N", "S"):
            y = inset if side == "N" else -inset
            size = (width, 0.02, tall)
            loc = (along, y, height)
        else:
            x = inset if side == "E" else -inset
            size = (0.02, width, tall)
            loc = (x, along, height)
        cube(f"NoCol_Grime_{index}", loc, size, grime_mat, root)


def add_floor_debris(root, debris_mat, spots) -> None:
    """Flat rubble decals. The middle cross of the tile has to stay clear of
    props so every doorway is reachable, so it gets dressed rather than filled."""
    for index, (x, y, width, depth) in enumerate(spots):
        cube(f"NoCol_Debris_{index}", (x, y, 0.012), (width, depth, 0.02), debris_mat, root)


def add_empty(name: str, loc, parent) -> None:
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.empty_display_size = 0.35
    if parent is not None:
        obj.parent = parent


def add_ceiling_lamp(root, shade_mat, bulb_mat, loc=(0.0, 0.0)) -> None:
    x, y = loc
    cube("NoCol_LampRod", (x, y, 2.28), (0.05, 0.05, 0.24), shade_mat, root)
    cylinder("NoCol_LampShade", (x, y, 2.12), 0.34, 0.14, shade_mat, root, verts=12)
    cylinder("NoCol_LampBulb", (x, y, 2.02), 0.13, 0.14, bulb_mat, root, verts=10)


# --------------------------------------------------------------------------- #
# Bedroom
# --------------------------------------------------------------------------- #


def build_bedroom():
    parquet = mat("BedroomFloor", (0.33, 0.24, 0.17), 0.8)
    plaster = mat("BedroomWall", (0.38, 0.44, 0.40), 0.85)
    grime = mat("BedroomGrime", (0.23, 0.26, 0.23), 0.95)
    iron = mat("BedIron", (0.30, 0.31, 0.33), 0.45)
    linen = mat("BedLinen", (0.62, 0.59, 0.51), 0.9)
    blanket = mat("BedBlanket", (0.45, 0.17, 0.15), 0.9)
    wood = mat("BedroomWood", (0.32, 0.22, 0.14), 0.7)
    brass = mat("BedroomBrass", (0.50, 0.40, 0.18), 0.4)
    debris = mat("BedroomDebris", (0.24, 0.19, 0.14), 0.95)
    bulb = emissive("BedroomBulb", (1.0, 0.88, 0.62), 1.6)

    root = build_shell("Bedroom", parquet, plaster, plaster)
    add_wall_grime(
        root,
        grime,
        [
            ("N", 3.6, 1.7, 1.6, 1.1),
            ("W", -3.4, 0.9, 2.2, 1.4),
            ("E", 2.0, 1.9, 1.3, 0.7),
        ],
    )

    # Iron bed along the west wall, head to the north.
    bed_x, bed_y = -4.5, 2.9
    cube("BedFrame", (bed_x, bed_y, 0.32), (1.34, 2.16, 0.22), iron, root)
    cube("BedMattress", (bed_x, bed_y - 0.05, 0.48), (1.24, 2.0, 0.16), linen, root)
    cube("BedBlanket", (bed_x, bed_y - 0.5, 0.58), (1.26, 1.1, 0.1), blanket, root)
    cube("BedPillow", (bed_x, bed_y + 0.76, 0.6), (1.0, 0.46, 0.14), linen, root)
    cube("BedHeadboard", (bed_x, bed_y + 1.1, 0.72), (1.34, 0.08, 1.0), iron, root)
    cube("BedFootboard", (bed_x, bed_y - 1.1, 0.5), (1.34, 0.08, 0.56), iron, root)
    for index, dx in enumerate((-0.44, 0.0, 0.44)):
        cube(f"BedBar_{index}", (bed_x + dx, bed_y + 1.1, 0.95), (0.06, 0.1, 0.5), iron, root)
    for index, (dx, dy) in enumerate(((-0.6, -1.0), (0.6, -1.0), (-0.6, 1.0), (0.6, 1.0))):
        cube(f"BedLeg_{index}", (bed_x + dx, bed_y + dy, 0.11), (0.1, 0.1, 0.22), iron, root)

    # Nightstand with a stub of candle.
    cube("Nightstand", (-4.9, 1.3, 0.32), (0.64, 0.6, 0.64), wood, root)
    cylinder("NoCol_Candle", (-4.9, 1.3, 0.74), 0.05, 0.2, linen, root, verts=8)
    cylinder("NoCol_CandleFlame", (-4.9, 1.3, 0.87), 0.04, 0.08, bulb, root, verts=8)

    # Wardrobe against the north wall, east of the doorway.
    cube("Wardrobe", (3.5, 5.2, 1.05), (1.3, 0.6, 2.1), wood, root)
    cube("WardrobeDoorL", (3.17, 4.88, 1.02), (0.58, 0.05, 1.86), plaster, root)
    cube("WardrobeDoorR", (3.83, 4.88, 1.02), (0.58, 0.05, 1.86), plaster, root)
    cube("NoCol_WardrobeHandleL", (3.42, 4.83, 1.02), (0.05, 0.06, 0.16), brass, root)
    cube("NoCol_WardrobeHandleR", (3.58, 4.83, 1.02), (0.05, 0.06, 0.16), brass, root)

    # Chest of drawers in the south-east corner.
    cube("Dresser", (4.6, -3.6, 0.45), (1.0, 1.8, 0.9), wood, root)
    for index, dy in enumerate((-0.55, 0.0, 0.55)):
        cube(f"NoCol_DresserDrawer_{index}", (4.08, -3.6 + dy, 0.45), (0.05, 0.5, 0.24), brass, root)

    # Rug and a toppled stool in the south-west quarter.
    cube("NoCol_Rug", (-3.4, -3.4, 0.01), (3.4, 2.8, 0.03), blanket, root)
    cube("Stool", (-2.2, -4.9, 0.42), (0.5, 0.5, 0.1), wood, root)
    for index, (dx, dy) in enumerate(((-0.18, -0.18), (0.18, -0.18), (-0.18, 0.18), (0.18, 0.18))):
        cube(f"StoolLeg_{index}", (-2.2 + dx, -4.9 + dy, 0.19), (0.07, 0.07, 0.38), wood, root)

    add_floor_debris(
        root,
        debris,
        [(-1.0, 0.7, 1.9, 1.2), (1.5, -1.3, 1.1, 0.8), (0.4, 2.5, 1.4, 0.9)],
    )

    # Wall radio: state broadcasts never stopped.
    cube("NoCol_Radio", (5.5, 2.2, 1.62), (0.16, 0.7, 0.44), wood, root)
    cube("NoCol_RadioGrille", (5.39, 2.2, 1.62), (0.03, 0.5, 0.3), iron, root)

    add_ceiling_lamp(root, iron, bulb)
    return root


# --------------------------------------------------------------------------- #
# Living room
# --------------------------------------------------------------------------- #


def build_living_room():
    boards = mat("LivingFloor", (0.36, 0.27, 0.18), 0.8)
    plaster = mat("LivingWall", (0.48, 0.40, 0.25), 0.85)
    grime = mat("LivingGrime", (0.28, 0.23, 0.15), 0.95)
    fabric = mat("CouchFabric", (0.31, 0.34, 0.37), 0.9)
    cushion = mat("CouchCushion", (0.40, 0.35, 0.29), 0.9)
    wood = mat("LivingWood", (0.32, 0.22, 0.13), 0.7)
    steel = mat("LivingSteel", (0.33, 0.34, 0.36), 0.4)
    brass = mat("LivingBrass", (0.50, 0.40, 0.18), 0.4)
    red = mat("LivingRed", (0.46, 0.14, 0.13), 0.8)
    screen = emissive("TvScreen", (0.36, 0.66, 0.46), 1.0)
    bulb = emissive("LivingBulb", (1.0, 0.86, 0.58), 1.6)
    debris = mat("LivingDebris", (0.26, 0.20, 0.14), 0.95)

    root = build_shell("LivingRoom", boards, plaster, plaster)
    add_wall_grime(
        root,
        grime,
        [
            ("S", -3.8, 1.5, 2.0, 1.3),
            ("E", -2.6, 1.0, 2.4, 1.5),
            ("N", 2.4, 1.8, 1.2, 0.8),
        ],
    )

    # Couch, table and television arranged across the northern half.
    couch_x, couch_y = -5.0, 3.0
    cube("CouchBase", (couch_x, couch_y, 0.28), (0.92, 2.2, 0.36), fabric, root)
    cube("CouchCushionN", (couch_x + 0.06, couch_y + 0.52, 0.5), (0.8, 0.98, 0.16), cushion, root)
    cube("CouchCushionS", (couch_x + 0.06, couch_y - 0.52, 0.5), (0.8, 0.98, 0.16), cushion, root)
    cube("CouchBack", (couch_x - 0.34, couch_y, 0.84), (0.22, 2.2, 0.92), fabric, root)
    cube("CouchArmN", (couch_x, couch_y + 1.16, 0.56), (0.92, 0.2, 0.72), fabric, root)
    cube("CouchArmS", (couch_x, couch_y - 1.16, 0.56), (0.92, 0.2, 0.72), fabric, root)
    cube("NoCol_CouchPillow", (couch_x + 0.02, couch_y + 0.7, 0.72), (0.2, 0.42, 0.42), red, root)

    cube("CoffeeTable", (-3.4, 3.0, 0.42), (0.9, 1.6, 0.08), wood, root)
    for index, (dx, dy) in enumerate(((-0.35, -0.65), (0.35, -0.65), (-0.35, 0.65), (0.35, 0.65))):
        cube(f"TableLeg_{index}", (-3.4 + dx, 3.0 + dy, 0.2), (0.08, 0.08, 0.4), wood, root)
    # Samovar: the one appliance nobody left behind.
    cylinder("Samovar", (-3.4, 3.3, 0.62), 0.22, 0.34, brass, root, verts=12)
    cylinder("NoCol_SamovarNeck", (-3.4, 3.3, 0.84), 0.09, 0.14, brass, root, verts=8)
    cube("NoCol_SamovarTap", (-3.2, 3.3, 0.58), (0.16, 0.05, 0.05), brass, root)

    cube("TvStand", (-1.9, 3.0, 0.3), (0.7, 1.3, 0.6), wood, root)
    cube("TvBody", (-1.9, 3.0, 0.95), (0.66, 1.1, 0.72), steel, root)
    cube("NoCol_TvScreen", (-2.25, 3.0, 0.98), (0.04, 0.86, 0.52), screen, root)
    cube("NoCol_TvAntennaA", (-1.75, 2.8, 1.55), (0.03, 0.5, 0.03), steel, root, yaw=0.0)
    cube("NoCol_TvAntennaB", (-1.75, 3.2, 1.55), (0.03, 0.5, 0.03), steel, root, yaw=0.0)

    # Bookshelf on the north wall and a reading corner to the south-east.
    cube("Bookshelf", (3.6, 5.3, 1.0), (1.9, 0.42, 2.0), wood, root)
    for index, z in enumerate((0.45, 0.95, 1.45, 1.85)):
        cube(f"NoCol_Books_{index}", (3.6, 5.22, z), (1.7, 0.3, 0.26), red if index % 2 else cushion, root)

    cube("Armchair", (4.2, -3.0, 0.3), (1.0, 1.0, 0.36), fabric, root)
    cube("ArmchairBack", (4.66, -3.0, 0.78), (0.2, 1.0, 0.8), fabric, root)
    cube("ArmchairSeat", (4.16, -3.0, 0.52), (0.86, 0.86, 0.14), cushion, root)
    cube("SideTable", (3.0, -4.4, 0.35), (0.6, 0.6, 0.7), wood, root)
    cube("NoCol_Rug", (-3.2, -3.4, 0.01), (3.6, 3.0, 0.03), red, root)

    cylinder("FloorLampPole", (1.9, -5.0, 0.75), 0.05, 1.5, steel, root, verts=8)
    cylinder("NoCol_FloorLampShade", (1.9, -5.0, 1.6), 0.28, 0.3, cushion, root, verts=10)

    add_floor_debris(
        root,
        debris,
        [(0.9, 0.4, 2.1, 1.3), (-1.3, -1.5, 1.2, 0.9), (1.7, 1.9, 0.9, 0.7)],
    )

    # Framed portrait of a leader whose ministry no longer exists.
    cube("NoCol_PortraitFrame", (5.52, -0.2, 1.75), (0.08, 1.0, 1.3), wood, root)
    cube("NoCol_PortraitCanvas", (5.45, -0.2, 1.75), (0.03, 0.84, 1.14), grime, root)
    cube("NoCol_PortraitStar", (5.41, -0.2, 1.75), (0.03, 0.34, 0.34), red, root, yaw=0.0)

    add_ceiling_lamp(root, steel, bulb)
    return root


# --------------------------------------------------------------------------- #
# Office
# --------------------------------------------------------------------------- #


def build_office():
    lino = mat("OfficeFloor", (0.27, 0.29, 0.27), 0.8)
    plaster = mat("OfficeWall", (0.32, 0.38, 0.33), 0.85)
    grime = mat("OfficeGrime", (0.21, 0.25, 0.22), 0.95)
    wood = mat("OfficeWood", (0.32, 0.22, 0.13), 0.7)
    steel = mat("OfficeSteel", (0.34, 0.35, 0.37), 0.4)
    olive = mat("OfficeOlive", (0.29, 0.32, 0.24), 0.7)
    paper = mat("OfficePaper", (0.66, 0.63, 0.53), 0.9)
    red = mat("OfficeRed", (0.47, 0.14, 0.13), 0.8)
    bulb = emissive("OfficeBulb", (0.94, 0.96, 0.82), 1.8)
    debris = mat("OfficeDebris", (0.20, 0.21, 0.19), 0.95)

    root = build_shell("Office", lino, plaster, plaster)
    add_wall_grime(
        root,
        grime,
        [
            ("W", 2.6, 1.4, 2.2, 1.6),
            ("S", 3.2, 1.2, 1.6, 1.0),
            ("N", -3.0, 1.9, 1.8, 0.7),
        ],
    )

    # Desk in the north-east quarter, facing south into the room.
    desk_x, desk_y = 3.6, 3.4
    cube("Desk", (desk_x, desk_y, 0.72), (2.1, 1.0, 0.08), wood, root)
    cube("DeskPanel", (desk_x, desk_y + 0.44, 0.36), (2.1, 0.08, 0.68), wood, root)
    for index, dx in enumerate((-0.95, 0.95)):
        cube(f"DeskPedestal_{index}", (desk_x + dx, desk_y, 0.34), (0.14, 0.96, 0.68), wood, root)
    cube("Typewriter", (desk_x - 0.4, desk_y + 0.05, 0.86), (0.5, 0.42, 0.2), steel, root)
    cube("NoCol_TypewriterPaper", (desk_x - 0.4, desk_y + 0.05, 1.02), (0.3, 0.02, 0.26), paper, root)
    cube("NoCol_DeskPapers", (desk_x + 0.55, desk_y - 0.1, 0.79), (0.6, 0.44, 0.06), paper, root)
    cylinder("DeskLampPole", (desk_x + 0.9, desk_y + 0.3, 0.9), 0.03, 0.28, steel, root, verts=8)
    cube("NoCol_DeskLampHood", (desk_x + 0.9, desk_y + 0.18, 1.06), (0.22, 0.3, 0.12), olive, root)
    cylinder("NoCol_DeskLampBulb", (desk_x + 0.9, desk_y + 0.18, 0.99), 0.06, 0.06, bulb, root, verts=8)

    cube("DeskChairSeat", (desk_x, desk_y - 1.15, 0.46), (0.56, 0.56, 0.1), olive, root)
    cube("DeskChairBack", (desk_x, desk_y - 1.4, 0.78), (0.56, 0.1, 0.56), olive, root)
    cylinder("DeskChairPost", (desk_x, desk_y - 1.15, 0.2), 0.06, 0.4, steel, root, verts=8)
    cylinder("DeskChairBase", (desk_x, desk_y - 1.15, 0.03), 0.3, 0.06, steel, root, verts=10)

    # Filing cabinets against the north wall, west of the doorway.
    for index, x in enumerate((-4.9, -3.7, -2.5)):
        cube(f"FileCabinet_{index}", (x, 5.28, 0.68), (1.06, 0.5, 1.36), steel, root)
        for drawer, z in enumerate((0.28, 0.68, 1.08)):
            cube(
                f"NoCol_FileHandle_{index}_{drawer}",
                (x, 5.0, z),
                (0.3, 0.06, 0.05),
                olive,
                root,
            )

    # Binder shelf on the west wall.
    cube("BinderShelf", (-5.28, -2.8, 0.95), (0.44, 2.6, 1.9), steel, root)
    for index, z in enumerate((0.4, 0.9, 1.4, 1.8)):
        cube(f"NoCol_Binders_{index}", (-5.2, -2.8, z), (0.32, 2.4, 0.26), red if index % 2 else paper, root)

    # Situation map and a plaque nobody dusts any more.
    cube("NoCol_MapBoard", (5.5, -2.6, 1.6), (0.1, 2.4, 1.5), wood, root)
    cube("NoCol_MapPaper", (5.42, -2.6, 1.6), (0.03, 2.2, 1.32), paper, root)
    cube("NoCol_MapPin", (5.38, -2.0, 1.8), (0.03, 0.12, 0.12), red, root)
    cube("NoCol_Plaque", (2.6, 5.68, 1.9), (0.5, 0.04, 0.5), red, root)

    # Files that went everywhere when the evacuation order came through.
    add_floor_debris(
        root,
        debris,
        [(-0.7, 0.9, 1.7, 1.1), (1.3, -1.7, 1.4, 1.0), (-1.7, -0.5, 0.9, 0.8)],
    )
    cube("NoCol_LooseForms_A", (0.9, 1.4, 0.02), (0.5, 0.36, 0.02), paper, root)
    cube("NoCol_LooseForms_B", (-1.4, -1.9, 0.02), (0.42, 0.3, 0.02), paper, root)

    # Requisition forms that outlived the ministry.
    cube("PaperStack", (-3.6, -3.4, 0.3), (1.2, 1.2, 0.6), paper, root)
    cube("PaperStackTop", (-3.5, -3.3, 0.68), (0.9, 0.9, 0.18), paper, root)
    cube("WasteBin", (1.9, -4.9, 0.24), (0.42, 0.42, 0.48), steel, root)
    cube("NoCol_BinPaper", (1.9, -4.9, 0.52), (0.34, 0.34, 0.12), paper, root)

    add_ceiling_lamp(root, steel, bulb)
    return root


# --------------------------------------------------------------------------- #
# Storage room
# --------------------------------------------------------------------------- #


def build_storage():
    concrete = mat("StorageFloor", (0.30, 0.30, 0.28), 0.9)
    plaster = mat("StorageWall", (0.35, 0.34, 0.32), 0.9)
    grime = mat("StorageGrime", (0.22, 0.21, 0.18), 0.95)
    steel = mat("StorageSteel", (0.34, 0.35, 0.37), 0.4)
    rust = mat("StorageRust", (0.42, 0.24, 0.14), 0.85)
    wood = mat("StorageWood", (0.40, 0.29, 0.17), 0.75)
    sack = mat("StorageSack", (0.46, 0.41, 0.30), 0.9)
    olive = mat("StorageOlive", (0.29, 0.32, 0.24), 0.7)
    hazard = mat("StorageHazard", (0.58, 0.49, 0.13), 0.7)
    bulb = emissive("StorageBulb", (0.96, 0.93, 0.76), 1.5)
    debris = mat("StorageDebris", (0.21, 0.20, 0.18), 0.95)

    root = build_shell("Storage", concrete, plaster, plaster)
    add_wall_grime(
        root,
        grime,
        [
            ("S", -2.4, 1.1, 2.6, 1.8),
            ("N", 4.0, 1.5, 1.6, 1.2),
            ("W", 3.4, 0.8, 1.8, 1.2),
        ],
    )

    # Shelving racks flanking the north half.
    for rack_index, rack_x in enumerate((-5.1, 5.1)):
        cube(f"RackBack_{rack_index}", (rack_x, 3.2, 1.05), (0.12, 3.4, 2.1), steel, root)
        for post_index, dy in enumerate((-1.6, 1.6)):
            cube(
                f"RackPost_{rack_index}_{post_index}",
                (rack_x + (0.34 if rack_x < 0 else -0.34), 3.2 + dy, 1.05),
                (0.1, 0.1, 2.1),
                steel,
                root,
            )
        for shelf_index, z in enumerate((0.4, 0.95, 1.5, 2.0)):
            cube(
                f"RackShelf_{rack_index}_{shelf_index}",
                (rack_x + (0.24 if rack_x < 0 else -0.24), 3.2, z),
                (0.62, 3.3, 0.06),
                steel,
                root,
            )
        for box_index, (dy, box_z) in enumerate(((-1.0, 0.62), (0.3, 0.62), (1.1, 1.17), (-0.6, 1.72))):
            cube(
                f"RackBox_{rack_index}_{box_index}",
                (rack_x + (0.24 if rack_x < 0 else -0.24), 3.2 + dy, box_z),
                (0.5, 0.7, 0.38),
                wood if box_index % 2 else olive,
                root,
            )

    # Crate stack in the south-west corner.
    crate_positions = ((-4.4, -3.0, 0.45), (-3.3, -3.4, 0.45), (-4.4, -3.0, 1.35), (-4.0, -4.6, 0.45))
    for index, (x, y, z) in enumerate(crate_positions):
        cube(f"Crate_{index}", (x, y, z), (0.9, 0.9, 0.9), wood, root)
        cube(f"NoCol_CrateStrapA_{index}", (x, y, z + 0.3), (0.94, 0.94, 0.06), steel, root)
        cube(f"NoCol_CrateStrapB_{index}", (x, y, z - 0.3), (0.94, 0.94, 0.06), steel, root)

    # Fuel drums in the south-east corner.
    for index, (x, y) in enumerate(((3.4, -3.2), (4.5, -3.6), (3.9, -4.7))):
        cylinder(f"Drum_{index}", (x, y, 0.44), 0.42, 0.88, rust, root, verts=14)
        cylinder(f"NoCol_DrumRib_{index}", (x, y, 0.62), 0.44, 0.06, steel, root, verts=14)
        cylinder(f"NoCol_DrumLid_{index}", (x, y, 0.88), 0.42, 0.04, hazard, root, verts=14)

    # Grain sacks and jerry cans along the south wall.
    for index, (x, y) in enumerate(((-1.9, -5.1), (-1.0, -5.3))):
        cylinder(f"Sack_{index}", (x, y, 0.3), 0.36, 0.6, sack, root, verts=10)
    for index, x in enumerate((2.0, 2.5)):
        cube(f"JerryCan_{index}", (x, -5.3, 0.24), (0.3, 0.18, 0.48), olive, root)
        cube(f"NoCol_JerryHandle_{index}", (x, -5.3, 0.5), (0.2, 0.05, 0.05), steel, root)

    add_floor_debris(
        root,
        debris,
        [(0.7, 0.3, 2.3, 1.4), (-1.5, 1.5, 1.2, 0.9), (1.5, -1.9, 1.0, 0.8)],
    )
    cube("NoCol_SpilledGrain", (-1.2, -2.1, 0.02), (0.9, 0.7, 0.02), sack, root)

    # Service pipes bolted along the north wall.
    for index, z in enumerate((1.95, 2.15)):
        cube(f"NoCol_Pipe_{index}", (0.0, 5.55, z), (11.2, 0.16, 0.16), rust if index else steel, root)
    for index, x in enumerate((-4.0, 0.0, 4.0)):
        cube(f"NoCol_PipeBracket_{index}", (x, 5.66, 2.05), (0.26, 0.1, 0.44), steel, root)

    add_ceiling_lamp(root, steel, bulb)
    return root


# --------------------------------------------------------------------------- #
# Stairwells
# --------------------------------------------------------------------------- #


def _stair_materials():
    return {
        "floor": mat("StairFloor", (0.28, 0.28, 0.26), 0.9),
        "wall": mat("StairWall", (0.30, 0.34, 0.31), 0.85),
        "grime": mat("StairGrime", (0.20, 0.22, 0.19), 0.95),
        "steel": mat("StairSteel", (0.34, 0.35, 0.37), 0.4),
        "rust": mat("StairRust", (0.42, 0.24, 0.14), 0.85),
        "wood": mat("StairWood", (0.34, 0.24, 0.15), 0.75),
        "olive": mat("StairOlive", (0.29, 0.32, 0.24), 0.7),
        "hazard": mat("StairHazard", (0.58, 0.49, 0.13), 0.7),
        "rail": mat("StairRail", (0.22, 0.23, 0.24), 0.35),
        "sign": mat("StairSign", (0.47, 0.14, 0.13), 0.7),
        "bulb": emissive("StairBulb", (0.96, 0.90, 0.70), 1.6),
        "glow": emissive("StairGlow", (0.55, 0.82, 0.45), 2.2),
        "debris": mat("StairDebris", (0.21, 0.20, 0.18), 0.95),
    }


def _add_stair_flight(root, mats, start_z: float, rise: float, run: float, steps: int, x: float, y0: float) -> None:
    """Axis-aligned stair run along +Y, kept off the doorway cross."""
    for index in range(steps):
        z = start_z + rise * (index + 0.5)
        y = y0 + run * (index + 0.5)
        cube(
            f"StairTread_{index}",
            (x, y, z),
            (1.7, run - 0.02, rise),
            mats["wood"] if index % 2 == 0 else mats["olive"],
            root,
        )
        cube(
            f"NoCol_StairNose_{index}",
            (x, y + run * 0.42, z + rise * 0.42),
            (1.66, 0.04, 0.04),
            mats["steel"],
            root,
        )
    rail_top = start_z + rise * steps + 0.9
    rail_len = run * steps
    rail_y = y0 + rail_len * 0.5
    for side, dx in (("L", -0.92), ("R", 0.92)):
        cube(f"StairRail_{side}", (x + dx, rail_y, rail_top), (0.06, rail_len, 0.06), mats["rail"], root)
        for post in range(0, steps + 1, 2):
            pz = start_z + rise * post + 0.55
            py = y0 + run * post
            cube(f"StairPost_{side}_{post}", (x + dx, py, pz), (0.06, 0.06, 1.1), mats["steel"], root)


def build_stairwell_up():
    mats = _stair_materials()
    root = build_shell("StairwellUp", mats["floor"], mats["wall"], mats["wall"])
    add_wall_grime(
        root,
        mats["grime"],
        [
            ("N", -3.8, 1.6, 1.6, 1.0),
            ("S", 3.0, 1.1, 1.8, 1.4),
            ("E", -2.4, 1.8, 1.6, 0.8),
        ],
    )

    # Northwest corner, north of the west doorway so the tile cross stays clear.
    _add_stair_flight(root, mats, start_z=0.0, rise=0.22, run=0.32, steps=8, x=-4.35, y0=1.7)
    cube("Landing", (-4.35, 4.66, 1.87), (1.9, 1.2, 0.12), mats["olive"], root)
    cube("LandingBack", (-4.35, 5.22, 2.15), (1.9, 0.12, 0.7), mats["steel"], root)
    cube("NoCol_HatchFrame", (-4.35, 4.66, 2.34), (1.5, 0.9, 0.08), mats["steel"], root)
    cube("NoCol_HatchGlow", (-4.35, 4.66, 2.28), (1.2, 0.7, 0.04), mats["glow"], root)
    cube("NoCol_UpSign", (-5.52, 3.4, 1.7), (0.04, 0.7, 0.5), mats["sign"], root)
    cube("NoCol_UpArrow", (-5.48, 3.4, 1.78), (0.03, 0.18, 0.28), mats["hazard"], root)

    cube("StairNewel", (-5.2, 1.7, 0.55), (0.16, 0.16, 1.1), mats["rail"], root)
    cube("CoatHookRail", (5.2, -3.4, 1.3), (0.08, 1.8, 0.08), mats["steel"], root)
    for index, y in enumerate((-4.1, -3.4, -2.7)):
        cube(f"NoCol_CoatHook_{index}", (5.05, y, 1.3), (0.16, 0.04, 0.04), mats["rust"], root)

    cube("Bench", (3.8, -4.6, 0.28), (1.8, 0.55, 0.5), mats["wood"], root)
    cube("FireBucket", (4.8, -3.6, 0.28), (0.36, 0.36, 0.5), mats["sign"], root)
    cube("Extinguisher", (5.2, 4.6, 0.7), (0.18, 0.18, 0.7), mats["sign"], root)
    cube("NoCol_ExtinguisherCap", (5.2, 4.6, 1.1), (0.14, 0.14, 0.12), mats["steel"], root)

    for index, z in enumerate((1.9, 2.12)):
        cube(f"NoCol_StairPipe_{index}", (1.4, 5.55, z), (6.8, 0.14, 0.14), mats["rust"] if index else mats["steel"], root)

    add_floor_debris(
        root,
        mats["debris"],
        [(1.2, 0.2, 1.8, 1.1), (0.4, -2.2, 1.2, 0.8), (2.4, 2.0, 1.0, 0.7)],
    )
    add_ceiling_lamp(root, mats["steel"], mats["bulb"], loc=(1.6, -1.2))
    add_empty("StairUse", (-4.35, 4.55, 2.1), root)
    return root


def build_stairwell_down():
    mats = _stair_materials()
    root = make_root("StairwellDown")
    # Ring floor with a northwest well. Named Floor keeps the module contract.
    cube("Floor", (1.15, -0.7, -0.05), (9.7, 10.6, 0.1), mats["floor"], root)
    cube("Floor_NW", (-4.35, -2.15, -0.05), (3.3, 7.7, 0.1), mats["floor"], root)
    cube("Floor_NStrip", (-4.35, 5.45, -0.05), (3.3, 1.1, 0.1), mats["floor"], root)
    for side in SIDES:
        build_wall(root, side, mats["wall"], mats["wall"])

    add_wall_grime(
        root,
        mats["grime"],
        [
            ("W", 3.6, 1.5, 1.6, 1.2),
            ("E", 2.2, 1.2, 1.8, 1.1),
            ("S", -3.0, 1.8, 1.4, 0.8),
        ],
    )

    # Well occupies x=-5.2..-2.0, y=1.75..4.85, north of the west doorway.
    cube("WellWall_N", (-3.6, 4.93, -0.9), (3.2, 0.16, 1.8), mats["steel"], root)
    cube("WellWall_S", (-3.6, 1.67, -0.9), (3.2, 0.16, 1.8), mats["steel"], root)
    cube("WellWall_W", (-5.12, 3.3, -0.9), (0.16, 3.1, 1.8), mats["steel"], root)
    cube("WellWall_E", (-2.08, 3.3, -0.9), (0.16, 3.1, 1.8), mats["steel"], root)
    cube("WellFloor", (-3.6, 3.3, -1.76), (3.0, 3.0, 0.1), mats["olive"], root)
    _add_stair_flight(root, mats, start_z=-1.76, rise=0.22, run=0.32, steps=8, x=-3.6, y0=1.75)
    cube("WellLip", (-3.6, 1.75, 0.04), (3.3, 0.16, 0.12), mats["hazard"], root)
    for side, dx in (("L", -5.05), ("R", -2.15)):
        cube(f"WellRail_{side}", (dx, 3.2, 0.95), (0.06, 2.4, 0.06), mats["rail"], root)
        for post, y in enumerate((2.1, 3.2, 4.3)):
            cube(f"WellPost_{side}_{post}", (dx, y, 0.5), (0.06, 0.06, 1.0), mats["steel"], root)

    cube("NoCol_DownSign", (5.52, 0.4, 1.7), (0.04, 0.7, 0.5), mats["sign"], root)
    cube("NoCol_DownArrow", (5.48, 0.4, 1.55), (0.03, 0.18, 0.28), mats["hazard"], root)
    cube("ToolCrate", (4.4, -4.4, 0.4), (0.9, 0.9, 0.8), mats["wood"], root)
    cube("NoCol_CrateStrap", (4.4, -4.4, 0.62), (0.94, 0.94, 0.06), mats["steel"], root)
    cube("CableSpool", (3.6, 4.7, 0.42), (0.9, 0.9, 0.84), mats["olive"], root)
    cube("NoCol_SpoolHub", (3.6, 4.7, 0.42), (0.2, 0.95, 0.2), mats["steel"], root)
    cube("Locker", (5.15, -2.6, 0.95), (0.5, 1.1, 1.9), mats["steel"], root)
    cube("NoCol_LockerHandle", (4.88, -2.6, 0.95), (0.06, 0.16, 0.08), mats["hazard"], root)

    add_floor_debris(
        root,
        mats["debris"],
        [(1.6, 1.4, 1.6, 1.0), (2.2, -1.8, 1.3, 0.9), (0.6, -0.8, 1.1, 0.7)],
    )
    add_ceiling_lamp(root, mats["steel"], mats["bulb"], loc=(2.2, -1.4))
    add_empty("StairUse", (-3.6, 1.9, 0.9), root)
    return root


# --------------------------------------------------------------------------- #
# Boiler — the steam valve lives here
# --------------------------------------------------------------------------- #


def build_boiler():
    """Heating plant. The wheel named ValveWheel is what the player turns;
    ValveUse is the standing spot Godot searches for."""
    concrete = mat("BoilerFloor", (0.26, 0.26, 0.25), 0.92)
    plaster = mat("BoilerWall", (0.34, 0.32, 0.30), 0.9)
    grime = mat("BoilerGrime", (0.18, 0.17, 0.16), 0.95)
    steel = mat("BoilerSteel", (0.34, 0.35, 0.37), 0.35)
    rust = mat("BoilerRust", (0.45, 0.24, 0.13), 0.8)
    soot = mat("BoilerSoot", (0.12, 0.11, 0.10), 0.95)
    hazard = mat("BoilerHazard", (0.62, 0.48, 0.10), 0.65)
    red = mat("BoilerRed", (0.55, 0.12, 0.08), 0.45)
    heat = emissive("BoilerHeat", (1.0, 0.42, 0.12), 1.4)
    lamp = emissive("BoilerLamp", (1.0, 0.22, 0.12), 2.4)
    bulb = emissive("BoilerBulb", (1.0, 0.84, 0.55), 1.5)
    debris = mat("BoilerDebris", (0.20, 0.18, 0.16), 0.95)

    root = build_shell("Boiler", concrete, plaster, plaster)
    add_wall_grime(
        root,
        grime,
        [
            ("N", -3.6, 1.3, 1.8, 1.4),
            ("E", 3.2, 1.6, 2.0, 1.1),
            ("S", -2.2, 0.9, 2.2, 1.3),
        ],
    )

    # Northwest corner, clear of the doorway cross.
    tank = (-4.05, 3.75)
    cylinder_along("BoilerTank", (*tank, 0.78), 0.62, 2.3, rust, root, axis="Y", verts=16)
    cylinder_along("BoilerTankBandA", (tank[0], tank[1] - 0.7, 0.78), 0.66, 0.08, steel, root, axis="Y", verts=16)
    cylinder_along("BoilerTankBandB", (tank[0], tank[1] + 0.7, 0.78), 0.66, 0.08, steel, root, axis="Y", verts=16)
    for index, dy in enumerate((-1.0, 1.0)):
        cube(f"BoilerLeg_{index}", (tank[0], tank[1] + dy, 0.16), (0.9, 0.16, 0.32), steel, root)
    cube("BoilerSoot", (tank[0], tank[1], 0.22), (1.5, 2.5, 0.04), soot, root)

    # Riser and a horizontal gate valve. The wheel's axis is vertical so a
    # yaw in Godot reads as turning it.
    riser = (-3.15, 3.75)
    cube("ValveRiser", (*riser, 1.05), (0.16, 0.16, 1.5), steel, root)
    cube("ValveBody", (*riser, 1.55), (0.28, 0.28, 0.22), rust, root)
    wheel = cylinder_along("ValveWheel", (*riser, 1.78), 0.4, 0.07, red, root, axis="Z", verts=20)
    spoke_a = cube("ValveSpoke_0", (*riser, 1.78), (0.72, 0.06, 0.05), steel, root)
    spoke_b = cube("ValveSpoke_1", (*riser, 1.78), (0.06, 0.72, 0.05), steel, root)
    hub = cylinder_along("ValveHub", (*riser, 1.78), 0.1, 0.12, steel, root, axis="Z", verts=12)
    for part in (spoke_a, spoke_b, hub):
        attach(part, wheel)
    cube("NoCol_ValveLamp", (riser[0], riser[1], 1.28), (0.1, 0.1, 0.1), lamp, root)

    # Standing spot south of the wheel, still in the corner, not in the cross.
    add_empty("ValveUse", (-2.35, 2.55, 1.0), root)

    # Hookup that meets the procedural pipe run at the ceiling centre.
    pipe_seg("BoilerHeader", (*riser, 2.02), (0.0, 0.0, 2.02), 0.07, rust, root)
    pipe_seg("BoilerHeaderB", (riser[0], riser[1], 1.78), (*riser, 2.02), 0.06, steel, root)
    pipe_seg("BoilerReturn", (tank[0], tank[1], 1.35), (*riser, 1.55), 0.06, rust, root)

    # Coal bin and a gauge board in the other corners.
    cube("CoalBin", (4.35, -4.15, 0.4), (1.3, 1.1, 0.8), steel, root)
    cube("NoCol_Coal", (4.35, -4.15, 0.86), (1.1, 0.9, 0.16), soot, root)
    cube("GaugeBoard", (-4.7, -3.6, 1.35), (0.12, 1.4, 0.9), steel, root)
    cylinder("NoCol_Gauge_0", (-4.58, -3.95, 1.5), 0.16, 0.06, hazard, root, verts=12)
    cylinder("NoCol_Gauge_1", (-4.58, -3.25, 1.5), 0.16, 0.06, heat, root, verts=12)
    cube("NoCol_GaugeNeedle", (-4.54, -3.25, 1.5), (0.03, 0.04, 0.18), red, root)

    cube("ToolChest", (4.4, 3.5, 0.38), (0.9, 0.55, 0.76), red, root)
    cube("NoCol_ChestHandle", (4.4, 3.2, 0.55), (0.4, 0.05, 0.06), steel, root)
    cube("NoCol_HazardStripe", (4.6, -2.3, 1.15), (0.06, 0.9, 0.16), hazard, root)

    add_floor_debris(
        root,
        debris,
        [(1.4, 1.6, 1.6, 1.0), (0.6, -1.8, 1.2, 0.8), (-1.2, 1.1, 0.9, 0.7)],
    )
    add_ceiling_lamp(root, steel, bulb, loc=(1.8, -1.4))
    return root


# --------------------------------------------------------------------------- #
# Pipe gallery — the run you follow away from a steaming doorway
# --------------------------------------------------------------------------- #


def _wall_pipe_runs(root, material, y: float, z: float, name: str) -> None:
    """North/south pipe broken around the centred doorway."""
    pipe_seg(f"{name}_W", (-5.3, y, z), (-1.85, y, z), 0.07, material, root)
    pipe_seg(f"{name}_E", (1.85, y, z), (5.3, y, z), 0.07, material, root)


def _side_pipe_runs(root, material, x: float, z: float, name: str) -> None:
    """East/west pipe broken around the centred doorway."""
    pipe_seg(f"{name}_S", (x, -5.3, z), (x, -1.85, z), 0.07, material, root)
    pipe_seg(f"{name}_N", (x, 1.85, z), (x, 5.3, z), 0.07, material, root)


def build_pipe_gallery():
    concrete = mat("PipeFloor", (0.24, 0.25, 0.24), 0.92)
    plaster = mat("PipeWall", (0.30, 0.32, 0.31), 0.9)
    grime = mat("PipeGrime", (0.16, 0.18, 0.17), 0.95)
    steel = mat("PipeSteel", (0.36, 0.37, 0.38), 0.32)
    rust = mat("PipeRust", (0.46, 0.26, 0.14), 0.78)
    hazard = mat("PipeHazard", (0.60, 0.46, 0.09), 0.6)
    red = mat("PipeRed", (0.48, 0.12, 0.10), 0.55)
    heat = emissive("PipeHeat", (1.0, 0.48, 0.16), 1.1)
    bulb = emissive("PipeBulb", (0.95, 0.90, 0.72), 1.4)
    debris = mat("PipeDebris", (0.18, 0.18, 0.17), 0.95)

    root = build_shell("PipeGallery", concrete, plaster, plaster)
    add_wall_grime(
        root,
        grime,
        [
            ("W", 2.8, 1.2, 2.0, 1.5),
            ("E", -2.4, 1.5, 1.8, 1.2),
            ("S", 3.4, 1.7, 1.4, 0.8),
        ],
    )

    for z, material, tag in ((1.72, rust, "Low"), (2.02, steel, "High")):
        _wall_pipe_runs(root, material, 5.42, z, f"North{tag}")
        _wall_pipe_runs(root, material, -5.42, z, f"South{tag}")
        _side_pipe_runs(root, material, 5.42, z, f"East{tag}")
        _side_pipe_runs(root, material, -5.42, z, f"West{tag}")

    # Brackets and a corner manifold. The doorway cross stays empty so the
    # generator can blast steam through whichever wall it chooses.
    for index, (x, y) in enumerate(((-4.2, 5.55), (-2.4, 5.55), (2.4, 5.55), (4.2, 5.55))):
        cube(f"NoCol_BracketN_{index}", (x, y, 1.87), (0.1, 0.16, 0.5), steel, root)
    for index, (x, y) in enumerate(((5.55, -4.0), (5.55, -2.3), (5.55, 2.3), (5.55, 4.0))):
        cube(f"NoCol_BracketE_{index}", (x, y, 1.87), (0.16, 0.1, 0.5), steel, root)

    cylinder_along("Manifold", (4.15, -4.15, 1.15), 0.28, 1.7, rust, root, axis="Z", verts=14)
    cylinder_along("ManifoldCap", (4.15, -4.15, 2.02), 0.34, 0.08, steel, root, axis="Z", verts=14)
    pipe_seg("ManifoldTapN", (4.15, -4.15, 1.72), (4.15, -1.9, 1.72), 0.06, steel, root)
    pipe_seg("ManifoldTapW", (4.15, -4.15, 2.02), (1.9, -4.15, 2.02), 0.06, rust, root)
    cube("NoCol_ManifoldHeat", (4.15, -4.15, 1.15), (0.12, 0.12, 0.5), heat, root)

    cube("ValveCabinet", (-4.35, -4.2, 0.7), (0.7, 1.1, 1.4), steel, root)
    cube("NoCol_CabinetDoor", (-3.98, -4.2, 0.75), (0.05, 0.9, 1.15), plaster, root)
    cube("NoCol_CabinetLamp", (-3.92, -4.2, 1.15), (0.05, 0.16, 0.1), heat, root)

    cube("NoCol_SteamSign", (5.55, 0.0, 1.55), (0.05, 1.3, 0.48), red, root)
    cube("NoCol_SteamSignBar", (5.5, 0.0, 1.55), (0.03, 0.9, 0.08), hazard, root)

    cube("DripTray", (-4.3, 3.4, 0.06), (1.2, 0.8, 0.08), steel, root)
    cube("NoCol_Drip", (-4.3, 3.4, 0.12), (0.7, 0.45, 0.02), grime, root)

    add_floor_debris(
        root,
        debris,
        [(1.1, 0.8, 1.8, 1.1), (-0.8, -1.4, 1.2, 0.8), (0.4, 2.2, 1.0, 0.7)],
    )
    add_ceiling_lamp(root, steel, bulb, loc=(-1.6, 1.2))
    return root


# --------------------------------------------------------------------------- #
# Export + preview
# --------------------------------------------------------------------------- #

ROOM_BUILDERS = (
    ("bedroom", build_bedroom),
    ("living_room", build_living_room),
    ("office", build_office),
    ("storage", build_storage),
)

STAIR_BUILDERS = (
    ("stairwell_up", build_stairwell_up),
    ("stairwell_down", build_stairwell_down),
)

STEAM_BUILDERS = (
    ("boiler", build_boiler),
    ("pipe_gallery", build_pipe_gallery),
)


def export_room(root, glb_path: Path) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )


def _place_preview_modules() -> None:
    spacing = TILE
    livable = (
        (-spacing * 0.5, spacing * 1.5),
        (spacing * 0.5, spacing * 1.5),
        (-spacing * 0.5, spacing * 0.5),
        (spacing * 0.5, spacing * 0.5),
    )
    for (_, builder), (x, y) in zip(ROOM_BUILDERS, livable):
        root = builder()
        root.location = (x, y, 0.0)
    stair_offsets = ((-spacing * 0.5, -spacing * 0.5), (spacing * 0.5, -spacing * 0.5))
    for (_, builder), (x, y) in zip(STAIR_BUILDERS, stair_offsets):
        root = builder()
        root.location = (x, y, 0.0)
    steam_offsets = ((-spacing * 0.5, -spacing * 1.5), (spacing * 0.5, -spacing * 1.5))
    for (_, builder), (x, y) in zip(STEAM_BUILDERS, steam_offsets):
        root = builder()
        root.location = (x, y, 0.0)


def build_preview() -> None:
    """Lay the livable modules, stairwells and steam rooms in four rows."""
    clear_scene()
    _place_preview_modules()

    ground = mat("PreviewGround", (0.15, 0.15, 0.14), 0.95)
    cube("PreviewGround", (0, -6, -0.14), (64, 110, 0.12), ground)

    bpy.ops.object.light_add(type="AREA", location=(0, -8, 24))
    key = bpy.context.active_object
    key.name = "KeyLight"
    key.data.energy = 7000
    key.data.size = 18
    key.rotation_euler = (math.radians(28), 0, 0)

    bpy.ops.object.light_add(type="SUN", location=(10, -14, 18))
    sun = bpy.context.active_object
    sun.name = "Sun"
    sun.data.energy = 1.9
    sun.rotation_euler = (math.radians(48), math.radians(12), math.radians(24))

    bpy.ops.object.camera_add(location=(34, -52, 42))
    cam = bpy.context.active_object
    cam.name = "PreviewCam"
    cam.rotation_euler = (math.radians(52), 0, math.radians(36))
    cam.data.lens = 38
    bpy.context.scene.camera = cam

    scene = bpy.context.scene
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    if background:
        background.inputs[0].default_value = (0.10, 0.11, 0.12, 1.0)
        background.inputs[1].default_value = 0.6

    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))

    # Cycles on CPU: cloud agents have no GPU/EGL for Eevee.
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 28
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.render.filepath = str(PNG_OUT)
    try:
        bpy.ops.render.render(write_still=True)
        print(f"Wrote {PNG_OUT}")
    except Exception as exc:  # noqa: BLE001 - preview art is optional
        print(f"Preview render skipped: {exc}")


def render_steam_closeup() -> None:
    """Closer shot of the boiler and the pipe gallery for the walkthrough."""
    clear_scene()
    spacing = TILE
    for (_, builder), x in zip(STEAM_BUILDERS, (-spacing * 0.55, spacing * 0.55)):
        root = builder()
        root.location = (x, 0.0, 0.0)
    ground = mat("SteamPreviewGround", (0.12, 0.12, 0.11), 0.95)
    cube("PreviewGround", (0, 0, -0.14), (40, 28, 0.12), ground)

    bpy.ops.object.light_add(type="AREA", location=(0, -10, 14))
    key = bpy.context.active_object
    key.data.energy = 4500
    key.data.size = 12
    key.rotation_euler = (math.radians(40), 0, 0)
    bpy.ops.object.light_add(type="SUN", location=(6, -8, 10))
    sun = bpy.context.active_object
    sun.data.energy = 1.6
    sun.rotation_euler = (math.radians(50), math.radians(8), math.radians(20))

    bpy.ops.object.camera_add(location=(16, -18, 12))
    cam = bpy.context.active_object
    cam.rotation_euler = (math.radians(58), 0, math.radians(42))
    cam.data.lens = 42
    bpy.context.scene.camera = cam

    scene = bpy.context.scene
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    if background:
        background.inputs[0].default_value = (0.08, 0.09, 0.10, 1.0)
        background.inputs[1].default_value = 0.45

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 800
    scene.render.filepath = str(PNG_STEAM)
    try:
        bpy.ops.render.render(write_still=True)
        print(f"Wrote {PNG_STEAM}")
    except Exception as exc:  # noqa: BLE001 - preview art is optional
        print(f"Steam preview skipped: {exc}")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    BLEND_OUT.parent.mkdir(parents=True, exist_ok=True)
    PNG_OUT.parent.mkdir(parents=True, exist_ok=True)
    PNG_STEAM.parent.mkdir(parents=True, exist_ok=True)

    # One room per scene: Blender would otherwise suffix duplicate object names
    # (Plug_N.001) and break the generator's node lookups.
    for name, builder in ROOM_BUILDERS + STAIR_BUILDERS + STEAM_BUILDERS:
        clear_scene()
        root = builder()
        glb_path = OUT_DIR / f"room_{name}.glb"
        export_room(root, glb_path)
        print(f"Wrote {glb_path}")

    render_steam_closeup()
    build_preview()
    print(f"Wrote {BLEND_OUT}")


if __name__ == "__main__":
    main()
