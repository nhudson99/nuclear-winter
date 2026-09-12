extends SceneTree

## Headless smoke for the monster track: doorway graph, intersection rolls,
## chase that goes through doors instead of walls, and return-to-track after
## losing the player.

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

	var player: CharacterBody3D = main.get_node("Player")
	var monster: CharacterBody3D = main.get_node("Monster")
	if player == null or monster == null:
		push_error("Player or Monster missing")
		quit(1)
		return
	if main.has_method("park_monsters"):
		main.park_monsters(monster)

	var layout: Dictionary = main.get_layout()
	var track: Dictionary = layout.get("monster_track", {})
	var nodes: Dictionary = track.get("nodes", {})
	var start_cell: Vector2i = layout["start_cell"]
	var start_center := _cell_center(start_cell)

	var rolls_ok: bool = (
		monster.direction_from_roll(0) == MapGenerator.TRACK_LEFT
		and monster.direction_from_roll(24) == MapGenerator.TRACK_LEFT
		and monster.direction_from_roll(25) == MapGenerator.TRACK_RIGHT
		and monster.direction_from_roll(49) == MapGenerator.TRACK_RIGHT
		and monster.direction_from_roll(50) == MapGenerator.TRACK_UP
		and monster.direction_from_roll(74) == MapGenerator.TRACK_UP
		and monster.direction_from_roll(75) == MapGenerator.TRACK_DOWN
		and monster.direction_from_roll(99) == MapGenerator.TRACK_DOWN
	)
	print("intersection_roll_ok=", rolls_ok)

	var hub_id := _first_intersection_id(nodes)
	var turn_ok := true
	if hub_id.is_empty():
		print("intersection_turn_ok=skipped (no 3-way room)")
	else:
		var exits: Dictionary = nodes[hub_id].get("exits", {})
		var cases := [
			{"roll": 0, "dir": MapGenerator.TRACK_LEFT},
			{"roll": 25, "dir": MapGenerator.TRACK_RIGHT},
			{"roll": 50, "dir": MapGenerator.TRACK_UP},
			{"roll": 75, "dir": MapGenerator.TRACK_DOWN},
		]
		for entry in cases:
			var dir: String = entry["dir"]
			if not exits.has(dir):
				continue
			var chosen: String = monster.pick_next_node_with_roll(hub_id, "", int(entry["roll"]))
			if chosen != str(exits[dir]):
				print("intersection_turn_wrong roll=", entry["roll"], " dir=", dir, " got=", chosen)
				turn_ok = false
		print("intersection_turn_ok=", turn_ok, " hub=", hub_id, " exits=", exits)

	var grace_ok := is_equal_approx(monster.lose_sight_grace, 5.0)
	print("lose_sight_grace_ok=", grace_ok, " grace=", monster.lose_sight_grace)

	monster.set_physics_process(false)
	monster.touch_damage = 0.0
	player.set_physics_process(false)

	# Chase around a wall: same-latitude rooms so a straight line hits the
	# shared wall instead of the doorway. The track must route through the door.
	var neighbour := _first_neighbour(layout, start_cell)
	var neighbour_center := _cell_center(neighbour)
	var door_pos := (start_center + neighbour_center) * 0.5
	door_pos.y = MapGenerator.TRACK_Y
	var offset := Vector3(0.0, 0.05, 4.0)
	monster.global_position = start_center + offset
	player.global_position = neighbour_center + offset
	player.velocity = Vector3.ZERO
	monster.velocity = Vector3.ZERO
	monster.set_force_detect(true)
	monster.debug_enter_chase()
	monster.set_physics_process(true)
	var min_door_dist := 999.0
	var chase_start := monster.global_position
	for _i in 90:
		await create_timer(0.033).timeout
		min_door_dist = minf(
			min_door_dist,
			_planar_distance(monster.global_position, door_pos)
		)
	var after := monster.global_position
	var crossed_toward := (
		_planar_distance(after, neighbour_center)
		< _planar_distance(chase_start, neighbour_center) - 1.0
	)
	var used_doorway := min_door_dist < 1.6
	var chase_ok := crossed_toward and used_doorway
	print(
		"doorway_chase_ok=",
		chase_ok,
		" min_door_dist=",
		min_door_dist,
		" start=",
		chase_start,
		" after=",
		after,
		" neighbour=",
		neighbour_center
	)

	# Return to the main track 5s (shortened for the smoke) after losing detection.
	monster.set_physics_process(false)
	monster.set_force_detect(false)
	player.global_position = start_center + Vector3(500.0, 0.0, 500.0)
	monster.global_position = start_center + Vector3(2.8, 0.05, 2.8)
	monster.lose_sight_grace = 0.25
	monster.debug_enter_chase()
	monster.set_physics_process(true)
	await create_timer(0.12).timeout
	var still_chasing: bool = monster.get_ai_mode_name() == "chase"
	await create_timer(0.4).timeout
	var returning: bool = monster.get_ai_mode_name() == "return" or monster.get_ai_mode_name() == "patrol"
	await create_timer(1.6).timeout
	var back_on_track: bool = MapGenerator.closest_distance_to_track(monster.global_position, track) < 0.95
	var settled: bool = monster.get_ai_mode_name() == "patrol" or monster.get_ai_mode_name() == "return"
	var return_ok: bool = still_chasing and returning and back_on_track and settled
	print(
		"return_to_track_ok=",
		return_ok,
		" still_chasing=",
		still_chasing,
		" after_grace=",
		monster.get_ai_mode_name(),
		" on_track=",
		back_on_track,
		" dist=",
		MapGenerator.closest_distance_to_track(monster.global_position, track)
	)

	var all_ok: bool = rolls_ok and turn_ok and grace_ok and chase_ok and return_ok
	print("monster_track_smoke_ok=", all_ok)
	quit(0 if all_ok else 2)


func _first_intersection_id(nodes: Dictionary) -> String:
	for id in nodes:
		if str(nodes[id].get("kind", "")) != "room":
			continue
		var exits: Dictionary = nodes[id].get("exits", {})
		if exits.size() >= 3:
			return str(id)
	return ""


func _first_neighbour(layout: Dictionary, cell: Vector2i) -> Vector2i:
	var occupied := {}
	for room in layout["rooms"]:
		occupied[room["cell"]] = true
	for side in MapGenerator.SIDES:
		var candidate: Vector2i = cell + MapGenerator.SIDE_STEPS[side]
		if occupied.has(candidate):
			return candidate
	return cell


func _cell_center(cell: Vector2i) -> Vector3:
	return MapGenerator.cell_to_world(cell)


func _planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
