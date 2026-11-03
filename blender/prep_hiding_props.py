"""
Prep CC0 Meshy hiding-spot props (Retro Fridge, Old Wardrobe, Wooden Wardrobe):
decimate to ~10k tris (collapse, UVs kept), origin bottom-centre, front -Y,
uniform scale to target height then widen/deepen to player-fit minimums
(non-uniform factors printed), textures 1024 px, preview render.
Run: blender -b -P prep_hiding_props.py -- <downloads_dir> <out_dir> [preview_dir]
"""
import bpy, sys, os, math
from mathutils import Vector, Matrix
a = sys.argv[sys.argv.index("--") + 1:]
SRC_DIR, OUT_DIR = a[0], a[1]
PREV = a[2] if len(a) > 2 else os.path.join(OUT_DIR, "hiding_props_previews")
os.makedirs(PREV, exist_ok=True)
TEX, TARGET = 1024, 10000
# name, src, height, min width, target depth (None=keep prop. but >=min_d), min depth, yaw deg
PROPS = [
 ("SovietFridge",  "Meshy_AI_Retro_Fridge_1103225226_texture.glb",    1.80, 0.70, None, 0.70, 0),
 ("OldWardrobe",   "Meshy_AI_Old_Wardrobe_1103225410_texture.glb",    2.00, 1.00, 0.60, 0.60, 0),
 ("WoodenWardrobe","Meshy_AI_Wooden_Wardrobe_1103225420_texture.glb", 2.00, 1.00, 0.60, 0.60, 0),
]
def tris(o): return sum(len(p.vertices) - 2 for p in o.data.polygons)
for name, src, H, MINW, TD, MIND, yaw in PROPS:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC_DIR, src))
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for m in meshes:
        mw = m.matrix_world.copy(); m.parent = None; m.matrix_world = mw
    for x in list(bpy.data.objects):
        if x.type != "MESH": bpy.data.objects.remove(x)
    bpy.ops.object.select_all(action="DESELECT")
    for m in meshes: m.select_set(True)
    o = meshes[0]; bpy.context.view_layer.objects.active = o
    if len(meshes) > 1: bpy.ops.object.join()
    o.name = o.data.name = name
    o.rotation_euler.z += math.radians(yaw)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    t0 = tris(o)
    d = o.modifiers.new("dec", "DECIMATE"); d.ratio = min(1, TARGET / t0); d.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=d.name)
    dm = o.dimensions.copy(); s = H / dm.z
    w, dp = dm.x * s, dm.y * s
    sx = max(1, MINW / w); sy = (TD / dp) if TD else max(1, MIND / dp)
    o.scale = (s * sx, s * sy, s)
    bpy.ops.object.transform_apply(scale=True)
    cs = [Vector(c) for c in o.bound_box]
    mn = Vector([min(c[i] for c in cs) for i in range(3)]); mx = Vector([max(c[i] for c in cs) for i in range(3)])
    o.data.transform(Matrix.Translation(-Vector(((mn.x+mx.x)/2, (mn.y+mx.y)/2, mn.z))))
    o.location = (0, 0, 0)
    for i in bpy.data.images:
        if max(i.size) > TEX: i.scale(TEX, TEX)
    print(f"PROP {name} src_tris {t0} tris {tris(o)} dims {tuple(round(v,3) for v in o.dimensions)} "
          f"nonuniform x{sx:.3f} y{sy:.3f} (rel. to uniform)")
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, name + ".glb"), export_format="GLB",
                              use_selection=True, export_image_format="JPEG", export_jpeg_quality=90)
    # preview: 3/4 front view (front = -Y)
    sc = bpy.context.scene; sc.render.engine = "BLENDER_EEVEE_NEXT"
    sc.render.resolution_x, sc.render.resolution_y = 800, 1000
    w = bpy.data.worlds.new("w"); sc.world = w; w.color = (0.25, 0.25, 0.28)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
    cam.location = (1.8, -3.6, H * 0.75)
    cam.rotation_euler = (Vector((0, 0, H/2)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    for loc, e in [((2, -3, 3), 800), ((-3, -2, 2), 300), ((0, 3, 3), 200)]:
        L = bpy.data.objects.new("l", bpy.data.lights.new("l", "POINT")); L.data.energy = e
        L.location = loc; sc.collection.objects.link(L)
    sc.render.filepath = os.path.join(PREV, name + ".png")
    bpy.ops.render.render(write_still=True)
