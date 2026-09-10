extends SceneTree

## Headless smoke for the procedural map: room module contract, seed replay,
## layout variety, full connectivity, doorway carving and collision cooking.

const ROOM_COUNT := 9

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var modules_ok := _check_room_modules()

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

	var types_ok := _covers_all_types(first["layout"]) and _covers_all_types(other["layout"])
	print("all_room_types_ok=", types_ok)

	var doorways_ok := _check_doorways(first) and _check_doorways(other)
	print("doorways_ok=", doorways_ok)

	var collision_ok := _check_collision(first["container"])
	print("collision_ok=", collision_ok)

	var spawns_ok := _check_spawns(first["layout"])
	print("spawn_points_ok=", spawns_ok)

	var ground_ok: bool = (first["container"] as Node3D).get_node_or_null("Ground") != null
	print("ground_ok=", ground_ok)

	var all_ok: bool = (
		modules_ok
		and count_ok
		and deterministic
		and varies
		and connected
		and types_ok
		and doorways_ok
		and collision_ok
		and spawns_ok
		and ground_ok
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
	parts.append("exit:%s" % layout["exit_side"])
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


func _covers_all_types(layout: Dictionary) -> bool:
	var seen := {}
	for room in layout["rooms"]:
		seen[room["type"]] = true
	for type_name in MapGenerator.ROOM_TYPES:
		if not seen.has(type_name):
			return false
	return true


## A plug must be gone wherever two rooms meet and present wherever a room
## faces the outside, except the one exterior wall opened for the exit.
func _check_doorways(result: Dictionary) -> bool:
	var layout: Dictionary = result["layout"]
	var container: Node3D = result["container"]
	var occupied := {}
	for room in layout["rooms"]:
		occupied[room["cell"]] = room

	var start_cell: Vector2i = layout["start_cell"]
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
			var is_exit: bool = cell == start_cell and side == exit_side
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
	var in_map := (
		centers.has(start_cell)
		and centers.has(objective_cell)
		and centers.has(monster_cell)
	)
	var objective_away: bool = objective_cell != start_cell
	var monster_away: bool = monster_cell != start_cell
	print(
		"spawns start=", start_cell,
		" objective=", objective_cell,
		" monster=", monster_cell,
		" in_map=", in_map
	)
	return in_map and objective_away and monster_away
