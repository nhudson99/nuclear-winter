"""Render 8-frame previews of the hide_break / hide_ejected clip from an exported _hb GLB.
Usage: blender -b --python render_hide_break_previews.py -- <file_hb.glb> <out_prefix>"""
import bpy, sys
from mathutils import Vector
f, pre = sys.argv[sys.argv.index('--')+1:][:2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=f)
sc = bpy.context.scene
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
act = [a for a in bpy.data.actions if a.name.startswith(('hide_break', 'hide_ejected'))][0]
for t in arm.animation_data.nla_tracks: t.mute = True
arm.animation_data.action = act
ms = [o for o in bpy.data.objects if o.type == 'MESH']
pts = [m.matrix_world @ Vector(c) for m in ms for c in m.bound_box]
mn = Vector([min(p[i] for p in pts) for i in range(3)]); mx = Vector([max(p[i] for p in pts) for i in range(3)])
H = mx.z - mn.z; cen = (mn + mx) / 2
sc.render.engine = 'BLENDER_WORKBENCH'; sc.display.shading.color_type = 'TEXTURE'
sc.render.resolution_x = sc.render.resolution_y = 360
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = 'ORTHO'; cam.data.ortho_scale = max(H, mx.y - mn.y) * 2.4
c = Vector((cen.x, cen.y - 0.4, mn.z + H / 2)); cam.location = c + Vector((4 * H, -2 * H, 0.6 * H))
cam.rotation_euler = (c - cam.location).to_track_quat('-Z', 'Y').to_euler()
s, e = int(act.frame_range[0]), int(act.frame_range[1])
for i in range(8):
    sc.frame_set(s + round(i * (e - s) / 7)); sc.render.filepath = f'{pre}_{i:02d}.png'
    bpy.ops.render.render(write_still=True)
print('ACT', act.name, s, e, 'clips', [a.name for a in bpy.data.actions])
