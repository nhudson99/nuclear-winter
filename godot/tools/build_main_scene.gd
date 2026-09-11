extends SceneTree

## Build a clean Main.tscn: lighting, iso camera, and the actors.
##
## The floorplan is deliberately absent. Main.gd runs MapGenerator at load time,
## which fills the empty `GeneratedMap` node with room tiles and then moves the
## player, monster, objective and exit onto the layout it produced. Positions
## authored here are only placeholders for the first frame.

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	var player_path := "res://assets/characters/player_prisoner.glb"
	var monster_path := "res://assets/characters/enemy_monster.glb"

	for path in [player_path, monster_path]:
		if not ResourceLoader.exists(path):
			push_error("Missing: " + path)
			quit(1)
			return
	for type_name in MapGenerator.ROOM_TYPES:
		var room_path: String = MapGenerator.ROOM_SCENES[type_name]
		if not ResourceLoader.exists(room_path):
			push_error("Missing room module: " + room_path)
			quit(1)
			return

	var main := Node3D.new()
	main.name = "Main"
	main.set_script(load("res://scripts/Main.gd"))

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	# Overcast fallout haze rather than the old clear blue sky.
	env.background_color = Color(0.13, 0.14, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.64, 0.63)
	# Rooms have no ceilings, so ambient plus sun hit the floors head-on. Keeping
	# the total near 1.0 renders surfaces close to their authored albedo instead
	# of blowing the palette out to pastel.
	env.ambient_light_energy = 0.34
	world_env.environment = env
	main.add_child(world_env)
	world_env.owner = main

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 0.95
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50, 30, 0)
	main.add_child(sun)
	sun.owner = main

	# Filled by MapGenerator during the loading screen.
	var generated_map := Node3D.new()
	generated_map.name = "GeneratedMap"
	main.add_child(generated_map)
	generated_map.owner = main

	var player := CharacterBody3D.new()
	player.name = "Player"
	player.set_script(load("res://scripts/Player.gd"))
	player.collision_layer = 2
	player.collision_mask = 1
	player.position = Vector3(0.0, 0.05, 0.0)
	main.add_child(player)
	player.owner = main

	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	# The prisoner is 1.8 m and stands on his origin, so the capsule has to
	# reach down to y = 0 or the body floats half a metre off the floor.
	capsule.height = 1.6
	col.shape = capsule
	col.position = Vector3(0, 0.8, 0)
	player.add_child(col)
	col.owner = main

	var model: Node3D = (load(player_path) as PackedScene).instantiate()
	model.name = "Model"
	player.add_child(model)
	model.owner = main

	var monster := CharacterBody3D.new()
	monster.name = "Monster"
	monster.set_script(load("res://scripts/Monster.gd"))
	monster.collision_layer = 4
	monster.collision_mask = 1
	monster.position = Vector3(0.0, 0.05, -MapGenerator.TILE)
	main.add_child(monster)
	monster.owner = main

	var mcol := CollisionShape3D.new()
	mcol.name = "CollisionShape3D"
	var mcapsule := CapsuleShape3D.new()
	mcapsule.radius = 0.42
	mcapsule.height = 1.35
	mcol.shape = mcapsule
	mcol.position = Vector3(0, 1.0, 0)
	monster.add_child(mcol)
	mcol.owner = main

	var monster_mesh: Node3D = (load(monster_path) as PackedScene).instantiate()
	monster_mesh.name = "MonsterMesh"
	monster_mesh.rotation.y = PI
	monster.add_child(monster_mesh)
	monster_mesh.owner = main

	var camera := Camera3D.new()
	camera.name = "IsoCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20.0
	camera.current = true
	camera.near = 0.05
	camera.far = 250.0
	main.add_child(camera)
	camera.owner = main

	var pickup := Area3D.new()
	pickup.name = "PickupItem"
	pickup.set_script(load("res://scripts/PickupItem.gd"))
	pickup.position = Vector3(0.0, 0.05, -MapGenerator.TILE * 2.0)
	main.add_child(pickup)
	pickup.owner = main

	var exit_zone := Area3D.new()
	exit_zone.name = "ExitZone"
	exit_zone.set_script(load("res://scripts/ExitZone.gd"))
	exit_zone.position = Vector3(0.0, 0.0, MapGenerator.TILE * 0.5)
	main.add_child(exit_zone)
	exit_zone.owner = main

	var exit_shape := CollisionShape3D.new()
	exit_shape.name = "CollisionShape3D"
	var exit_box := BoxShape3D.new()
	# Roughly one doorway wide; the exit can land on any side of the start room.
	exit_box.size = Vector3(3.2, 3.0, 3.2)
	exit_shape.shape = exit_box
	exit_shape.position = Vector3(0.0, 1.5, 0.0)
	exit_zone.add_child(exit_shape)
	exit_shape.owner = main

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

	print("Wrote res://scenes/Main.tscn (procedural map, %d room modules available)" % MapGenerator.ROOM_TYPES.size())
	quit(0)
