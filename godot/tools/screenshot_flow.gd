extends SceneTree

## Capture the three menu screens plus Level 1 after a short settle.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var out_dir := "/opt/cursor/artifacts"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var shots := [
		{"scene": "res://scenes/TitleScreen.tscn", "file": "godot_title_screen.png", "wait": 0.6},
		{"scene": "res://scenes/AristocratScreen.tscn", "file": "godot_aristocrat_screen.png", "wait": 1.4},
		{"scene": "res://scenes/GameMap.tscn", "file": "godot_game_map.png", "wait": 0.5},
	]

	for shot in shots:
		var packed: PackedScene = load(shot["scene"])
		if packed == null:
			push_error("Missing " + shot["scene"])
			quit(1)
			return
		var node: Node = packed.instantiate()
		root.add_child(node)
		if node is Control:
			(node as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
		if node.has_method("finish_typing_now"):
			await create_timer(0.15).timeout
			node.finish_typing_now()
		await create_timer(shot["wait"]).timeout
		var img: Image = root.get_viewport().get_texture().get_image()
		var path: String = "%s/%s" % [out_dir, shot["file"]]
		var err := img.save_png(path)
		print("shot=", shot["file"], " err=", err, " size=", img.get_width(), "x", img.get_height())
		node.queue_free()
		await create_timer(0.05).timeout

	await _shoot_level_1(out_dir)
	quit(0)


## Level 1 needs two frames captured: the loading overlay mid-generation, and
## the finished map once MapGenerator has handed the layout back.
func _shoot_level_1(out_dir: String) -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed == null:
		push_error("Missing res://scenes/Main.tscn")
		return
	var level: Node = packed.instantiate()
	root.add_child(level)

	await create_timer(0.5).timeout
	var loading_img: Image = root.get_viewport().get_texture().get_image()
	var loading_err := loading_img.save_png("%s/godot_loading_screen.png" % out_dir)
	print("shot=godot_loading_screen.png err=", loading_err)

	if not level.is_level_ready():
		await level.level_ready
	await create_timer(0.4).timeout
	var level_img: Image = root.get_viewport().get_texture().get_image()
	var level_err := level_img.save_png("%s/godot_level_1.png" % out_dir)
	var layout: Dictionary = level.get_layout()
	print(
		"shot=godot_level_1.png err=", level_err,
		" seed=", layout.get("seed", 0),
		" rooms=", (layout.get("rooms", []) as Array).size()
	)
	level.queue_free()
	await create_timer(0.05).timeout
