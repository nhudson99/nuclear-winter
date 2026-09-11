extends SceneTree

## Capture Level 1 with the flashlight on, then off, so the dark map and cone
## can be eyeballed. Needs a real renderer:
##   Godot --rendering-driver opengl3 --resolution 1280x720 \
##         -s res://tools/screenshot_flashlight.gd

const OUT_DIR := "/opt/cursor/artifacts"
const SEED := 101

func _initialize() -> void:
	OS.set_environment("NW_LEVEL_SEED", str(SEED))
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main: Node3D = packed.instantiate()
	root.add_child(main)
	if not main.is_level_ready():
		await main.level_ready

	var player: CharacterBody3D = main.get_node("Player")
	var monster: CharacterBody3D = main.get_node_or_null("Monster")
	if monster:
		monster.set_physics_process(false)
		monster.visible = false
		monster.global_position += Vector3(200.0, 0.0, 200.0)

	# Face the beam into the room so the cone reads on the floor.
	var visual: Node3D = player.get_node("Model")
	visual.rotation.y = PI
	player.set_flashlight_on(true)
	await create_timer(0.5).timeout
	_snap("godot_flashlight_on.png")

	player.set_flashlight_on(false)
	await create_timer(0.35).timeout
	_snap("godot_flashlight_off.png")

	player.set_flashlight_on(true)
	visual.rotation.y = PI * 0.5
	await create_timer(0.35).timeout
	_snap("godot_flashlight_yaw.png")

	quit(0)

func _snap(filename: String) -> void:
	var image: Image = get_root().get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, filename]
	var err := image.save_png(path)
	print("screenshot_err=", err, " path=", path, " size=", image.get_width(), "x", image.get_height())
