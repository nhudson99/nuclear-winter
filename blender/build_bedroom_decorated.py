"""
Decorated bedroom module for Nuclear Winter, built from the Pripyat Apartment
pack (blender/PripyatApartment_FBX_PBR/).

Output: godot/assets/rooms/room_bedroom_decorated.glb

Same tile contract as build_rooms.py (12 m tile, 2.4 m walls, 0.28 m thick,
2.6 x 2.1 m doorway centred on every wall, Plug_<side> fillers, NoCol_ prefix
for meshes the MapGenerator must not collide). Every prop sits in one of the
four corner quadrants, outside the doorway cross (|x| or |y| < 1.9 m), so any
doorway the generator opens stays walkable.

Blender axes: +Y = north (Godot -Z), +X = east. Pack props face -Y, back +Y.

Run:  blender -b -P blender/build_bedroom_decorated.py
      (PRIPYAT_PACK / ROOM_OUT env vars override the default paths)
"""
from __future__ import annotations
import math, os, sys
from pathlib import Path
import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
PACK_ROOT = Path(os.environ.get("PRIPYAT_PACK", HERE / "PripyatApartment_FBX_PBR"))
OUT_GLB = Path(os.environ.get("ROOM_OUT", HERE.parent / "godot/assets/rooms/room_bedroom_decorated.glb"))
PREVIEW_DIR = os.environ.get("PREVIEW_DIR")

TILE = 12.0; HALF = TILE / 2; WALL_H = 2.4; WALL_T = 0.28
DOOR_W = 2.6; DOOR_H = 2.1; SIDES = ("N", "S", "E", "W")
INNER = HALF - WALL_T          # 5.72 interior face
GAP = 0.02                     # clearance from wall faces
CLEAR = DOOR_W * 0.5 + 0.6     # 1.9 doorway cross half-width


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# ---------------------------------------------------------------- materials
_MATS = {}


