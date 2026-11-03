"""
Meshy AI prop loader for the decorated Nuclear Winter rooms.

meshy(stem, name, ...) imports blender/meshy_props/Meshy_AI_<stem>*.glb once,
joins it to one mesh, turns it so its front faces -Y (pack convention),
scales it to a real-world size (height=, width= or depth=), decimates it to
<= MAX_TRIS and caps its textures at TEX_PX, then places it with the same
AABB anchoring as pripyat_room_base.prop() (x/y centre or xmin..ymax edges,
z = bottom). Repeat instances share mesh data.
"""
import glob, math, os
from pathlib import Path
import bpy
from mathutils import Vector
import pripyat_room_base as B

HERE = Path(__file__).resolve().parent
MESHY_DIR = Path(os.environ.get("MESHY_PROPS", HERE / "meshy_props"))
MAX_TRIS = 60000
TEX_PX = 1024
_CACHE = {}


def _load(stem, front, max_tris):
    key = (stem, front)
    if key in _CACHE: return _CACHE[key]
    hits = sorted(glob.glob(str(MESHY_DIR / "**" / f"Meshy_AI_{stem}*.glb"), recursive=True))
    if not hits: raise FileNotFoundError(stem)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=hits[0])
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        mw = o.matrix_world.copy(); o.parent = None; o.matrix_world = mw; o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1: bpy.ops.object.join()
    m = bpy.context.active_object
    for o in new:
        if o != m and o.name in bpy.data.objects: bpy.data.objects.remove(o)
    from mathutils import Matrix
    m.matrix_world = Matrix.Rotation(math.radians({"-Y": 0, "-X": 90, "+X": -90, "+Y": 180}[front]), 4, "Z") @ m.matrix_world
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    tris = sum(len(p.vertices) - 2 for p in m.data.polygons)
    if tris > max_tris:
        d = m.modifiers.new("dec", "DECIMATE"); d.ratio = max_tris / tris
        bpy.ops.object.modifier_apply(modifier=d.name)
    for s in m.material_slots:
        if s.material and s.material.use_nodes:
            for n in s.material.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image and max(n.image.size) > TEX_PX:
                    n.image.scale(TEX_PX, TEX_PX)
    mn, mx = B.world_bounds(m)
    _CACHE[key] = (m.data, mx - mn)
    bpy.data.objects.remove(m)
    return _CACHE[key]


def meshy(stem, name, yaw=0.0, *, height=None, width=None, depth=None, front="-Y", sy=1.0,
          x=None, y=None, xmin=None, xmax=None, ymin=None, ymax=None, z=0.0, tilt=(0.0, 0.0),
          collide=True, parent=None, stack_on=None, max_tris=MAX_TRIS):
    data, dims = _load(stem, front, max_tris)
    s = height / dims.z if height else width / dims.x if width else depth / dims.y
    o = bpy.data.objects.new(name if collide else f"NoCol_{name}", data)
    bpy.context.scene.collection.objects.link(o)
    o.rotation_euler = (math.radians(tilt[0]), math.radians(tilt[1]), math.radians(yaw))
    o.scale = (s, s * sy, s)
    bpy.context.view_layer.update()
    mn, mx = B.world_bounds(o); c = (mn + mx) / 2
    dx = (x - c.x) if x is not None else (xmin - mn.x) if xmin is not None else (xmax - mx.x)
    dy = (y - c.y) if y is not None else (ymin - mn.y) if ymin is not None else (ymax - mx.y)
    o.location = (dx, dy, z - mn.z)
    bpy.context.view_layer.update()
    if parent: o.parent = parent
    B.PROPS.append((o, collide, stack_on))
    return o
