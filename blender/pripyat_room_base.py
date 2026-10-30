"""
Shared base for the decorated Nuclear Winter room tiles built from the Pripyat
Apartment pack (blender/PripyatApartment_FBX_PBR/).

Each build_<room>_decorated.py imports this module, lays the pack floor /
wallpaper / baseboards, places pack props in the four corner quadrants and
exports godot/assets/rooms/room_<room>_decorated.glb.

Tile contract (same as build_rooms.py / MapGenerator.gd): 12 m tile, 2.4 m
walls 0.28 m thick, 2.6 x 2.1 m doorway centred on every wall, Plug_<side>
fillers, NoCol_ prefix for meshes that must not get a collider. Props stay out
of the doorway cross (|x| or |y| < 1.9 m) so every doorway stays walkable.

Blender axes: +Y = north (Godot -Z), +X = east. Pack props face -Y, back +Y.
Wall yaw: N 0, S 180, E -90, W +90.

Env overrides: PRIPYAT_PACK (pack folder), ROOM_OUT (glb path), BLEND_OUT
(optional .blend dump).
"""
from __future__ import annotations
import importlib.util, math, os, sys
from pathlib import Path
import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
PACK_ROOT = Path(os.environ.get("PRIPYAT_PACK", HERE / "PripyatApartment_FBX_PBR"))

TILE = 12.0; HALF = TILE / 2; WALL_H = 2.4; WALL_T = 0.28
DOOR_W = 2.6; DOOR_H = 2.1; SIDES = ("N", "S", "E", "W")
INNER = HALF - WALL_T          # 5.72 interior face
GAP = 0.02                     # clearance from wall faces
CLEAR = DOOR_W * 0.5 + 0.6     # 1.9 doorway cross half-width
W, E, N, S = -INNER + GAP, INNER - GAP, INNER - GAP, -INNER + GAP
BB = 0.04                      # baseboard depth: furniture backs sit just proud of it
Wb, Eb, Nb, Sb = W + BB, E - BB, N - BB, S + BB
FZ = 0.022                     # top of the floor tiles; floor props stand here
ARCH = "Stairwell_Architecture"
WALL_WALK = {"N": 0, "S": 180, "E": -90, "W": 90}


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _MATS.clear(); _MESH_CACHE.clear(); PROPS.clear(); OBSTACLES.clear()


# ---------------------------------------------------------------- materials
_MATS = {}


def pbr_mat(name, folder: Path, stem: str):
    """One material per asset (shared by every instance) so the glTF exporter
    packs each texture once."""
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


def plain_mat(name, srgb, rough, emit=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    b.inputs["Base Color"].default_value = (*lin, 1); b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*lin, 1); b.inputs["Emission Strength"].default_value = emit
    return m


def subfloor_mat(): return plain_mat("Subfloor", (0.16, 0.12, 0.09), 0.9)
def plaster_mat(): return plain_mat("Plaster", (0.58, 0.56, 0.49), 0.95)


def box_uv(obj, tile_m=2.0):
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
    build_walls(root, wall_mat)


def build_walls(root, wall_mat):
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
    """Delete loose parts reaching past `limit` on `axis` (below or above)."""
    import bmesh
    bm = bmesh.new(); bm.from_mesh(obj.data); bm.verts.ensure_lookup_table()
    seen = set(); kill = []
    for v in bm.verts:
        if v.index in seen: continue
        stack = [v]; island = []; seen.add(v.index)
        while stack:
            cur = stack.pop(); island.append(cur)
            for e in cur.link_edges:
                o = e.other_vert(cur)
                if o.index not in seen: seen.add(o.index); stack.append(o)
        vals = [p.co[axis] for p in island]
        if (min(vals) < limit) if below else (max(vals) > limit): kill.extend(island)
    bmesh.ops.delete(bm, geom=kill, context="VERTS"); bm.to_mesh(obj.data); bm.free()


