extends SceneTree

## Capture the map SHOP button, the three-card shop, and a dim zoomed Level 1.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var out_dir := "/opt/cursor/artifacts"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var gp: Node = root.get_node("GameProgress")
	gp.reset_for_tests()
	gp.rations = 8

	var map_packed: PackedScene = load("res://scenes/GameMap.tscn")
	var map: Control = map_packed.instantiate()
	root.add_child(map)
	map.set_anchors_preset(Control.PRESET_FULL_RECT)
	await create_timer(0.35).timeout
	_shot(out_dir, "godot_map_shop_button.png")

	map.open_shop()
	await create_timer(0.35).timeout
	_shot(out_dir, "godot_shop_three_cards.png")
	map.queue_free()
	await create_timer(0.05).timeout

	gp.has_pistol = true
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main: Node3D = packed.instantiate()
	root.add_child(main)
	if not main.is_level_ready():
		await main.level_ready
	await create_timer(0.4).timeout
	_shot(out_dir, "godot_level_dim_zoom.png")

	var player: CharacterBody3D = main.get_node("Player")
	var monster: CharacterBody3D = main.get_node("Monster")
	monster.set_physics_process(false)
	var start: Vector3 = main.get_layout()["start"]
	player.global_position = start
	monster.global_position = start + Vector3(4.0, 0.05, 0.0)
	player.get_node("Model").rotation.y = atan2(1.0, 0.0) + PI
	player.set_aim_world_override(monster.global_position)
	Input.action_press("flashlight")
	for _i in 8:
		await physics_frame
	monster._update_health_bar_visibility()
	await create_timer(0.2).timeout
	_shot(out_dir, "godot_monster_hp_flashlight.png")
	Input.action_release("flashlight")

	player.global_position = main.get_node("PickupItem").global_position + Vector3(0.6, 0.0, 0.0)
	Input.action_press("interact")
	await create_timer(0.05).timeout
	player._physics_process(0.033)
	Input.action_release("interact")
	await create_timer(0.15).timeout
	var exit_zone: Node3D = main.get_node("ExitZone")
	# Stand next to the doorway (outside the trigger) so the follow cam
	# frames the green beacon without winning the run.
	player.global_position = exit_zone.global_position + Vector3(3.6, 0.05, 0.0)
	player.velocity = Vector3.ZERO
	for _i in 12:
		await physics_frame
	await create_timer(0.25).timeout
	_shot(out_dir, "godot_green_exit_glow.png")

	player.global_position = exit_zone.global_position + Vector3(0.0, 0.05, 0.0)
	if exit_zone.has_method("_on_body_entered"):
		exit_zone._on_body_entered(player)
	await create_timer(0.25).timeout
	var overlay := main.get_node_or_null("VictoryOverlay/AristocratScreen")
	if overlay and overlay.has_method("finish_typing_now"):
		overlay.finish_typing_now()
	await create_timer(0.25).timeout
	_shot(out_dir, "godot_victory_aristocrat_line.png")
	quit(0)


func _shot(out_dir: String, file_name: String) -> void:
	var img: Image = root.get_viewport().get_texture().get_image()
	var path := "%s/%s" % [out_dir, file_name]
	var err := img.save_png(path)
	print("shot=", file_name, " err=", err, " size=", img.get_width(), "x", img.get_height())
