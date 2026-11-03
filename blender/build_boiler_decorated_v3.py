"""
Boiler tile v3 (room_boiler_decorated_v3.glb) = v2 + a bank of five rusty
lockers (CC0 Meshy community 'Rusty Locker', prepped by prep_rusty_locker.py
into godot/assets/props/RustyLocker.glb: 8k tris, 0.48 x 0.50 x 1.85 m).

Built on top of the exported v2 glb (v2 script/glb untouched). The bank
stands against the south wall, west of the S doorway (x -1.97 .. -4.4),
doors facing north. To make room, three NoCol_ decor pieces move:
MeterPanel (wall-mounted) slides west along the south wall to x = -5.05,
and the floor clutter Glass / DebrisPile shift north out of the footprint.
Lockers keep collider-friendly names (Locker_1..5, no NoCol_ prefix).

Run:  blender -b -P blender/build_boiler_decorated_v3.py
Env:  V2_GLB, LOCKER_GLB, ROOM_OUT override paths.
"""
import math, os, random
from pathlib import Path
import bpy
from mathutils import Vector

REPO = Path(__file__).resolve().parent.parent
V2 = Path(os.environ.get("V2_GLB", REPO / "godot/assets/rooms/room_boiler_decorated_v2.glb"))
LOCKER = Path(os.environ.get("LOCKER_GLB", REPO / "godot/assets/props/RustyLocker.glb"))
OUT = Path(os.environ.get("ROOM_OUT", REPO / "godot/assets/rooms/room_boiler_decorated_v3.glb"))
INNER, CLEAR, FZ = 5.72, 1.9, 0.022
SB = -5.62   # front face of the south baseboard (overridden from the glb below)
N_LOCKERS, PITCH, X0 = 5, 0.53, -2.24   # first locker centre, marching west
random.seed(1986)


def bounds(o):
    cs = [o.matrix_world @ Vector(c) for c in o.bound_box]
    return (Vector([min(c[i] for c in cs) for i in range(3)]), Vector([max(c[i] for c in cs) for i in range(3)]))


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(V2))
    root = bpy.data.objects["Boiler"]
    ob = bpy.data.objects
    ob["NoCol_MeterPanel"].location.x += -5.05 - (-3.0)
    ob["NoCol_Glass"].location.y += 0.75
    ob["NoCol_Glass"].location.x -= 0.08
    ob["NoCol_DebrisPile"].location.y += 0.55
    ob["NoCol_DebrisPile"].location.x += -0.25
    global SB
    SB = max(bounds(o)[1].y for o in ob if o.name.startswith("NoCol_Baseboard_S"))
    before = set(ob)
    bpy.ops.import_scene.gltf(filepath=str(LOCKER))
    src = [o for o in ob if o not in before and o.type == "MESH"][0]
    data = src.data; bpy.data.objects.remove(src)
    lockers = []
    for i in range(N_LOCKERS):
        o = bpy.data.objects.new(f"Locker_{i + 1}", data)
        bpy.context.scene.collection.objects.link(o)
        yaw = 180 + random.uniform(-3, 3)                 # doors face +Y (into room)
        o.rotation_euler = (0, 0, math.radians(yaw))
        o.location = (X0 - i * PITCH + random.uniform(-0.015, 0.015), 0, FZ)
        bpy.context.view_layer.update()
        mn, mx = bounds(o)
        o.location.y += (SB + 0.01 + random.uniform(0, 0.05)) - mn.y   # back to wall + gap
        bpy.context.view_layer.update()
        o.parent = root; o.matrix_parent_inverse = root.matrix_world.inverted()
        lockers.append(o)
    bpy.context.view_layer.update()
    return root, lockers


def check(root, lockers):
    probs = []
    others = [o for o in bpy.data.objects if o.type == "MESH" and o not in lockers
              and not o.name.startswith(("Floor", "FloorTile", "Baseboard", "Wallpaper"))
              or o.name.startswith("NoCol_Baseboard_S")]
    others = [o for o in others if not (o.name.startswith("NoCol_Wallpaper"))]
    for o in [*lockers, ob_("NoCol_MeterPanel"), ob_("NoCol_Glass"), ob_("NoCol_DebrisPile")]:
        mn, mx = bounds(o)
        print(f"PROP {o.name:18s} min {tuple(round(v,3) for v in mn)} max {tuple(round(v,3) for v in mx)}")
        if mn.x < -INNER or mx.x > INNER or mn.y < -INNER or mx.y > INNER: probs.append(f"{o.name} in wall")
        if min(abs(mn.x), abs(mx.x)) < CLEAR and mn.x * mx.x > 0 and mx.x > -CLEAR and mn.x < CLEAR:
            probs.append(f"{o.name} in doorway cross")
        targets = others + lockers if o in lockers else others
        for b in targets:
            if b is o or (o in lockers and b in lockers and b.name < o.name): continue
            bmn, bmx = bounds(b)
            ov = [min(mx[k], bmx[k]) - max(mn[k], bmn[k]) for k in range(3)]
            if min(ov) > 0.002: probs.append(f"overlap {o.name} x {b.name} {[round(v,3) for v in ov]}")
    for p in probs: print("PROBLEM", p)
    print(f"CHECK {len(probs)} problems")


def ob_(n): return bpy.data.objects[n]


if __name__ == "__main__":
    root, lockers = build()
    check(root, lockers)
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for c in root.children_recursive: c.select_set(True)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(OUT), export_format="GLB", use_selection=True,
                              export_image_format="JPEG", export_jpeg_quality=90)
    print("WROTE", OUT, OUT.stat().st_size)
