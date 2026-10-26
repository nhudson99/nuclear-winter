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

	var reach1_ok := _check_steam(level1["layout"], true)
	var reach2_blocked := not _reachable_without_locks(level2["layout"], level2["layout"]["objective_cell"])
	var reach2_key := _reachable_without_locks(level2["layout"], (level2["layout"]["keys"] as Array)[0]["cell"])
	var steam_higher_ok := _check_steam(level2["layout"], false) and _check_steam(level3["layout"], false)
	print(
		"steam_l1_ok=", reach1_ok,
		" mission_l2_locked_ok=", reach2_blocked,
		" key_l2_open_ok=", reach2_key,
		" steam_higher_ok=", steam_higher_ok
	)

	var floors_ok := (
		_check_floor_rules(level1["layout"], 1, level1["container"])
		and _check_floor_rules(level2["layout"], 2, level2["container"])
		and _check_floor_rules(level3["layout"], 3, level3["container"])
		and _check_floor_rules(level4["layout"], 4, level4["container"])
	)
	print("floors_ok=", floors_ok)
	# These maps sit on the same world origin as the live scenes below. Free
	# them before any walk, or a leftover steam jet blocks the doorway.
	for probe in [level1, level2, level3, level4, level6]:
		var leftover: Node = probe["container"]
		if is_instance_valid(leftover):
			leftover.queue_free()
	await create_timer(0.05).timeout

	var stairs_ok := _check_stairs(level3["layout"], 3) and _check_stairs(level4["layout"], 4)
	print("stairs_ok=", stairs_ok)

	var spawn_rand_ok := await _check_spawn_randomization()
	print("spawn_random_ok=", spawn_rand_ok)

	var clear_start_ok := await _check_level1_no_start_web()
	print("level1_start_clear_ok=", clear_start_ok)

	var live_ok := await _check_live_level_2()
	print("live_unlock_ok=", live_ok)

	var live_steam_ok := await _check_live_steam()
	print("live_steam_ok=", live_steam_ok)

	var live_floor_ok := await _check_live_floor_change()
	print("live_floor_ok=", live_floor_ok)

	var advance_ok := _check_level_advance(gp)
	print("advance_ok=", advance_ok)

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
		and steam_higher_ok
		and floors_ok
		and stairs_ok
		and spawn_rand_ok
		and clear_start_ok
		and live_ok
		and live_steam_ok
		and live_floor_ok
		and advance_ok
	)
	print("level_progression_smoke_ok=", all_ok)
	quit(0 if all_ok else 1)


