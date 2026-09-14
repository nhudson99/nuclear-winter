extends SceneTree

## Close-ups of the toad searching, swallowing the mission item, and dropping it.

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
	var toad: CharacterBody3D = main.get_node("Toad")
	var mission: Area3D = main.get_node("PickupItem")
	var camera: Camera3D = main.get_node("IsoCamera")
	var layout: Dictionary = main.get_layout()
	var rooms: Array = layout.get("rooms", [])
	main.park_monsters()
	toad.visible = true
	toad.touch_damage = 0.0
	var room: Dictionary = rooms[0] if not rooms.is_empty() else {"center": player.global_position, "cell": Vector2i.ZERO}
	var center: Vector3 = room.get("center", player.global_position)
	toad.global_position = center + Vector3(-0.55, 0.05, 0.15)
	mission.global_position = center + Vector3(0.7, 0.05, 0.05)
	mission.visible = true
	toad.configure_level(rooms, layout.get("bounds", AABB()), layout.get("monster_track", {}))
	player.global_position = center + Vector3(1.6, 0.05, 1.7)
	player.set_aim_world_override(toad.global_position)
	Input.action_press("flashlight")
	camera.size = 6.5
	main.set_physics_process(false)
	_aim_camera(camera, toad.global_position + Vector3(0.2, 0.25, 0.0))
	for _i in range(16):
		await physics_frame
	toad._update_health_bar_visibility()
	await create_timer(0.2).timeout
	_snap("godot_toad_search_close.png")

	toad.debug_finish_search()
	if main.has_method("_refresh_objective_hud"):
		main._refresh_objective_hud()
	for _i in range(8):
		await physics_frame
	_aim_camera(camera, toad.global_position + Vector3(0.15, 0.25, 0.0))
	await create_timer(0.15).timeout
	_snap("godot_toad_item_swallowed.png")

	player.global_position = toad.global_position + Vector3(1.15, 0.05, 0.85)
	player.set_aim_world_override(toad.global_position)
	var visual: Node3D = player.get_node("Model")
	var to_toad := toad.global_position - player.global_position
	visual.rotation.y = atan2(to_toad.x, to_toad.z) + PI
	var gp: Node = root.get_node("GameProgress")
	gp.has_pistol = false
	player._fire_cooldown = 0.0
	player.attack()
	toad.take_damage(200.0)
	if main.has_method("_refresh_objective_hud"):
		main._refresh_objective_hud()
	for _i in range(10):
		await physics_frame
	_aim_camera(camera, toad.global_position + Vector3(0.1, 0.2, 0.0))
	await create_timer(0.2).timeout
	_snap("godot_toad_item_dropped.png")
	Input.action_release("flashlight")
	quit(0)


func _aim_camera(camera: Camera3D, look: Vector3) -> void:
	camera.global_position = look + Vector3(7.2, 7.2, 7.2)
	camera.look_at(look, Vector3.UP)


func _snap(filename: String) -> void:
	var image: Image = get_root().get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, filename]
	var err := image.save_png(path)
	print("screenshot_err=", err, " path=", path, " size=", image.get_width(), "x", image.get_height())