PROPS = []      # (obj, collide, stack_on)
OBSTACLES = []  # kept procedural meshes (stairs, tank, valve...) the props must avoid
_MESH_CACHE = {}


def world_bounds(o):
    vs = [o.matrix_world @ v.co for v in o.data.vertices]
    return (Vector([min(v[i] for v in vs) for i in range(3)]),
            Vector([max(v[i] for v in vs) for i in range(3)]))


def surface_z(x, y, from_z=WALL_H - 0.05):
    dg = bpy.context.evaluated_depsgraph_get()
    hit, loc, *_ = bpy.context.scene.ray_cast(dg, Vector((x, y, from_z)), Vector((0, 0, -1)))
    return loc.z if hit else 0.0


def _import_mesh(cat, asset, strip_front, strip_above):
    """Import (or reuse) a pack mesh with its FBX axis transform baked in. Repeat
    instances share mesh data so the GLB stores the geometry once."""
    key = (cat, asset, strip_front, strip_above)
    if key in _MESH_CACHE:
        o = bpy.data.objects.new(asset, _MESH_CACHE[key]); bpy.context.scene.collection.objects.link(o)
        return o
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
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if strip_front is not None: strip_islands(mesh, strip_front)
    if strip_above is not None: strip_islands(mesh, strip_above, axis=2, below=False)
    pbr = pbr_mat(f"M_{asset[3:]}", folder, asset[3:])
    for slot in mesh.material_slots:
        if slot.material and "Glass" in slot.material.name:
            b = slot.material.node_tree.nodes.get("Principled BSDF")
            if b:
                b.inputs["Base Color"].default_value = (0.7, 0.72, 0.7, 1); b.inputs["Roughness"].default_value = 0.08
                b.inputs["Alpha"].default_value = 0.25; slot.material.blend_method = "BLEND"
        else:
            slot.material = pbr
    _MESH_CACHE[key] = mesh.data
    return mesh


def prop(cat, asset, name, yaw=0.0, *, x=None, y=None, xmin=None, xmax=None, ymin=None, ymax=None,
         z=0.0, on_surface=False, tilt=(0.0, 0.0), collide=True, scale=1.0, sx=1.0, sy=1.0, sz=1.0,
         parent=None, stack_on=None, raw=False, strip_front=None, strip_above=None):
    """Place one pack prop. Rotation/scale live on the object (mesh data is
    shared). Anchors the rotated world AABB: x/y = centre, xmin..ymax = edges,
    z = bottom (or the surface under the centre when on_surface). raw=True puts
    the asset's own origin at (x, y, z)."""
    mesh = _import_mesh(cat, asset, strip_front, strip_above)
    mesh.name = name if collide else f"NoCol_{name}"
    mesh.rotation_euler = (math.radians(tilt[0]), math.radians(tilt[1]), math.radians(yaw))
    mesh.scale = (scale * sx, scale * sy, scale * sz)
    mesh.location = (0, 0, 0)
    bpy.context.view_layer.update()
    if raw:
        mesh.location = (x, y, z); bpy.context.view_layer.update()
        if parent: mesh.parent = parent
        PROPS.append((mesh, collide, "RAW")); return mesh
    mn, mx = world_bounds(mesh); c = (mn + mx) / 2
    dx = (x - c.x) if x is not None else (xmin - mn.x) if xmin is not None else (xmax - mx.x)
    dy = (y - c.y) if y is not None else (ymin - mn.y) if ymin is not None else (ymax - mx.y)
    if on_surface:
        mesh.hide_set(True); z = surface_z(c.x + dx, c.y + dy); mesh.hide_set(False)
    mesh.location = (dx, dy, z - mn.z)
    bpy.context.view_layer.update()
    if parent: mesh.parent = parent
    PROPS.append((mesh, collide, stack_on))
    return mesh