def pbr_mat(name, folder: Path, stem: str):
    """One material per asset (shared by every instance) so the glTF exporter
    packs each metallic/roughness texture once."""
    if stem in _MATS: return _MATS[stem]
    m = _MATS[stem] = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; bsdf = nt.nodes["Principled BSDF"]
    def tex(suffix, cs):
        p = folder / f"T_{stem}_{suffix}.png"
        if not p.is_file(): return None
        n = nt.nodes.new("ShaderNodeTexImage"); n.image = bpy.data.images.load(str(p), check_existing=True)
        n.image.colorspace_settings.name = cs; return n
    if (t := tex("BaseColor", "sRGB")): nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    if (t := tex("Roughness", "Non-Color")): nt.links.new(t.outputs["Color"], bsdf.inputs["Roughness"])
    if (t := tex("Metallic", "Non-Color")): nt.links.new(t.outputs["Color"], bsdf.inputs["Metallic"])
    if (t := tex("Normal", "Non-Color")):
        nm = nt.nodes.new("ShaderNodeNormalMap"); nt.links.new(t.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def plain_mat(name, srgb, rough):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    b.inputs["Base Color"].default_value = (*lin, 1); b.inputs["Roughness"].default_value = rough
    return m


def box_uv(obj, tile_m=2.0):
    """World-metre box projection so tiled textures survive glTF export."""
    me = obj.data
    uv = me.uv_layers.new(name="UVMap") if not me.uv_layers else me.uv_layers[0]
    mw = obj.matrix_world
    for poly in me.polygons:
        n = poly.normal; ax = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            co = mw @ me.vertices[me.loops[li].vertex_index].co
            u, v = {0: (co.y, co.z), 1: (co.x, co.z), 2: (co.x, co.y)}[ax]
            uv.data[li].uv = (u / tile_m, v / tile_m)


def cube(name, loc, size, material, parent):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object; o.name = name; o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    box_uv(o); o.data.materials.append(material); o.parent = parent
    return o


def build_shell(root, floor_mat, wall_mat):
    cube("Floor", (0, 0, -0.05), (TILE, TILE, 0.1), floor_mat, root)
    lintel_h = WALL_H - DOOR_H
    for side in SIDES:
        span = HALF if side in ("N", "S") else HALF - WALL_T
        run = span - DOOR_W * 0.5; off = (span + DOOR_W * 0.5) * 0.5
        face = (HALF - WALL_T * 0.5) * (1 if side in ("N", "E") else -1)
        if side in ("N", "S"):
            cube(f"Wall_{side}_A", (-off, face, WALL_H / 2), (run, WALL_T, WALL_H), wall_mat, root)
            cube(f"Wall_{side}_B", (off, face, WALL_H / 2), (run, WALL_T, WALL_H), wall_mat, root)
            cube(f"Wall_{side}_L", (0, face, DOOR_H + lintel_h / 2), (DOOR_W, WALL_T, lintel_h), wall_mat, root)
            cube(f"Plug_{side}", (0, face, DOOR_H / 2), (DOOR_W, WALL_T, DOOR_H), wall_mat, root)
        else:
            cube(f"Wall_{side}_A", (face, -off, WALL_H / 2), (WALL_T, run, WALL_H), wall_mat, root)
            cube(f"Wall_{side}_B", (face, off, WALL_H / 2), (WALL_T, run, WALL_H), wall_mat, root)
            cube(f"Wall_{side}_L", (face, 0, DOOR_H + lintel_h / 2), (WALL_T, DOOR_W, lintel_h), wall_mat, root)
            cube(f"Plug_{side}", (face, 0, DOOR_H / 2), (WALL_T, DOOR_W, DOOR_H), wall_mat, root)


# ---------------------------------------------------------------- props
def strip_islands(obj, limit, axis=1, below=True):
    """Delete loose parts that reach further than `min_y` in front (-Y) of the
    asset's plane: peeling flaps and floor crumbs on wall/floor panels that
    would otherwise clip through furniture pushed against the wall."""
    import bmesh
    bm = bmesh.new(); bm.from_mesh(obj.data); bm.verts.ensure_lookup_table()
    seen = set(); kill = []
    for v in bm.verts:
        if v.index in seen: continue
        stack = [v]; island = []
        seen.add(v.index)
        while stack:
            cur = stack.pop(); island.append(cur)
            for e in cur.link_edges:
                o = e.other_vert(cur)
                if o.index not in seen: seen.add(o.index); stack.append(o)
        vals = [p.co[axis] for p in island]
        if (min(vals) < limit) if below else (max(vals) > limit): kill.extend(island)
    bmesh.ops.delete(bm, geom=kill, context="VERTS"); bm.to_mesh(obj.data); bm.free()


PROPS = []   # (obj, collide, stack_on)


def world_bounds(o):
    vs = [o.matrix_world @ v.co for v in o.data.vertices]
    return (Vector([min(v[i] for v in vs) for i in range(3)]),
            Vector([max(v[i] for v in vs) for i in range(3)]))


def surface_z(x, y, from_z=WALL_H - 0.05):
    dg = bpy.context.evaluated_depsgraph_get()
    hit, loc, *_ = bpy.context.scene.ray_cast(dg, Vector((x, y, from_z)), Vector((0, 0, -1)))
    return loc.z if hit else 0.0


def prop(cat, asset, name, yaw=0.0, *, x=None, y=None, xmin=None, xmax=None, ymin=None, ymax=None,
         z=0.0, on_surface=False, tilt=(0.0, 0.0), collide=True, scale=1.0, sx=1.0, sz=1.0, parent=None, stack_on=None,
         raw=False, strip_front=None, strip_above=None):
    """Import one pack FBX, rotate, then anchor its *rotated* world AABB:
    x/y = AABB centre, xmin/xmax/ymin/ymax = AABB edge, z = AABB bottom
    (or the surface under the centre when on_surface)."""
    folder = PACK_ROOT / cat / asset
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(folder / f"{asset}.fbx"))
    new = [o for o in bpy.data.objects if o not in before]
    mesh = [o for o in new if o.type == "MESH"][0]
    for o in new:
        if o is not mesh: bpy.data.objects.remove(o)
    bpy.ops.object.select_all(action="DESELECT"); mesh.select_set(True)
    bpy.context.view_layer.objects.active = mesh
    mw = mesh.matrix_world.copy(); mesh.parent = None; mesh.matrix_world = mw
    # Bake the FBX axis/unit conversion into the mesh so yaw is a pure Z turn.
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if strip_front is not None:
        strip_islands(mesh, strip_front)
    if strip_above is not None:
        strip_islands(mesh, strip_above, axis=2, below=False)
    stem = asset[3:]
    pbr = pbr_mat(f"M_{stem}", folder, stem)
    for slot in mesh.material_slots:   # rewire the pack material, keep glass slots
        if slot.material and "Glass" in slot.material.name:
            b = slot.material.node_tree.nodes.get("Principled BSDF")
            if b:
                b.inputs["Base Color"].default_value = (0.7, 0.72, 0.7, 1); b.inputs["Roughness"].default_value = 0.08
                b.inputs["Alpha"].default_value = 0.25; slot.material.blend_method = "BLEND"
        else:
            slot.material = pbr
    mesh.name = (name if collide else f"NoCol_{name}")
    mesh.rotation_euler = (math.radians(tilt[0]), math.radians(tilt[1]), math.radians(yaw))
    mesh.scale = (scale * sx, scale, scale * sz)
    mesh.location = (0, 0, 0)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT"); mesh.select_set(True)
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if raw:   # keep the asset's own pivot: (x, y, z) is where its origin goes
        mesh.location = (x, y, z); bpy.context.view_layer.update()
        if parent: mesh.parent = parent
        PROPS.append((mesh, collide, "RAW")); return mesh
    mn, mx = world_bounds(mesh); c = (mn + mx) / 2
    dx = (x - c.x) if x is not None else (xmin - mn.x) if xmin is not None else (xmax - mx.x)
    dy = (y - c.y) if y is not None else (ymin - mn.y) if ymin is not None else (ymax - mx.y)
    if on_surface:
        mesh.hide_set(True)
        z = surface_z(c.x + dx, c.y + dy)
        mesh.hide_set(False)
    mesh.location = (dx, dy, z - mn.z)
    bpy.context.view_layer.update()
    if parent: mesh.parent = parent
    PROPS.append((mesh, collide, stack_on))
    return mesh