func _check_formulas() -> bool:
	var expected := {
		1: [1, 0, 0, 0, 0, 0],
		2: [1, 1, 0, 0, 0, 0],
		3: [1, 1, 1, 0, 0, 0],
		4: [1, 1, 1, 1, 0, 0],
		5: [1, 1, 1, 1, 1, 0],
		6: [1, 1, 1, 1, 1, 1],
		7: [2, 1, 1, 1, 1, 1],
		8: [2, 2, 1, 1, 1, 1],
		9: [2, 2, 2, 1, 1, 1],
	}
	var ok := true
	for level in expected:
		var got := [
			LevelRules.slime_count(level),
			LevelRules.hare_count(level),
			LevelRules.tank_count(level),
			LevelRules.tarantula_count(level),
			LevelRules.widow_count(level),
			LevelRules.toad_count(level),
		]
		var want: Array = expected[level]
		var match_ok: bool = got == want and LevelRules.counts_match_cycle(level)
		var valve_listed := false
		for spec in LevelRules.objectives(level):
			if String(spec.get("kind", "")) == LevelRules.KIND_VALVE:
				valve_listed = true
		var obj_ok: bool = (
			LevelRules.objective_count(level) == level + 1
			and LevelRules.key_count(level) == maxi(level - 1, 0)
			and LevelRules.objectives(level).size() == level + 1
			and valve_listed
		)
		var floors_ok: bool = (
			LevelRules.floor_count(level) == int(ceili(float(level) / 2.0))
			and LevelRules.zones_on_floor(level, 0).size() <= LevelRules.MAX_WINGS_PER_FLOOR
		)
		print(
			"formula n=", level,
			" monsters=", got,
			" match=", match_ok,
			" objectives=", obj_ok,
			" floors=", LevelRules.floor_count(level),
			" floors_ok=", floors_ok
		)
		if not match_ok or not obj_ok or not floors_ok:
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
	var counts := {
		LevelRules.KIND_SLIME: 0,
		LevelRules.KIND_HARE: 0,
		LevelRules.KIND_TANK: 0,
		LevelRules.KIND_TARANTULA: 0,
		LevelRules.KIND_WIDOW: 0,
		LevelRules.KIND_TOAD: 0,
	}
	for spec in layout.get("enemies", []):
		var kind := String(spec.get("kind", ""))
		if not counts.has(kind):
			print("unknown_enemy=", kind, " level=", level)
			return false
		counts[kind] += 1
		if spec.get("cell") == layout.get("start_cell"):
			print("enemy_on_start kind=", kind, " level=", level)
			return false
	if not _roster_stays_clear(layout, layout.get("enemies", [])):
		print("roster_not_clear level=", level)
		return false
	var ok := (
		int(counts[LevelRules.KIND_SLIME]) == LevelRules.slime_count(level)
		and int(counts[LevelRules.KIND_HARE]) == LevelRules.hare_count(level)
		and int(counts[LevelRules.KIND_TANK]) == LevelRules.tank_count(level)
		and int(counts[LevelRules.KIND_TARANTULA]) == LevelRules.tarantula_count(level)
		and int(counts[LevelRules.KIND_WIDOW]) == LevelRules.widow_count(level)
		and int(counts[LevelRules.KIND_TOAD]) == LevelRules.toad_count(level)
	)
	print("roster level=", level, " counts=", counts, " ok=", ok)
	return ok


func _objectives_match(layout: Dictionary, level: int) -> bool:
	var keys: Array = layout.get("keys", [])
	var locks: Array = layout.get("locks", [])
	var objectives: Array = layout.get("objectives", [])
	var valve := 0
	for spec in objectives:
		if String(spec.get("kind", "")) == LevelRules.KIND_VALVE:
			valve += 1
	var ok := (
		keys.size() == LevelRules.key_count(level)
		and locks.size() >= LevelRules.locked_door_count(level)
		and objectives.size() == LevelRules.objective_count(level)
		and valve == 1
	)
	print(
		"objectives level=", level,
		" keys=", keys.size(),
		" locks=", locks.size(),
		" list=", objectives.size(),
		" ok=", ok
	)
	return ok


func _roster_stays_clear(layout: Dictionary, enemies: Array) -> bool:
	var cells: Array = []
	var floor_of: Dictionary = layout.get("floors", {})
	for room in layout.get("rooms", []):
		cells.append(room["cell"])
	var start: Vector2i = layout["start_cell"]
	var reserved := {start: true}
	if layout.has("exit_cell"):
		reserved[layout["exit_cell"]] = true
	if layout.has("objective_cell"):
		reserved[layout["objective_cell"]] = true
	for key in layout.get("keys", []):
		reserved[key["cell"]] = true
	for stair in layout.get("stairs", []):
		reserved[stair["cell"]] = true
	var opposite := 0
	for cell in cells:
		if reserved.has(cell):
			continue
		if MapGenerator.is_opposite_monster_spawn(cell, start, cells, floor_of):
			opposite += 1
	var offside := 0
	for spec in enemies:
		var cell: Vector2i = spec["cell"]
		if not MapGenerator.is_clear_of_start(cell, start, floor_of):
			print("enemy_too_close kind=", spec.get("kind"), " cell=", cell, " start=", start)
			return false
		if MapGenerator.is_opposite_monster_spawn(cell, start, cells, floor_of):
			continue
		offside += 1
	# The far half can be smaller than the roster once the objective and stairs
	# are reserved. Only the overflow may leave that half, and it still has to
	# stay out of the start neighbourhood.
	if offside > maxi(enemies.size() - opposite, 0):
		print("enemy_offside=", offside, " opposite_free=", opposite, " roster=", enemies.size())
		return false
	return true


