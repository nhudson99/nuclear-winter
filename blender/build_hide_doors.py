"""Nuclear Winter: split hiding-spot props into body + hinged doors (Blend).
Input: /workspace/meshyrooms/out/<Prop>.glb (origin bottom-centre, front = -Y).
Output: godot/assets/props/<Prop>_Doors.glb with child meshes Door / Door_L / Door_R
(pivot on hinge edge; +rot about local Z(Blender) == +Y(Godot) opens outward for hinge on +X,
-rot for hinge on -X; the clips already encode the correct sign), Interior (dark cavity),
and animations DoorOpen (0->95deg, 0.25s) and DoorBurst (slam with overshoot).
Run: blender -b -P build_hide_doors.py -- <repo_root>"""
import bpy, bmesh, math, sys, os
from mathutils import Vector, Matrix
REPO = sys.argv[sys.argv.index("--")+1] if "--" in sys.argv else "/workspace/nw"
SRC = "/workspace/meshyrooms/out"
OUT = os.path.join(REPO, "godot/assets/props"); PREV = os.path.join(REPO, "blender/hide_doors_previews")
os.makedirs(PREV, exist_ok=True)
# door rects: name, x0, x1, z0, z1, hinge side (+1 = +X, -1 = -X); front slab depth
PROPS = {
 "SovietFridge":  dict(depth=0.25, doors=[("Door", -0.40, 0.40, 0.46, 1.74, +1)]),
 "OldWardrobe":   dict(depth=0.10, doors=[("Door_L", -0.50, 0.0, 0.19, 1.95, -1), ("Door_R", 0.0, 0.50, 0.19, 1.95, +1)]),
 "WoodenWardrobe":dict(depth=0.08, doors=[("Door_L", -0.46, 0.0, 0.05, 1.95, -1), ("Door_R", 0.0, 0.46, 0.05, 1.95, +1)]),
 "RustyLocker":   dict(depth=0.06, doors=[("Door", -0.215, 0.215, 0.05, 1.80, +1)]),
}
FPS = 30
def dark_mat():
    m = bpy.data.materials.get("Interior_Dark") or bpy.data.materials.new("Interior_Dark")
    m.use_nodes = True; b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.02, 0.018, 0.016, 1); b.inputs["Roughness"].default_value = 1; b.inputs["Specular IOR Level"].default_value = 0
    return m
def tris(o): return sum(len(p.vertices)-2 for p in o.data.polygons)

