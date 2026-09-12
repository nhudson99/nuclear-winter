extends SceneTree

## Drive the player with fake WASD and assert Walk/Run play and the mesh yaws.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main: Node3D = packed.instantiate()
	root.add_child(main)
	if not main.is_level_ready():
		await main.level_ready

	if main.has_method("park_monsters"):
		main.park_monsters()

	var player: CharacterBody3D = main.get_node("Player")
	player.unlock_input()
	var anim := _find_anim(player)
	var visual: Node3D = player.get_node("Model")
	var start := player.global_position
	var yaw0 := visual.rotation.y

	Input.action_press("move_up")
	for _i in range(20):
		await physics_frame
	Input.action_release("move_up")

	var walked := player.global_position.distance_to(start) > 0.4
	var clip := anim.current_animation if anim else ""
	var yaw1 := visual.rotation.y
	var turned := absf(angle_difference(yaw1, yaw0)) > 0.15
	print(
		"walk_clip=",
		clip,
		" walk_playing=",
		anim.is_playing() if anim else false,
		" moved=",
		walked,
		" dist=",
		player.global_position.distance_to(start),
		" yaw0=",
		yaw0,
		" yaw1=",
		yaw1,
		" turned=",
		turned
	)

	Input.action_press("move_right")
	for _i in range(20):
		await physics_frame
	var yaw2 := visual.rotation.y
	var clip2 := anim.current_animation if anim else ""
	Input.action_release("move_right")
	print(
		"strafe_clip=",
		clip2,
		" yaw2=",
		yaw2,
		" yaw_delta=",
		angle_difference(yaw2, yaw1)
	)

	var run_start := player.global_position
	Input.action_press("sprint")
	Input.action_press("move_up")
	for _i in range(20):
		await physics_frame
	Input.action_release("move_up")
	Input.action_release("sprint")
	var run_clip := anim.current_animation if anim else ""
	var ran := player.global_position.distance_to(run_start) > 1.2
	print("run_clip=", run_clip, " ran=", ran, " dist=", player.global_position.distance_to(run_start))

	var ok := walked and clip == "Walk" and turned and run_clip == "Run" and ran
	print("player_anim_smoke_ok=", ok)
	quit(0 if ok else 1)

func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_anim(child)
		if found:
			return found
	return null
