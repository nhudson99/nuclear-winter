extends SceneTree

## Headless smoke: title → aristocrat briefing → Pip-Boy map → Level 1.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var flow: Node = root.get_node_or_null("SceneFlow")
	if flow == null:
		push_error("SceneFlow autoload missing")
		quit(1)
		return
	flow.fade_duration = 0.0

	var title_ok := ResourceLoader.exists(SceneFlow.TITLE)
	var boss_ok := ResourceLoader.exists(SceneFlow.ARISTOCRAT)
	var map_ok := ResourceLoader.exists(SceneFlow.GAME_MAP)
	var level_ok := ResourceLoader.exists(SceneFlow.LEVEL_1)
	print("scenes_exist_ok=", title_ok and boss_ok and map_ok and level_ok)

	var err := change_scene_to_file(SceneFlow.TITLE)
	if err != OK:
		push_error("Failed to load TitleScreen")
		quit(1)
		return
	await process_frame
	await create_timer(0.05).timeout

	var title := current_scene
	var title_nodes_ok := (
		title != null
		and title.name == "TitleScreen"
		and title.get_node_or_null("Background") != null
		and title.get_node_or_null("Prompt") != null
		and title.get_node_or_null("Ash") != null
	)
	print("title_nodes_ok=", title_nodes_ok, " scene=", title.name if title else "")

	title.advance()
	await _wait_for_scene("AristocratScreen")
	var boss := current_scene
	var boss_nodes_ok := (
		boss != null
		and boss.name == "AristocratScreen"
		and boss.get_node_or_null("CrtPortrait") != null
		and boss.get_node_or_null("DialoguePanel") != null
		and boss.get_node_or_null("DialoguePanel/DialogueText") != null
		and boss.get_node_or_null("DialoguePanel/ContinuePrompt") != null
	)
	print("aristocrat_nodes_ok=", boss_nodes_ok, " scene=", boss.name if boss else "")

	# First input finishes the typewriter; second advances.
	boss.on_any_input()
	await process_frame
	var typed_ok: bool = boss.is_typing_complete() and str(boss.get_node("DialoguePanel/DialogueText").text).length() > 10
	print("aristocrat_typewriter_ok=", typed_ok)

	boss.advance()
	await _wait_for_scene("GameMap")
	var map := current_scene
	var level_btn: Button = map.get_level_1_button() if map and map.has_method("get_level_1_button") else null
	var map_nodes_ok := (
		map != null
		and map.name == "GameMap"
		and map.get_node_or_null("MapImage") != null
		and map.get_node_or_null("Level1Marker/Level1Button") != null
		and level_btn != null
		and level_btn.text == "LEVEL 1"
	)
	print("map_nodes_ok=", map_nodes_ok, " button=", level_btn.text if level_btn else "")

	if level_btn:
		level_btn.emit_signal("pressed")
	elif map and map.has_method("enter_level_1"):
		map.enter_level_1()
	await _wait_for_scene("Main")

	var level := current_scene
	var level_ok_nodes := (
		level != null
		and level.name == "Main"
		and level.get_node_or_null("Player") != null
		and level.get_node_or_null("Monster") != null
		and level.get_node_or_null("PickupItem") != null
		and level.get_node_or_null("ExitZone") != null
	)
	print("level1_nodes_ok=", level_ok_nodes, " scene=", level.name if level else "")

	var all_ok: bool = (
		title_ok
		and boss_ok
		and map_ok
		and level_ok
		and title_nodes_ok
		and boss_nodes_ok
		and typed_ok
		and map_nodes_ok
		and level_ok_nodes
	)
	print("flow_smoke_ok=", all_ok)
	quit(0 if all_ok else 1)


func _wait_for_scene(expected: String) -> void:
	var flow: Node = root.get_node_or_null("SceneFlow")
	if flow and flow.busy:
		await flow.transition_finished
	for i in 20:
		if current_scene and current_scene.name == expected:
			await process_frame
			return
		await process_frame
	push_error("Timed out waiting for scene %s (have %s)" % [expected, current_scene.name if current_scene else "none"])
