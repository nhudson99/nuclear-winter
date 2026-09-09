extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main: Node = packed.instantiate()
	root.add_child(main)
	await create_timer(0.8).timeout
	var img: Image = get_root().get_viewport().get_texture().get_image()
	# Dummy renderer may not produce pixels; still attempt.
	var out := ProjectSettings.globalize_path("res://../artifacts_godot_main.png")
	# Prefer absolute artifacts path
	out = "/opt/cursor/artifacts/godot_isometric_main.png"
	var err := img.save_png(out)
	print("screenshot_err=", err, " path=", out, " size=", img.get_width(), "x", img.get_height())
	quit(0)
