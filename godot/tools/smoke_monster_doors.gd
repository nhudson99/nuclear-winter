extends SceneTree

## Headless gameplay smoke test: doors are walkable and monster tracks when in view.

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

	# Walk north through the center doors toward the monster.
	player.set_physics_process(false)
	var start := player.global_position
	player.velocity = Vector3(0, 0, -5.5)
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

	# Place player in front of monster with clear LOS and force facing.
	player.global_position = Vector3(0.0, 0.05, -3.5)
	monster.global_position = Vector3(0.0, 0.05, -6.2)
	var mesh: Node3D = monster.get_node("MonsterMesh")
	# Face toward player (+Z): mesh -Z forward => yaw = PI.
	mesh.rotation.y = PI
	player.velocity = Vector3.ZERO
	monster.velocity = Vector3.ZERO

	var monster_start := monster.global_position
	for i in 75:
		await create_timer(0.033).timeout
	var monster_after := monster.global_position
	var chased := monster_after.z > monster_start.z + 0.6
	print("monster_chase_ok=", chased, " start_z=", monster_start.z, " after_z=", monster_after.z)

	# Break LOS by hiding player behind a side wall position.
	player.global_position = Vector3(-4.5, 0.05, -6.2)
	mesh.rotation.y = PI
	var hidden_start := monster.global_position
	await create_timer(2.0).timeout
	var hidden_after := monster.global_position
	var stopped := hidden_after.distance_to(hidden_start) < 1.25
	print("monster_lose_sight_ok=", stopped, " drift=", hidden_after.distance_to(hidden_start))

	var ok := moved_north and chased and stopped
	print("SMOKE_RESULT=", ok)
	quit(0 if ok else 2)
