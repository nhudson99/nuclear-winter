extends SceneTree

## Capture Widow and Tarantula (with a finished web) under the flashlight.

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
	var widow: CharacterBody3D = main.get_node("Widow")
	var tarantula: CharacterBody3D = main.get_node("Tarantula")
	var layout: Dictionary = main.get_layout()
	var rooms: Array = layout.get("rooms", [])
	main.park_monsters()
	widow.visible = true
	tarantula.visible = true
	tarantula.touch_damage = 0.0
	widow.touch_damage = 0.0

	var room: Dictionary = rooms[0] if not rooms.is_empty() else {"center": player.global_position, "cell": Vector2i.ZERO}
	var center: Vector3 = room.get("center", player.global_position)
	tarantula.global_position = center + Vector3(-1.6, 0.05, -0.4)
	tarantula.configure_level(rooms, layout.get("bounds", AABB()), layout.get("monster_track", {}))
	tarantula.debug_finish_weave()
	widow.global_position = center + Vector3(2.4, 0.05, 0.8)
	player.global_position = center + Vector3(0.2, 0.05, 2.4)
	player.get_node("Model").rotation.y = atan2(1.0, 0.0) + PI
	player.set_aim_world_override(widow.global_position)
	Input.action_press("flashlight")
	for _i in range(12):
		await physics_frame
	widow._update_health_bar_visibility()
	tarantula._update_health_bar_visibility()
	await create_timer(0.25).timeout
	_snap("godot_widow_and_tarantula.png")

	player.set_aim_world_override(widow.global_position)
	player.global_position = widow.global_position + Vector3(2.8, 0.05, 1.8)
	for _i in range(10):
		await physics_frame
	await create_timer(0.2).timeout
	_snap("godot_widow_close.png")

	player.set_aim_world_override(tarantula.global_position)
	player.global_position = tarantula.global_position + Vector3(2.2, 0.05, 1.6)
	for _i in range(10):
		await physics_frame
	await create_timer(0.2).timeout
	_snap("godot_tarantula_web.png")
	Input.action_release("flashlight")
	quit(0)


func _snap(filename: String) -> void:
	var image: Image = get_root().get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, filename]
	var err := image.save_png(path)
	print("screenshot_err=", err, " path=", path, " size=", image.get_width(), "x", image.get_height())
