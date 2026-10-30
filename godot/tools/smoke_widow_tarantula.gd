extends SceneTree

## Headless coverage for Widow stats and Tarantula web weaving / slowdown.


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
	if not main.is_level_ready():
		await main.level_ready

	var widow: CharacterBody3D = main.get_node_or_null("Widow")
	var tarantula: CharacterBody3D = main.get_node_or_null("Tarantula")
	var player: CharacterBody3D = main.get_node_or_null("Player")
	var nodes_ok := widow != null and tarantula != null and player != null
	print("new_enemy_nodes_ok=", nodes_ok)

	var widow_stats_ok: bool = (
		widow != null
		and is_equal_approx(widow.max_health, 250.0)
		and is_equal_approx(widow.touch_damage, 100.0)
		and widow.idle_clip == "Idle"
		and widow.walk_clip == "Walk"
	)
	print(
		"widow_stats_ok=", widow_stats_ok,
		" hp=", widow.max_health if widow else -1.0,
		" dmg=", widow.touch_damage if widow else -1.0
	)

	var tara_stats_ok: bool = (
		tarantula != null
		and is_equal_approx(tarantula.max_health, 100.0)
		and is_equal_approx(tarantula.touch_damage, 50.0)
		and is_equal_approx(float(tarantula.get("weave_duration")), 30.0)
		and tarantula.has_method("is_weaving")
	)
	print(
		"tarantula_stats_ok=", tara_stats_ok,
		" hp=", tarantula.max_health if tarantula else -1.0,
		" dmg=", tarantula.touch_damage if tarantula else -1.0
	)

	var widow_anim: AnimationPlayer = widow.get_animation_player() if widow and widow.has_method("get_animation_player") else null
	var tara_anim: AnimationPlayer = tarantula.get_animation_player() if tarantula and tarantula.has_method("get_animation_player") else null
	var widow_anim_ok := widow_anim != null and widow_anim.has_animation("Idle") and widow_anim.has_animation("Walk")
	var tara_mesh: Node3D = tarantula.get_node_or_null("MonsterMesh/Character") as Node3D if tarantula != null else null
	var tara_anim_ok: bool = (
		tara_anim != null
		and tara_mesh != null
		and is_equal_approx(absf(tara_mesh.rotation.y), PI)
		and is_equal_approx(tara_mesh.scale.x, 0.67)
		and tara_anim.has_animation("Idle")
		and tara_anim.has_animation("Walk")
		and tara_anim.has_animation("Bite")
		and tara_anim.has_animation("WebWeave")
		and tarantula.attack_clip == "Bite"
		and String(tarantula.get("weave_clip")) == "WebWeave"
	)
	print("widow_anim_ok=", widow_anim_ok, " tarantula_anim_ok=", tara_anim_ok)

	var grouped := (
		widow != null
		and widow.is_in_group("monster")
		and tarantula != null
		and tarantula.is_in_group("monster")
		and tarantula.is_in_group("tarantula")
	)
	print("new_enemy_group_ok=", grouped)

	var layout: Dictionary = main.get_layout()
	var rooms: Array = layout.get("rooms", [])
	if rooms.is_empty() or tarantula == null or player == null:
		print("widow_tarantula_smoke_ok=false")
		quit(1)
		return

	main.park_monsters()
	tarantula.visible = true
	tarantula.touch_damage = 0.0
	var spawn_room: Dictionary = rooms[0]
	var other_room: Dictionary = rooms[1] if rooms.size() > 1 else rooms[0]
	player.global_position = Vector3(400.0, 0.05, 400.0)
	player.velocity = Vector3.ZERO
	tarantula.global_position = spawn_room.get("center", Vector3.ZERO) + Vector3(0.0, 0.05, 0.0)
	tarantula.proximity_radius = 0.1
	tarantula.detect_range = 0.1
	tarantula.set_force_detect(false)
	tarantula.configure_level(rooms, layout.get("bounds", AABB()), layout.get("monster_track", {}))
	tarantula.weave_duration = 0.15
	tarantula.set_physics_process(true)

	var weaving_ok := false
	for _i in range(20):
		await physics_frame
		if tarantula.has_method("is_weaving") and tarantula.is_weaving():
			weaving_ok = true
			break
	print("tarantula_weaving_ok=", weaving_ok, " mode=", tarantula.get_ai_mode_name())

	var first_cell: Vector2i = spawn_room.get("cell", Vector2i.ZERO)
	var webbed_ok := false
	for _i in range(90):
		await physics_frame
		if WebField.is_cell_webbed(self, first_cell):
			webbed_ok = true
			break
	print("tarantula_webbed_ok=", webbed_ok, " webs=", WebField.webs_in(self).size())
	tarantula.proximity_radius = 3.2
	tarantula.detect_range = 14.0

	player.global_position = spawn_room.get("center", Vector3.ZERO) + Vector3(0.4, 0.05, 0.0)
	await physics_frame
	var player_slow_ok := is_equal_approx(player.movement_speed_scale(), WebField.PLAYER_REMAINING)
	print("player_web_slow_ok=", player_slow_ok, " scale=", player.movement_speed_scale())

	tarantula.global_position = spawn_room.get("center", Vector3.ZERO) + Vector3(-0.4, 0.05, 0.0)
	await physics_frame
	var tara_fast_ok := is_equal_approx(tarantula._effective_move_speed(), tarantula.move_speed * 1.25)
	print("tarantula_web_fast_ok=", tara_fast_ok, " speed=", tarantula._effective_move_speed())

	var refuse_ok: bool = not bool(tarantula._start_weave_at_current_room())
	print("tarantula_skip_webbed_ok=", refuse_ok)

	player.global_position = other_room.get("center", Vector3.ZERO) + Vector3(0.0, 0.05, 0.0)
	tarantula.set_force_detect(true)
	for _i in range(8):
		await physics_frame
	tarantula.set_force_detect(false)
	tarantula._time_since_seen = 999.0
	tarantula._begin_return_to_track()
	var retarget := String(tarantula.get("_return_node_id"))
	var retarget_ok := not retarget.is_empty()
	if retarget_ok and tarantula._track_nodes.has(retarget):
		var dest_cell: Vector2i = tarantula._track_nodes[retarget].get("cell", first_cell)
		retarget_ok = dest_cell != first_cell or rooms.size() == 1
		if WebField.is_cell_webbed(self, dest_cell) and rooms.size() > 1:
			retarget_ok = false
	print("tarantula_retarget_ok=", retarget_ok, " return=", retarget)

	var cycle_ok := (
		LevelRules.tarantula_count(4) == 1
		and LevelRules.widow_count(4) == 0
		and LevelRules.widow_count(5) == 1
		and LevelRules.monster_kinds(5).has(LevelRules.KIND_WIDOW)
		and LevelRules.monster_kinds(4).has(LevelRules.KIND_TARANTULA)
	)
	print("new_enemy_cycle_ok=", cycle_ok)

	var all_ok: bool = (
		nodes_ok
		and widow_stats_ok
		and tara_stats_ok
		and widow_anim_ok
		and tara_anim_ok
		and grouped
		and weaving_ok
		and webbed_ok
		and player_slow_ok
		and tara_fast_ok
		and refuse_ok
		and retarget_ok
		and cycle_ok
	)
	print("widow_tarantula_smoke_ok=", all_ok)
	quit(0 if all_ok else 1)
