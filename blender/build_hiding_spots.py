"""
Hiding-spot room variants (fridge / wardrobes) for Nuclear Winter.

Loads each finished decorated room glb, backs the hiding prop against a wall
(front facing into the room, yaw jitter within +/-2 deg), runs an AABB overlap
+ doorway check against every existing mesh, and exports a NEW versioned glb
(originals untouched). Props are named HideSpot_* (no NoCol_ prefix -> colliders).
Also writes top-down + close-up previews.

Run:   blender -b -P blender/build_hiding_spots.py
Env:   ROOMS_DIR (source room glbs, default godot/assets/rooms),
       PROPS_DIR (default godot/assets/props), OUT_DIR (default ROOMS_DIR),
       PREVIEW_DIR (default blender/hiding_placement_previews), NO_RENDER=1
"""
import math, os, random
from pathlib import Path
import bpy
from mathutils import Vector

REPO = Path(__file__).resolve().parent.parent
ROOMS = Path(os.environ.get("ROOMS_DIR", REPO / "godot/assets/rooms"))
PROPS = Path(os.environ.get("PROPS_DIR", REPO / "godot/assets/props"))
OUTD = Path(os.environ.get("OUT_DIR", ROOMS))
PREV = Path(os.environ.get("PREVIEW_DIR", REPO / "blender/hiding_placement_previews"))
INNER, DOOR, FZ = 5.72, 1.9, 0.02
# front faces -Y by default; yaw that turns it to face into the room from each wall
WALL_YAW = {"N": 0.0, "S": 180.0, "E": -90.0, "W": 90.0}

# room key: (source glb, output glb, [(prop glb, node name, wall, coord along wall)])
# coord along wall = centre x for N/S walls, centre y for E/W walls.
ROOMS_SPEC = {
    "storage": ("room_storage_decorated.glb", "room_storage_decorated_v2.glb",
                [("SovietFridge.glb", "HideSpot_Fridge", "E", -5.08)]),      # SE corner, just south of the counter run
    "bedroom": ("room_bedroom_decorated.glb", "room_bedroom_decorated_v2.glb",
                [("OldWardrobe.glb", "HideSpot_Wardrobe_1", "W", -3.00)]),   # west wall, south of W door
    "office": ("room_office_decorated.glb", "room_office_decorated_v2.glb",
               [("WoodenWardrobe.glb", "HideSpot_Wardrobe_1", "N", -2.62)]),  # north wall, between desk and N door
    "living_room": ("room_living_room_decorated.glb", "room_living_room_decorated_v2.glb",
                    [("WoodenWardrobe.glb", "HideSpot_Wardrobe_1", "W", -2.52)]),  # west wall, south of W door
}
# Library: every wall run is already lined with colliding bookcases (Antiquarian/
# Elegance/Bookcase_*), so no wardrobe fits against a wall without removing one.
random.seed(1986)


def bounds(o):
    cs = [o.matrix_world @ Vector(c) for c in o.bound_box]
    return (Vector([min(c[i] for c in cs) for i in range(3)]), Vector([max(c[i] for c in cs) for i in range(3)]))


def skip(o):
    n = o.name
    return n == "Floor" or n.startswith("Wall_") or "FloorTile" in n or "Wallpaper" in n


def back_plane(wall):
    """Inner face of whatever sits on the wall surface (baseboards) -> distance from centre."""
    d = INNER
    for o in bpy.data.objects:
        if o.type != "MESH" or "Baseboard" not in o.name: continue
        mn, mx = bounds(o)
        if wall == "N" and mn.y > 5: d = min(d, mn.y)
        if wall == "S" and mx.y < -5: d = min(d, -mx.y)
        if wall == "E" and mn.x > 5: d = min(d, mn.x)
        if wall == "W" and mx.x < -5: d = min(d, -mx.x)
    return d


