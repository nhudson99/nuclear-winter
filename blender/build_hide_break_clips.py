"""Adds `hide_break` (monsters) / `hide_ejected` (Prisoner) clips to rigged GLBs.
Usage: blender -b --python build_hide_break_clips.py -- <in.glb> <out.glb> <mode:monster|ejected> <preview_png_prefix>
Existing clips are kept; output is a new file (never overwrites the input).
Characters face -Y in Blender (glTF +Z forward). Rotations are authored as world-space
deltas converted into each bone's local space, so it works across different rigs."""
import bpy, sys, math, os
from mathutils import Quaternion, Vector, Matrix
a = sys.argv[sys.argv.index('--')+1:]
src, dst, mode, prev = a[0], a[1], a[2], a[3]
assert os.path.abspath(src) != os.path.abspath(dst)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene
fps = sc.render.fps
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
meshes = [o for o in bpy.data.objects if o.type == 'MESH' and o.find_armature() == arm] or [o for o in bpy.data.objects if o.type=='MESH']
# world bounds of the character
pts = [m.matrix_world @ Vector(c) for m in meshes for c in m.bound_box]
mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
H = mx.z - mn.z; W = mx.x - mn.x; D = mx.y - mn.y; cen = (mn + mx) / 2
AW = arm.matrix_world
def wrest(b): return AW @ b.matrix_local
def whead(b): return AW @ b.head_local
def wtail(b): return AW @ b.tail_local

# clear pose, new action
if not arm.animation_data: arm.animation_data_create()
old = arm.animation_data.action
arm.animation_data.action = None
for pb in arm.pose.bones:
    pb.rotation_mode = 'QUATERNION'; pb.location = (0,0,0); pb.rotation_quaternion = (1,0,0,0); pb.scale = (1,1,1)
name = 'hide_break' if mode == 'monster' else 'hide_ejected'
act = bpy.data.actions.new(name); arm.animation_data.action = act

def rot_local(b, axis, deg):
    R = wrest(b).to_quaternion()
    q = Quaternion(axis, math.radians(deg))
    return R.inverted() @ q @ R
def key_rot(bname, frame, axis, deg, accum=None):
    pb = arm.pose.bones[bname]
    q = rot_local(pb.bone, axis, deg)
    if accum is not None: q = accum @ q
    pb.rotation_quaternion = q
    pb.keyframe_insert('rotation_quaternion', frame=frame, group=bname)
def key_loc(bname, frame, wvec):
    pb = arm.pose.bones[bname]
    M = wrest(pb.bone).to_3x3()
    pb.location = M.inverted() @ Vector(wvec)
    pb.keyframe_insert('location', frame=frame, group=bname)

X = Vector((1,0,0)); Z = Vector((0,0,1)); Y = Vector((0,1,0))
bones = arm.data.bones
root = [b for b in bones if b.parent is None][0]
# use hips-like bone if root is a pure root at floor with a single child
def body_bone():
    for n in ('Hips', 'mixamorig:Hips', 'Root'):
        if n in bones: return bones[n]
    b = root
    while len(b.children) == 1 and (whead(b).z - mn.z) < 0.15 * H: b = b.children[0]
    return b
body = body_bone()

def is_desc(b, anc):
    p = b.parent
    while p:
        if p == anc: return True
        p = p.parent
    return False

def keys(times_vals, fn):
    for t, v in times_vals: fn(round(t * fps) + 1, v)

