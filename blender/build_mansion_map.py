"""
Build a simple isometric-style mansion floorplan in Blender matching the
reference blockout: white walls, mint floor, tapered outer footprint,
multi-room interior with doorway openings.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy

OUT_DIR = Path("/workspace/godot/assets/maps")
BLEND_OUT = Path("/workspace/blender/ussr_mansion_map.blend")
GLB_OUT = OUT_DIR / "ussr_mansion_map.glb"
PNG_OUT = Path("/opt/cursor/artifacts/blender_mansion_map.png")

WALL_H = 2.4
WALL_T = 0.28
FLOOR_Z = 0.0


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in bpy.data.meshes:
        bpy.data.meshes.remove(block)
    for block in bpy.data.materials:
        bpy.data.materials.remove(block)


def make_mat(name: str, color: tuple[float, float, float, float]):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = 0.55
    return mat


def add_box(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat,
):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if obj.data.materials:
        obj.data.materials[0] = mat
    else:
        obj.data.materials.append(mat)
    return obj


DOOR = 1.8  # doorway clear width (fits capsule player + wall thickness)


def wall_segment(
    name: str,
    x0: float,
    y0: float,
    x1: float,
    y1: float,
    mat,
    thickness: float = WALL_T,
    height: float = WALL_H,
):
    """Place a wall box from (x0,y0) to (x1,y1) on the XY plane."""
    dx = x1 - x0
    dy = y1 - y0
    length = math.hypot(dx, dy)
    if length < 1e-4:
        return None
    cx = (x0 + x1) * 0.5
    cy = (y0 + y1) * 0.5
    angle = math.atan2(dy, dx)
    obj = add_box(
        name,
        (cx, cy, height * 0.5),
        (length, thickness, height),
        mat,
    )
    obj.rotation_euler[2] = angle
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return obj


def wall_with_door(
    name: str,
    x0: float,
    y0: float,
    x1: float,
    y1: float,
    mat,
    door_center: float,
    door_width: float = DOOR,
) -> None:
    """
    Build a straight wall with a doorway gap.
    door_center is the coordinate along the wall's long axis
    (x for horizontal walls, y for vertical walls).
    """
    dx = x1 - x0
    dy = y1 - y0
    length = math.hypot(dx, dy)
    if length < 1e-4:
        return
    ux, uy = dx / length, dy / length
    # Parameterize by distance from start.
    # Project door_center onto the wall axis.
    if abs(dx) >= abs(dy):
        # Horizontal-ish: use x as parameter
        t_door = (door_center - x0) / dx if abs(dx) > 1e-6 else 0.5
    else:
        t_door = (door_center - y0) / dy if abs(dy) > 1e-6 else 0.5
    t_door = max(0.0, min(1.0, t_door))
    half = (door_width * 0.5) / length
    t0 = max(0.0, t_door - half)
    t1 = min(1.0, t_door + half)

    def pt(t: float) -> tuple[float, float]:
        return (x0 + dx * t, y0 + dy * t)

    if t0 > 0.02:
        ax, ay = pt(0.0)
        bx, by = pt(t0)
        wall_segment(f"{name}_A", ax, ay, bx, by, mat)
    if t1 < 0.98:
        ax, ay = pt(t1)
        bx, by = pt(1.0)
        wall_segment(f"{name}_B", ax, ay, bx, by, mat)


def build_map() -> None:
    wall_mat = make_mat("WallWhite", (0.92, 0.92, 0.90, 1.0))
    floor_mat = make_mat("FloorMint", (0.55, 0.78, 0.62, 1.0))
    ground_mat = make_mat("OutsideBlue", (0.45, 0.62, 0.82, 1.0))

    # Footprint roughly matching reference (meters). Origin at center.
    # Rooms:
    #   Bottom: L / R
    #   Middle: L / C / R
    #   Top:    L / C / R
    # Doorways connect every adjacent room so the whole map is walkable.

    add_box("Floor", (0, 0.5, -0.05), (12.4, 18.2, 0.1), floor_mat)
    add_box("Outside", (0, 0.5, -0.2), (24, 28, 0.05), ground_mat)

    walls: list[tuple[str, float, float, float, float]] = []

    # Outer perimeter (entrance gap on south wall)
    walls += [
        ("Outer_SW", -6.0, -8.0, -6.0, -1.0),
        ("Outer_NW", -6.0, -1.0, -6.0, 6.0),
        ("Outer_NWL", -6.0, 6.0, -4.0, 8.0),
        ("Outer_NTL", -4.0, 8.0, -1.5, 9.0),
        ("Outer_NTM", -1.5, 9.0, 1.5, 9.0),
        ("Outer_NTR", 1.5, 9.0, 4.0, 8.0),
        ("Outer_NER", 4.0, 8.0, 6.0, 6.0),
        ("Outer_SE", 6.0, 6.0, 6.0, -1.0),
        ("Outer_SSE", 6.0, -1.0, 6.0, -8.0),
        ("Outer_S_L", -6.0, -8.0, 1.0, -8.0),
        ("Outer_S_R", 2.8, -8.0, 6.0, -8.0),
    ]

    for name, x0, y0, x1, y1 in walls:
        wall_segment(name, x0, y0, x1, y1, wall_mat)

    # --- Interior walls with doorways between every adjacent room ---
    # Shared door centers so double-sided room walls never seal each other.

    # Bottom L <-> Bottom R
    wall_with_door("V_Bot", 0.0, -8.0, 0.0, -1.0, wall_mat, door_center=-4.5)

    # Bottom <-> Middle (L, C, R)
    wall_with_door("H_Mid_L", -6.0, -1.0, -2.2, -1.0, wall_mat, door_center=-4.0)
    wall_with_door("H_Mid_C", -2.2, -1.0, 2.2, -1.0, wall_mat, door_center=0.0)
    wall_with_door("H_Mid_R", 2.2, -1.0, 6.0, -1.0, wall_mat, door_center=4.0)

    # Middle L <-> Middle C  and  Middle C <-> Middle R
    wall_with_door("V_Mid_L", -2.2, -1.0, -2.2, 4.2, wall_mat, door_center=1.5)
    wall_with_door("V_Mid_R", 2.2, -1.0, 2.2, 4.2, wall_mat, door_center=1.5)

    # Middle <-> Top (L, C, R)
    wall_with_door("H_Top_L", -6.0, 4.2, -2.2, 4.2, wall_mat, door_center=-4.0)
    wall_with_door("H_Top_C", -2.2, 4.2, 2.2, 4.2, wall_mat, door_center=0.0)
    wall_with_door("H_Top_R", 2.2, 4.2, 6.0, 4.2, wall_mat, door_center=4.0)

    # Top L <-> Top C  and  Top C <-> Top R
    wall_with_door("V_Top_L", -2.2, 4.2, -2.2, 8.6, wall_mat, door_center=6.4)
    wall_with_door("V_Top_R", 2.2, 4.2, 2.2, 8.6, wall_mat, door_center=6.4)

    # Angled accents on middle-center — stop short of the top center doorway
    wall_segment("Chamfer_L", -2.2, 2.6, -1.35, 3.7, wall_mat)
    wall_segment("Chamfer_R", 2.2, 2.6, 1.35, 3.7, wall_mat)

    # Lighting similar to reference
    bpy.ops.object.light_add(type="AREA", location=(0, -4, 12))
    light = bpy.context.active_object
    light.name = "KeyLight"
    light.data.energy = 1200
    light.data.size = 8
    light.rotation_euler = (math.radians(35), 0, 0)

    bpy.ops.object.light_add(type="SUN", location=(4, -6, 10))
    sun = bpy.context.active_object
    sun.name = "Sun"
    sun.data.energy = 2.0
    sun.rotation_euler = (math.radians(45), math.radians(15), math.radians(20))

    # Camera: elevated isometric-ish view for preview render
    bpy.ops.object.camera_add(location=(10, -14, 12))
    cam = bpy.context.active_object
    cam.name = "PreviewCam"
    cam.rotation_euler = (math.radians(55), 0, math.radians(35))
    bpy.context.scene.camera = cam


def export_assets() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    BLEND_OUT.parent.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))

    # Export only mesh objects (floor + walls) for Godot
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.data.objects:
        if obj.type == "MESH" and obj.name != "Outside":
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj

    bpy.ops.export_scene.gltf(
        filepath=str(GLB_OUT),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )

    # Preview render
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in dir(bpy.types) or True else "BLENDER_EEVEE"
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except Exception:
        scene.render.engine = "CYCLES"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.filepath = str(PNG_OUT)
    bpy.ops.render.render(write_still=True)


def main() -> None:
    clear_scene()
    build_map()
    export_assets()
    print(f"Wrote {BLEND_OUT}")
    print(f"Wrote {GLB_OUT}")
    print(f"Wrote {PNG_OUT}")


if __name__ == "__main__":
    main()
