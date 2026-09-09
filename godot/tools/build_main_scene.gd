extends SceneTree

## Build a clean Main.tscn: instance GLB map + player + iso camera.

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	var map_path := "res://assets/maps/ussr_mansion_map.glb"
	if not ResourceLoader.exists(map_path):
		push_error("Missing map: " + map_path)
		quit(1)
		return

	var main := Node3D.new()
	main.name = "Main"
	main.set_script(load("res://scripts/Main.gd"))

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.62, 0.82)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.82, 0.86)
	env.ambient_light_energy = 0.7
	world_env.environment = env
	main.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50, 30, 0)
	main.add_child(sun)

	var map_scene: PackedScene = load(map_path)
	var map_root: Node3D = map_scene.instantiate()
	map_root.name = "MansionMap"
	main.add_child(map_root)

	var player := CharacterBody3D.new()
	player.name = "Player"
	player.set_script(load("res://scripts/Player.gd"))
	player.collision_layer = 2
	player.collision_mask = 1
	# Spawn near the southern entrance gap.
	player.position = Vector3(1.8, 1.1, 6.5)

	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.2
	col.shape = capsule
	col.position = Vector3(0, 0.85, 0)
	player.add_child(col)

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var sphere := SphereMesh.new()
	sphere.radius = 0.4
	sphere.height = 0.8
	mesh.mesh = sphere
	mesh.position = Vector3(0, 1.0, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.35, 0.22)
	mesh.material_override = mat
	player.add_child(mesh)
	main.add_child(player)

	var camera := Camera3D.new()
	camera.name = "IsoCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20.0
	camera.current = true
	main.add_child(camera)

	# Owners for saving.
	for child in main.get_children():
		child.owner = main
		_set_owner_recursive(child, main)

	var packed := PackedScene.new()
	if packed.pack(main) != OK:
		push_error("Failed to pack Main")
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes"))
	var save_err := ResourceSaver.save(packed, "res://scenes/Main.tscn")
	if save_err != OK:
		push_error("Failed to save Main.tscn: %s" % save_err)
		quit(1)
		return

	print("Wrote res://scenes/Main.tscn")
	quit(0)

func _set_owner_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_set_owner_recursive(child, owner)
