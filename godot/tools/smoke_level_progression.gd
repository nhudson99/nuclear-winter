extends SceneTree

## Headless coverage for level scaling: monster cycle, objective/key counts,
## zoned rooms, and locked-door unlocking.

const WALK_STEPS := 160
const WALK_SPEED := 5.5
const WALK_GRAVITY := 20.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var gp: Node = root.get_node("GameProgress")
	gp.reset_for_tests()

	var formulas_ok := _check_formulas()
	print("formulas_ok=", formulas_ok)

	var level1 := await _generate_level(1, 11)
	var level2 := await _generate_level(2, 22)
	var level3 := await _generate_level(3, 33)
	var level4 := await _generate_level(4, 44)
	var level6 := await _generate_level(6, 66)

	var counts_ok := (
		_roster_matches(level1["layout"], 1)
		and _roster_matches(level2["layout"], 2)
		and _roster_matches(level3["layout"], 3)
		and _roster_matches(level4["layout"], 4)
		and _roster_matches(level6["layout"], 6)
	)
	print("roster_ok=", counts_ok)

	var rooms_ok := (
		_room_count(level1["layout"]) == LevelRules.room_count(1)
		and _room_count(level2["layout"]) == LevelRules.room_count(2)
		and _room_count(level3["layout"]) == LevelRules.room_count(3)
	)
	print(
		"rooms_ok=", rooms_ok,
		" l1=", _room_count(level1["layout"]),
		" l2=", _room_count(level2["layout"]),
		" l3=", _room_count(level3["layout"])
	)

	var obj_ok := (
		_objectives_match(level1["layout"], 1)
		and _objectives_match(level2["layout"], 2)
		and _objectives_match(level3["layout"], 3)
	)
	print("objectives_ok=", obj_ok)

	var zones1_ok := _lock_count(level1["layout"]) == 0 and _max_zone(level1["layout"]) == 0
	var zones2_ok := _check_chained_zones(level2["layout"], 2)
	var zones3_ok := _check_chained_zones(level3["layout"], 3)
	print("zones_l1_ok=", zones1_ok, " zones_l2_ok=", zones2_ok, " zones_l3_ok=", zones3_ok)

	var reach1_ok := _reachable_without_locks(level1["layout"], level1["layout"]["objective_cell"])
	var reach2_blocked := not _reachable_without_locks(level2["layout"], level2["layout"]["objective_cell"])
	var reach2_key := _reachable_without_locks(level2["layout"], (level2["layout"]["keys"] as Array)[0]["cell"])
	print(
		"mission_l1_open_ok=", reach1_ok,
		" mission_l2_locked_ok=", reach2_blocked,
		" key_l2_open_ok=", reach2_key
	)

	var live_ok := await _check_live_level_2()
	print("live_unlock_ok=", live_ok)

	var advance_ok := _check_level_advance(gp)
	print("advance_ok=", advance_ok)

	(level1["container"] as Node3D).queue_free()
	(level2["container"] as Node3D).queue_free()
	(level3["container"] as Node3D).queue_free()
	(level4["container"] as Node3D).queue_free()
	(level6["container"] as Node3D).queue_free()

	var all_ok: bool = (
		formulas_ok
		and counts_ok
		and rooms_ok
		and obj_ok
		and zones1_ok
		and zones2_ok
		and zones3_ok
		and reach1_ok
		and reach2_blocked
		and reach2_key
		and live_ok
		and advance_ok
	)
	print("level_progression_smoke_ok=", all_ok)
	quit(0 if all_ok else 1)


func _check_formulas() -> bool:
	var expected := {
		1: [1, 0, 0],
		2: [1, 1, 0],
		3: [1, 1, 1],
		4: [2, 1, 1],
		5: [2, 2, 1],
		6: [2, 2, 2],
		7: [3, 2, 2],
		8: [3, 3, 2],
		9: [3, 3, 3],
	}
	var ok := true
	for level in expected:
		var got := [
			LevelRules.slime_count(level),
			LevelRules.hare_count(level),
			LevelRules.tank_count(level),
		]
		var want: Array = expected[level]
		var match_ok: bool = got == want and LevelRules.counts_match_cycle(level)
		var obj_ok: bool = (
			LevelRules.objective_count(level) == level
			and LevelRules.key_count(level) == maxi(level - 1, 0)
			and LevelRules.objectives(level).size() == level
		)
		print("formula n=", level, " monsters=", got, " match=", match_ok, " objectives=", obj_ok)
		if not match_ok or not obj_ok:
			ok = false
	return ok


func _generate_level(level: int, level_seed: int) -> Dictionary:
	var container := Node3D.new()
	container.name = "Map_L%d" % level
	root.add_child(container)
	var generator := MapGenerator.new()
	root.add_child(generator)
	var layout: Dictionary = await generator.generate(
		container,
		level_seed,
		LevelRules.room_count(level),
		level
	)
	generator.queue_free()
	return {"layout": layout, "container": container}


