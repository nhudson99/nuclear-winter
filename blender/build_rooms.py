"""
Build tileable room modules for Nuclear Winter's procedural maps:
bedroom, living room, office, storage, up/down stairwells, a boiler
room (steam valve) and a pipe gallery.

Every room shares one square footprint with a doorway centred on each of the
four walls, so the Godot map generator can butt any two rooms together on a
grid. Each doorway ships with a `Plug_<side>` filler block: the generator
deletes the plug where two rooms meet and keeps it where a room faces the
outside, which seals the map edge without needing per-room wall variants.

Furniture and shell materials come from blender/PripyatApartment_FBX_PBR/
(Pripyat Apartment pack). Shell topology stays procedural so the MapGenerator
naming contract is unchanged.

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
from mathutils import Vector

ROOT = Path(__file__).resolve().parent.parent
PACK_ROOT = Path(__file__).resolve().parent / "PripyatApartment_FBX_PBR"
OUT_DIR = ROOT / "godot" / "assets" / "rooms"
BLEND_OUT = ROOT / "blender" / "procedural_rooms.blend"
_ARTIFACTS = Path("/opt/cursor/artifacts")
if _ARTIFACTS.is_dir():
    PNG_OUT = _ARTIFACTS / "blender_procedural_rooms.png"
    PNG_STEAM = _ARTIFACTS / "blender_steam_rooms.png"
else:
    PNG_OUT = ROOT / "blender" / "blender_procedural_rooms.png"
    PNG_STEAM = ROOT / "blender" / "blender_steam_rooms.png"

TILE = 12.0  # grid pitch; must match MapGenerator.TILE
HALF = TILE * 0.5
WALL_H = 2.4
WALL_T = 0.28
DOOR_W = 2.6
DOOR_H = 2.1
SIDES = ("N", "S", "E", "W")
# Floor and wallpaper maps in the pack are authored for a 2 m repeat.
# glTF cannot carry Blender's object-space mapping, so shell meshes get a
# UV map where one unit is this many metres.
SHELL_TILE_M = 2.0
# Pack furniture already reads at the right proportion. Rooms want it larger.
PROP_VISUAL_SCALE = 1.5

# Keeping props out of the middle cross of the tile leaves every doorway
# reachable no matter which neighbours the generator attaches.
CLEAR = DOOR_W * 0.5 + 0.6

_PROP_SERIAL = 0


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for material in list(bpy.data.materials):
        bpy.data.materials.remove(material)
    for image in list(bpy.data.images):
        bpy.data.images.remove(image)
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
    apply_metre_uvs(obj)
    return obj


def apply_metre_uvs(obj: bpy.types.Object, tile_m: float = SHELL_TILE_M) -> None:
    """Planar UVs in world metres so a shell map repeats every `tile_m`.

    Adjacent wall and floor pieces share one continuous pattern because the
    coordinates are world-space, not the default cube unwrap.
    """
    mesh = obj.data
    if mesh is None or not hasattr(mesh, "polygons"):
        return
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    uv_layer = mesh.uv_layers.active
    bpy.context.view_layer.update()
    world = obj.matrix_world
    normal_matrix = world.to_3x3()
    for poly in mesh.polygons:
        normal = (normal_matrix @ poly.normal).normalized()
        ax, ay, az = abs(normal.x), abs(normal.y), abs(normal.z)
        if ax >= ay and ax >= az:
            u_axis, v_axis = 1, 2
        elif ay >= ax and ay >= az:
            u_axis, v_axis = 0, 2
        else:
            u_axis, v_axis = 0, 1
        for loop_index in poly.loop_indices:
            co = world @ mesh.vertices[mesh.loops[loop_index].vertex_index].co
            uv_layer.data[loop_index].uv = (co[u_axis] / tile_m, co[v_axis] / tile_m)


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
    apply_metre_uvs(obj)
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
# Pripyat pack helpers
# --------------------------------------------------------------------------- #


def _asset_stem(asset_name: str) -> str:
    return asset_name[3:] if asset_name.startswith("SM_") else asset_name


def _pack_asset_dir(category: str, asset_name: str) -> Path:
    path = PACK_ROOT / category / asset_name
    if not path.is_dir():
        raise FileNotFoundError(f"Missing pack asset folder: {path}")
    return path


def _load_image(path: Path):
    image = bpy.data.images.load(str(path), check_existing=True)
    return image


def pbr_shell_mat(name: str, category: str, asset_name: str):
    """PBR material for procedural shell meshes.

    Density is written into the mesh UV by `apply_metre_uvs` (one UV unit =
    SHELL_TILE_M metres). Sampling that UV map, rather than object coordinates,
    is what survives glTF export. An object-space Mapping node used to become
    a 0.5 texture transform on the cube's 0–1 unwrap, which magnified the
    wallpaper and the floor.
    """
    folder = _pack_asset_dir(category, asset_name)
    stem = _asset_stem(asset_name)
    material = bpy.data.materials.new(name=name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    tex_coord = nodes.new("ShaderNodeTexCoord")

    def link_map(suffix: str, colorspace: str, bsdf_input: str, non_color: bool = False):
        path = folder / f"T_{stem}_{suffix}.png"
        if not path.is_file():
            return
        image = _load_image(path)
        image.colorspace_settings.name = colorspace
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = image
        tex.extension = "REPEAT"
        links.new(tex_coord.outputs["UV"], tex.inputs["Vector"])
        if non_color and bsdf_input == "Normal":
            normal = nodes.new("ShaderNodeNormalMap")
            links.new(tex.outputs["Color"], normal.inputs["Color"])
            links.new(normal.outputs["Normal"], bsdf.inputs["Normal"])
        else:
            links.new(tex.outputs["Color"], bsdf.inputs[bsdf_input])

    link_map("BaseColor", "sRGB", "Base Color")
    link_map("Roughness", "Non-Color", "Roughness")
    link_map("Metallic", "Non-Color", "Metallic")
    link_map("Normal", "Non-Color", "Normal", non_color=True)
    return material


def _world_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    mins = Vector((1e9, 1e9, 1e9))
    maxs = Vector((-1e9, -1e9, -1e9))
    for corner in obj.bound_box:
        world = obj.matrix_world @ Vector(corner)
        for i in range(3):
            mins[i] = min(mins[i], world[i])
            maxs[i] = max(maxs[i], world[i])
    return mins, maxs


def _fix_glass_material(material: bpy.types.Material, green: bool = False) -> None:
    if material is None or not material.use_nodes:
        return
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    if bsdf is None:
        return
    color = (0.45, 0.60, 0.48, 1.0) if green else (0.70, 0.72, 0.70, 1.0)
    alpha = 0.40 if green else 0.20
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = 0.08
    if "Alpha" in bsdf.inputs:
        bsdf.inputs["Alpha"].default_value = alpha
    if "Transmission Weight" in bsdf.inputs:
        bsdf.inputs["Transmission Weight"].default_value = 1.0
    elif "Transmission" in bsdf.inputs:
        bsdf.inputs["Transmission"].default_value = 1.0
    material.blend_method = "HASHED"
    if hasattr(material, "shadow_method"):
        material.shadow_method = "HASHED"


def place_prop(
    category: str,
    asset_name: str,
    loc_xy,
    parent,
    yaw_deg: float = 0.0,
    collide: bool = True,
    name: str | None = None,
    z: float | None = None,
    scale: float = 1.0,
):
    """Import a Pripyat FBX prop, plant it, and parent it under the room root."""
    global _PROP_SERIAL
    scale *= PROP_VISUAL_SCALE
    folder = _pack_asset_dir(category, asset_name)
    fbx_path = folder / f"{asset_name}.fbx"
    if not fbx_path.is_file():
        raise FileNotFoundError(f"Missing FBX: {fbx_path}")

    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(fbx_path), automatic_bone_orientation=False)
    imported = [obj for obj in bpy.data.objects if obj not in before]
    meshes = [obj for obj in imported if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError(f"No mesh in {fbx_path}")

    _PROP_SERIAL += 1
    label = name or asset_name.replace("SM_", "")
    if not collide and not label.startswith("NoCol_"):
        label = f"NoCol_{label}"
    unique = f"{label}_{_PROP_SERIAL}"

    bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0.0, 0.0, 0.0))
    holder = bpy.context.active_object
    holder.name = unique

    for obj in imported:
        if obj.parent is None and obj != holder:
            obj.parent = holder

    for obj in meshes:
        for slot in obj.material_slots:
            mat_name = slot.material.name if slot.material else ""
            if "Glass" in mat_name:
                _fix_glass_material(slot.material, green="Green" in mat_name)

    bpy.context.view_layer.update()
    mins = Vector((1e9, 1e9, 1e9))
    maxs = Vector((-1e9, -1e9, -1e9))
    for obj in meshes:
        obj_min, obj_max = _world_bounds(obj)
        for i in range(3):
            mins[i] = min(mins[i], obj_min[i])
            maxs[i] = max(maxs[i], obj_max[i])

    if scale != 1.0:
        holder.scale = (scale, scale, scale)
        bpy.context.view_layer.update()
        mins = Vector((1e9, 1e9, 1e9))
        maxs = Vector((-1e9, -1e9, -1e9))
        for obj in meshes:
            obj_min, obj_max = _world_bounds(obj)
            for i in range(3):
                mins[i] = min(mins[i], obj_min[i])
                maxs[i] = max(maxs[i], obj_max[i])

    # Centre on X/Y of the asset, plant Z on the floor unless overridden.
    holder.location.x = -0.5 * (mins.x + maxs.x)
    holder.location.y = -0.5 * (mins.y + maxs.y)
    holder.location.z = -mins.z
    bpy.context.view_layer.update()

    if yaw_deg:
        holder.rotation_euler[2] = math.radians(yaw_deg)
        bpy.context.view_layer.update()

    x, y = loc_xy
    target_z = 0.0 if z is None else z
    holder.location.x += x
    holder.location.y += y
    holder.location.z += target_z
    bpy.context.view_layer.update()

    if parent is not None:
        attach(holder, parent)
    return holder


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


def shell_mats(floor_asset: str, wall_asset: str, prefix: str):
    floor = pbr_shell_mat(f"{prefix}Floor", "Stairwell_Architecture", floor_asset)
    wall = pbr_shell_mat(f"{prefix}Wall", "Stairwell_Architecture", wall_asset)
    return floor, wall


# --------------------------------------------------------------------------- #
# Bedroom
# --------------------------------------------------------------------------- #


def build_bedroom():
    floor, wall = shell_mats("SM_Floor_Parquet_2m", "SM_Wall_Wallpaper_A", "Bedroom")
    steel = mat("BedroomSteel", (0.30, 0.31, 0.33), 0.45)
    bulb = emissive("BedroomBulb", (1.0, 0.88, 0.62), 1.6)

    root = build_shell("Bedroom", floor, wall, wall)

    # West wall bed, head toward north.
    place_prop("Bedroom", "SM_Bed_Double_Wooden", (-4.2, 3.1), root, yaw_deg=0.0, name="Bed")
    place_prop("Bedroom", "SM_Nightstand", (-4.9, 1.55), root, yaw_deg=90.0, name="Nightstand")
    place_prop(
        "Bedroom",
        "SM_AlarmClock_TwinBell",
        (-4.9, 1.55),
        root,
        yaw_deg=90.0,
        collide=False,
        name="AlarmClock",
        z=0.72,
    )
    place_prop("Bedroom", "SM_Dresser_Mirror", (4.4, -3.8), root, yaw_deg=-90.0, name="Dresser")
    place_prop("Bedroom", "SM_CoatRack_Standing", (4.6, 4.6), root, yaw_deg=180.0, name="CoatRack")
    place_prop("Bedroom", "SM_Suitcase_Old", (-4.5, -4.6), root, yaw_deg=25.0, name="Suitcase")
    place_prop(
        "Bedroom",
        "SM_Suitcase_Open",
        (-3.2, -4.8),
        root,
        yaw_deg=-15.0,
        collide=False,
        name="SuitcaseOpen",
    )
    place_prop(
        "Bedroom",
        "SM_IroningBoard",
        (3.2, 4.9),
        root,
        yaw_deg=90.0,
        collide=False,
        name="IroningBoard",
    )
    place_prop(
        "Abandonment",
        "SM_Wallpaper_Strips",
        (-5.2, -2.2),
        root,
        yaw_deg=90.0,
        collide=False,
        name="WallpaperStrips",
    )
    place_prop(
        "Abandonment",
        "SM_Debris_Pile",
        (1.8, -4.6),
        root,
        yaw_deg=40.0,
        collide=False,
        name="Debris",
    )

    add_ceiling_lamp(root, steel, bulb)
    return root


# --------------------------------------------------------------------------- #
# Living room
# --------------------------------------------------------------------------- #


def build_living_room():
    floor, wall = shell_mats("SM_Floor_Parquet_2m", "SM_Wall_Wallpaper_B", "Living")
    steel = mat("LivingSteel", (0.33, 0.34, 0.36), 0.4)
    bulb = emissive("LivingBulb", (1.0, 0.86, 0.58), 1.6)

    root = build_shell("LivingRoom", floor, wall, wall)

    place_prop("LivingRoom", "SM_SofaBed", (-4.7, 3.2), root, yaw_deg=90.0, name="Sofa")
    place_prop("LivingRoom", "SM_CoffeeTable", (-3.2, 3.2), root, yaw_deg=90.0, name="CoffeeTable")
    place_prop(
        "Kitchen",
        "SM_Samovar_Electric",
        (-3.2, 3.5),
        root,
        yaw_deg=0.0,
        collide=False,
        name="Samovar",
        z=0.55,
    )
    place_prop("LivingRoom", "SM_Armchair_Upholstered", (4.2, -3.2), root, yaw_deg=-90.0, name="Armchair")
    place_prop("LivingRoom", "SM_FloorLamp", (2.8, -4.8), root, yaw_deg=20.0, name="FloorLamp")
    place_prop("LivingRoom", "SM_WallUnit_Wardrobe", (3.4, 5.1), root, yaw_deg=180.0, name="WallUnit")
    place_prop(
        "LivingRoom",
        "SM_WallUnit_Shelves",
        (-3.6, 5.15),
        root,
        yaw_deg=180.0,
        name="WallShelves",
    )
    place_prop(
        "LivingRoom",
        "SM_Rug_Floor",
        (-3.0, -3.2),
        root,
        yaw_deg=15.0,
        collide=False,
        name="Rug",
    )
    place_prop(
        "LivingRoom",
        "SM_Radiogram",
        (5.0, 2.4),
        root,
        yaw_deg=-90.0,
        collide=False,
        name="Radiogram",
    )
    place_prop(
        "LivingRoom",
        "SM_PhotoFrames_Set",
        (5.35, -0.4),
        root,
        yaw_deg=-90.0,
        collide=False,
        name="PhotoFrames",
        z=1.2,
    )
    place_prop(
        "LivingRoom",
        "SM_Chandelier_3Arm",
        (0.0, 0.0),
        root,
        yaw_deg=0.0,
        collide=False,
        name="Chandelier",
        z=1.55,
    )
    place_prop(
        "Abandonment",
        "SM_Newspaper_Stack",
        (-4.6, -4.6),
        root,
        yaw_deg=30.0,
        collide=False,
        name="Newspapers",
    )

    add_ceiling_lamp(root, steel, bulb, loc=(2.2, -1.6))
    return root


# --------------------------------------------------------------------------- #
# Office (Soviet study — hallway + living props)
# --------------------------------------------------------------------------- #


def build_office():
    floor, wall = shell_mats("SM_Floor_Linoleum_2m", "SM_Wall_Wallpaper_A", "Office")
    steel = mat("OfficeSteel", (0.34, 0.35, 0.37), 0.4)
    bulb = emissive("OfficeBulb", (0.94, 0.96, 0.82), 1.8)

    root = build_shell("Office", floor, wall, wall)

    place_prop(
        "LivingRoom",
        "SM_DiningTable_Extendable",
        (3.5, 3.4),
        root,
        yaw_deg=0.0,
        name="Desk",
    )
    place_prop(
        "LivingRoom",
        "SM_DiningChair_Upholstered",
        (3.5, 2.2),
        root,
        yaw_deg=0.0,
        name="DeskChair",
    )
    place_prop(
        "LivingRoom",
        "SM_SewingMachine",
        (3.2, 3.5),
        root,
        yaw_deg=180.0,
        collide=False,
        name="SewingMachine",
        z=0.78,
    )
    place_prop(
        "LivingRoom",
        "SM_WallUnit_Shelves",
        (-4.6, 5.1),
        root,
        yaw_deg=180.0,
        name="BinderShelf",
    )
    place_prop(
        "Hallway",
        "SM_Telephone_Wall",
        (5.45, -2.4),
        root,
        yaw_deg=-90.0,
        collide=False,
        name="Telephone",
        z=1.2,
    )
    place_prop(
        "Hallway",
        "SM_LightSwitch_Socket",
        (-5.45, 2.0),
        root,
        yaw_deg=90.0,
        collide=False,
        name="LightSwitch",
        z=1.15,
    )
    place_prop(
        "Hallway",
        "SM_ElectricMeter_Panel",
        (-5.45, -3.4),
        root,
        yaw_deg=90.0,
        collide=False,
        name="ElectricMeter",
        z=1.4,
    )
    place_prop(
        "Abandonment",
        "SM_Newspaper_Stack",
        (-3.6, -4.0),
        root,
        yaw_deg=-20.0,
        name="PaperStack",
    )
    place_prop(
        "Abandonment",
        "SM_PhotoAlbum",
        (4.6, -4.6),
        root,
        yaw_deg=40.0,
        collide=False,
        name="PhotoAlbum",
    )
    place_prop(
        "Abandonment",
        "SM_Drawer_Fallen",
        (-4.4, -2.2),
        root,
        yaw_deg=70.0,
        collide=False,
        name="FallenDrawer",
    )
    place_prop(
        "LivingRoom",
        "SM_FloorLamp",
        (1.8, -5.0),
        root,
        yaw_deg=-30.0,
        name="FloorLamp",
    )

    add_ceiling_lamp(root, steel, bulb)
    return root


# --------------------------------------------------------------------------- #
# Storage
# --------------------------------------------------------------------------- #


def build_storage():
    floor, wall = shell_mats("SM_Floor_Linoleum_2m", "SM_Wall_Wallpaper_B", "Storage")
    steel = mat("StorageSteel", (0.34, 0.35, 0.37), 0.4)
    rust = mat("StorageRust", (0.42, 0.24, 0.14), 0.85)
    bulb = emissive("StorageBulb", (0.96, 0.93, 0.76), 1.5)

    root = build_shell("Storage", floor, wall, wall)

    place_prop(
        "Kitchen",
        "SM_KitchenCabinet_Base",
        (-4.8, 3.6),
        root,
        yaw_deg=90.0,
        name="CabinetBaseA",
    )
    place_prop(
        "Kitchen",
        "SM_KitchenCabinet_Base",
        (-4.8, 4.7),
        root,
        yaw_deg=90.0,
        name="CabinetBaseB",
    )
    place_prop(
        "Kitchen",
        "SM_KitchenCabinet_Wall",
        (4.9, 3.8),
        root,
        yaw_deg=-90.0,
        name="CabinetWall",
        z=1.0,
    )
    place_prop(
        "Kitchen",
        "SM_Canisters_Set",
        (-4.6, -3.2),
        root,
        yaw_deg=20.0,
        name="Canisters",
    )
    place_prop(
        "Kitchen",
        "SM_CannedFood_Set",
        (-3.4, -4.6),
        root,
        yaw_deg=-10.0,
        collide=False,
        name="CannedFood",
    )
    place_prop(
        "Kitchen",
        "SM_Pot_Enamel_Set",
        (3.6, -4.4),
        root,
        yaw_deg=45.0,
        collide=False,
        name="Pots",
    )
    place_prop(
        "Abandonment",
        "SM_Chair_Broken",
        (4.4, -3.0),
        root,
        yaw_deg=-35.0,
        name="BrokenChair",
    )
    place_prop(
        "Abandonment",
        "SM_Debris_Pile",
        (3.8, 4.6),
        root,
        yaw_deg=80.0,
        collide=False,
        name="Debris",
    )
    place_prop(
        "Abandonment",
        "SM_GasMask",
        (-2.2, -5.0),
        root,
        yaw_deg=15.0,
        collide=False,
        name="GasMask",
    )
    place_prop(
        "Abandonment",
        "SM_GlassShards",
        (1.6, -4.8),
        root,
        yaw_deg=0.0,
        collide=False,
        name="GlassShards",
    )
    place_prop(
        "Bedroom",
        "SM_Suitcase_Old",
        (4.8, 2.2),
        root,
        yaw_deg=90.0,
        name="Suitcase",
    )

    for index, z in enumerate((1.95, 2.15)):
        cube(f"NoCol_Pipe_{index}", (0.0, 5.55, z), (11.2, 0.16, 0.16), rust if index else steel, root)

    add_ceiling_lamp(root, steel, bulb)
    return root


# --------------------------------------------------------------------------- #
# Stairwells
# --------------------------------------------------------------------------- #


def _stair_materials():
    floor, wall = shell_mats("SM_Floor_Linoleum_2m", "SM_Wall_Wallpaper_A", "Stair")
    return {
        "floor": floor,
        "wall": wall,
        "steel": mat("StairSteel", (0.34, 0.35, 0.37), 0.4),
        "rust": mat("StairRust", (0.42, 0.24, 0.14), 0.85),
        "wood": mat("StairWood", (0.34, 0.24, 0.15), 0.75),
        "olive": mat("StairOlive", (0.29, 0.32, 0.24), 0.7),
        "hazard": mat("StairHazard", (0.58, 0.49, 0.13), 0.7),
        "rail": mat("StairRail", (0.22, 0.23, 0.24), 0.35),
        "sign": mat("StairSign", (0.47, 0.14, 0.13), 0.7),
        "bulb": emissive("StairBulb", (0.96, 0.90, 0.70), 1.6),
        "glow": emissive("StairGlow", (0.55, 0.82, 0.45), 2.2),
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

    _add_stair_flight(root, mats, start_z=0.0, rise=0.22, run=0.32, steps=8, x=-4.35, y0=1.7)
    cube("Landing", (-4.35, 4.66, 1.87), (1.9, 1.2, 0.12), mats["olive"], root)
    cube("LandingBack", (-4.35, 5.22, 2.15), (1.9, 0.12, 0.7), mats["steel"], root)
    cube("NoCol_HatchFrame", (-4.35, 4.66, 2.34), (1.5, 0.9, 0.08), mats["steel"], root)
    cube("NoCol_HatchGlow", (-4.35, 4.66, 2.28), (1.2, 0.7, 0.04), mats["glow"], root)
    cube("NoCol_UpSign", (-5.52, 3.4, 1.7), (0.04, 0.7, 0.5), mats["sign"], root)
    cube("NoCol_UpArrow", (-5.48, 3.4, 1.78), (0.03, 0.18, 0.28), mats["hazard"], root)
    cube("StairNewel", (-5.2, 1.7, 0.55), (0.16, 0.16, 1.1), mats["rail"], root)

    place_prop(
        "Stairwell_Architecture",
        "SM_Mailboxes_Block",
        (4.6, 4.8),
        root,
        yaw_deg=180.0,
        name="Mailboxes",
    )
    place_prop(
        "Hallway",
        "SM_CoatRack_Wall",
        (5.35, -3.2),
        root,
        yaw_deg=-90.0,
        collide=False,
        name="CoatRack",
        z=1.1,
    )
    place_prop(
        "Hallway",
        "SM_Doormat",
        (3.6, -4.9),
        root,
        yaw_deg=0.0,
        collide=False,
        name="Doormat",
    )
    place_prop(
        "Stairwell_Architecture",
        "SM_CeilingLamp_Bare",
        (1.6, -1.2),
        root,
        yaw_deg=0.0,
        collide=False,
        name="CeilingLamp",
        z=1.7,
    )
    place_prop(
        "Stairwell_Architecture",
        "SM_Elevator_Door",
        (5.25, 1.8),
        root,
        yaw_deg=-90.0,
        collide=False,
        name="ElevatorDoor",
    )
    place_prop(
        "Abandonment",
        "SM_Debris_Pile",
        (2.4, 4.6),
        root,
        yaw_deg=50.0,
        collide=False,
        name="Debris",
    )

    for index, z in enumerate((1.9, 2.12)):
        cube(
            f"NoCol_StairPipe_{index}",
            (1.4, 5.55, z),
            (6.8, 0.14, 0.14),
            mats["rust"] if index else mats["steel"],
            root,
        )

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

    place_prop(
        "Hallway",
        "SM_ShoeCabinet",
        (4.6, -4.2),
        root,
        yaw_deg=-90.0,
        name="ShoeCabinet",
    )
    place_prop(
        "Stairwell_Architecture",
        "SM_Mailboxes_Block",
        (4.8, 4.6),
        root,
        yaw_deg=180.0,
        name="Mailboxes",
    )
    place_prop(
        "Stairwell_Architecture",
        "SM_CeilingLamp_Bare",
        (2.2, -1.4),
        root,
        yaw_deg=0.0,
        collide=False,
        name="CeilingLamp",
        z=1.7,
    )
    place_prop(
        "Abandonment",
        "SM_Debris_Pile",
        (2.0, 4.4),
        root,
        yaw_deg=-25.0,
        collide=False,
        name="Debris",
    )
    place_prop(
        "Abandonment",
        "SM_GasMask",
        (3.4, -2.8),
        root,
        yaw_deg=60.0,
        collide=False,
        name="GasMask",
    )

    add_empty("StairUse", (-3.6, 1.9, 0.9), root)
    return root


# --------------------------------------------------------------------------- #
# Boiler — the steam valve lives here
# --------------------------------------------------------------------------- #


def build_boiler():
    """Heating plant. The wheel named ValveWheel is what the player turns;
    ValveUse is the standing spot Godot searches for."""
    floor = pbr_shell_mat("BoilerFloor", "Stairwell_Architecture", "SM_Floor_Linoleum_2m")
    plaster = mat("BoilerWall", (0.34, 0.32, 0.30), 0.9)
    steel = mat("BoilerSteel", (0.34, 0.35, 0.37), 0.35)
    rust = mat("BoilerRust", (0.45, 0.24, 0.13), 0.8)
    soot = mat("BoilerSoot", (0.12, 0.11, 0.10), 0.95)
    hazard = mat("BoilerHazard", (0.62, 0.48, 0.10), 0.65)
    red = mat("BoilerRed", (0.55, 0.12, 0.08), 0.45)
    heat = emissive("BoilerHeat", (1.0, 0.42, 0.12), 1.4)
    lamp = emissive("BoilerLamp", (1.0, 0.22, 0.12), 2.4)
    bulb = emissive("BoilerBulb", (1.0, 0.84, 0.55), 1.5)

    root = build_shell("Boiler", floor, plaster, plaster)

    tank = (-4.05, 3.75)
    cylinder_along("BoilerTank", (*tank, 0.78), 0.62, 2.3, rust, root, axis="Y", verts=16)
    cylinder_along("BoilerTankBandA", (tank[0], tank[1] - 0.7, 0.78), 0.66, 0.08, steel, root, axis="Y", verts=16)
    cylinder_along("BoilerTankBandB", (tank[0], tank[1] + 0.7, 0.78), 0.66, 0.08, steel, root, axis="Y", verts=16)
    for index, dy in enumerate((-1.0, 1.0)):
        cube(f"BoilerLeg_{index}", (tank[0], tank[1] + dy, 0.16), (0.9, 0.16, 0.32), steel, root)
    cube("BoilerSoot", (tank[0], tank[1], 0.22), (1.5, 2.5, 0.04), soot, root)

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

    add_empty("ValveUse", (-2.35, 2.55, 1.0), root)

    pipe_seg("BoilerHeader", (*riser, 2.02), (0.0, 0.0, 2.02), 0.07, rust, root)
    pipe_seg("BoilerHeaderB", (riser[0], riser[1], 1.78), (*riser, 2.02), 0.06, steel, root)
    pipe_seg("BoilerReturn", (tank[0], tank[1], 1.35), (*riser, 1.55), 0.06, rust, root)

    cube("GaugeBoard", (-4.7, -3.6, 1.35), (0.12, 1.4, 0.9), steel, root)
    cylinder("NoCol_Gauge_0", (-4.58, -3.95, 1.5), 0.16, 0.06, hazard, root, verts=12)
    cylinder("NoCol_Gauge_1", (-4.58, -3.25, 1.5), 0.16, 0.06, heat, root, verts=12)
    cube("NoCol_GaugeNeedle", (-4.54, -3.25, 1.5), (0.03, 0.04, 0.18), red, root)
    cube("ToolChest", (4.4, 3.5, 0.38), (0.9, 0.55, 0.76), red, root)
    cube("NoCol_ChestHandle", (4.4, 3.2, 0.55), (0.4, 0.05, 0.06), steel, root)
    cube("NoCol_HazardStripe", (4.6, -2.3, 1.15), (0.06, 0.9, 0.16), hazard, root)

    place_prop(
        "Kitchen",
        "SM_GasWaterHeater",
        (4.5, -4.4),
        root,
        yaw_deg=-90.0,
        name="GasWaterHeater",
    )
    place_prop(
        "Abandonment",
        "SM_Debris_Pile",
        (2.2, 4.6),
        root,
        yaw_deg=35.0,
        collide=False,
        name="Debris",
    )
    place_prop(
        "Abandonment",
        "SM_GasMask",
        (-4.6, -4.6),
        root,
        yaw_deg=-40.0,
        collide=False,
        name="GasMask",
    )
    place_prop(
        "Abandonment",
        "SM_Newspaper_Stack",
        (3.2, -4.8),
        root,
        yaw_deg=10.0,
        collide=False,
        name="Newspapers",
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
    floor = pbr_shell_mat("PipeFloor", "Stairwell_Architecture", "SM_Floor_Linoleum_2m")
    plaster = mat("PipeWall", (0.30, 0.32, 0.31), 0.9)
    grime = mat("PipeGrime", (0.16, 0.18, 0.17), 0.95)
    steel = mat("PipeSteel", (0.36, 0.37, 0.38), 0.32)
    rust = mat("PipeRust", (0.46, 0.26, 0.14), 0.78)
    hazard = mat("PipeHazard", (0.60, 0.46, 0.09), 0.6)
    red = mat("PipeRed", (0.48, 0.12, 0.10), 0.55)
    heat = emissive("PipeHeat", (1.0, 0.48, 0.16), 1.1)
    bulb = emissive("PipeBulb", (0.95, 0.90, 0.72), 1.4)

    root = build_shell("PipeGallery", floor, plaster, plaster)

    for z, material, tag in ((1.72, rust, "Low"), (2.02, steel, "High")):
        _wall_pipe_runs(root, material, 5.42, z, f"North{tag}")
        _wall_pipe_runs(root, material, -5.42, z, f"South{tag}")
        _side_pipe_runs(root, material, 5.42, z, f"East{tag}")
        _side_pipe_runs(root, material, -5.42, z, f"West{tag}")

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

    place_prop(
        "Abandonment",
        "SM_Debris_Pile",
        (2.6, 4.5),
        root,
        yaw_deg=-55.0,
        collide=False,
        name="Debris",
    )
    place_prop(
        "Abandonment",
        "SM_Wallpaper_Strips",
        (-5.2, 2.6),
        root,
        yaw_deg=90.0,
        collide=False,
        name="WallpaperStrips",
    )
    place_prop(
        "Abandonment",
        "SM_GasMask_Pile",
        (-4.4, 4.6),
        root,
        yaw_deg=25.0,
        collide=False,
        name="GasMaskPile",
        scale=0.7,
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
    if not PACK_ROOT.is_dir():
        raise FileNotFoundError(f"Pripyat pack missing at {PACK_ROOT}")
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

    # Last room scene is left in the blend for inspection; full multi-room
    # preview / Cycles shots are opt-in via build_preview() / render_steam_closeup().
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
    print(f"Wrote {BLEND_OUT}")


if __name__ == "__main__":
    main()
