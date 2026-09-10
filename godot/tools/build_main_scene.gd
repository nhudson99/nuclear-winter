extends SceneTree

## Build a clean Main.tscn: map + furniture + player + monster + iso camera.
## Only top-level authored nodes get scene ownership so packed GLBs stay external.

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	var map_path := "res://assets/maps/ussr_mansion_map.glb"
	var humanoid_path := "res://assets/characters/humanoid_scavenger.glb"
	var monster_path := "res://assets/characters/enemy_monster.glb"
	var prop_paths := {
		"crate": "res://assets/props/crate.glb",
		"wardrobe": "res://assets/props/wardrobe.glb",
		"couch": "res://assets/props/couch.glb",
	}

	for path in [map_path, humanoid_path, monster_path]:
		if not ResourceLoader.exists(path):
			push_error("Missing: " + path)
			quit(1)
			return
	for key in prop_paths:
		if not ResourceLoader.exists(prop_paths[key]):
			push_error("Missing prop: " + prop_paths[key])
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
	world_env.owner = main

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50, 30, 0)
	main.add_child(sun)
	sun.owner = main

	var map_root: Node3D = (load(map_path) as PackedScene).instantiate()
	map_root.name = "MansionMap"
	main.add_child(map_root)
	map_root.owner = main

	var furniture := Node3D.new()
	furniture.name = "Furniture"
	main.add_child(furniture)
	furniture.owner = main

	# Placements in Godot space (glTF Y-up): Blender +Y -> Godot -Z.
	# Southern entrance ~ z=+8; northern tip ~ z=-9.
	var placements: Array = [
		{"name": "Crate_Entrance", "prop": "crate", "pos": Vector3(4.6, 0.0, 6.2), "yaw": 18.0},
		{"name": "Crate_SW", "prop": "crate", "pos": Vector3(-4.7, 0.0, 5.4), "yaw": -12.0},
		{"name": "Crate_MidWest", "prop": "crate", "pos": Vector3(-4.5, 0.0, -0.8), "yaw": 35.0},
		{"name": "Crate_TopEast", "prop": "crate", "pos": Vector3(4.4, 0.0, -6.2), "yaw": -25.0},
		{"name": "Wardrobe_East", "prop": "wardrobe", "pos": Vector3(5.35, 0.0, -2.0), "yaw": -90.0},
		{"name": "Wardrobe_West", "prop": "wardrobe", "pos": Vector3(-5.35, 0.0, 3.5), "yaw": 90.0},
		{"name": "Wardrobe_North", "prop": "wardrobe", "pos": Vector3(-0.1, 0.0, -8.2), "yaw": 180.0},
		{"name": "Couch_Center", "prop": "couch", "pos": Vector3(0.0, 0.0, -2.8), "yaw": 0.0},
		{"name": "Couch_SE", "prop": "couch", "pos": Vector3(3.2, 0.0, 2.2), "yaw": 180.0},
		{"name": "Couch_SW", "prop": "couch", "pos": Vector3(-3.0, 0.0, 3.8), "yaw": 90.0},
	]

	for item in placements:
		var scene: PackedScene = load(prop_paths[item["prop"]])
		var node: Node3D = scene.instantiate()
		node.name = item["name"]
		node.position = item["pos"]
		node.rotation_degrees = Vector3(0.0, item["yaw"], 0.0)
		furniture.add_child(node)
		node.owner = main

	var player := CharacterBody3D.new()
	player.name = "Player"
	player.set_script(load("res://scripts/Player.gd"))
	player.collision_layer = 2
	player.collision_mask = 1
	player.position = Vector3(1.8, 0.05, 6.5)
	main.add_child(player)
	player.owner = main

	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.2
	col.shape = capsule
	col.position = Vector3(0, 0.9, 0)
	player.add_child(col)
	col.owner = main

	var humanoid: Node3D = (load(humanoid_path) as PackedScene).instantiate()
	humanoid.name = "Humanoid"
	player.add_child(humanoid)
	humanoid.owner = main

	var monster := CharacterBody3D.new()
	monster.name = "Monster"
	monster.set_script(load("res://scripts/Monster.gd"))
	monster.collision_layer = 4
	monster.collision_mask = 1
	monster.position = Vector3(0.0, 0.05, -6.2)
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

	var hud := CanvasLayer.new()
	hud.name = "HUD"
	main.add_child(hud)
	hud.owner = main

	var hint := Label.new()
	hint.name = "ReturnHint"
	hint.text = "Esc  //  return to map"
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 28.0
	hint.offset_top = -60.0
	hint.offset_right = 428.0
	hint.offset_bottom = -24.0
	var hint_settings := LabelSettings.new()
	hint_settings.font_size = 18
	hint_settings.font_color = Color(0.909804, 0.886275, 0.831373)
	hint_settings.outline_size = 8
	hint_settings.outline_color = Color(0.101961, 0.101961, 0.086275)
	hint.label_settings = hint_settings
	hud.add_child(hint)
	hint.owner = main

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

	print("Wrote res://scenes/Main.tscn with %d furniture props + monster" % placements.size())
	quit(0)
