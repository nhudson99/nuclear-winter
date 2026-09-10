extends SceneTree

## Renders a whole generated map from above for a handful of seeds, so layout
## variety can be eyeballed without playing through a run.
##
## Needs a real renderer:
##   Godot --rendering-driver opengl3 --resolution 1600x900 \
##         -s res://tools/screenshot_layouts.gd

const SEEDS: Array[int] = [101, 202, 303]
const ROOM_COUNT := 9
const OUT_DIR := "/opt/cursor/artifacts"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.14, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.64, 0.63)
	env.ambient_light_energy = 0.34
	world_env.environment = env
	root.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.95
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.05
	camera.far = 500.0
	camera.current = true
	root.add_child(camera)

	for level_seed in SEEDS:
		var container := Node3D.new()
		container.name = "Layout_%d" % level_seed
		root.add_child(container)

		var generator := MapGenerator.new()
		root.add_child(generator)
		var layout: Dictionary = await generator.generate(container, level_seed, ROOM_COUNT)
		generator.queue_free()

		var bounds: AABB = layout["bounds"]
		var center := Vector3(
			bounds.position.x + bounds.size.x * 0.5,
			0.0,
			bounds.position.z + bounds.size.z * 0.5
		)
		var reach := maxf(bounds.size.x, bounds.size.z)
		camera.size = reach * 1.35
		camera.global_position = center + Vector3(reach, reach * 1.1, reach)
		camera.look_at(center, Vector3.UP)

		await create_timer(0.6).timeout
		var image: Image = root.get_viewport().get_texture().get_image()
		var path := "%s/godot_layout_seed_%d.png" % [OUT_DIR, level_seed]
		var err := image.save_png(path)
		var types: Array[String] = []
		for room in layout["rooms"]:
			types.append(room["type"])
		print(
			"layout seed=", level_seed,
			" err=", err,
			" exit_side=", layout["exit_side"],
			" types=", types
		)

		container.queue_free()
		await create_timer(0.1).timeout

	quit(0)