# ---------------------------------------------------------------- surfaces
def floor_tiles(root, asset="SM_Floor_Parquet_2m", skip=lambda x, y: False, prefix="FloorTile", z=None):
    """6 x 6 pack floor tiles (visual only, NoCol) over the Floor slab."""
    for i in range(6):
        for j in range(6):
            x, y = -5.0 + 2 * i, -5.0 + 2 * j
            if skip(x, y): continue
            prop(ARCH, asset, f"{prefix}_{i}{j}", 90 * ((i * 7 + j * 3) % 4), x=x, y=y,
                     z=0.002, collide=False, raw=True, strip_above=0.028, parent=root)


def wallpaper(root, asset="SM_Wall_Wallpaper_A", sides=SIDES, h=WALL_H):
    """Two pack wall panels per wall run, 4 mm off the face, squashed to 2.4 m."""
    seg = (INNER - DOOR_W / 2) / 2      # 2.21 m
    cat = "Bathroom" if asset == "SM_Wall_Tiled_2m" else ARCH
    for side in sides:
        yaw = WALL_WALK[side]
        for k, c in enumerate((-INNER + seg / 2, -INNER + 1.5 * seg, INNER - 1.5 * seg, INNER - seg / 2)):
            f = INNER - 0.004
            xy = {"N": (c, f), "S": (c, -f), "E": (f, c), "W": (-f, c)}[side]
            prop(cat, asset, f"Wallpaper_{side}{k}", yaw, x=xy[0], y=xy[1], z=0.0, collide=False, raw=True,
                 sx=seg / 2.0, sz=h / 2.7, strip_front=-0.03, parent=root)


def baseboards(root, sides=SIDES):
    run = INNER - DOOR_W / 2; mid = (INNER + DOOR_W / 2) / 2
    bb = (ARCH, "SM_Baseboard_2m")
    for i, sgn in enumerate((-1, 1)):
        if "N" in sides: prop(*bb, f"Baseboard_N{i}", 0, x=sgn * mid, ymax=INNER, collide=False, sx=run / 2.0, parent=root)
        if "S" in sides: prop(*bb, f"Baseboard_S{i}", 180, x=sgn * mid, ymin=-INNER, collide=False, sx=run / 2.0, parent=root)
        if "E" in sides: prop(*bb, f"Baseboard_E{i}", -90, xmax=INNER, y=sgn * mid, collide=False, sx=run / 2.0, parent=root)
        if "W" in sides: prop(*bb, f"Baseboard_W{i}", 90, xmin=-INNER, y=sgn * mid, collide=False, sx=run / 2.0, parent=root)


# ---------------------------------------------------------------- legacy rooms
def load_legacy():
    """Import the repo's build_rooms.py (functional stairs / valve / pipes) with
    PACK_ROOT pointed at the same pack."""
    spec = importlib.util.spec_from_file_location("build_rooms", HERE / "build_rooms.py")
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    mod.PACK_ROOT = PACK_ROOT
    return mod


def strip_legacy_props(root):
    """Delete the legacy place_prop holders (empties carrying FBX children) so
    the decorated pass can place its own; functional empties are kept."""
    for o in list(root.children):
        if o.type == "EMPTY" and o.children:
            for c in list(o.children_recursive): bpy.data.objects.remove(c)
            bpy.data.objects.remove(o)


def legacy_bake_uv(root):
    """build_rooms.py textures shell cubes in object space; glTF needs UVs."""
    for o in root.children_recursive:
        if o.type == "MESH" and not o.data.uv_layers: box_uv(o)


# ---------------------------------------------------------------- checks
SKIP_PREFIX = ("NoCol_Baseboard", "NoCol_FloorTile", "NoCol_Wallpaper_", "NoCol_DebrisTile")
OVERLAP_SKIP = SKIP_PREFIX + ("NoCol_LightSwitch", "NoCol_WallRug", "NoCol_FloorRug", "NoCol_Doormat")