func _check_level1_no_start_web() -> bool:
	OS.set_environment("NW_LEVEL", "")
	OS.set_environment("NW_LEVEL_SEED", "")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed == null:
		print("level1_scene_missing")
		return false
	var main: Node3D = packed.instantiate()
	root.add_child(main)
	if not main.is_level_ready():
		await main.level_ready
	var layout: Dictionary = main.get_layout()
	var start: Vector2i = layout.get("start_cell", Vector2i.ZERO)
	var webs := WebField.webs_in(self)
	var on_start := false
	for node in webs:
		if node.get("room_cell") == start:
			on_start = true
	var clear := webs.is_empty() and not on_start
	var spawn_clear := _spawn_floor_is_clear(main)
	print("level1_webs=", webs.size(), " on_start=", on_start, " start=", start)
	print("level1_spawn_clear_ok=", spawn_clear)
	main.queue_free()
	return clear and spawn_clear


func _spawn_floor_is_clear(main: Node3D) -> bool:
	var player := main.get_node_or_null("Player") as Node3D
	var map := main.get_node_or_null("GeneratedMap")
	if player == null or map == null:
		print("level1_spawn_missing")
		return false
	return _spawn_debris_clear(map, player.global_position)


func _spawn_debris_clear(node: Node, origin: Vector3) -> bool:
	if node is MeshInstance3D and String(node.name).begins_with("NoCol_Debris"):
		if MapGenerator.debris_covers_point(node as MeshInstance3D, origin, MapGenerator.SPAWN_CLEAR_RADIUS):
			print("spawn_debris=", node.get_path())
			return false
	for child in node.get_children():
		if not _spawn_debris_clear(child, origin):
			return false
	return true


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


func _check_steam(layout: Dictionary, valve_from_start: bool) -> bool:
	var steam: Dictionary = layout.get("steam", {})
	if not steam.has("boiler_cell") or not steam.has("mission_cell"):
		print("steam_missing level=", layout.get("level"))
		return false
	var boiler: Vector2i = steam["boiler_cell"]
	var gallery: Vector2i = steam["gallery_cell"]
	var mission: Vector2i = steam["mission_cell"]
	if mission != layout.get("objective_cell"):
		print("steam_mission_mismatch mission=", mission, " objective=", layout.get("objective_cell"))
		return false
	if _room_type(layout, boiler) != MapGenerator.TYPE_BOILER:
		print("boiler_type_wrong cell=", boiler, " type=", _room_type(layout, boiler))
		return false
	if gallery != boiler:
		var gallery_type := _room_type(layout, gallery)
		var gallery_ok := (
			gallery_type == MapGenerator.TYPE_PIPE_GALLERY
			or MapGenerator.is_stair_type(gallery_type)
		)
		if not gallery_ok:
			print("gallery_type_wrong cell=", gallery, " type=", gallery_type)
			return false
	var pipes: Array = steam.get("pipe_cells", [])
	if pipes.is_empty() or pipes[0] != gallery or pipes[pipes.size() - 1] != boiler:
		print("pipe_path_wrong pipes=", pipes, " gallery=", gallery, " boiler=", boiler)
		return false
	var mission_blocked := not _reachable_past(layout, gallery, mission, true, true)
	var mission_open := _reachable_past(layout, gallery, mission, false, true)
	var valve_open := _reachable_past(layout, gallery, boiler, true, true)
	var from_start := _reachable_past(layout, layout["start_cell"], boiler, true, true)
	var far_has_mission := false
	for cell in steam.get("far_cells", []):
		if cell == mission:
			far_has_mission = true
	var ok := (
		mission_blocked
		and mission_open
		and valve_open
		and from_start == valve_from_start
		and far_has_mission
		and boiler != mission
	)
	print(
		"steam level=", layout.get("level"),
		" blocked=", mission_blocked,
		" opens=", mission_open,
		" valve=", valve_open,
		" from_start=", from_start,
		" ok=", ok
	)
	return ok