func _roster_matches(layout: Dictionary, level: int) -> bool:
	var counts := {LevelRules.KIND_SLIME: 0, LevelRules.KIND_HARE: 0, LevelRules.KIND_TANK: 0}
	for spec in layout.get("enemies", []):
		var kind := String(spec.get("kind", ""))
		if not counts.has(kind):
			print("unknown_enemy=", kind, " level=", level)
			return false
		counts[kind] += 1
		if spec.get("cell") == layout.get("start_cell"):
			print("enemy_on_start kind=", kind, " level=", level)
			return false
	var ok := (
		int(counts[LevelRules.KIND_SLIME]) == LevelRules.slime_count(level)
		and int(counts[LevelRules.KIND_HARE]) == LevelRules.hare_count(level)
		and int(counts[LevelRules.KIND_TANK]) == LevelRules.tank_count(level)
	)
	print("roster level=", level, " counts=", counts, " ok=", ok)
	return ok


func _objectives_match(layout: Dictionary, level: int) -> bool:
	var keys: Array = layout.get("keys", [])
	var locks: Array = layout.get("locks", [])
	var objectives: Array = layout.get("objectives", [])
	var ok := (
		keys.size() == LevelRules.key_count(level)
		and locks.size() >= LevelRules.locked_door_count(level)
		and objectives.size() == LevelRules.objective_count(level)
	)
	print(
		"objectives level=", level,
		" keys=", keys.size(),
		" locks=", locks.size(),
		" list=", objectives.size(),
		" ok=", ok
	)
	return ok


func _room_count(layout: Dictionary) -> int:
	return (layout.get("rooms", []) as Array).size()


func _lock_count(layout: Dictionary) -> int:
	return (layout.get("locks", []) as Array).size()


func _max_zone(layout: Dictionary) -> int:
	var best := 0
	var zones: Dictionary = layout.get("zones", {})
	for cell in zones:
		best = maxi(best, int(zones[cell]))
	return best


func _check_chained_zones(layout: Dictionary, level: int) -> bool:
	var zones: Dictionary = layout.get("zones", {})
	var locks: Array = layout.get("locks", [])
	var keys: Array = layout.get("keys", [])
	if locks.size() < level - 1 or keys.size() != level - 1:
		return false
	var stages := {}
	for lock in locks:
		stages[int(lock.get("stage", 0))] = true
	for stage in range(1, level):
		if not stages.has(stage):
			print("missing_lock_stage=", stage, " level=", level)
			return false
	var last := _max_zone(layout)
	if last != level - 1:
		print("zone_last_wrong level=", level, " last=", last)
		return false
	var objective_cell: Vector2i = layout["objective_cell"]
	if int(zones.get(objective_cell, -1)) != last:
		print("mission_not_in_last_zone level=", level, " zone=", zones.get(objective_cell, -1))
		return false
	for lock in locks:
		var stage := int(lock.get("stage", 0))
		if int(zones.get(lock["from_cell"], -1)) != stage - 1:
			print("lock_from_wrong stage=", stage, " zone=", zones.get(lock["from_cell"], -1))
			return false
		if int(zones.get(lock["to_cell"], -1)) != stage:
			print("lock_to_wrong stage=", stage, " zone=", zones.get(lock["to_cell"], -1))
			return false
	for key in keys:
		var stage := int(key.get("stage", 0))
		if int(zones.get(key["cell"], -1)) != stage - 1:
			print("key_zone_wrong stage=", stage, " zone=", zones.get(key["cell"], -1))
			return false
		if key["cell"] == layout.get("start_cell"):
			print("key_on_start stage=", stage)
			return false
	return true


func _reachable_without_locks(layout: Dictionary, goal: Vector2i) -> bool:
	var rooms: Array = layout.get("rooms", [])
	var locked := {}
	for lock in layout.get("locks", []):
		locked[MapGenerator.edge_key(lock["from_cell"], lock["to_cell"])] = true
	var cells := {}
	for room in rooms:
		cells[room["cell"]] = true
	var start: Vector2i = layout["start_cell"]
	if not cells.has(start) or not cells.has(goal):
		return false
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		if cell == goal:
			return true
		for side in MapGenerator.SIDES:
			var nxt: Vector2i = cell + MapGenerator.SIDE_STEPS[side]
			if not cells.has(nxt) or seen.has(nxt):
				continue
			if locked.has(MapGenerator.edge_key(cell, nxt)):
				continue
			seen[nxt] = true
			queue.append(nxt)
	return seen.has(goal)