def build():
    clear_scene()
    arch = PACK_ROOT / "Stairwell_Architecture"
    floor = plain_mat("BedroomSubfloor", (0.16, 0.12, 0.09), 0.9)
    wall = plain_mat("BedroomPlaster", (0.58, 0.56, 0.49), 0.95)
    bpy.ops.object.empty_add(type="PLAIN_AXES"); root = bpy.context.active_object; root.name = "Bedroom"
    build_shell(root, floor, wall)
    W, E, N, S = -INNER + GAP, INNER - GAP, INNER - GAP, -INNER + GAP
    P = lambda *a, **k: prop(*a, parent=root, **k)

    # Parquet: 6 x 6 pack floor tiles laid just above the Floor slab (visual only).
    for i in range(6):
        for j in range(6):
            P("Stairwell_Architecture", "SM_Floor_Parquet_2m", f"FloorTile_{i}{j}", 90 * ((i * 7 + j * 3) % 4),
              x=-5.0 + 2 * i, y=-5.0 + 2 * j, z=0.002, collide=False, raw=True,
              strip_above=0.028)  # drop raised loose boards so floor props sit flat
    # Wallpaper: two pack wall panels per wall run, plane 4 mm off the wall face,
    # squashed to the 2.4 m ceiling; flaps that stick out are stripped.
    seg = (INNER - DOOR_W / 2) / 2      # 2.21 m
    for side, yaw in (("N", 0), ("S", 180), ("E", -90), ("W", 90)):
        for k, c in enumerate((-INNER + seg / 2, -INNER + 1.5 * seg, INNER - 1.5 * seg, INNER - seg / 2)):
            f = INNER - 0.004
            xy = {"N": (c, f), "S": (c, -f), "E": (f, c), "W": (-f, c)}[side]
            P("Stairwell_Architecture", "SM_Wall_Wallpaper_A", f"Wallpaper_{side}{k}", yaw, x=xy[0], y=xy[1], z=0.0,
              collide=False, raw=True, sx=seg / 2.0, sz=WALL_H / 2.7, strip_front=-0.03)

    # Baseboards along every wall run (NoCol trim), stretched to the run.
    run = INNER - DOOR_W / 2           # 4.42 m from doorway jamb to corner
    mid = (INNER + DOOR_W / 2) / 2
    bb = ("Stairwell_Architecture", "SM_Baseboard_2m")
    for i, sgn in enumerate((-1, 1)):
        P(*bb, f"Baseboard_N{i}", 0, x=sgn * mid, ymax=INNER, collide=False, sx=run / 2.0)
        P(*bb, f"Baseboard_S{i}", 180, x=sgn * mid, ymin=-INNER, collide=False, sx=run / 2.0)
        P(*bb, f"Baseboard_E{i}", -90, xmax=INNER, y=sgn * mid, collide=False, sx=run / 2.0)
        P(*bb, f"Baseboard_W{i}", 90, xmin=-INNER, y=sgn * mid, collide=False, sx=run / 2.0)
    BB = 0.04   # baseboard depth: furniture backs sit just proud of it
    Wb, Eb, Nb, Sb = W + BB, E - BB, N - BB, S + BB
    FZ = 0.022  # parquet plank tops (2 cm boards + 2 mm lift)

    # NW: the sleeping corner. Bare-spring bed, headboard on the north wall;
    # its stained mattress dragged off onto the floor beside it.
    P("Bedroom", "SM_Bed_Double_Wooden", "Bed", 0, x=-3.85, ymax=Nb, z=FZ)
    P("Bedroom", "SM_Nightstand", "NightstandL", 0, xmax=-4.68, ymax=Nb, z=FZ)
    P("Bedroom", "SM_Nightstand", "NightstandR", -8, xmin=-3.0, ymax=Nb - 0.04, z=FZ)
    P("Bedroom", "SM_AlarmClock_TwinBell", "AlarmClock", 160, x=-4.98, y=5.22, on_surface=True, collide=False, stack_on="NightstandL")
    P("Bedroom", "SM_Mattress_Stained", "Mattress", 88, x=-3.9, ymin=1.93, collide=False, z=FZ)
    P("LivingRoom", "SM_Rug_Wall", "WallRug", 90, xmin=W, y=3.15, z=0.75, collide=False)
    P("Abandonment", "SM_GasMask", "GasMask", 35, x=-2.35, y=3.3, collide=False, z=FZ)

    # NE: packing in a hurry. Wardrobe hanging open, hangers dropped, open
    # suitcase on the floor, coat rack in the corner, the second case by the wall.
    P("LivingRoom", "SM_WallUnit_Wardrobe", "Wardrobe", 0, x=3.05, ymax=Nb, z=FZ)
    P("Bedroom", "SM_CoatRack_Standing", "CoatRack", 20, xmax=Eb - 0.05, ymax=Nb - 0.05, z=FZ)
    P("Bedroom", "SM_Hanger_Wire", "Hanger1", 15, x=3.0, y=4.35, collide=False, z=FZ)
    P("Bedroom", "SM_Hanger_Wire", "Hanger2", -50, x=3.7, y=3.85, collide=False, z=FZ)
    P("LivingRoom", "SM_Rug_Floor", "FloorRug", -6, x=3.25, y=2.95, collide=False, z=FZ)
    P("Bedroom", "SM_Suitcase_Open", "SuitcaseOpen", 200, x=4.45, y=4.1, collide=False, z=FZ)
    P("Bedroom", "SM_Suitcase_Old", "Suitcase", -90, xmax=Eb, y=2.7, z=FZ)
    P("Hallway", "SM_LightSwitch_Socket", "LightSwitch", -90, xmax=INNER, y=2.15, z=0.72, collide=False)

    # SE: dresser with the cracked mirror on the east wall, a drawer yanked out
    # and dumped, glass on the floor, photos left on top.
    P("Bedroom", "SM_Dresser_Mirror", "Dresser", -90, xmax=Eb, y=-3.6, z=FZ)
    P("LivingRoom", "SM_PhotoFrames_Set", "PhotoFrames", -100, x=5.15, y=-3.95, on_surface=True, collide=False, stack_on="Dresser")
    P("Abandonment", "SM_Drawer_Fallen", "DrawerFallen", -75, x=4.15, y=-3.6, collide=False, z=FZ)
    P("Abandonment", "SM_GlassShards", "GlassShards", 20, x=4.25, y=-2.48, collide=False, z=FZ)
    P("Abandonment", "SM_PhotoAlbum", "PhotoAlbum", 130, x=3.2, y=-4.6, collide=False, z=FZ)

    # SW: chores interrupted. Ironing board on the south wall, the iron knocked
    # to the floor, a broken chair, peeled wallpaper and old newspapers.
    P("Bedroom", "SM_IroningBoard", "IroningBoard", 180, x=-3.05, ymin=Sb + 0.05, z=FZ)
    P("Bedroom", "SM_Iron_Electric", "Iron", 205, x=-3.0, y=-4.55, collide=False, z=FZ)
    P("Abandonment", "SM_Chair_Broken", "ChairBroken", 60, x=-3.0, y=-3.85, collide=False, z=FZ)
    P("Abandonment", "SM_Wallpaper_Strips", "WallpaperStrips", 90, xmin=W + 0.02, y=-3.3, collide=False, z=FZ)
    P("Abandonment", "SM_Newspaper_Stack", "Newspapers", -20, x=-2.9, y=-2.75, collide=False, z=FZ)
    P("Abandonment", "SM_Debris_Pile", "Debris", 40, x=-4.9, y=-4.95, collide=False, z=FZ)

    # Bare bulb in the middle of the ceiling (above head height).
    P("Stairwell_Architecture", "SM_CeilingLamp_Bare", "CeilingLamp", 0, x=0.0, y=0.0, z=WALL_H - 0.63, collide=False)
    return root


