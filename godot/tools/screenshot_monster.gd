extends SceneTree

## Close-up of the Level 1 hare next to the player in a generated room.
##
##   godot --path godot --rendering-driver opengl3 --resolution 1280x720 \
##         -s res://tools/screenshot_monster.gd

const OUT := "/opt/cursor/artifacts/godot_level1_hare_monster.png"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed == null:
		push_error("Missing Main.tscn")
		quit(1)
		return
	var main: Node3D = packed.instantiate()
	main.level_seed = 101
	main.min_loading_seconds = 0.0
	root.add_child(main)
	if not main.is_level_ready():
		await main.level_ready

	main.set_physics_process(false)
	var player: CharacterBody3D = main.get_node("Player")
	var monster: CharacterBody3D = main.get_node("Monster")
	player.lock_input()
	monster.set_physics_process(false)

	var start: Vector3 = main.get_layout()["start"]
	player.global_position = start + Vector3(1.1, 0.05, 0.6)
	monster.global_position = start + Vector3(-1.15, 0.05, -0.9)
	var mesh: Node3D = monster.get_node("MonsterMesh")
	# Face the isometric camera (looking from +X/+Z).
	mesh.rotation.y = deg_to_rad(210.0)
	player.get_node("Humanoid").rotation.y = deg_to_rad(40.0)

	var camera: Camera3D = main.get_node("IsoCamera")
	camera.size = 7.5
	camera.global_position = start + Vector3(7.5, 8.0, 7.5)
	camera.look_at(start + Vector3(0.0, 1.1, 0.0), Vector3.UP)

	await create_timer(0.35).timeout
	var img: Image = root.get_viewport().get_texture().get_image()
	var err := img.save_png(OUT)
	print("screenshot_err=", err, " path=", OUT, " size=", img.get_width(), "x", img.get_height())
	quit(0)
