extends SceneTree

## Headless smoke for the procedural map: room module contract, seed replay,
## layout variety, full connectivity, doorway carving, collision cooking and
## the monster track through room and doorway centres.

const ROOM_COUNT := 9

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var modules_ok := _check_room_modules()
	var stairs_ok := _check_stair_modules()
	print("stair_modules_ok=", stairs_ok)

	var first := await _generate(101, ROOM_COUNT)
	var replay := await _generate(101, ROOM_COUNT)
	var other := await _generate(202, ROOM_COUNT)

	var count_ok: bool = (first["layout"]["rooms"] as Array).size() == ROOM_COUNT
	print("room_count_ok=", count_ok, " rooms=", (first["layout"]["rooms"] as Array).size())

	var deterministic: bool = _fingerprint(first["layout"]) == _fingerprint(replay["layout"])
	print("seed_replay_ok=", deterministic)

	var varies: bool = _fingerprint(first["layout"]) != _fingerprint(other["layout"])
	print("seed_variety_ok=", varies)

	var connected := _is_connected(first["layout"]) and _is_connected(other["layout"])
	print("connectivity_ok=", connected)

	var types_ok := _check_types(first["layout"]) and _check_types(other["layout"])
	print("all_room_types_ok=", types_ok)

	# A layout whose growth buries the start cell must still open an exit
	# somewhere, otherwise the run is unwinnable.
	var exits_ok := true
	for level_seed in range(1, 40):
		var probe := await _generate(level_seed, ROOM_COUNT)
		var side: String = probe["layout"]["exit_side"]
		if side.is_empty() or not MapGenerator.SIDES.has(side):
			print("exit_missing seed=", level_seed)
			exits_ok = false
		(probe["container"] as Node3D).queue_free()
	print("exit_always_opened_ok=", exits_ok)

	var doorways_ok := _check_doorways(first) and _check_doorways(other)
	print("doorways_ok=", doorways_ok)

	var collision_ok := _check_collision(first["container"])
	print("collision_ok=", collision_ok)

	var spawns_ok := _check_spawns(first["layout"])
	print("spawn_points_ok=", spawns_ok)

	var ground_ok: bool = (first["container"] as Node3D).get_node_or_null("Ground") != null
	print("ground_ok=", ground_ok)

	var track_ok := _check_monster_track(first) and _check_monster_track(other)
	print("monster_track_ok=", track_ok)

	var all_ok: bool = (
		modules_ok
		and stairs_ok
		and exits_ok
		and count_ok
		and deterministic
		and varies
		and connected
		and types_ok
		and doorways_ok
		and collision_ok
		and spawns_ok
		and ground_ok
		and track_ok
	)
	print("procgen_smoke_ok=", all_ok)
	quit(0 if all_ok else 1)


## Every module needs the shell nodes the generator manipulates by name.
func _check_room_modules() -> bool:
	var ok := true
	for type_name in MapGenerator.ROOM_TYPES:
		var path: String = MapGenerator.ROOM_SCENES[type_name]
		if not ResourceLoader.exists(path):
			print("module_missing=", path)
			ok = false
			continue
		var room: Node3D = (load(path) as PackedScene).instantiate()
		var required: Array[String] = ["Floor"]
		for side in MapGenerator.SIDES:
			required.append("Wall_%s_A" % side)
			required.append("Wall_%s_B" % side)
			required.append("Wall_%s_L" % side)
			required.append("Plug_%s" % side)
		var missing: Array[String] = []
		for node_name in required:
			if MapGenerator.find_child_by_name(room, node_name) == null:
				missing.append(node_name)
		print("module_ok=", missing.is_empty(), " type=", type_name, " missing=", missing)
		if not missing.is_empty():
			ok = false
		room.free()
	return ok


func _check_stair_modules() -> bool:
	var ok := true
	for type_name in MapGenerator.STAIR_TYPES:
		var path: String = MapGenerator.ROOM_SCENES[type_name]
		if not ResourceLoader.exists(path):
			print("stair_module_missing=", path)
			ok = false
			continue
		var room: Node3D = (load(path) as PackedScene).instantiate()
		var required: Array[String] = ["Floor", "StairUse"]
		for side in MapGenerator.SIDES:
			required.append("Wall_%s_A" % side)
			required.append("Wall_%s_B" % side)
			required.append("Wall_%s_L" % side)
			required.append("Plug_%s" % side)
		var missing: Array[String] = []
		for node_name in required:
			if MapGenerator.find_child_by_name(room, node_name) == null:
				missing.append(node_name)
		print("stair_module_ok=", missing.is_empty(), " type=", type_name, " missing=", missing)
		if not missing.is_empty():
			ok = false
		room.free()
	return ok