func _room_type(layout: Dictionary, cell: Vector2i) -> String:
	for room in layout.get("rooms", []):
		if room.get("cell") == cell:
			return String(room.get("type", ""))
	return ""


func _reachable_past(
	layout: Dictionary,
	start: Vector2i,
	goal: Vector2i,
	block_steam: bool,
	block_sealed: bool
) -> bool:
	var rooms: Array = layout.get("rooms", [])
	var locked := {}
	for lock in layout.get("locks", []):
		if String(lock.get("kind", "")) == MapGenerator.LOCK_KIND_STAIR:
			continue
		locked[MapGenerator.edge_key(lock["from_cell"], lock["to_cell"])] = true
	var cells := {}
	for room in rooms:
		cells[room["cell"]] = true
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
			if block_steam and MapGenerator.edge_is_steam_door(layout, cell, nxt):
				continue
			if block_sealed and MapGenerator.edge_is_sealed(layout, cell, nxt):
				continue
			seen[nxt] = true
			queue.append(nxt)
	return false


func _panel_stand(main: Node3D, valve: SteamValve) -> Vector3:
	var board := MapGenerator.find_child_by_name(main.get_node("GeneratedMap"), "GaugeBoard") as Node3D
	if board == null:
		var fallback := valve.global_position
		fallback.y = 0.05
		return fallback
	var stand := board.global_position
	var room: Node = board
	while room != null and not String(room.name).begins_with("Room_"):
		room = room.get_parent()
	if room is Node3D:
		var inward: Vector3 = (room as Node3D).global_position - board.global_position
		inward.y = 0.0
		if inward.length() > 0.2:
			stand += inward.normalized() * 1.15
	stand.y = 0.05
	return stand


