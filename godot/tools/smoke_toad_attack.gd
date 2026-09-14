extends SceneTree

## Headless coverage for the Toad (search / swallow / drop) and LMB attack
## (melee when unarmed, pistol when a weapon is equipped).


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var gp: Node = root.get_node("GameProgress")
	gp.reset_for_tests()

	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed == null:
		push_error("Missing Main.tscn")
		quit(1)
		return
	var main: Node3D = packed.instantiate()
	root.add_child(main)
	if not main.is_level_ready():
		await main.level_ready

	var toad: CharacterBody3D = main.get_node_or_null("Toad")
	var player: CharacterBody3D = main.get_node_or_null("Player")
	var monster: CharacterBody3D = main.get_node_or_null("Monster")
	var mission: Area3D = main.get_node_or_null("PickupItem")
	var nodes_ok := toad != null and player != null and monster != null and mission != null
	print("toad_nodes_ok=", nodes_ok)

	var toad_stats_ok: bool = (
		toad != null
		and is_equal_approx(toad.max_health, 200.0)
		and is_equal_approx(toad.touch_damage, 0.0)
		and is_equal_approx(float(toad.get("search_duration")), 10.0)
		and toad.is_in_group("toad")
		and toad.is_in_group("monster")
	)
	print("toad_stats_ok=", toad_stats_ok, " hp=", toad.max_health if toad else -1.0)

	var toad_anim: AnimationPlayer = toad.get_animation_player() if toad and toad.has_method("get_animation_player") else null
	var toad_anim_ok := toad_anim != null and toad_anim.has_animation("Idle") and toad_anim.has_animation("Walk")
	print("toad_anim_ok=", toad_anim_ok)

	var layout: Dictionary = main.get_layout()
	var rooms: Array = layout.get("rooms", [])
	if not nodes_ok or rooms.is_empty():
		print("toad_attack_smoke_ok=false")
		quit(1)
		return

	main.park_monsters()
	toad.visible = true
	toad.touch_damage = 0.0
	player.global_position = Vector3(400.0, 0.05, 400.0)
	var item_room: Dictionary = {}
	for room in rooms:
		if room.get("cell") == layout.get("objective_cell"):
			item_room = room
			break
	if item_room.is_empty():
		item_room = rooms[0]
	var item_center: Vector3 = item_room.get("center", mission.global_position)
	mission.global_position = item_center + Vector3(0.0, 0.05, 0.0)
	mission.visible = true
	toad.global_position = item_center + Vector3(0.0, 0.05, 0.0)
	toad.search_duration = 0.12
	toad.configure_level(rooms, layout.get("bounds", AABB()), layout.get("monster_track", {}))
	toad.set_physics_process(true)

	var searching_ok := false
	for _i in range(20):
		await physics_frame
		if toad.has_method("is_searching") and toad.is_searching():
			searching_ok = true
			break
	print("toad_searching_ok=", searching_ok, " mode=", toad.get_ai_mode_name())

	var ate_ok := false
	for _i in range(90):
		await physics_frame
		if toad.has_mission_item() and mission.is_swallowed() and not mission.visible:
			ate_ok = true
			break
	print(
		"toad_ate_ok=", ate_ok,
		" swallowed=", mission.is_swallowed(),
		" taken=", mission.is_taken(),
		" visible=", mission.visible
	)

	var player_blocked: bool = not mission.can_interact(item_center)
	print("toad_blocks_pickup_ok=", player_blocked)

	var chase_ok: bool = not toad._allows_chase() and not toad._can_see_player()
	print("toad_passive_ok=", chase_ok)

	var drop_pos := item_center + Vector3(2.0, 0.05, 0.0)
	toad.global_position = drop_pos
	toad.take_damage(200.0)
	await physics_frame
	var dropped_ok: bool = (
		not toad.has_mission_item()
		and not mission.is_taken()
		and mission.visible
		and _planar(mission.global_position, drop_pos) < 0.6
	)
	print("toad_drop_ok=", dropped_ok, " item_pos=", mission.global_position)

	gp.has_pistol = false
	player.global_position = monster.global_position + Vector3(1.2, 0.05, 0.0)
	monster.visible = true
	monster.global_position = player.global_position + Vector3(-1.1, 0.0, 0.0)
	monster.health = 100.0
	monster.set_physics_process(false)
	var visual: Node3D = player.get_node("Model")
	var to_monster := monster.global_position - player.global_position
	visual.rotation.y = atan2(to_monster.x, to_monster.z) + PI
	player.set_aim_world_override(monster.global_position)
	player._fire_cooldown = 0.0
	var melee_hit: Node3D = player.attack()
	var melee_ok: bool = melee_hit == monster and is_equal_approx(float(monster.health), 90.0)
	print("melee_attack_ok=", melee_ok, " hp=", monster.health, " hit=", melee_hit)

	gp.has_pistol = true
	player._fire_cooldown = 0.0
	var shot: Node3D = player.attack()
	var weapon_ok: bool = shot != null and shot != monster and shot != player
	print("weapon_attack_ok=", weapon_ok, " shot=", shot)

	var cycle_ok := (
		LevelRules.toad_count(5) == 0
		and LevelRules.toad_count(6) == 1
		and LevelRules.monster_kinds(6).has(LevelRules.KIND_TOAD)
	)
	print("toad_cycle_ok=", cycle_ok)

	var all_ok: bool = (
		nodes_ok
		and toad_stats_ok
		and toad_anim_ok
		and searching_ok
		and ate_ok
		and player_blocked
		and chase_ok
		and dropped_ok
		and melee_ok
		and weapon_ok
		and cycle_ok
	)
	print("toad_attack_smoke_ok=", all_ok)
	quit(0 if all_ok else 1)


func _planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