def check():
    problems = []
    boxes = {o.name: world_bounds(o) for o, _, _ in PROPS}
    skip_cross = {"NoCol_CeilingLamp"}
    for o, col, _ in PROPS:
        mn, mx = boxes[o.name]
        if o.name.startswith(("NoCol_Baseboard", "NoCol_FloorTile", "NoCol_Wallpaper_")): continue
        if mn.x < -INNER - 1e-3 or mx.x > INNER + 1e-3 or mn.y < -INNER - 1e-3 or mx.y > INNER + 1e-3:
            problems.append(f"{o.name} pokes into a wall {tuple(round(v,2) for v in mn)} {tuple(round(v,2) for v in mx)}")
        if o.name not in skip_cross and (min(abs(mn.x), abs(mx.x)) < CLEAR or mn.x * mx.x < 0
                                         or min(abs(mn.y), abs(mx.y)) < CLEAR or mn.y * mx.y < 0):
            problems.append(f"{o.name} inside doorway cross")
        if mn.z < -0.02: problems.append(f"{o.name} below floor {mn.z:.3f}")
    items = [(o, s) for o, c, s in PROPS if not o.name.startswith(("NoCol_FloorTile", "NoCol_Wallpaper_", "NoCol_Baseboard", "NoCol_LightSwitch", "NoCol_WallRug", "NoCol_FloorRug"))]
    for i, (a, sa) in enumerate(items):
        for b, sb in items[i + 1:]:
            if sa and sa in b.name or sb and sb in a.name: continue
            amn, amx = boxes[a.name]; bmn, bmx = boxes[b.name]
            ov = [min(amx[k], bmx[k]) - max(amn[k], bmn[k]) for k in range(3)]
            if min(ov) > 0.01:
                problems.append(f"overlap {a.name} x {b.name} by {tuple(round(v,2) for v in ov)}")
    for o, _, _ in PROPS:
        mn, mx = boxes[o.name]
        print(f"PROP {o.name:24s} min {tuple(round(v,2) for v in mn)} max {tuple(round(v,2) for v in mx)}")
    for p in problems: print("PROBLEM", p)
    return problems


def export(root):
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for c in root.children_recursive: c.select_set(True)
    OUT_GLB.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(OUT_GLB), export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True,
                              # JPEG keeps the module under GitHub's 100 MB file limit
                              export_image_format="JPEG", export_jpeg_quality=90)


if __name__ == "__main__":
    r = build()
    check()
    export(r)
    blend = os.environ.get("BLEND_OUT")
    if blend: bpy.ops.wm.save_as_mainfile(filepath=blend)