func _check_live_steam() -> bool:
	OS.set_environment("NW_LEVEL", "1")
	OS.set_environment("NW_LEVEL_SEED", "11")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed == null:
		OS.set_environment("NW_LEVEL", "")
		return false
	var main: Node3D = packed.instantiate()
	root.add_child(main)
	if not main.is_level_ready():
		await main.level_ready
	if main.has_method("park_monsters"):
		main.park_monsters()
	var layout: Dictionary = main.get_layout()
	var steam: Dictionary = layout.get("steam", {})
	var barriers: Array = main.steam_barriers()
	var barrier_ok := barriers.size() == 1 and (barriers[0] as SteamBarrier).is_blocked()
	var pipes := main.get_node_or_null("GeneratedMap/Steam/SteamPipes")
	var valve := main.get_node_or_null("GeneratedMap/Steam/SteamValve") as SteamValve
	var placed_ok := pipes != null and valve != null and pipes.get_child_count() > 0
	print(
		"steam_placed barrier=", barrier_ok,
		" count=", barriers.size(),
		" pipes=", placed_ok,
		" valve=", valve != null,
		" level=", main.get_play_level()
	)
	if valve == null or barriers.is_empty():
		main.queue_free()
		OS.set_environment("NW_LEVEL", "")
		OS.set_environment("NW_LEVEL_SEED", "")
		return false

	var player: CharacterBody3D = main.get_node("Player")
	player.set_physics_process(false)
	var from_cell: Vector2i = steam["from_cell"]
	var to_cell: Vector2i = steam["to_cell"]
	var from_center := MapGenerator.cell_to_world(from_cell)
	var to_center := MapGenerator.cell_to_world(to_cell)
	var walk_dir := (to_center - from_center).normalized()
	await _walk_from(player, from_center, walk_dir, WALK_STEPS)
	var blocked := _planar(player.global_position, to_center) > MapGenerator.TILE * 0.45
	print("steam_blocked_ok=", blocked, " dist=", _planar(player.global_position, to_center))

	player.set_physics_process(false)
	var stand := _panel_stand(main, valve)
	player.global_position = stand
	player.velocity = Vector3.ZERO
	var panel_reach := valve.can_interact(player.global_position)
	var status_before := valve.get_node_or_null("PanelStatusLight") as MeshInstance3D
	var before_mat: StandardMaterial3D = null
	if status_before != null:
		before_mat = status_before.material_override as StandardMaterial3D
	var started_orange := before_mat != null and before_mat.emission.r > before_mat.emission.g and before_mat.emission.r > 0.6
	var live_pipe: MeshInstance3D = null
	if pipes != null and pipes.get_child_count() > 0:
		live_pipe = pipes.get_child(0) as MeshInstance3D
	var live_pipe_mat: StandardMaterial3D = null
	if live_pipe != null:
		live_pipe_mat = live_pipe.material_override as StandardMaterial3D
	var pipes_plain := (
		live_pipe_mat != null
		and not live_pipe_mat.emission_enabled
		and pipes.get_child_count() > 0
	)
	print("pipes_not_orange=", pipes_plain)
	print(
		"panel_reach=", panel_reach,
		" dist=", valve.interact_distance(player.global_position),
		" started_orange=", started_orange
	)
	player.interact()
	await create_timer(0.1).timeout
	var barrier := barriers[0] as SteamBarrier
	var shut: bool = (
		panel_reach
		and started_orange
		and main.valve_is_shut()
		and valve.is_shut()
		and valve.indicator_is_green()
		and not barrier.is_blocked()
		and barrier.is_visually_clear()
	)
	var pipe: MeshInstance3D = null
	if pipes != null and pipes.get_child_count() > 0:
		pipe = pipes.get_child(0) as MeshInstance3D
	var pipe_mat: StandardMaterial3D = null
	if pipe != null:
		pipe_mat = pipe.material_override as StandardMaterial3D
	var pipes_cold := pipe_mat != null and pipe_mat.emission.r < 0.2 and pipe_mat.emission.g > pipe_mat.emission.r
	var lamp := MapGenerator.find_child_by_name(main.get_node("GeneratedMap"), "NoCol_ValveLamp") as MeshInstance3D
	var lamp_mat: StandardMaterial3D = null
	if lamp != null:
		lamp_mat = lamp.material_override as StandardMaterial3D
	var lamp_green := lamp_mat != null and lamp_mat.emission.g > lamp_mat.emission.r and lamp_mat.emission_energy_multiplier > 3.0
	var gauge := MapGenerator.find_child_by_name(main.get_node("GeneratedMap"), "NoCol_Gauge_1") as MeshInstance3D
	var gauge_mat: StandardMaterial3D = null
	if gauge != null:
		gauge_mat = gauge.material_override as StandardMaterial3D
	var gauge_green := gauge_mat != null and gauge_mat.emission.g > gauge_mat.emission.r and gauge_mat.emission_energy_multiplier > 3.0
	var status := valve.get_node_or_null("PanelStatusLight") as MeshInstance3D
	var status_mat: StandardMaterial3D = null
	if status != null:
		status_mat = status.material_override as StandardMaterial3D
	var status_green := status_mat != null and status_mat.emission.g > status_mat.emission.r
	print(
		"steam_shut_ok=", shut,
		" valve_flag=", main.valve_is_shut(),
		" valve_closed=", valve.is_shut(),
		" indicator=", valve.indicator_is_green(),
		" barrier_blocked=", barrier.is_blocked(),
		" barrier_clear=", barrier.is_visually_clear(),
		" pipes_cold=", pipes_cold,
		" lamp_green=", lamp_green,
		" gauge_green=", gauge_green,
		" status_green=", status_green
	)
	shut = shut and pipes_cold and lamp_green and gauge_green and status_green

	player.set_physics_process(false)
	await _walk_from(player, from_center, walk_dir, WALK_STEPS)
	var opened := _planar(player.global_position, to_center) < MapGenerator.TILE * 0.45
	print("steam_opened_ok=", opened, " dist=", _planar(player.global_position, to_center))

	var track_open := false
	var nodes: Dictionary = main.get_layout().get("monster_track", {}).get("nodes", {})
	var side := String(steam.get("side", "E"))
	var canon_cell := from_cell
	var canon_side := side
	if not MapGenerator.TRACK_CANONICAL_SIDES.has(side):
		canon_cell = to_cell
		canon_side = String(MapGenerator.OPPOSITE_SIDE.get(side, "E"))
	track_open = nodes.has(MapGenerator.door_track_id(canon_cell, canon_side))
	print("steam_track_open=", track_open)

	main.queue_free()
	await create_timer(0.05).timeout
	OS.set_environment("NW_LEVEL", "")
	OS.set_environment("NW_LEVEL_SEED", "")
	return barrier_ok and placed_ok and blocked and shut and opened and track_open and pipes_plain


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
	var roster_ok := _count_active_kinds(main) == {
		LevelRules.KIND_SLIME: 1,
		LevelRules.KIND_HARE: 1,
		LevelRules.KIND_TANK: 0,
		LevelRules.KIND_TARANTULA: 0,
		LevelRules.KIND_WIDOW: 0,
		LevelRules.KIND_TOAD: 0,
	}
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
	var counts := {
		LevelRules.KIND_SLIME: 0,
		LevelRules.KIND_HARE: 0,
		LevelRules.KIND_TANK: 0,
		LevelRules.KIND_TARANTULA: 0,
		LevelRules.KIND_WIDOW: 0,
		LevelRules.KIND_TOAD: 0,
	}
	for spec in main.get_layout().get("enemies", []):
		counts[String(spec.get("kind", ""))] = int(counts.get(String(spec.get("kind", "")), 0)) + 1
	return counts