report = []
for name, cfg in PROPS.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=f"{SRC}/{name}.glb")
    body = [o for o in bpy.data.objects if o.type == 'MESH'][0]
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    t0 = tris(body)
    ymin = min(v.co.y for v in body.data.vertices)
    dm = dark_mat(); body.data.materials.append(dm); DI = len(body.data.materials)-1
    doors = []
    for dname, x0, x1, z0, z1, hs in cfg["doors"]:
        bm = bmesh.new(); bm.from_mesh(body.data)
        # clean straight cuts along the door rectangle so the seam is not ragged
        for co, no in [((x0,0,0),(1,0,0)), ((x1,0,0),(1,0,0)), ((0,0,z0),(0,0,1)), ((0,0,z1),(0,0,1)), ((0,ymin+cfg['depth'],0),(0,1,0))]:
            ff = [f for f in bm.faces if f.calc_center_median().y < ymin + cfg['depth'] + 0.03]
            geom = list({e for f in ff for e in f.edges}) + ff + list({v for f in ff for v in f.verts})
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no)
        bm.faces.ensure_lookup_table()
        sel = [f for f in bm.faces if (c := f.calc_center_median()).y < ymin + cfg["depth"]
               and x0 <= c.x <= x1 and z0 <= c.z <= z1 and f.normal.y < 0.3]
        dbm = bmesh.new(); vmap = {}
        uvs = bm.loops.layers.uv.active; duv = dbm.loops.layers.uv.new("UVMap") if uvs else None
        for f in sel:
            vs = []
            for v in f.verts:
                if v not in vmap: vmap[v] = dbm.verts.new(v.co)
                vs.append(vmap[v])
            try: nf = dbm.faces.new(vs)
            except ValueError: continue
            nf.material_index = f.material_index; nf.smooth = f.smooth
            if uvs:
                for l, ol in zip(nf.loops, f.loops): l[duv].uv = ol[uvs].uv
        bmesh.ops.delete(bm, geom=sel, context='FACES')
        bm.to_mesh(body.data); bm.free()
        # door back panel (dark quad facing +Y) behind the door skin
        yb = max(v.co.y for v in dbm.verts) + 0.005
        q = [dbm.verts.new((x, yb, z)) for x, z in [(x0, z0), (x0, z1), (x1, z1), (x1, z0)]]
        bf = dbm.faces.new(q); bf.material_index = 1
        me = bpy.data.meshes.new(dname); dbm.to_mesh(me); dbm.free()
        for m in body.data.materials[:1]: me.materials.append(m)
        me.materials.append(dm)
        hinge = Vector((x1 if hs > 0 else x0, ymin, 0))
        me.transform(Matrix.Translation(-hinge))
        d = bpy.data.objects.new(dname, me); bpy.context.collection.objects.link(d)
        d.location = hinge; d.parent = body
        doors.append((d, hs, len(sel)))
    # Interior: dark box cavity behind the opening(s), normals facing in/toward viewer
    X0 = min(c[1] for c in cfg["doors"]); X1 = max(c[2] for c in cfg["doors"])
    Z0 = min(c[3] for c in cfg["doors"]); Z1 = max(c[4] for c in cfg["doors"])
    yf = ymin + cfg['depth'] - 0.01
    from mathutils.bvhtree import BVHTree
    tree = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())
    hits = []
    for fx in (0.25, 0.5, 0.75):
        for fz in (0.25, 0.5, 0.75):
            p = Vector((X0+(X1-X0)*fx, yf, Z0+(Z1-Z0)*fz)); r = tree.ray_cast(p, Vector((0,1,0)), 2.0)
            if r[0] is not None: hits.append(r[0].y)
    yk = (min(hits) if hits else -ymin) - 0.01
    # drop hidden body faces inside the cavity (Meshy inner layers) so the interior reads dark
    X0_ = min(c[1] for c in cfg["doors"]); X1_ = max(c[2] for c in cfg["doors"])
    Z0_ = min(c[3] for c in cfg["doors"]); Z1_ = max(c[4] for c in cfg["doors"])
    bm = bmesh.new(); bm.from_mesh(body.data)
    inner = [f for f in bm.faces if (c := f.calc_center_median()) and X0_+0.01 < c.x < X1_-0.01
             and Z0_+0.01 < c.z < Z1_-0.01 and ymin + cfg["depth"] - 0.005 < c.y < yk + 0.005]
    bmesh.ops.delete(bm, geom=inner, context='FACES'); bm.to_mesh(body.data); bm.free()
    print("CULLED", name, len(inner))
    print("BACK", name, round(yk,3), [round(h,3) for h in hits])
    ib = bmesh.new()
    P = lambda x, y, z: ib.verts.new((x, y, z))
    a,b_,c,d_ = P(X0,yf,Z0),P(X1,yf,Z0),P(X1,yf,Z1),P(X0,yf,Z1)
    e,f,g,h = P(X0,yk,Z0),P(X1,yk,Z0),P(X1,yk,Z1),P(X0,yk,Z1)
    for quad in [(e,h,g,f),(a,e,f,b_),(d_,c,g,h),(a,d_,h,e),(b_,f,g,c)]: ib.faces.new(quad)
    bmesh.ops.recalc_face_normals(ib, faces=ib.faces[:]); bmesh.ops.reverse_faces(ib, faces=ib.faces[:])
    ime = bpy.data.meshes.new("Interior"); ib.to_mesh(ime); ib.free(); ime.materials.append(dm)
    io = bpy.data.objects.new("Interior", ime); bpy.context.collection.objects.link(io); io.parent = body
    # animations as NLA tracks (merged per name on export)
    def anim(d, hs, track, keys):
        d.animation_data_create()
        act = bpy.data.actions.new(f"{d.name}_{track}")
        fc = act.fcurves.new("rotation_euler", index=2)
        for t, deg in keys:
            k = fc.keyframe_points.insert(t*FPS + 1, math.radians(deg)*hs)
            k.interpolation = 'BEZIER'
        d.animation_data.action = act
        tr = d.animation_data.nla_tracks.new(); tr.name = track
        tr.strips.new(track, 1, act); d.animation_data.action = None
    for d, hs, _ in doors:
        anim(d, hs, "DoorOpen", [(0, 0), (0.25, 95)])
        anim(d, hs, "DoorBurst", [(0, 0), (0.08, 118), (0.18, 88), (0.28, 99), (0.4, 95)])
    total = tris(body) + sum(tris(d) for d, _, _ in doors) + tris(io)
    report.append(f"{name}: src {t0} tris -> {total} tris (body {tris(body)}, " +
                  ", ".join(f"{d.name} {tris(d)} [{n} faces cut, hinge {'+X' if hs>0 else '-X'}]" for d, hs, n in doors) +
                  f", Interior {tris(io)})")
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, f"{name}_Doors.glb"), export_format="GLB",
        use_selection=True, export_animations=True, export_animation_mode='NLA_TRACKS',
        export_image_format="JPEG", export_jpeg_quality=90)
    # preview: doors open (frame of DoorOpen end)
    for d, hs, _ in doors:
        d.animation_data.nla_tracks.clear() if False else None
        for tr in d.animation_data.nla_tracks: tr.mute = True
        d.rotation_euler.z = math.radians(95)*hs
    sc = bpy.context.scene; sc.render.engine = "BLENDER_EEVEE_NEXT"
    sc.render.resolution_x, sc.render.resolution_y = 800, 1000
    w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.25, 0.25, 0.28, 1)
    H = max(v.co.z for v in body.data.vertices)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
    cam.location = (1.6, -3.8, H*0.7)
    cam.rotation_euler = (Vector((0, 0, H/2)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    for loc, en in [((1.5, -3, 3), 800), ((-3, -2, 2), 300), ((0, -1.2, H*0.6), 60)]:
        L = bpy.data.objects.new("l", bpy.data.lights.new("l", "POINT")); L.data.energy = en
        L.location = loc; sc.collection.objects.link(L)
    sc.render.filepath = os.path.join(PREV, f"{name}_Doors_open.png")
    bpy.ops.render.render(write_still=True)
print("\n".join("REPORT " + r for r in report))
