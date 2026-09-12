extends SceneTree

## Build a clean Main.tscn: dark environment, iso camera, and the actors.
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
	var slime_path := "res://assets/characters/enemy_slime.glb"
	var tank_path := "res://assets/characters/enemy_tank.glb"

	for path in [player_path, monster_path, slime_path, tank_path]:
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
	# Dim ambient (10% energy) so the map is faintly readable with the
	# flashlight off. The sun stays dark; hold RMB for the beam.
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.60, 0.58)
	env.ambient_light_energy = 0.10
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	world_env.environment = env
	main.add_child(world_env)
	world_env.owner = main

	# Kept in the tree so debug tools can re-enable it, but it contributes
	# nothing at runtime.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 0.0
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = false
	sun.visible = false
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

	_add_enemy(
		main,
		"Slime",
		slime_path,
		{
			"move_speed": 5.2,
			"max_health": 45.0,
			"touch_damage": 35.0,
			"proximity_radius": 2.4,
			"detect_range": 12.0,
			"health_bar_height": 1.35,
			"touch_radius": 0.7,
			"eye_height": 0.65,
			"section_dwell_time": 16.0,
			"idle_clip": "idle",
			"walk_clip": "moving",
			"hit_clip": "hit",
			"death_clip": "death",
			"attack_clip": "attack",
			"walk_cycle_metres": 1.1,
		},
		0.36,
		0.85,
		0.48
	)
	_add_enemy(
		main,
		"Tank",
		tank_path,
		{
			"move_speed": 2.35,
			"turn_speed": 4.6,
			"max_health": 320.0,
			"touch_damage": 100.0,
			"proximity_radius": 4.2,
			"detect_range": 14.0,
			"health_bar_height": 2.55,
			"touch_radius": 1.25,
			"eye_height": 1.72,
			"section_dwell_time": 40.0,
			"idle_clip": "Idle",
			"walk_clip": "Walk",
			"death_clip": "Die",
			"walk_cycle_metres": 1.9,
		},
		0.58,
		1.45,
		0.95
	)

	var camera := Camera3D.new()
	camera.name = "IsoCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20.0 / 1.5
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


func _add_enemy(
	main: Node3D,
	node_name: String,
	glb_path: String,
	stats: Dictionary,
	capsule_r: float,
	capsule_h: float,
	capsule_y: float
) -> void:
	var body := CharacterBody3D.new()
	body.name = node_name
	body.set_script(load("res://scripts/Monster.gd"))
	body.collision_layer = 4
	body.collision_mask = 1
	body.position = Vector3(0.0, 0.05, -MapGenerator.TILE)
	for key in stats:
		body.set(String(key), stats[key])
	main.add_child(body)
	body.owner = main

	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = capsule_r
	capsule.height = capsule_h
	col.shape = capsule
	col.position = Vector3(0.0, capsule_y, 0.0)
	body.add_child(col)
	col.owner = main

	var mesh: Node3D = (load(glb_path) as PackedScene).instantiate()
	mesh.name = "MonsterMesh"
	mesh.rotation.y = PI
	body.add_child(mesh)
	mesh.owner = main
