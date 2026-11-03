"""
Prep the CC0 Meshy 'Rusty Locker' (community post 019c1053-b0c4-719b-9f71-80c6089bc984)
as a game prop: decimate ~165k -> ~8k tris (collapse, UVs kept), scale to
0.48 W x 0.50 D x 1.85 H m (front -Y, origin bottom-centre), textures 1024 px.
Run: blender -b -P blender/prep_rusty_locker.py -- <src.glb> <out.glb>
"""
import bpy, sys, math
a = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = a[0], a[1]
TARGET_TRIS, W, D, H, TEX = 8000, 0.48, 0.50, 1.85, 1024
FRONT_YAW = float(a[2]) if len(a) > 2 else 0.0   # deg to turn the model so its doors face -Y
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
o = [o for o in bpy.data.objects if o.type == "MESH"][0]
mw = o.matrix_world.copy(); o.parent = None; o.matrix_world = mw
for x in list(bpy.data.objects):
    if x != o: bpy.data.objects.remove(x)
o.name = o.data.name = "RustyLocker"
bpy.context.view_layer.objects.active = o; o.select_set(True)
o.rotation_euler.z += math.radians(FRONT_YAW)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
d = o.modifiers.new("dec", "DECIMATE"); d.ratio = TARGET_TRIS / tris; d.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier=d.name)
dims = o.dimensions.copy()
o.scale = (W / dims.x, D / dims.y, H / dims.z)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
from mathutils import Vector
cs = [Vector(c) for c in o.bound_box]
mn = Vector([min(c[i] for c in cs) for i in range(3)]); mx = Vector([max(c[i] for c in cs) for i in range(3)])
off = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
o.data.transform(__import__("mathutils").Matrix.Translation(-off))
for i in bpy.data.images:
    if max(i.size) > TEX: i.scale(TEX, TEX)
bpy.ops.object.shade_smooth() if False else None
print("LOCKER tris", sum(len(p.vertices) - 2 for p in o.data.polygons), "dims", tuple(round(v, 3) for v in o.dimensions))
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True,
                          export_image_format="JPEG", export_jpeg_quality=90)