func _generate(level_seed: int, count: int) -> Dictionary:
	var container := Node3D.new()
	container.name = "Map_%d" % level_seed
	root.add_child(container)

	var generator := MapGenerator.new()
	root.add_child(generator)
	var layout: Dictionary = await generator.generate(container, level_seed, count)
	generator.queue_free()

	return {"layout": layout, "container": container}


func _fingerprint(layout: Dictionary) -> String:
	var parts: Array[String] = []
	for room in layout["rooms"]:
		parts.append("%d/%d:%s" % [room["cell"].x, room["cell"].y, room["type"]])
	parts.append("exit:%d/%d:%s" % [layout["exit_cell"].x, layout["exit_cell"].y, layout["exit_side"]])
	return "|".join(parts)


## Grid-flood from the start cell must reach every placed room.
func _is_connected(layout: Dictionary) -> bool:
	var cells := {}
	for room in layout["rooms"]:
		cells[room["cell"]] = false

	var start: Vector2i = layout["start_cell"]
	if not cells.has(start):
		return false

	var queue: Array[Vector2i] = [start]
	cells[start] = true
	var reached := 1
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for side in MapGenerator.SIDES:
			var next: Vector2i = cell + MapGenerator.SIDE_STEPS[side]
			if cells.has(next) and not cells[next]:
				cells[next] = true
				reached += 1
				queue.append(next)
	return reached == cells.size()


## All four types must appear, and dealing in whole cycles should keep their
## counts within one of each other rather than letting one type dominate.
func _check_types(layout: Dictionary) -> bool:
	var counts := {}
	for type_name in MapGenerator.ROOM_TYPES:
		counts[type_name] = 0
	for room in layout["rooms"]:
		if not counts.has(room["type"]):
			print("unknown_room_type=", room["type"])
			return false
		counts[room["type"]] += 1

	var lowest := 1 << 30
	var highest := 0
	for type_name in counts:
		lowest = mini(lowest, counts[type_name])
		highest = maxi(highest, counts[type_name])
	var balanced := lowest >= 1 and highest - lowest <= 1
	print("room_type_counts=", counts, " balanced=", balanced)
	return balanced


## A plug must be gone wherever two rooms meet and present wherever a room
## faces the outside, except the one exterior wall opened for the exit.
func _check_doorways(result: Dictionary) -> bool:
	var layout: Dictionary = result["layout"]
	var container: Node3D = result["container"]
	var occupied := {}
	for room in layout["rooms"]:
		occupied[room["cell"]] = room

	var exit_cell: Vector2i = layout["exit_cell"]
	var exit_side: String = layout["exit_side"]
	var ok := true
	for room in layout["rooms"]:
		var cell: Vector2i = room["cell"]
		var node: Node3D = container.get_node_or_null(
			"Room_%d_%d_%s" % [cell.x, cell.y, room["type"]]
		)
		if node == null:
			print("room_node_missing=", cell)
			return false
		for side in MapGenerator.SIDES:
			var has_plug := MapGenerator.find_child_by_name(node, "Plug_%s" % side) != null
			var is_shared: bool = occupied.has(cell + MapGenerator.SIDE_STEPS[side])
			var is_exit: bool = cell == exit_cell and side == exit_side
			var should_be_open := is_shared or is_exit
			if has_plug == should_be_open:
				print(
					"doorway_wrong cell=", cell,
					" side=", side,
					" plug=", has_plug,
					" shared=", is_shared,
					" exit=", is_exit
				)
				ok = false
	return ok


func _check_collision(container: Node3D) -> bool:
	var ok := true
	for child in container.get_children():
		if not (child as Node3D).name.begins_with("Room_"):
			continue
		var body := child.get_node_or_null("RoomCollision") as StaticBody3D
		if body == null or body.get_child_count() == 0:
			print("collision_missing=", child.name)
			ok = false
			continue
		if body.collision_layer != MapGenerator.WORLD_LAYER:
			print("collision_layer_wrong=", child.name, " layer=", body.collision_layer)
			ok = false
	return ok


