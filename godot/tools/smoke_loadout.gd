extends SceneTree

## Headless smoke: zoom, dim ambient, hidden monster HP until flashlight,
## pistol damage, sneak sight immunity, speed bonus, exit glow.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var gp: Node = root.get_node("GameProgress")
	gp.reset_for_tests()
	gp.has_pistol = true
	gp.has_sneak = true
	gp.speed_ranks = 1

	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed == null:
		push_error("Missing Main.tscn")
		quit(1)
		return
	var main: Node3D = packed.instantiate()
	root.add_child(main)
	if not main.is_level_ready():
		await main.level_ready

	var player: CharacterBody3D = main.get_node("Player")
	var monster: CharacterBody3D = main.get_node("Monster")
	var exit_zone: Area3D = main.get_node("ExitZone")
	var pickup: Area3D = main.get_node_or_null("PickupItem")
	monster.set_physics_process(false)
	monster.touch_damage = 0.0
	if main.has_method("park_monsters"):
		main.park_monsters(monster)

	var zoom_ok := is_equal_approx(main.camera.size, 20.0 / 1.5)
	print("zoom_ok=", zoom_ok, " camera_size=", main.camera.size)

	var world := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var env := world.environment if world else null
	var ambient_ok := (
		env != null
		and env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR
		and absf(env.ambient_light_energy - 0.10) < 0.02
	)
	print(
		"ambient_ok=", ambient_ok,
		" source=", env.ambient_light_source if env else -1,
		" energy=", env.ambient_light_energy if env else -1.0
	)

	var speed_ok := is_equal_approx(player.move_speed, 2.4 * 1.05) and is_equal_approx(player.run_speed, 5.5 * 1.05)
	print("speed_bonus_ok=", speed_ok, " walk=", player.move_speed, " run=", player.run_speed)

	var bar: Node3D = monster.get_node_or_null("HealthBar")
	var hidden_ok: bool = bar != null and not bar.visible and not monster.is_health_bar_revealed()
	print("hp_hidden_ok=", hidden_ok)

	var start: Vector3 = main.get_layout()["start"]
	player.global_position = start + Vector3(0.0, 0.05, 0.0)
	monster.global_position = start + Vector3(4.0, 0.05, 0.0)
	var visual: Node3D = player.get_node("Model")
	visual.rotation.y = atan2(1.0, 0.0) + PI
	player.set_aim_world_override(monster.global_position)
	player.set_flashlight_on(true)
	await physics_frame
	monster._update_health_bar_visibility()
	var revealed_ok: bool = monster.is_health_bar_revealed() and bar.visible
	print(
		"hp_revealed_ok=", revealed_ok,
		" illuminates=", player.illuminates_point(monster.global_position + Vector3(0.0, 1.2, 0.0))
	)
	player.set_flashlight_on(false)
	var stays_ok: bool = monster.is_health_bar_revealed() and bar.visible
	print("hp_stays_revealed_ok=", stays_ok)

	monster.health = 100.0
	var fired: Node3D = player.fire_weapon()
	var spawned: bool = fired != null
	for _i in 45:
		await physics_frame
	var pistol_ok: bool = spawned and is_equal_approx(float(monster.health), 90.0)
	print("pistol_hit_ok=", pistol_ok, " hp=", monster.health, " spawned=", spawned)

	var mesh: Node3D = monster.get_node("MonsterMesh")
	monster.proximity_radius = 0.15
	monster.detect_range = 16.0
	player.global_position = start + Vector3(5.0, 0.05, 0.0)
	monster.global_position = start + Vector3(0.0, 0.05, 0.0)
	mesh.rotation.y = atan2(1.0, 0.0) + PI
	player.set_flashlight_on(false)
	Input.action_press("sneak")
	await physics_frame
	var sneak_hidden: bool = player.is_sneaking() and not monster._can_see_player()
	Input.action_release("sneak")
	await physics_frame
	var seen_without: bool = monster._can_see_player()
	print(
		"sneak_ok=", sneak_hidden and seen_without,
		" sneaking=", sneak_hidden,
		" seen_after=", seen_without
	)

	var glow_off: bool = not exit_zone.is_glow_visible()
	player.global_position = pickup.global_position + Vector3(0.8, 0.0, 0.0)
	await create_timer(0.05).timeout
	Input.action_press("interact")
	await create_timer(0.05).timeout
	player._physics_process(0.033)
	Input.action_release("interact")
	await create_timer(0.05).timeout
	var glow_on: bool = player.has_collected_item() and exit_zone.is_glow_visible()
	print("exit_glow_ok=", glow_off and glow_on, " had_item=", player.has_collected_item())

	var all_ok: bool = (
		zoom_ok
		and ambient_ok
		and speed_ok
		and hidden_ok
		and revealed_ok
		and stays_ok
		and pistol_ok
		and sneak_hidden
		and seen_without
		and glow_off
		and glow_on
	)
	print("loadout_smoke_ok=", all_ok)
	quit(0 if all_ok else 1)
