extends SceneTree

## Capture the slime and tank in Level 1 with the flashlight on.

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
	var slime: CharacterBody3D = main.get_node("Slime")
	var tank: CharacterBody3D = main.get_node("Tank")
	main.park_monsters()
	slime.visible = true
	tank.visible = true
	slime.global_position = player.global_position + Vector3(3.2, 0.05, 0.4)
	tank.global_position = player.global_position + Vector3(-0.4, 0.05, -4.2)
	player.get_node("Model").rotation.y = atan2(1.0, 0.0) + PI
	player.set_aim_world_override(slime.global_position)
	Input.action_press("flashlight")
	for _i in range(12):
		await physics_frame
	slime._update_health_bar_visibility()
	tank._update_health_bar_visibility()
	await create_timer(0.25).timeout
	_snap("godot_slime_and_tank.png")

	player.set_aim_world_override(tank.global_position)
	player.global_position = tank.global_position + Vector3(3.4, 0.05, 2.2)
	for _i in range(10):
		await physics_frame
	await create_timer(0.2).timeout
	_snap("godot_tank_close.png")

	player.set_aim_world_override(slime.global_position)
	player.global_position = slime.global_position + Vector3(2.4, 0.05, 1.6)
	slime.global_position = player.global_position + Vector3(-2.0, 0.05, -1.2)
	for _i in range(10):
		await physics_frame
	await create_timer(0.2).timeout
	_snap("godot_slime_close.png")
	Input.action_release("flashlight")
	quit(0)


func _snap(filename: String) -> void:
	var image: Image = get_root().get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, filename]
	var err := image.save_png(path)
	print("screenshot_err=", err, " path=", path, " size=", image.get_width(), "x", image.get_height())
