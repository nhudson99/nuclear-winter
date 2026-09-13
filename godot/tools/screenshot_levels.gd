extends SceneTree

## Capture the Pip-Boy level button and in-world HUD for levels 1 and 2.

const OUT_DIR := "/opt/cursor/artifacts"
const SEED := 77


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	await _shot_map(1, "gamemap_level_1.png")
	await _shot_map(2, "gamemap_level_2.png")
	await _shot_level(1, "level_1_objectives_hud.png", false)
	await _shot_level(2, "level_2_locked_door.png", true)
	await _shot_level(2, "level_2_door_unlocked.png", true, true)
	quit(0)


func _shot_map(level: int, file_name: String) -> void:
	var gp: Node = root.get_node("GameProgress")
	gp.reset_for_tests()
	gp.current_level = level
	var packed: PackedScene = load("res://scenes/GameMap.tscn")
	var node: Node = packed.instantiate()
	root.add_child(node)
	if node is Control:
		(node as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
	await create_timer(0.4).timeout
	_save(file_name)
	node.queue_free()
	await create_timer(0.05).timeout


func _shot_level(level: int, file_name: String, look_at_door: bool, unlock_first: bool = false) -> void:
	var gp: Node = root.get_node("GameProgress")
	gp.reset_for_tests()
	OS.set_environment("NW_LEVEL", str(level))
	OS.set_environment("NW_LEVEL_SEED", str(SEED))
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main: Node = packed.instantiate()
	root.add_child(main)
	if not main.is_level_ready():
		await main.level_ready
	if main.has_method("park_monsters"):
		main.park_monsters()
	var player: CharacterBody3D = main.get_node("Player")
	var layout: Dictionary = main.get_layout()
	if unlock_first and main.has_method("unlock_stage"):
		main.unlock_stage(1)
	if look_at_door:
		var locks: Array = layout.get("locks", [])
		if not locks.is_empty():
			var lock: Dictionary = locks[0]
			var from_cell: Vector2i = lock["from_cell"]
			player.global_position = MapGenerator.cell_to_world(from_cell) + Vector3(0.0, 0.05, 0.0)
			if player.has_method("set_aim_world_override"):
				var to_cell: Vector2i = lock["to_cell"]
				player.set_aim_world_override(MapGenerator.cell_to_world(to_cell))
				player.set_flashlight_on(true)
	if main.has_method("_snap_camera"):
		main._snap_camera()
	await create_timer(0.45).timeout
	_save(file_name)
	print(
		"shot=", file_name,
		" level=", level,
		" rooms=", (layout.get("rooms", []) as Array).size(),
		" locks=", (layout.get("locks", []) as Array).size(),
		" enemies=", (layout.get("enemies", []) as Array).size()
	)
	main.queue_free()
	OS.set_environment("NW_LEVEL", "")
	OS.set_environment("NW_LEVEL_SEED", "")
	await create_timer(0.05).timeout


func _save(file_name: String) -> void:
	var img: Image = root.get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, file_name]
	var err := img.save_png(path)
	print("saved=", file_name, " err=", err, " size=", img.get_width(), "x", img.get_height())
