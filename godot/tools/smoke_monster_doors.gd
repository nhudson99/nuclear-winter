extends SceneTree

## Headless gameplay smoke: doors, proximity chase, track patrol, touch damage,
## health bars. Positions are read from the generated layout rather than authored
## coordinates, since every run rolls a different floorplan.

## One tile is 12 m and a driven step covers move_speed / physics tick, so this
## is comfortably more than enough to cross a room.
const WALK_STEPS := 150
const WALK_SPEED := 5.5
const WALK_GRAVITY := 20.0

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

	var layout: Dictionary = main.get_layout()
	var start_cell: Vector2i = layout["start_cell"]
	var start_center: Vector3 = _cell_center(start_cell)

	var player_bar := player.get_node_or_null("HealthBar")
	var monster_bar := monster.get_node_or_null("HealthBar")
	var bars_ok := player_bar != null and monster_bar != null
	print("health_bars_ok=", bars_ok)

	var hp_ok := is_equal_approx(float(player.health), 100.0) and is_equal_approx(float(monster.health), 100.0)
	print("starting_hp_ok=", hp_ok, " player=", player.health, " monster=", monster.health)

	# Park the monster far away so it cannot interfere with the walk tests.
	monster.set_physics_process(false)
	monster.touch_damage = 0.0
	monster.global_position = Vector3(1000.0, 0.05, 1000.0)
	player.set_physics_process(false)

	# A shared wall must be walkable: cross from the start room into a neighbour.
	var neighbour_cell := _first_neighbour(layout, start_cell)
	var neighbour_center := _cell_center(neighbour_cell)
	var walk_dir := (neighbour_center - start_center).normalized()
	await _walk_from(player, start_center, walk_dir, WALK_STEPS)
	var walked_distance := _planar_distance(player.global_position, neighbour_center)
	var walked_through := walked_distance < MapGenerator.TILE * 0.5
	print(
		"door_walk_ok=", walked_through,
		" from=", start_cell,
		" to=", neighbour_cell,
		" dist_to_target_room=", walked_distance
	)

	# An outward-facing wall must not be: the same walk into a sealed side stops.
	var sealed := _find_sealed_wall(layout)
	var sealed_blocked := false
	var sealed_progress := 0.0
	if sealed.is_empty():
		print("sealed_wall_ok=skipped (layout has no sealed side)")
		sealed_blocked = true
	else:
		var sealed_center := _cell_center(sealed["cell"])
		var sealed_dir: Vector3 = Vector3(
			MapGenerator.SIDE_STEPS[sealed["side"]].x,
			0.0,
			MapGenerator.SIDE_STEPS[sealed["side"]].y
		)
		await _walk_from(player, sealed_center, sealed_dir, WALK_STEPS)
		sealed_progress = (player.global_position - sealed_center).dot(sealed_dir)
		sealed_blocked = sealed_progress < MapGenerator.TILE * 0.5 - 0.1
		print(
			"sealed_wall_ok=", sealed_blocked,
			" cell=", sealed["cell"],
			" side=", sealed["side"],
			" progress=", sealed_progress
		)

	# Proximity chase: player beside the monster, outside its FOV cone.
	monster.global_position = start_center + Vector3(0.0, 0.05, 0.0)
	player.global_position = start_center + Vector3(2.4, 0.05, 0.0)
	var mesh: Node3D = monster.get_node("MonsterMesh")
	# Face north (-Z); player is due east → outside 75° FOV, inside proximity radius.
	mesh.rotation.y = 0.0
	monster._time_since_seen = 999.0
	player.velocity = Vector3.ZERO
	monster.velocity = Vector3.ZERO
	monster.set_physics_process(true)
	var prox_start := monster.global_position
	var prox_player_start := player.global_position
	for _i in 45:
		await create_timer(0.033).timeout
	var prox_after := monster.global_position
	var proximity_chased := prox_after.distance_to(prox_player_start) < prox_start.distance_to(prox_player_start) - 0.5
	print(
		"proximity_chase_ok=",
		proximity_chased,
		" start_dist=",
		prox_start.distance_to(prox_player_start),
		" after_dist=",
		prox_after.distance_to(prox_player_start)
	)

	# Touch damage: approach from outside the touch radius so body_entered fires.
	monster.set_physics_process(false)
	monster.touch_damage = 100.0
	player._alive = true
	player.health = 100.0
	if player_bar and player_bar.has_method("set_health"):
		player_bar.set_health(100.0, 100.0)
	monster.global_position = start_center + Vector3(0.0, 0.05, 0.0)
	player.global_position = start_center + Vector3(3.0, 0.05, 0.0)
	await create_timer(0.15).timeout
	player.global_position = start_center + Vector3(0.15, 0.05, 0.0)
	await create_timer(0.35).timeout
	var touch_ok: bool = float(player.health) <= 0.0 or not player.is_alive()
	print("touch_damage_ok=", touch_ok, " player_hp=", player.health)

	# Track patrol: hide the player and walk from the southern room centre. The
	# monster should move and stay on the generated doorway track.
	player._alive = true
	player.health = 100.0
	player.global_position = start_center + Vector3(0.0, 0.05, 0.0) + Vector3(500.0, 0.0, 500.0)
	monster.global_position = _southernmost_center(layout) + Vector3(0.0, 0.05, 0.0)
	monster.configure_patrol_for_test(1.0, 0)
	print("patrol_setup mode=", monster.get_ai_mode_name(), " grace=", monster.lose_sight_grace)
	monster.set_physics_process(true)
	var patrol_start := monster.global_position
	await create_timer(1.6).timeout
	var patrol_moved := monster.global_position.distance_to(patrol_start) > 0.35
	var on_track := (
		MapGenerator.closest_distance_to_track(monster.global_position, layout["monster_track"]) < 1.2
	)
	var grace_ok := is_equal_approx(monster.lose_sight_grace, 5.0)
	print(
		"track_patrol_ok=",
		patrol_moved and on_track,
		" moved=",
		patrol_moved,
		" on_track=",
		on_track,
		" mode=",
		monster.get_ai_mode_name(),
		" grace_ok=",
		grace_ok
	)

	var ok: bool = (
		bars_ok
		and hp_ok
		and walked_through
		and sealed_blocked
		and proximity_chased
		and touch_ok
		and patrol_moved
		and on_track
		and grace_ok
	)
	print("SMOKE_RESULT=", ok)
	quit(0 if ok else 2)