func _check_floor_rules(layout: Dictionary, level: int, container: Node3D) -> bool:
	var wanted_floors := LevelRules.floor_count(level)
	var floor_of: Dictionary = layout.get("floors", {})
	var seen := {}
	var wings := {}
	for cell in floor_of:
		var fl := int(floor_of[cell])
		seen[fl] = true
		var zone := int((layout.get("zones", {}) as Dictionary).get(cell, 0))
		if not wings.has(fl):
			wings[fl] = {}
		wings[fl][zone] = true
	if seen.size() != wanted_floors:
		print("floor_count_wrong level=", level, " got=", seen.size(), " want=", wanted_floors)
		return false
	for fl in wings:
		if (wings[fl] as Dictionary).size() > LevelRules.MAX_WINGS_PER_FLOOR:
			print("too_many_wings level=", level, " floor=", fl)
			return false
	var instantiated := 0
	for child in container.get_children():
		if String(child.name).begins_with("Room_"):
			instantiated += 1
	var active_rooms := 0
	for room in layout.get("rooms", []):
		if int(room.get("floor", 0)) == 0:
			active_rooms += 1
	if instantiated != active_rooms:
		print(
			"floor_scope_wrong level=", level,
			" instantiated=", instantiated,
			" active=", active_rooms
		)
		return false
	print("floor_rules level=", level, " floors=", wanted_floors, " scoped=", instantiated)
	return true


func _check_stairs(layout: Dictionary, level: int) -> bool:
	var stairs: Array = layout.get("stairs", [])
	if stairs.size() != 2 * (LevelRules.floor_count(level) - 1):
		print("stair_count_wrong level=", level, " stairs=", stairs.size())
		return false
	var has_up := false
	var has_down := false
	for spec in stairs:
		if String(spec.get("direction", "")) == Stairwell.DIR_UP:
			has_up = true
			if int(spec.get("required_stage", 0)) <= 0:
				print("up_stair_unlocked level=", level)
				return false
		elif String(spec.get("direction", "")) == Stairwell.DIR_DOWN:
			has_down = true
	var stair_locks := 0
	for lock in layout.get("locks", []):
		if String(lock.get("kind", "")) == MapGenerator.LOCK_KIND_STAIR:
			stair_locks += 1
	if not has_up or not has_down or stair_locks != LevelRules.floor_count(level) - 1:
		print("stair_pair_wrong level=", level, " up=", has_up, " down=", has_down, " locks=", stair_locks)
		return false
	var types := {}
	for room in layout.get("rooms", []):
		types[String(room.get("type", ""))] = true
	if not types.has(LevelRules.TYPE_STAIR_UP) or not types.has(LevelRules.TYPE_STAIR_DOWN):
		print("stair_rooms_missing level=", level, " types=", types)
		return false
	return true


