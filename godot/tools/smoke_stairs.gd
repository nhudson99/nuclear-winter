extends SceneTree

## Walking up the stair flight changes floors. A locked flight can be climbed
## but does not. Arriving upstairs does not immediately send you back.

const WALK_FRAMES := 420


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var gp: Node = root.get_node("GameProgress")
	gp.reset_for_tests()
	OS.set_environment("NW_LEVEL", "3")
	OS.set_environment("NW_LEVEL_SEED", "91")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main: Node3D = packed.instantiate()
	root.add_child(main)
	if not main.is_level_ready():
		await main.level_ready
	main.park_monsters()
	var player: CharacterBody3D = main.get_node("Player")

	var up_room := _room_ending(main, "stairwell_up")
	var up_centered := _flight_centered(up_room)
	print("stair_up_centered=", up_centered)

	var locked_floor: int = main.get_active_floor()
	await _walk_flight(main, player, _room_ending(main, "stairwell_up"), true)
	var stayed_locked: bool = main.get_active_floor() == locked_floor
	print("stair_locked_stays=", stayed_locked, " floor=", main.get_active_floor())

	for stage in range(1, LevelRules.key_count(3) + 1):
		main.unlock_stage(stage)
	await _walk_flight(main, player, _room_ending(main, "stairwell_up"), true)
	var climbed: bool = main.get_active_floor() == 1
	print("stair_walk_up=", climbed, " floor=", main.get_active_floor())

	for _i in 150:
		await physics_frame
	var settled: bool = main.get_active_floor() == 1
	print("stair_no_bounce=", settled, " floor=", main.get_active_floor())

	var down_room := _room_ending(main, "stairwell_down")
	var down_centered := _flight_centered(down_room)
	var down_open := not _floor_covers_mid(down_room)
	var down_descends := _flight_descends(down_room)
	print(
		"stair_down_centered=", down_centered,
		" stair_down_open=", down_open,
		" stair_down_descends=", down_descends
	)

	await _walk_flight(main, player, down_room, false)
	var descended: bool = main.get_active_floor() == 0
	print("stair_walk_down=", descended, " floor=", main.get_active_floor())

	var ok: bool = (
		stayed_locked
		and climbed
		and settled
		and descended
		and up_centered
		and down_centered
		and down_open
		and down_descends
	)
	print("stair_walk_ok=", ok)
	main.queue_free()
	OS.set_environment("NW_LEVEL", "")
	OS.set_environment("NW_LEVEL_SEED", "")
	quit(0 if ok else 1)


func _walk_flight(main: Node, player: CharacterBody3D, room: Node3D, ascending: bool) -> void:
	if room == null or player == null:
		print("stair_room_missing")
		return
	var flight := _flight(room)
	if flight.is_empty():
		print("stair_flight_missing")
		return
	var run: Vector3 = flight["run"]
	var high: Vector3 = flight["high"]
	var start: Vector3 = flight["low"] - run * 1.2
	var direction := run
	if not ascending:
		start = high + run * 2.4
		direction = -run
	start.y = 0.05
	var floor_before: int = main.get_active_floor()
	player.velocity = Vector3.ZERO
	player.global_position = start
	print(
		"stair_walk_begin up=", ascending,
		" start=", start,
		" dir=", direction,
		" low=", flight["low"],
		" high=", flight["high"]
	)
	_press_walk(direction)
	for _i in WALK_FRAMES:
		await physics_frame
		if main.get_active_floor() != floor_before:
			break
	_release_walk()
	player.velocity = Vector3.ZERO


func _flight(room: Node3D) -> Dictionary:
	if room == null:
		return {}
	var treads: Array[MeshInstance3D] = []
	_collect_treads(room, treads)
	if treads.size() < 2:
		return {}
	var low := treads[0]
	var high := treads[0]
	for tread in treads:
		if tread.global_position.y < low.global_position.y:
			low = tread
		if tread.global_position.y > high.global_position.y:
			high = tread
	var run := high.global_position - low.global_position
	run.y = 0.0
	if run.length() < 0.2:
		return {}
	return {"low": low.global_position, "high": high.global_position, "run": run.normalized()}


func _room_ending(main: Node, suffix: String) -> Node3D:
	var map := main.get_node_or_null("GeneratedMap")
	if map == null:
		return null
	for child in map.get_children():
		if String(child.name).ends_with(suffix):
			return child as Node3D
	return null


func _press_walk(direction: Vector3) -> void:
	_release_walk()
	var sx := (direction.x - direction.z) * 0.5
	var sy := -(direction.x + direction.z) * 0.5
	if sx > 0.2:
		Input.action_press("move_right")
	elif sx < -0.2:
		Input.action_press("move_left")
	if sy > 0.2:
		Input.action_press("move_up")
	elif sy < -0.2:
		Input.action_press("move_down")


func _release_walk() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_up")
	Input.action_release("move_down")


func _flight_centered(room: Node3D) -> bool:
	if room == null:
		return false
	var flight := _flight(room)
	if flight.is_empty():
		return false
	var mid: Vector3 = (flight["low"] + flight["high"]) * 0.5
	var flat := mid - room.global_position
	flat.y = 0.0
	return flat.length() < 1.5


func _flight_descends(room: Node3D) -> bool:
	var flight := _flight(room)
	if flight.is_empty():
		return false
	var low: Vector3 = flight["low"]
	var high: Vector3 = flight["high"]
	return high.y > low.y + 0.8 and high.y < 0.45 and low.y < -0.8


func _floor_covers_mid(room: Node3D) -> bool:
	var flight := _flight(room)
	if flight.is_empty():
		return true
	var mid: Vector3 = (flight["low"] + flight["high"]) * 0.5
	return _floor_covers(room, mid)


func _floor_covers(room: Node3D, point: Vector3) -> bool:
	var floors: Array[MeshInstance3D] = []
	_collect_floors(room, floors)
	for mesh in floors:
		if mesh.mesh == null:
			continue
		var xf := mesh.global_transform
		var bounds := mesh.mesh.get_aabb()
		var center := xf * bounds.get_center()
		var half := (xf.basis * bounds.size).abs() * 0.5
		if absf(point.x - center.x) <= half.x and absf(point.z - center.z) <= half.z:
			return true
	return false


func _collect_floors(node: Node, into: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and String(node.name).begins_with("Floor"):
		into.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_floors(child, into)


func _collect_treads(node: Node, into: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and String(node.name).begins_with("StairTread_"):
		into.append(node)
	for child in node.get_children():
		_collect_treads(child, into)
