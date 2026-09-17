extends SceneTree

## Headless smoke for the core loop: pickup (E), monster alert, victory aristocrat, defeat aristocrat.

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
	var pickup: Area3D = main.get_node_or_null("PickupItem")
	var exit_zone: Area3D = main.get_node_or_null("ExitZone")
	if player == null or monster == null or pickup == null or exit_zone == null:
		push_error("Missing Player/Monster/PickupItem/ExitZone")
		quit(1)
		return
	if main.has_method("park_monsters"):
		main.park_monsters(monster)

	var nodes_ok := true
	print("loop_nodes_ok=", nodes_ok)

	var gp: Node = root.get_node("GameProgress")
	gp.reset_for_tests()

	var anim := _find_animation_player(player)
	var clips := PackedStringArray()
	if anim:
		for clip_name in anim.get_animation_list():
			clips.append(clip_name)
	var clips_ok := (
		anim != null
		and clips.has("Idle")
		and clips.has("Walk")
		and clips.has("Run")
		and clips.has("Die")
	)
	print("player_clips_ok=", clips_ok, " clips=", clips)

	# Baseline monster difficulty.
	var base_dwell: float = monster.section_dwell_time
	var base_prox: float = monster.proximity_radius
	print("base_dwell=", base_dwell, " base_prox=", base_prox)

	# Pickup via interact near the item.
	monster.set_physics_process(false)
	monster.touch_damage = 0.0
	player.global_position = pickup.global_position + Vector3(0.8, 0.0, 0.0)
	player.velocity = Vector3.ZERO
	await create_timer(0.05).timeout

	Input.action_press("interact")
	await create_timer(0.05).timeout
	# Drive one physics tick so Player sees the just_pressed edge.
	player._physics_process(0.033)
	Input.action_release("interact")
	await create_timer(0.1).timeout

	var has_item: bool = player.has_collected_item()
	var pickup_gone: bool = not is_instance_valid(pickup) or pickup.is_taken()
	print("pickup_ok=", has_item and pickup_gone, " has_item=", has_item, " gone=", pickup_gone)

	var glow_ok: bool = exit_zone.has_method("is_glow_visible") and exit_zone.is_glow_visible()
	print("exit_glow_ok=", glow_ok)

	var alerted: bool = monster.is_item_alerted()
	var dwell_halved: bool = is_equal_approx(monster.section_dwell_time, base_dwell * 0.5)
	var prox_doubled: bool = is_equal_approx(monster.proximity_radius, base_prox * 2.0)
	print(
		"alert_ok=",
		alerted and dwell_halved and prox_doubled,
		" dwell=",
		monster.section_dwell_time,
		" prox=",
		monster.proximity_radius
	)

	# Escaping through the exit with the item should WIN.
	player.global_position = exit_zone.global_position + Vector3(0.0, 0.05, 0.0)
	player.velocity = Vector3.ZERO
	# Force exit overlap evaluation.
	await create_timer(0.15).timeout
	if main.get_game_state() != main.GameState.WON:
		# Nudge body_entered if physics missed the teleport.
		exit_zone._on_body_entered(player)
		await create_timer(0.05).timeout
	var win_ok: bool = main.get_game_state() == main.GameState.WON
	var overlay := main.get_node_or_null("VictoryOverlay")
	var aristocrat := overlay.get_node_or_null("AristocratScreen") if overlay else null
	if aristocrat and aristocrat.has_method("finish_typing_now"):
		aristocrat.finish_typing_now()
	var win_line: String = aristocrat.spoken_line() if aristocrat and aristocrat.has_method("spoken_line") else ""
	var win_text_ok: bool = (
		overlay != null
		and aristocrat != null
		and win_line == "Well, you survived. Good for you. Here is your ration reward"
	)
	var rations_ok: bool = int(gp.rations) == 5
	print(
		"win_ok=", win_ok and win_text_ok and rations_ok,
		" state=", main.get_game_state(),
		" line=", win_line,
		" rations=", gp.rations
	)

	# Fresh scene for defeat aristocrat path. Victory advanced the campaign level;
	# pin this probe back to level 1 so it stays a single open floorplan.
	# Load via change_scene so SceneFlow can replace Main with the title screen.
	gp.current_level = 1
	main.queue_free()
	await create_timer(0.1).timeout
	var load_err := change_scene_to_file("res://scenes/Main.tscn")
	if load_err != OK:
		push_error("Failed to reload Main for defeat path")
		quit(1)
		return
	await process_frame
	main = current_scene as Node3D
	if main == null:
		push_error("Main was not current scene after reload")
		quit(1)
		return
	if not main.is_level_ready():
		await main.level_ready
	player = main.get_node("Player")
	monster = main.get_node("Monster")
	if main.has_method("park_monsters"):
		main.park_monsters(monster)
	monster.set_physics_process(false)
	monster.touch_damage = 100.0
	# Overlap them in the start room of the freshly generated layout.
	var start: Vector3 = main.get_layout()["start"]
	player.global_position = start
	monster.global_position = start
	# Re-fire touch after placing bodies on top of each other.
	var touch: Area3D = monster.get_node_or_null("TouchArea")
	if touch:
		touch.monitoring = false
		await create_timer(0.05).timeout
		touch.monitoring = true
	await create_timer(0.2).timeout
	if player.is_alive():
		player.take_damage(100.0)
	await create_timer(0.05).timeout
	var lose_ok: bool = main.get_game_state() == main.GameState.LOST
	var defeat_overlay := main.get_node_or_null("DefeatOverlay")
	var defeat_aristocrat := defeat_overlay.get_node_or_null("AristocratScreen") if defeat_overlay else null
	if defeat_aristocrat and defeat_aristocrat.has_method("finish_typing_now"):
		defeat_aristocrat.finish_typing_now()
	var lose_line: String = (
		defeat_aristocrat.spoken_line()
		if defeat_aristocrat and defeat_aristocrat.has_method("spoken_line")
		else ""
	)
	var lose_text_ok: bool = (
		defeat_overlay != null
		and defeat_aristocrat != null
		and lose_line == "Finally, you are no longer a drain on the motherland"
	)
	print(
		"game_over_ok=",
		lose_ok and lose_text_ok,
		" state=",
		main.get_game_state(),
		" line=",
		lose_line
	)

	# Continuing from defeat should return to the title screen.
	var flow: Node = root.get_node_or_null("SceneFlow")
	if flow:
		flow.fade_duration = 0.0
	if defeat_aristocrat and defeat_aristocrat.has_method("advance"):
		defeat_aristocrat.advance()
	if flow and flow.busy:
		await flow.transition_finished
	for i in 20:
		if current_scene and current_scene.name == "TitleScreen":
			break
		await process_frame
	var title_ok: bool = current_scene != null and current_scene.name == "TitleScreen"
	print("defeat_to_title_ok=", title_ok, " scene=", current_scene.name if current_scene else "")

	var all_ok: bool = (
		clips_ok
		and has_item
		and pickup_gone
		and alerted
		and dwell_halved
		and prox_doubled
		and glow_ok
		and win_ok
		and win_text_ok
		and rations_ok
		and lose_ok
		and lose_text_ok
		and title_ok
	)
	print("game_loop_smoke_ok=", all_ok)
	quit(0 if all_ok else 1)


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null