func _check_spawn_randomization() -> bool:
	if not LevelRules.randomize_monster_spawns(3):
		print("spawn_flag_wrong")
		return false
	if LevelRules.randomize_monster_spawns(1):
		print("spawn_flag_level1_wrong")
		return false
	var fingerprints: Dictionary = {}
	for level_seed in [33, 133, 233, 333, 433]:
		var result := await _generate_level(3, level_seed)
		var parts: Array[String] = []
		for spec in result["layout"].get("enemies", []):
			var cell: Vector2i = spec["cell"]
			parts.append("%s:%d:%d" % [String(spec.get("kind", "")), cell.x, cell.y])
		fingerprints["|".join(parts)] = true
		(result["container"] as Node3D).queue_free()
	var varied := fingerprints.size() > 1
	print("spawn_fingerprints=", fingerprints.size(), " varied=", varied)
	return varied


func _check_live_floor_change() -> bool:
	OS.set_environment("NW_LEVEL", "3")
	OS.set_environment("NW_LEVEL_SEED", "91")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed == null:
		OS.set_environment("NW_LEVEL", "")
		return false
	var main: Node3D = packed.instantiate()
	root.add_child(main)
	if not main.is_level_ready():
		await main.level_ready

	var layout: Dictionary = main.get_layout()
	var start_floor_ok: bool = main.get_active_floor() == 0
	var rooms_floor0 := 0
	for child in main.get_node("GeneratedMap").get_children():
		if String(child.name).begins_with("Room_"):
			rooms_floor0 += 1
	var expected0 := 0
	for room in layout.get("rooms", []):
		if int(room.get("floor", 0)) == 0:
			expected0 += 1
	var scoped_ok := rooms_floor0 == expected0 and expected0 > 0
	print("live_floor0 scoped=", scoped_ok, " rooms=", rooms_floor0)

	if main.has_method("park_monsters"):
		main.park_monsters()

	var stairs: Array = main.stairwells()
	var up: Stairwell = null
	for stair in stairs:
		if (stair as Stairwell).is_up():
			up = stair
	if up == null:
		print("live_up_stair_missing")
		main.queue_free()
		OS.set_environment("NW_LEVEL", "")
		return false

	var blocked := not up.can_use()
	for stage in range(1, LevelRules.key_count(3) + 1):
		main.unlock_stage(stage)
	var unlocked := up.can_use()
	print("live_stair_lock blocked=", blocked, " unlocked=", unlocked)

	await main.change_floor(up.dest_floor, up.dest_cell)
	var moved: bool = main.get_active_floor() == 1
	var rooms_floor1 := 0
	for child in main.get_node("GeneratedMap").get_children():
		if String(child.name).begins_with("Room_"):
			rooms_floor1 += 1
	var expected1 := 0
	for room in main.get_layout().get("rooms", []):
		if int(room.get("floor", 0)) == 1:
			expected1 += 1
	var scoped1_ok := rooms_floor1 == expected1 and expected1 > 0
	print("live_floor1 moved=", moved, " scoped=", scoped1_ok, " rooms=", rooms_floor1)

	var downs: Array = main.stairwells()
	var back_ok := false
	for stair in downs:
		if (stair as Stairwell).is_down():
			await main.change_floor((stair as Stairwell).dest_floor, (stair as Stairwell).dest_cell)
			back_ok = main.get_active_floor() == 0
			break
	print("live_floor_return_ok=", back_ok)

	main.queue_free()
	await create_timer(0.05).timeout
	OS.set_environment("NW_LEVEL", "")
	OS.set_environment("NW_LEVEL_SEED", "")
	return start_floor_ok and scoped_ok and blocked and unlocked and moved and scoped1_ok and back_ok


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