## Spawns must sit inside distinct rooms, with the objective away from the start.
func _check_spawns(layout: Dictionary) -> bool:
	var centers := {}
	for room in layout["rooms"]:
		centers[room["cell"]] = true

	var start_cell: Vector2i = layout["start_cell"]
	var objective_cell: Vector2i = layout["objective_cell"]
	var monster_cell: Vector2i = layout["monster_cell"]
	var slime_cell: Vector2i = layout.get("slime_cell", monster_cell)
	var tank_cell: Vector2i = layout.get("tank_cell", monster_cell)
	var exit_cell: Vector2i = layout["exit_cell"]
	var in_map := (
		centers.has(start_cell)
		and centers.has(objective_cell)
		and centers.has(monster_cell)
		and centers.has(slime_cell)
		and centers.has(tank_cell)
		and centers.has(exit_cell)
	)
	# Standing on the objective, or on the exit while holding it, would let a run
	# resolve itself the moment it starts.
	var objective_away: bool = objective_cell != start_cell and objective_cell != exit_cell
	var monster_away: bool = monster_cell != start_cell
	var slime_away: bool = slime_cell != start_cell
	var tank_away: bool = tank_cell != start_cell
	print(
		"spawns start=", start_cell,
		" objective=", objective_cell,
		" monster=", monster_cell,
		" slime=", slime_cell,
		" tank=", tank_cell,
		" exit=", exit_cell,
		" in_map=", in_map
	)
	return in_map and objective_away and monster_away and slime_away and tank_away


## Room centres and interior doorway centres must form one connected graph.
func _check_monster_track(result: Dictionary) -> bool:
	var layout: Dictionary = result["layout"]
	var container: Node3D = result["container"]
	var track: Dictionary = layout.get("monster_track", {})
	var nodes: Dictionary = track.get("nodes", {})
	if nodes.is_empty():
		print("track_missing")
		return false

	var scene_root := container.get_node_or_null("MonsterTrack")
	if scene_root == null or scene_root.get_child_count() != nodes.size():
		print(
			"track_scene_wrong root=",
			scene_root != null,
			" children=",
			scene_root.get_child_count() if scene_root else 0,
			" nodes=",
			nodes.size()
		)
		return false

	for room in layout["rooms"]:
		var cell: Vector2i = room["cell"]
		var room_id := MapGenerator.room_track_id(cell)
		if not nodes.has(room_id):
			print("room_track_missing=", cell)
			return false
		var pos: Vector3 = nodes[room_id]["position"]
		var expected := MapGenerator.cell_to_world(cell) + Vector3(0.0, MapGenerator.TRACK_Y, 0.0)
		if _planar_distance(pos, expected) > 0.01:
			print("room_center_wrong cell=", cell, " pos=", pos, " expected=", expected)
			return false

	var occupied := {}
	for room in layout["rooms"]:
		occupied[room["cell"]] = true

	var expected_doors := 0
	for room in layout["rooms"]:
		var cell: Vector2i = room["cell"]
		for side in MapGenerator.TRACK_CANONICAL_SIDES:
			var neighbor: Vector2i = cell + MapGenerator.SIDE_STEPS[side]
			if not occupied.has(neighbor):
				continue
			expected_doors += 1
			var door_id := MapGenerator.door_track_id(cell, side)
			if not nodes.has(door_id):
				print("door_track_missing cell=", cell, " side=", side)
				return false
			var door_pos: Vector3 = nodes[door_id]["position"]
			var door_expected := MapGenerator.door_track_position(cell, side)
			if _planar_distance(door_pos, door_expected) > 0.01:
				print("door_center_wrong id=", door_id, " pos=", door_pos)
				return false
			var exits: Dictionary = nodes[door_id].get("exits", {})
			var room_a := MapGenerator.room_track_id(cell)
			var room_b := MapGenerator.room_track_id(neighbor)
			var has_a := false
			var has_b := false
			for dir in exits:
				var dest := str(exits[dir])
				if dest == room_a:
					has_a = true
				if dest == room_b:
					has_b = true
			if not has_a or not has_b:
				print("door_links_wrong id=", door_id, " exits=", exits)
				return false

	var room_count: int = (layout["rooms"] as Array).size()
	if nodes.size() != room_count + expected_doors:
		print(
			"track_count_wrong nodes=", nodes.size(),
			" rooms=", room_count,
			" doors=", expected_doors
		)
		return false

	var start_id := MapGenerator.room_track_id(layout["start_cell"])
	if not _track_graph_connected(nodes, start_id):
		print("track_not_connected start=", start_id)
		return false

	print(
		"track_graph_ok=true rooms=", room_count,
		" doors=", expected_doors,
		" nodes=", nodes.size()
	)
	return true


func _planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _track_graph_connected(nodes: Dictionary, start_id: String) -> bool:
	if not nodes.has(start_id):
		return false
	var seen := {start_id: true}
	var queue: Array[String] = [start_id]
	while not queue.is_empty():
		var cur: String = queue.pop_back()
		var exits: Dictionary = nodes[cur].get("exits", {})
		for dir in exits:
			var nxt := str(exits[dir])
			if seen.has(nxt):
				continue
			if not nodes.has(nxt):
				return false
			seen[nxt] = true
			queue.append(nxt)
	return seen.size() == nodes.size()