## Drives the body straight from a room centre. Stepping on `physics_frame`
## keeps move_and_slide's delta in sync with the engine, which a wall-clock
## timer does not.
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


## First room side that faces the outside, skipping the wall opened for the exit.
func _find_sealed_wall(layout: Dictionary) -> Dictionary:
	var occupied := {}
	for room in layout["rooms"]:
		occupied[room["cell"]] = true
	var exit_cell: Vector2i = layout["exit_cell"]
	var exit_side: String = layout["exit_side"]
	for room in layout["rooms"]:
		var cell: Vector2i = room["cell"]
		for side in MapGenerator.SIDES:
			if occupied.has(cell + MapGenerator.SIDE_STEPS[side]):
				continue
			if cell == exit_cell and side == exit_side:
				continue
			return {"cell": cell, "side": side}
	return {}


func _planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _cell_center(cell: Vector2i) -> Vector3:
	return Vector3(float(cell.x) * MapGenerator.TILE, 0.0, float(cell.y) * MapGenerator.TILE)


func _first_neighbour(layout: Dictionary, cell: Vector2i) -> Vector2i:
	var occupied := {}
	for room in layout["rooms"]:
		occupied[room["cell"]] = true
	for side in MapGenerator.SIDES:
		var candidate: Vector2i = cell + MapGenerator.SIDE_STEPS[side]
		if occupied.has(candidate):
			return candidate
	return cell


func _southernmost_center(layout: Dictionary) -> Vector3:
	var best: Vector2i = layout["start_cell"]
	for room in layout["rooms"]:
		if (room["cell"] as Vector2i).y > best.y:
			best = room["cell"]
	return _cell_center(best)
