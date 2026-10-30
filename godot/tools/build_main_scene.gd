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
	var player_path := "res://assets/characters/Meshy_AI_Gulag_Winter_Warden_All_Animations.glb"
	var monster_path := "res://assets/characters/enemy_monster.glb"
	# Rigged exports. The static SovietSlime.glb / SovietTankMan.glb in blender/
	# have no clips; these are the animated twins.
	var slime_path := "res://assets/characters/SovietSlime.glb"
	var tank_path := "res://assets/characters/SovietTankMan.glb"
	var tarantula_path := "res://assets/characters/Tarantula.glb"
	var widow_path := "res://assets/characters/enemy_widow.glb"
	var toad_path := "res://assets/characters/Toad.glb"

	for path in [player_path, monster_path, slime_path, tank_path, tarantula_path, widow_path, toad_path]:
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
	# Dim ambient (9% energy) so the map is faintly readable with the
	# flashlight off. The sun stays dark; hold RMB for the beam.
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.60, 0.58)
	env.ambient_light_energy = 0.09
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

	# Flashlight and the gun boxes hang off Model, which faces -Z. The warden
	# mesh faces +Z, so the instance is turned around under that node.
	var model := Node3D.new()
	model.name = "Model"
	player.add_child(model)
	model.owner = main
	var character: Node3D = (load(player_path) as PackedScene).instantiate()
	character.name = "Character"
	character.rotation.y = PI
	model.add_child(character)
	character.owner = main

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

	# SovietSlime rests at ~0.62 m tall and 1.9 m long. The capsule stays narrow
	# enough that a fully grown (2x) slime still clears the 2.6 m doorway.
	_add_enemy(
		main,
		"Slime",
		slime_path,
		{
			"move_speed": 3.9,
			"max_health": 45.0,
			"touch_damage": 35.0,
			"proximity_radius": 2.4,
			"detect_range": 12.0,
			"health_bar_height": 0.9,
			"touch_radius": 0.95,
			"eye_height": 0.45,
			"section_dwell_time": 16.0,
			"idle_clip": "Idle",
			"walk_clip": "Move",
			"walk_cycle_metres": 2.6,
			"grow_and_split": true,
			"grow_duration": 30.0,
			"grow_scale_target": 2.0,
		},
		0.55,
		1.15,
		0.58
	)
	_save_packed_subtree(main.get_node("Slime"), "res://scenes/Slime.tscn")
	# SovietTankMan is 1.7 m tall. Walk loops; Smash plays on touch.
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
			"health_bar_height": 1.95,
			"touch_radius": 1.0,
			"eye_height": 1.52,
			"section_dwell_time": 40.0,
			"idle_clip": "Idle",
			"walk_clip": "Walk",
			"attack_clip": "Smash",
			"walk_cycle_metres": 2.5,
		},
		0.62,
		1.7,
		0.85
	)
	# Native leg span is 3.28 m, wider than the 2.6 m doorway. 0.67 brings the
	# span to ~2.2 m and the height to ~1.14 m. Walk / Bite / WebWeave.
	_add_enemy(
		main,
		"Tarantula",
		tarantula_path,
		{
			"move_speed": 4.0,
			"turn_speed": 7.2,
			"max_health": 100.0,
			"touch_damage": 50.0,
			"proximity_radius": 3.2,
			"detect_range": 14.0,
			"health_bar_height": 1.3,
			"touch_radius": 1.05,
			"eye_height": 0.55,
			"section_dwell_time": 30.0,
			"idle_clip": "Idle",
			"walk_clip": "Walk",
			"attack_clip": "Bite",
			"walk_cycle_metres": 2.4,
			"weave_duration": 30.0,
			"web_move_bonus": 0.25,
			"weave_clip": "WebWeave",
		},
		0.5,
		1.1,
		0.55,
		"res://scripts/Tarantula.gd",
		0.67
	)
	_add_enemy(
		main,
		"Widow",
		widow_path,
		{
			"move_speed": 2.85,
			"turn_speed": 6.4,
			"max_health": 250.0,
			"touch_damage": 100.0,
			"proximity_radius": 3.6,
			"detect_range": 15.0,
			"health_bar_height": 2.2,
			"touch_radius": 0.9,
			"eye_height": 1.62,
			"section_dwell_time": 36.0,
			"idle_clip": "Idle",
			"walk_clip": "Walk",
			"death_clip": "Die",
			"walk_cycle_metres": 1.5,
		},
		0.32,
		1.55,
		0.88,
		"res://scripts/Monster.gd",
		1.0,
		0.0
	)
	# Toad is 1.7 m tall. JumpForward is the hop; Eat plays when it swallows.
	_add_enemy(
		main,
		"Toad",
		toad_path,
		{
			"move_speed": 2.6,
			"turn_speed": 5.4,
			"max_health": 200.0,
			"touch_damage": 0.0,
			"proximity_radius": 0.1,
			"detect_range": 0.1,
			"health_bar_height": 1.95,
			"touch_radius": 0.9,
			"eye_height": 1.15,
			"section_dwell_time": 10.0,
			"idle_clip": "Idle",
			"walk_clip": "JumpForward",
			"action_clip": "Eat",
			"walk_cycle_metres": 2.5,
			"search_duration": 10.0,
		},
		0.72,
		1.7,
		0.85,
		"res://scripts/Toad.gd"
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
	capsule_y: float,
	script_path: String = "res://scripts/Monster.gd",
	mesh_scale: float = 1.0,
	mesh_yaw: float = PI
) -> void:
	var body := CharacterBody3D.new()
	body.name = node_name
	body.set_script(load(script_path))
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

	# Monster.gd aims MonsterMesh so its -Z follows travel. A mesh that faces
	# +Z (the new rigs) is turned 180°; the widow already faces -Z, so her
	# yaw stays 0.
	var visual := Node3D.new()
	visual.name = "MonsterMesh"
	body.add_child(visual)
	visual.owner = main
	var mesh: Node3D = (load(glb_path) as PackedScene).instantiate()
	mesh.name = "Character"
	mesh.rotation.y = mesh_yaw
	mesh.scale = Vector3.ONE * mesh_scale
	visual.add_child(mesh)
	mesh.owner = main


func _save_packed_subtree(root: Node, path: String) -> void:
	var parent := root.get_parent()
	root.owner = null
	_set_owner_recursive(root, root)
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("Failed to pack %s" % path)
		quit(1)
		return
	var save_err := ResourceSaver.save(packed, path)
	if save_err != OK:
		push_error("Failed to save %s: %s" % [path, save_err])
		quit(1)
		return
	root.owner = parent
	_set_owner_recursive(root, parent)
	print("Wrote ", path)


func _set_owner_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		# Children of an instanced GLB stay owned by that instance. Claiming
		# them here inlines the whole mesh into the packed scene.
		if child.scene_file_path.is_empty():
			_set_owner_recursive(child, owner)
