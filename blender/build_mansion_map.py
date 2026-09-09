"""
Build a simple isometric-style mansion floorplan in Blender matching the
reference blockout: white walls, mint floor, tapered outer footprint,
multi-room interior with doorway openings and open door props.
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
DOOR = 2.2  # doorway clear width (empty gap; no door mesh)



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
    Build a straight wall with a doorway gap (no door mesh).
    door_center is the coordinate along the wall's long axis
    (x for horizontal walls, y for vertical walls).
    """
    dx = x1 - x0
    dy = y1 - y0
    length = math.hypot(dx, dy)
    if length < 1e-4:
        return
    # Parameterize by distance from start.
    if abs(dx) >= abs(dy):
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

    # Rooms:
    #   Bottom: L / R
    #   Middle: L / C / R
    #   Top:    L / C / R
    # Doorway gaps connect every adjacent room so the whole map is walkable.

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

    doorway_specs: list[tuple[str, float, float, float, float, float]] = [
        # Bottom L <-> Bottom R
        ("V_Bot", 0.0, -8.0, 0.0, -1.0, -4.5),
        # Bottom <-> Middle
        # H_Mid_C door is offset from x=0 so V_Bot can T-junction into solid wall
        # instead of leaving a wall stub that looks like a door in the opening.
        ("H_Mid_L", -6.0, -1.0, -2.2, -1.0, -4.0),
        ("H_Mid_C", -2.2, -1.0, 2.2, -1.0, 1.0),
        ("H_Mid_R", 2.2, -1.0, 6.0, -1.0, 4.0),
        # Middle L <-> C and C <-> R
        ("V_Mid_L", -2.2, -1.0, -2.2, 4.2, 1.5),
        ("V_Mid_R", 2.2, -1.0, 2.2, 4.2, 1.5),
        # Middle <-> Top
        ("H_Top_L", -6.0, 4.2, -2.2, 4.2, -4.0),
        ("H_Top_C", -2.2, 4.2, 2.2, 4.2, 0.0),
        ("H_Top_R", 2.2, 4.2, 6.0, 4.2, 4.0),
        # Top L <-> C and C <-> R
        ("V_Top_L", -2.2, 4.2, -2.2, 8.6, 6.4),
        ("V_Top_R", 2.2, 4.2, 2.2, 8.6, 6.4),
    ]

    for name, x0, y0, x1, y1, door_center in doorway_specs:
        wall_with_door(name, x0, y0, x1, y1, wall_mat, door_center=door_center)

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

    # Preview render (Cycles CPU — works without GPU/EGL in cloud agents)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.filepath = str(PNG_OUT)
    try:
        bpy.ops.render.render(write_still=True)
    except Exception as exc:
        print(f"Preview render skipped: {exc}")


def main() -> None:
    clear_scene()
    build_map()
    export_assets()
    print(f"Wrote {BLEND_OUT}")
    print(f"Wrote {GLB_OUT}")
    print(f"Wrote {PNG_OUT}")


if __name__ == "__main__":
    main()
