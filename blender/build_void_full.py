"""Merge Void Walk (Void_walking.glb), Run (Void_running.glb) and hide_break (Void_rigged_hb.glb) onto one rig.
Usage: blender -b --python build_void_full.py -- <characters_dir>
Checks that the three skeletons match (names, hierarchy, rest matrices); aborts if they don't."""
import bpy, sys, os
d = sys.argv[sys.argv.index('--')+1]
bpy.ops.wm.read_factory_settings(use_empty=True)
def load(fn):
    before = set(bpy.data.objects); acts0 = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=os.path.join(d, fn))
    objs = [o for o in bpy.data.objects if o not in before]
    arm = [o for o in objs if o.type == 'ARMATURE'][0]
    return objs, arm, [a for a in bpy.data.actions if a not in acts0]
base_objs, base, wa = load('Void_walking.glb')
rest = {b.name: ((base.matrix_world @ b.matrix_local), b.parent.name if b.parent else None) for b in base.data.bones}
keep = {}
keep['Walk'] = wa[0]
for fn, pick, nm in (('Void_running.glb', lambda a: 'running' in a.name, 'Run'),
                     ('Void_rigged_hb.glb', lambda a: a.name.startswith('hide_break'), 'hide_break')):
    objs, arm, acts = load(fn)
    names = {b.name for b in arm.data.bones}
    assert names == set(rest), (fn, names ^ set(rest))
    md = 0
    for b in arm.data.bones:
        m, par = rest[b.name]
        assert (b.parent.name if b.parent else None) == par, (fn, b.name)
        diff = (arm.matrix_world @ b.matrix_local) - m
        md = max(md, max(abs(x) for r in diff for x in r))
    print('SKEL', fn, 'max rest diff', md)
    assert md < 1e-3, 'skeleton mismatch, retarget needed'
    keep[nm] = [a for a in acts if pick(a)][0]
    for a in acts:
        if a is not keep[nm]: bpy.data.actions.remove(a)
    for o in objs:
        m = o.data if o.type == 'MESH' else None
        bpy.data.objects.remove(o)
for nm, a in keep.items():
    a.name = nm; a.use_fake_user = True
ad = base.animation_data or base.animation_data_create()
for t in list(ad.nla_tracks): ad.nla_tracks.remove(t)
for nm, a in keep.items():
    tr = ad.nla_tracks.new(); tr.name = nm; tr.strips.new(nm, int(a.frame_range[0]), a); tr.mute = True
ad.action = None
for a in list(bpy.data.actions):
    if a.name not in keep: bpy.data.actions.remove(a)
out = os.path.join(d, 'Void_full.glb')
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True, export_yup=True)
print('WROTE', out, list(keep))
