"""Fit Charlie's Poly Pizza slime into the Godot character convention.

The uploaded GLB is centimetre-scale, faces -X, and ships a leftover 2 m
icosphere. This script deletes the sphere, scales the blob to ~1.05 m,
plants the feet on z = 0, and yaws it to face +Y so export_yup matches the
prisoner / monster forward axis.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector

SRC = Path("/workspace/blender/SlimeEnemy.glb")
OUT = Path("/workspace/godot/assets/characters/enemy_slime.glb")
TARGET_HEIGHT = 1.05


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def world_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    mins = Vector((1e9, 1e9, 1e9))
    maxs = Vector((-1e9, -1e9, -1e9))
    for corner in obj.bound_box:
        world = obj.matrix_world @ Vector(corner)
        for i in range(3):
            mins[i] = min(mins[i], world[i])
            maxs[i] = max(maxs[i], world[i])
    return mins, maxs


def main() -> None:
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=str(SRC))

    stray = bpy.data.objects.get("Icosphere")
    if stray is not None:
        bpy.data.objects.remove(stray, do_unlink=True)

    mesh = bpy.data.objects.get("enemy2")
    if mesh is None:
        raise RuntimeError("Slime mesh 'enemy2' missing")

    bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0.0, 0.0, 0.0))
    root = bpy.context.active_object
    root.name = "SlimeRoot"

    for obj in list(bpy.data.objects):
        if obj == root or obj.parent is not None:
            continue
        obj.parent = root

    mins, maxs = world_bounds(mesh)
    height = maxs.z - mins.z
    if height <= 1e-6:
        raise RuntimeError("Slime mesh has no height")
    root.scale = (TARGET_HEIGHT / height,) * 3
    bpy.context.view_layer.update()

    # Face +Y (Godot -Z after export_yup). Imported rest pose looks down -X.
    root.rotation_euler = (0.0, 0.0, -0.5 * math.pi)
    bpy.context.view_layer.update()

    mins, maxs = world_bounds(mesh)
    root.location.z -= mins.z
    bpy.context.view_layer.update()
    mins, maxs = world_bounds(mesh)
    size = maxs - mins
    print(
        "slime_ready min=", tuple(round(c, 4) for c in mins),
        "max=", tuple(round(c, 4) for c in maxs),
        "size=", tuple(round(c, 4) for c in size),
    )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for obj in root.children_recursive:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=str(OUT),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_yup=True,
        export_animations=True,
        export_nla_strips=True,
        export_force_sampling=True,
    )
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
