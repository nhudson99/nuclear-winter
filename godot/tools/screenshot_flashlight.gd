extends SceneTree

## Capture Level 1 dark, then with RMB-aim held in two directions, then
## strafing while the beam stays locked. Needs a real renderer:
##   Godot --rendering-driver opengl3 --resolution 1280x720 \
##         -s res://tools/screenshot_flashlight.gd

const OUT_DIR := "/opt/cursor/artifacts"
const SEED := 101

func _initialize() -> void:
	OS.set_environment("NW_LEVEL_SEED", str(SEED))
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main: Node3D = packed.instantiate()
	root.add_child(main)
	if not main.is_level_ready():
		await main.level_ready

	var player: CharacterBody3D = main.get_node("Player")
	var monster: CharacterBody3D = main.get_node_or_null("Monster")
	if main.has_method("park_monsters"):
		main.park_monsters()
	elif monster:
		monster.set_physics_process(false)
		monster.visible = false
		monster.global_position += Vector3(200.0, 0.0, 200.0)

	await create_timer(0.35).timeout
	_snap("godot_flashlight_rmb_off.png")

	player.set_aim_world_override(player.global_position + Vector3(0.0, 0.0, -8.0))
	Input.action_press("flashlight")
	for _i in range(20):
		await physics_frame
	await create_timer(0.2).timeout
	_snap("godot_flashlight_rmb_aim.png")

	player.set_aim_world_override(player.global_position + Vector3(8.0, 0.0, 0.0))
	for _i in range(20):
		await physics_frame
	await create_timer(0.2).timeout
	_snap("godot_flashlight_rmb_aim_yaw.png")

	var start := player.global_position
	Input.action_press("move_up")
	for _i in range(24):
		await physics_frame
	Input.action_release("move_up")
	await create_timer(0.15).timeout
	print("strafe_dist=", player.global_position.distance_to(start))
	_snap("godot_flashlight_rmb_strafe.png")

	Input.action_release("flashlight")
	player.clear_aim_world_override()
	quit(0)

func _snap(filename: String) -> void:
	var image: Image = get_root().get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, filename]
	var err := image.save_png(path)
	print("screenshot_err=", err, " path=", path, " size=", image.get_width(), "x", image.get_height())