def place(root, prop_path, name, wall, along):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(prop_path))
    new = [o for o in bpy.data.objects if o not in before]
    src = [o for o in new if o.type == "MESH"][0]
    data = src.data
    for o in new: bpy.data.objects.remove(o)
    o = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(o)
    o.rotation_euler = (0, 0, math.radians(WALL_YAW[wall] + random.uniform(-2, 2)))
    o.location = (along, 0, FZ) if wall in "NS" else (0, along, FZ)
    bpy.context.view_layer.update()
    mn, mx = bounds(o)
    b = back_plane(wall) - 0.01
    if wall == "N": o.location.y += b - mx.y
    if wall == "S": o.location.y += -b - mn.y
    if wall == "E": o.location.x += b - mx.x
    if wall == "W": o.location.x += -b - mn.x
    bpy.context.view_layer.update()
    o.parent = root; o.matrix_parent_inverse = root.matrix_world.inverted()
    return o


def check(props):
    probs = []
    others = [o for o in bpy.data.objects if o.type == "MESH" and o not in props and not skip(o)]
    for o in props:
        mn, mx = bounds(o)
        print(f"PROP {o.name:22s} loc {tuple(round(v,3) for v in o.matrix_world.translation)} "
              f"yaw {math.degrees(o.matrix_world.to_euler().z):.2f}  min {tuple(round(v,3) for v in mn)} max {tuple(round(v,3) for v in mx)}")
        if mn.x < -INNER or mx.x > INNER or mn.y < -INNER or mx.y > INNER: probs.append(f"{o.name} in wall")
        for a, b in ((0, 1), (1, 0)):   # doorway corridors
            if mn[a] < DOOR and mx[a] > -DOOR and (mx[b] > INNER - 1.9 or mn[b] < -INNER + 1.9):
                probs.append(f"{o.name} in doorway")
        for t in others:
            tmn, tmx = bounds(t)
            ov = [min(mx[k], tmx[k]) - max(mn[k], tmn[k]) for k in range(3)]
            if min(ov) > 0.002: probs.append(f"overlap {o.name} x {t.name} {[round(v,3) for v in ov]}")
    for p in probs: print("PROBLEM", p)
    print(f"CHECK {len(probs)} problems")
    return probs


def render(key, props):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.color_type = "TEXTURE"
    sc.display.shading.light = "STUDIO"
    sc.render.resolution_x = sc.render.resolution_y = 1024
    hidden = [o for o in bpy.data.objects if o.type == "MESH" and bounds(o)[0].z > 2.0]
    PREV.mkdir(parents=True, exist_ok=True)
    cam = bpy.data.objects.new("PrevCam", bpy.data.cameras.new("PrevCam"))
    sc.collection.objects.link(cam); sc.camera = cam
    for h in hidden: h.hide_render = True
    cam.data.type = "ORTHO"; cam.data.ortho_scale = 12.6
    cam.location = (0, 0, 20); cam.rotation_euler = (0, 0, 0)
    sc.render.filepath = str(PREV / f"{key}_v2_top.png"); bpy.ops.render.render(write_still=True)
    cam.data.type = "PERSP"; cam.data.lens = 22
    for p in props:
        c = p.matrix_world.translation
        f = p.matrix_world.to_quaternion() @ Vector((0, -1, 0))  # front direction
        eye = c + f * 3.4 + Vector((0, 0, 1.6))
        cam.location = eye
        cam.rotation_euler = (c + Vector((0, 0, 0.9)) - eye).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = str(PREV / f"{key}_v2_{p.name}.png"); bpy.ops.render.render(write_still=True)
    for h in hidden: h.hide_render = False
    bpy.data.objects.remove(cam)


def build(key):
    src, out, items = ROOMS_SPEC[key]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(ROOMS / src))
    root = [o for o in bpy.data.objects if o.parent is None][0]
    props = [place(root, PROPS / p, n, w, a) for p, n, w, a in items]
    bpy.context.view_layer.update()
    probs = check(props)
    if probs: raise SystemExit(f"{key}: {len(probs)} placement problems, not exporting")
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for c in root.children_recursive: c.select_set(True)
    OUTD.mkdir(parents=True, exist_ok=True)
    o = OUTD / out
    assert o.resolve() != (ROOMS / src).resolve()
    bpy.ops.export_scene.gltf(filepath=str(o), export_format="GLB", use_selection=True,
                              export_image_format="JPEG", export_jpeg_quality=90)
    print("WROTE", o, o.stat().st_size)
    if not os.environ.get("NO_RENDER"): render(key, props)


if __name__ == "__main__":
    for k in os.environ.get("ROOMS_ONLY", ",".join(ROOMS_SPEC)).split(","):
        build(k)
