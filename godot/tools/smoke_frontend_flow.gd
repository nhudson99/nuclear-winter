extends SceneTree

const TITLE_SCENE := "res://scenes/TitleScreen.tscn"
const ARISTOCRAT_SCENE := "res://scenes/AristocratScreen.tscn"
const MAP_SCENE := "res://scenes/GameMap.tscn"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var title := await _show_scene(TITLE_SCENE)
	var title_ok := title != null and title.get_node_or_null("ActionButton") != null
	print("title_screen_ok=", title_ok)
	if not title_ok:
		quit(1)
		return
	title.get_node("ActionButton").pressed.emit()
	await create_timer(0.35).timeout

	var aristocrat := current_scene
	var aristocrat_ok := (
		aristocrat != null
		and aristocrat.scene_file_path == ARISTOCRAT_SCENE
		and aristocrat.get_node_or_null("ActionButton") != null
	)
	print("aristocrat_screen_ok=", aristocrat_ok)
	if not aristocrat_ok:
		quit(1)
		return
	aristocrat.get_node("ActionButton").pressed.emit()
	await create_timer(0.35).timeout

	var game_map := current_scene
	var map_button := game_map.get_node_or_null("LevelOneButton") if game_map else null
	var map_ok := game_map != null and game_map.scene_file_path == MAP_SCENE and map_button != null
	print("game_map_ok=", map_ok)
	if not map_ok:
		quit(1)
		return
	map_button.pressed.emit()
	await create_timer(0.45).timeout

	var level_ok := current_scene != null and current_scene.scene_file_path == "res://scenes/Main.tscn"
	print("level_one_button_ok=", level_ok)
	print("frontend_flow_smoke_ok=", title_ok and aristocrat_ok and map_ok and level_ok)
	quit(0 if level_ok else 1)

func _show_scene(path: String) -> Node:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	return scene