def check(cross_ok=("NoCol_CeilingLamp",), overlap_ok=()):
    problems = []
    boxes = {o.name: world_bounds(o) for o, _, _ in PROPS}
    for o in OBSTACLES: boxes[o.name] = world_bounds(o)
    for o, col, _ in PROPS:
        mn, mx = boxes[o.name]
        if o.name.startswith(SKIP_PREFIX): continue
        if mn.x < -INNER - 1e-3 or mx.x > INNER + 1e-3 or mn.y < -INNER - 1e-3 or mx.y > INNER + 1e-3:
            problems.append(f"{o.name} pokes into a wall {tuple(round(v,2) for v in mn)} {tuple(round(v,2) for v in mx)}")
        if not o.name.startswith(cross_ok) and (min(abs(mn.x), abs(mx.x)) < CLEAR or mn.x * mx.x < 0
                                                or min(abs(mn.y), abs(mx.y)) < CLEAR or mn.y * mx.y < 0):
            problems.append(f"{o.name} inside doorway cross")
        if mn.z < -0.02: problems.append(f"{o.name} below floor {mn.z:.3f}")
    items = [(o, s) for o, c, s in PROPS if not o.name.startswith(OVERLAP_SKIP)] + [(o, None) for o in OBSTACLES]
    for i, (a, sa) in enumerate(items):
        for b, sb in items[i + 1:]:
            if sa and sa in b.name or sb and sb in a.name: continue
            if a in OBSTACLES and b in OBSTACLES: continue   # authored legacy geometry
            if (a.name, b.name) in overlap_ok or (b.name, a.name) in overlap_ok: continue
            amn, amx = boxes[a.name]; bmn, bmx = boxes[b.name]
            ov = [min(amx[k], bmx[k]) - max(amn[k], bmn[k]) for k in range(3)]
            if min(ov) > 0.01:
                problems.append(f"overlap {a.name} x {b.name} by {tuple(round(v,2) for v in ov)}")
    for o, _, _ in PROPS:
        if o.name.startswith(SKIP_PREFIX): continue
        mn, mx = boxes[o.name]
        print(f"PROP {o.name:24s} min {tuple(round(v,2) for v in mn)} max {tuple(round(v,2) for v in mx)}")
    for p in problems: print("PROBLEM", p)
    print(f"CHECK {len(problems)} problems")
    return problems


# ---------------------------------------------------------------- export
def shrink_small_textures(limit_m=1.0, px=1024):
    """Props smaller than `limit_m` never fill the screen: cap their maps at 1K."""
    big = {}
    for o, _, _ in PROPS:
        mn, mx = world_bounds(o); d = max(mx - mn)
        for s in o.material_slots:
            if s.material: big[s.material.name] = max(big.get(s.material.name, 0), d)
    for m in bpy.data.materials:
        if m.name in big and big[m.name] < limit_m and m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image and max(n.image.size) > px:
                    n.image.scale(px, px)


def export(root, out_glb):
    out_glb = Path(os.environ.get("ROOM_OUT", out_glb))
    shrink_small_textures()
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for c in root.children_recursive: c.select_set(True)
    out_glb.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(out_glb), export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True,
                              export_image_format="JPEG", export_jpeg_quality=90)
    blend = os.environ.get("BLEND_OUT")
    if blend: bpy.ops.wm.save_as_mainfile(filepath=blend)
    print("WROTE", out_glb, out_glb.stat().st_size)


def legacy_room(builder_name):
    """Rebuild one functional room from build_rooms.py (stairs, valve, pipes
    keep their exact names and positions), drop its old pack props, swap the
    shell to plain subfloor / plaster (the pack tiles and wallpaper cover it)
    and register every kept procedural mesh as an obstacle for check()."""
    clear_scene()
    L = load_legacy()
    root = getattr(L, builder_name)()
    strip_legacy_props(root)
    legacy_bake_uv(root)
    sub, pla = subfloor_mat(), plaster_mat()
    for o in root.children_recursive:
        if o.type != "MESH": continue
        n = o.name
        if n.startswith("Floor"): o.data.materials[0] = sub
        elif n.startswith(("Wall_", "Plug_")): o.data.materials[0] = pla
        else: OBSTACLES.append(o)
    return root
