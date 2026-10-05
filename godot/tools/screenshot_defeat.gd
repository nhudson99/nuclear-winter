extends SceneTree

## Capture the defeat aristocrat line and the title screen after continue.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var out_dir := "/opt/cursor/artifacts"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var gp: Node = root.get_node("GameProgress")
	gp.reset_for_tests()

	var flow: Node = root.get_node_or_null("SceneFlow")
	if flow:
		flow.fade_duration = 0.0

	var err := change_scene_to_file("res://scenes/Main.tscn")
	if err != OK:
		push_error("Failed to load Main")
		quit(1)
		return
	for i in 30:
		await process_frame
		if current_scene != null and current_scene.name == "Main":
			break
	var main: Node3D = current_scene as Node3D
	if main == null:
		push_error("Main missing")
		quit(1)
		return
	if not main.is_level_ready():
		await main.level_ready

	var player: CharacterBody3D = main.get_node("Player")
	var monster: CharacterBody3D = main.get_node("Monster")
	if main.has_method("park_monsters"):
		main.park_monsters(monster)
	monster.set_physics_process(false)
	monster.touch_damage = 100.0
	var start: Vector3 = main.get_layout()["start"]
	player.global_position = start
	monster.global_position = start
	var touch: Area3D = monster.get_node_or_null("TouchArea")
	if touch:
		touch.monitoring = false
		await create_timer(0.05).timeout
		touch.monitoring = true
	await create_timer(0.2).timeout
	if player.is_alive():
		player.take_damage(100.0)
	await create_timer(0.15).timeout

	var aristocrat := main.get_node_or_null("DefeatOverlay/AristocratScreen")
	if aristocrat and aristocrat.has_method("finish_typing_now"):
		aristocrat.finish_typing_now()
	await create_timer(0.3).timeout
	_shot(out_dir, "godot_defeat_aristocrat_line.png")

	if aristocrat and aristocrat.has_method("advance"):
		aristocrat.advance()
	if flow and flow.busy:
		await flow.transition_finished
	for i in 30:
		if current_scene and current_scene.name == "TitleScreen":
			break
		await process_frame
	await create_timer(0.4).timeout
	_shot(out_dir, "godot_defeat_returns_to_title.png")
	quit(0)


func _shot(out_dir: String, file_name: String) -> void:
	var img: Image = root.get_viewport().get_texture().get_image()
	var path := "%s/%s" % [out_dir, file_name]
	var shot_err := img.save_png(path)
	print("shot=", file_name, " err=", shot_err, " size=", img.get_width(), "x", img.get_height())