func _check_live_level_2() -> bool:
	OS.set_environment("NW_LEVEL", "2")
	OS.set_environment("NW_LEVEL_SEED", "77")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed == null:
		OS.set_environment("NW_LEVEL", "")
		return false
	var main: Node3D = packed.instantiate()
	root.add_child(main)
	if not main.is_level_ready():
		await main.level_ready

	var layout: Dictionary = main.get_layout()
	var doors: Array = main.locked_doors()
	var keys_ok: bool = (layout.get("keys", []) as Array).size() == 1
	var door_ok: bool = doors.size() >= 1
	for door in doors:
		if not (door as LockedDoor).is_locked():
			door_ok = false
	var roster_ok := _count_active_kinds(main) == {LevelRules.KIND_SLIME: 1, LevelRules.KIND_HARE: 1, LevelRules.KIND_TANK: 0}
	print("live_nodes keys=", keys_ok, " door=", door_ok, " roster=", roster_ok, " play_level=", main.get_play_level())

	var player: CharacterBody3D = main.get_node("Player")
	if main.has_method("park_monsters"):
		main.park_monsters()

	var lock: Dictionary = (layout.get("locks", []) as Array)[0]
	var from_cell: Vector2i = lock["from_cell"]
	var to_cell: Vector2i = lock["to_cell"]
	var from_center := MapGenerator.cell_to_world(from_cell)
	var to_center := MapGenerator.cell_to_world(to_cell)
	var walk_dir := (to_center - from_center).normalized()
	player.set_physics_process(false)
	await _walk_from(player, from_center, walk_dir, WALK_STEPS)
	var blocked := _planar(player.global_position, to_center) > MapGenerator.TILE * 0.5
	print("live_blocked_ok=", blocked, " dist=", _planar(player.global_position, to_center))

	var key: Area3D = main.get_node_or_null("Key_1")
	if key == null:
		print("live_key_missing")
		main.queue_free()
		OS.set_environment("NW_LEVEL", "")
		return false
	player.set_physics_process(true)
	player.global_position = key.global_position + Vector3(0.8, 0.05, 0.0)
	player.velocity = Vector3.ZERO
	await create_timer(0.05).timeout
	Input.action_press("interact")
	await create_timer(0.05).timeout
	player._physics_process(0.033)
	Input.action_release("interact")
	await create_timer(0.1).timeout

	var key_taken: bool = main.collected_key_stages().has(1)
	var unlocked := doors.size() >= 1
	for door in doors:
		if int((door as LockedDoor).stage) == 1 and (door as LockedDoor).is_locked():
			unlocked = false
	print("live_key_taken=", key_taken, " unlocked=", unlocked)

	player.set_physics_process(false)
	await _walk_from(player, from_center, walk_dir, WALK_STEPS)
	var opened := _planar(player.global_position, to_center) < MapGenerator.TILE * 0.5
	print("live_opened_ok=", opened, " dist=", _planar(player.global_position, to_center))

	var mission: Area3D = main.get_node_or_null("PickupItem")
	if mission:
		player.set_physics_process(true)
		player.global_position = mission.global_position + Vector3(0.8, 0.05, 0.0)
		player.velocity = Vector3.ZERO
		await create_timer(0.05).timeout
		Input.action_press("interact")
		await create_timer(0.05).timeout
		player._physics_process(0.033)
		Input.action_release("interact")
		await create_timer(0.1).timeout
	var mission_ok: bool = player.has_collected_item()
	print("live_mission_ok=", mission_ok)

	main.queue_free()
	await create_timer(0.05).timeout
	OS.set_environment("NW_LEVEL", "")
	OS.set_environment("NW_LEVEL_SEED", "")
	return keys_ok and door_ok and roster_ok and blocked and key_taken and unlocked and opened and mission_ok


func _count_active_kinds(main: Node) -> Dictionary:
	var counts := {LevelRules.KIND_SLIME: 0, LevelRules.KIND_HARE: 0, LevelRules.KIND_TANK: 0}
	for spec in main.get_layout().get("enemies", []):
		counts[String(spec.get("kind", ""))] = int(counts.get(String(spec.get("kind", "")), 0)) + 1
	return counts


func _check_level_advance(gp: Node) -> bool:
	gp.reset_for_tests()
	if int(gp.current_level) != 1:
		return false
	gp.award_escape()
	gp.advance_level()
	var ok := int(gp.current_level) == 2 and int(gp.rations) == 5
	gp.reset_for_tests()
	return ok


func _walk_from(body: CharacterBody3D, from: Vector3, dir: Vector3, steps: int) -> void:
	body.global_position = from + Vector3(0.0, 0.05, 0.0)
	body.velocity = Vector3.ZERO
	await physics_frame
	var step_delta := 1.0 / float(Engine.physics_ticks_per_second)
	for _i in steps:
		if body.is_on_floor():
			body.velocity.y = 0.0
		else:
			body.velocity.y -= WALK_GRAVITY * step_delta
		body.velocity.x = dir.x * WALK_SPEED
		body.velocity.z = dir.z * WALK_SPEED
		body.move_and_slide()
		await physics_frame


func _planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
