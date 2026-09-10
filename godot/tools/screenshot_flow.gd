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
		{"scene": "res://scenes/Main.tscn", "file": "godot_level_1.png", "wait": 0.8},
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

	quit(0)
