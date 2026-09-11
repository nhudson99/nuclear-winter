"""
Preview renders for the player character.

    blender -b blender/player_prisoner.blend --python blender/render_prisoner.py -- views
    blender -b blender/player_prisoner.blend --python blender/render_prisoner.py -- anim Walk
    blender -b blender/player_prisoner.blend --python blender/render_prisoner.py -- turntable

Stills go to /opt/cursor/artifacts, videos are written as MP4 by Blender's own
ffmpeg writer so nothing else has to be installed.
"""

from __future__ import annotations

import math
import subprocess
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ART = Path("/opt/cursor/artifacts")
FOCUS = Vector((0.0, 0.0, 0.95))


def reset_pose() -> None:
    rig = bpy.data.objects["PrisonerRig"]
    if rig.animation_data:
        rig.animation_data.action = None
        for track in rig.animation_data.nla_tracks:
            track.mute = True
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"
        pose_bone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pose_bone.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()


def studio(samples: int = 48, resolution: tuple[int, int] = (700, 1100)) -> None:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = resolution
    scene.render.film_transparent = False
    # Standard keeps the baked albedo readable; the filmic looks desaturate it.
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"

    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes["Background"]
    background.inputs[0].default_value = (0.22, 0.23, 0.25, 1.0)
    background.inputs[1].default_value = 0.55

    bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 0, 0))
    floor = bpy.context.object
    floor.name = "StudioFloor"
    material = bpy.data.materials.new("StudioFloor")
    material.use_nodes = True
    bsdf = material.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.18, 0.18, 0.19, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.75
    floor.data.materials.append(material)

    for name, location, energy, size in (
        ("Key", (2.4, -3.0, 3.2), 420.0, 2.5),
        ("Fill", (-3.0, -2.0, 1.9), 130.0, 3.0),
        ("Rim", (-1.2, 3.2, 3.0), 260.0, 2.0),
    ):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.size = size
        direction = FOCUS - Vector(location)
        light.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def camera_position(angle_deg: float, distance: float, height: float) -> Vector:
    # The character faces +Y, so angle 0 sits in front of it and orbits right.
    angle = math.radians(angle_deg)
    return Vector((math.sin(angle) * distance, math.cos(angle) * distance, height))


def add_camera(angle_deg: float, distance: float = 4.4, height: float = 1.15,
               lens: float = 85.0) -> bpy.types.Object:
    location = camera_position(angle_deg, distance, height)
    bpy.ops.object.camera_add(location=location)
    camera = bpy.context.object
    camera.data.lens = lens
    camera.rotation_euler = (FOCUS - location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera
    return camera


def render_still(path: Path) -> None:
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    print(f"Wrote {path}")


def use_action(name: str) -> bpy.types.Action:
    rig = bpy.data.objects["PrisonerRig"]
    action = bpy.data.actions[name]
    if rig.animation_data is None:
        rig.animation_data_create()
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    rig.animation_data.action = action
    start, end = (int(v) for v in action.frame_range)
    bpy.context.scene.frame_start = start
    bpy.context.scene.frame_end = end
    return action


def render_video(path: Path, repeats: int = 1, fps: int = 24) -> None:
    """Render the current frame range. Repeats are tiled afterwards with ffmpeg;
    extending frame_end past the action instead just renders frozen frames."""
    scene = bpy.context.scene
    scene.render.fps = fps
    scene.render.image_settings.file_format = "FFMPEG"
    scene.render.ffmpeg.format = "MPEG4"
    scene.render.ffmpeg.codec = "H264"
    scene.render.ffmpeg.constant_rate_factor = "HIGH"
    scene.render.ffmpeg.ffmpeg_preset = "GOOD"
    once = path if repeats == 1 else path.with_name(f"{path.stem}_once.mp4")
    scene.render.filepath = str(once)
    bpy.ops.render.render(animation=True)
    if repeats > 1:
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-stream_loop", str(repeats - 1),
             "-i", str(once), "-c", "copy", str(path)],
            check=True,
        )
        once.unlink()
    print(f"Wrote {path}")


def cmd_views() -> None:
    reset_pose()
    studio()
    for name, angle in (("front", 0.0), ("three_quarter", 38.0), ("side", 90.0), ("back", 180.0)):
        add_camera(angle)
        render_still(ART / f"prisoner_{name}.png")


def cmd_head() -> None:
    reset_pose()
    studio(samples=64, resolution=(700, 700))
    camera = add_camera(28.0, distance=1.2, height=1.70, lens=95.0)
    camera.rotation_euler = (Vector((0.0, 0.0, 1.70)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    render_still(ART / "prisoner_head.png")


def cmd_anim(name: str, quick: bool = False) -> None:
    studio(samples=10 if quick else 28,
           resolution=(320, 480) if quick else (520, 780))
    add_camera(34.0)
    use_action(name)
    loops = {"Walk": 4, "Run": 6, "Idle": 1, "Die": 1}.get(name, 1)
    # A looping cycle repeats its first frame at the end; drop it when tiling.
    if loops > 1:
        bpy.context.scene.frame_end -= 1
    render_video(ART / f"prisoner_{name.lower()}.mp4", repeats=loops)


def cmd_poses(name: str, angle: float, frames: list[int]) -> None:
    """Single frames of one action, for checking a pose without a video."""
    studio(samples=16, resolution=(420, 620))
    add_camera(angle)
    use_action(name)
    for frame in frames:
        bpy.context.scene.frame_set(frame)
        render_still(Path(f"/tmp/pose_{name.lower()}_{frame:03d}.png"))


def cmd_turntable(steps: int = 48) -> None:
    reset_pose()
    studio(samples=28, resolution=(560, 840))
    scene = bpy.context.scene
    camera = add_camera(0.0)
    empty_action = bpy.data.actions.new("Turntable")
    camera.animation_data_create().action = empty_action
    for step in range(steps + 1):
        location = camera_position(360.0 * step / steps, 4.4, 1.15)
        camera.location = location
        camera.rotation_euler = (FOCUS - location).to_track_quat("-Z", "Y").to_euler()
        camera.keyframe_insert("location", frame=step + 1)
        camera.keyframe_insert("rotation_euler", frame=step + 1)
    for curve in empty_action.fcurves:
        for keyframe in curve.keyframe_points:
            keyframe.interpolation = "LINEAR"
    scene.frame_start = 1
    scene.frame_end = steps
    render_video(ART / "prisoner_turntable.mp4", fps=24)


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["views"]
    ART.mkdir(parents=True, exist_ok=True)
    command = argv[0]
    if command == "views":
        cmd_views()
    elif command == "head":
        cmd_head()
    elif command == "anim":
        cmd_anim(argv[1], quick="--quick" in argv)
    elif command == "poses":
        cmd_poses(argv[1], float(argv[2]), [int(v) for v in argv[3:]])
    elif command == "turntable":
        cmd_turntable()
    else:
        raise SystemExit(f"unknown command {command}")


if __name__ == "__main__":
    main()
