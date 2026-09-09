extends SceneTree

## Headless gameplay smoke: doors, proximity chase, section patrol, touch damage, health bars.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed == null:
		push_error("Missing Main.tscn")
		quit(1)
		return
	var main: Node3D = packed.instantiate()
	root.add_child(main)
	await create_timer(0.35).timeout

	var player: CharacterBody3D = main.get_node("Player")
	var monster: CharacterBody3D = main.get_node("Monster")
	if player == null or monster == null:
		push_error("Player or Monster missing")
		quit(1)
		return

	var player_bar := player.get_node_or_null("HealthBar")
	var monster_bar := monster.get_node_or_null("HealthBar")
	var bars_ok := player_bar != null and monster_bar != null
	print("health_bars_ok=", bars_ok)

	var hp_ok := is_equal_approx(float(player.get("health")), 100.0) and is_equal_approx(float(monster.get("health")), 100.0)
	print("starting_hp_ok=", hp_ok, " player=", player.get("health"), " monster=", monster.get("health"))

	# Walk north through the center doors toward the monster.
	player.set_physics_process(false)
	var start := player.global_position
	for i in 120:
		if not player.is_on_floor():
			player.velocity.y -= 20.0 * 0.033
		else:
			player.velocity.y = 0.0
		player.velocity.x = 0.0
		player.velocity.z = -5.5
		player.move_and_slide()
		await create_timer(0.033).timeout
	var after_walk := player.global_position
	var moved_north := after_walk.z < start.z - 3.5
	print("door_walk_ok=", moved_north, " start_z=", start.z, " after_z=", after_walk.z)
	player.set_physics_process(true)

	# Proximity chase: place player behind the monster (outside FOV) but inside radius.
	player.global_position = Vector3(0.0, 0.05, -8.4)
	monster.global_position = Vector3(0.0, 0.05, -6.2)
	var mesh: Node3D = monster.get_node("MonsterMesh")
	# Face north (-Z) so player behind is outside FOV.
	mesh.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	monster.velocity = Vector3.ZERO
	var prox_start := monster.global_position
	for i in 75:
		await create_timer(0.033).timeout
	var prox_after := monster.global_position
	var proximity_chased := prox_after.distance_to(player.global_position) < prox_start.distance_to(player.global_position) - 0.4
	print("proximity_chase_ok=", proximity_chased, " start_dist=", prox_start.distance_to(player.global_position), " after_dist=", prox_after.distance_to(player.global_position))

	# Touch damage: place overlapping, wait one physics tick.
	player.global_position = Vector3(0.0, 0.05, -6.0)
	monster.global_position = Vector3(0.0, 0.05, -6.0)
	player.set("health", 100.0)
	if player.has_method("take_damage") == false:
		push_error("Player missing take_damage")
		quit(1)
		return
	# Force re-entry by toggling positions slightly across frames.
	await create_timer(0.1).timeout
	player.global_position = Vector3(0.2, 0.05, -6.0)
	await create_timer(0.25).timeout
	var touch_ok := float(player.get("health")) <= 0.0 or not bool(player.call("is_alive"))
	print("touch_damage_ok=", touch_ok, " player_hp=", player.get("health"))

	# Section patrol: hide player far away, shorten dwell, confirm section advance + room targets.
	player.global_position = Vector3(20.0, 0.05, 20.0)
	monster.global_position = Vector3(0.0, 0.05, -6.2)
	monster.set("section_dwell_time", 1.5)
	monster.set("_section_timer", 0.0)
	monster.set("_section_index", 0)
	monster.set("_room_index", 0)
	monster.call("_refresh_patrol_target")
	var section_start: int = int(monster.call("get_current_section"))
	var rooms_in_start: Array = monster.call("get_section_rooms", section_start)
	var rooms_ok := rooms_in_start.size() >= 1
	print("section_rooms_ok=", rooms_ok, " section=", section_start, " rooms=", rooms_in_start.size())
	var patrol_start := monster.global_position
	await create_timer(2.0).timeout
	var section_after: int = int(monster.call("get_current_section"))
	var section_advanced := section_after != section_start
	var patrol_moved := monster.global_position.distance_to(patrol_start) > 0.35
	print("section_patrol_ok=", section_advanced and patrol_moved, " from=", section_start, " to=", section_after, " moved=", patrol_moved)

	var ok := bars_ok and hp_ok and moved_north and proximity_chased and touch_ok and rooms_ok and section_advanced and patrol_moved
	print("SMOKE_RESULT=", ok)
	quit(0 if ok else 2)