if mode == 'monster':
    T = 1.5  # seconds
    # timeline: 0 rest, .45 wind-up, .70 strike, .80 hold/grab, 1.15 yank back, 1.5 settle
    tl = [0, .45, .70, .80, 1.15, 1.5]
    lunge = [0, +0.18, -0.45, -0.42, +0.25, 0]   # world Y (+ = back)
    lift  = [0, +0.08, -0.04, -0.04, +0.03, 0]
    pitch = [0, -14, +16, +14, -10, 0]          # + leans forward
    s = H / 1.7
    for t, ly, lz in zip(tl, lunge, lift):
        key_loc(body.name, round(t*fps)+1, (0, ly*s, lz*s))
    for t, p in zip(tl, pitch):
        key_rot(body.name, round(t*fps)+1, X, p)
    # reaching chains: humanoid arms by name, otherwise bones in front or high & lateral
    named = [b for b in bones if any(k in b.name for k in ('Shoulder','UpperArm','Arm'))]
    if named:
        chains = [b for b in named if 'Shoulder' in b.name or (b.parent and 'Shoulder' not in b.parent.name and b.parent.name not in [n.name for n in named])]
        chains = [b for b in named if 'Fore' not in b.name and 'Shoulder' not in b.name] or chains
        armmode = 'humanoid'
    else:
        cand = []
        for b in bones:
            if b == body or b == root or b.parent is None: continue
            h, tl_ = whead(b), wtail(b)
            front = h.y < cen.y - 0.2 * D
            high_lat = (h.z - mn.z) > 0.5 * H and abs(h.x - cen.x) > 0.22 * W
            if (front and (h.z - mn.z) > 0.15 * H) or high_lat:
                if not (b.parent and b.parent in cand): cand.append(b)
        chains = cand; armmode = 'auto'
    raise_ = [0, -55, +35, +40, -20, 0]   # about X: - raises tip/forward-up, + slams down-forward
    curl   = [0, -15, +20, +25, +10, 0]   # children curl (grab)
    hang_ = [0, -140, -80, -85, -35, 0]  # hanging limbs: overhead wind-up, swing forward to door height
    for b in chains:
        d = (wtail(b) - whead(b)).normalized()
        curve = hang_ if d.z < -0.5 else raise_
        if abs(d.x) > 0.7:  # T-pose arm: swing it forward first, then raise/strike about X
            pb = arm.pose.bones[b.name]; R = wrest(b).to_quaternion()
            zs = [0, 60, 85, 85, 45, 0]; xs = [0, -50, +10, +15, -5, 0]
            for t, zv, xv in zip(tl, zs, xs):
                qw = Quaternion(X, math.radians(xv)) @ Quaternion(Z, math.radians(-zv if d.x > 0 else zv))
                pb.rotation_quaternion = R.inverted() @ qw @ R
                pb.keyframe_insert('rotation_quaternion', frame=round(t*fps)+1, group=b.name)
            continue
        for t, v in zip(tl, curve): key_rot(b.name, round(t*fps)+1, X, v)
        for c in b.children_recursive[:3]:
            for t, v in zip(tl, curl): key_rot(c.name, round(t*fps)+1, X, v)
    # head/spine chain toward front gets a snap
    for b in bones:
        if any(k in b.name for k in ('Head', 'neck', 'Neck', 'Spine_Head', 'Spine_Front')):
            for t, v in zip(tl, [0, -10, +15, +12, -8, 0]): key_rot(b.name, round(t*fps)+1, X, v)
    print('HB chains', armmode, [b.name for b in chains])
else:
    T = 1.3
    tl = [0, .25, .55, .80, 1.05, 1.3]
    fwd   = [0, -0.35, -0.80, -1.00, -1.08, -1.10]   # thrown forward (-Y)
    drop  = [0, -0.02, -0.18, -0.30, -0.08, 0]
    pitch = [0, +18, +38, +45, +12, 0]
    for t, y, z in zip(tl, fwd, drop): key_loc(body.name, round(t*fps)+1, (0, y, z))
    for t, p in zip(tl, pitch): key_rot(body.name, round(t*fps)+1, X, p)
    def kb(n, vals, axis=X):
        if n in bones:
            for t, v in zip(tl, vals): key_rot(n, round(t*fps)+1, axis, v)
    kb('Spine', [0, 8, 12, 10, 4, 0]); kb('Chest', [0, 6, 8, 8, 2, 0])
    kb('Head', [0, -20, -25, -15, -5, 0])
    # arms flail forward/out to catch the fall
    kb('UpperArm_R', [0, -60, -85, -70, -25, 0]); kb('UpperArm_L', [0, -40, -95, -75, -20, 0])
    kb('Forearm_R', [0, -20, -10, -15, -10, 0]); kb('Forearm_L', [0, -30, -10, -15, -10, 0])
    # stumbling steps
    kb('Thigh_R', [0, -35, +10, -45, -10, 0]); kb('Shin_R', [0, 40, 15, 55, 15, 0])
    kb('Thigh_L', [0, +20, -50, +5, -15, 0]); kb('Shin_L', [0, 10, 60, 30, 10, 0])
    kb('Foot_R', [0, -10, 0, -15, 0, 0]); kb('Foot_L', [0, 0, -15, 0, 0, 0])
act.frame_range = (1, round(T * fps) + 1)
for fc in act.fcurves:
    for k in fc.keyframe_points: k.interpolation = 'BEZIER'
print('CLIP', name, 'frames', round(T*fps), 'fps', fps, 'sec', T)
# stash in NLA so every clip is exported
tr = arm.animation_data.nla_tracks.new(); tr.name = name
tr.strips.new(name, 1, act); tr.mute = True

# ---- preview contact sheet ----
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.color_type = 'TEXTURE'
sc.render.resolution_x = 360; sc.render.resolution_y = 360
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = 'ORTHO'; cam.data.ortho_scale = max(H, D) * 2.2
c = Vector((cen.x, cen.y - (0.3 if mode=='monster' else 0.55), mn.z + H/2))
cam.location = c + Vector((4*H, -2*H, 0.6*H)); 
cam.rotation_euler = (c - cam.location).to_track_quat('-Z', 'Y').to_euler()
sc.world = bpy.data.worlds.new('w') if not sc.world else sc.world
sc.frame_start = 1; sc.frame_end = round(T*fps)+1
n = 8
for i in range(n):
    f = 1 + round(i * (T*fps) / (n-1))
    sc.frame_set(f)
    sc.render.filepath = f'{prev}_{i:02d}.png'
    bpy.ops.render.render(write_still=True)
# ---- export ----
arm.animation_data.action = old
bpy.data.objects.remove(cam)
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True, export_yup=True)
print('WROTE', dst)
