extends SceneTree

## Library hosts the stage-1 sector key and LockedDoor into the next wing.
## Also covers pitch-black ambient, stalker freeze, void, tracker, melee, despawn.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("NW_LEVEL", "4")
	OS.set_environment("NW_LEVEL_SEED", "4242")
	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed == null:
		push_error("Missing Main.tscn")
		quit(1)
		return
	var main: Node3D = packed.instantiate()
	root.add_child(main)
	if not main.is_level_ready():
		await main.level_ready

	var layout: Dictionary = main.get_layout()
	var library: Dictionary = layout.get("library", {})
	var has_library_room := false
	for room in layout.get("rooms", []):
		if String(room.get("type", "")) == MapGenerator.TYPE_LIBRARY:
			has_library_room = true
	var key_stage := LevelRules.library_key_stage(4)
	var library_key := false
	for spec in layout.get("keys", []):
		if int(spec.get("stage", 0)) == key_stage and bool(spec.get("in_library", false)):
			library_key = true
	var library_ok: bool = (
		has_library_room
		and library_key
		and not library.is_empty()
		and key_stage == 1
		and int(library.get("key_stage", 0)) == key_stage
		and library.has("from_cell")
		and library.has("to_cell")
		and library.get("cell") == library.get("from_cell")
	)
	print(
		"library_ok=", library_ok,
		" room=", has_library_room,
		" key=", library_key,
		" stage=", key_stage,
		" secret=", library
	)

	var player: CharacterBody3D = main.get_node("Player")
	if main.has_method("park_monsters"):
		main.park_monsters()

	var metal_door := false
	for node in main.get_tree().get_nodes_in_group("library_door"):
		metal_door = true
		break
	var bookshelf := false
	for node in main.get_tree().get_nodes_in_group("secret_bookshelf"):
		bookshelf = true
		break
	var stage_door: LockedDoor = null
	for node in main.get_tree().get_nodes_in_group("locked_door"):
		if node is LockedDoor and (node as LockedDoor).stage == key_stage:
			stage_door = node as LockedDoor
			break
	var key_node: Area3D = main.get_node_or_null("Key_%d" % key_stage) as Area3D
	var secret_nodes_ok: bool = (
		key_node != null
		and not metal_door
		and not bookshelf
		and stage_door != null
	)
	print(
		"secret_nodes_ok=", secret_nodes_ok,
		" key=", key_node,
		" metal_door=", metal_door,
		" bookshelf=", bookshelf,
		" locked_door=", stage_door
	)

	var locked_before := stage_door != null and stage_door.is_locked()
	if key_node != null:
		player.global_position = key_node.global_position + Vector3(0.9, 0.05, 0.0)
		await create_timer(0.05).timeout
		Input.action_press("interact")
		await create_timer(0.05).timeout
		player._physics_process(0.033)
		Input.action_release("interact")
		await create_timer(0.1).timeout
	var opened_ok: bool = (
		main.collected_key_stages().has(key_stage)
		and locked_before
		and stage_door != null
		and not stage_door.is_locked()
	)
	print("library_key_unlock_ok=", opened_ok, " was_locked=", locked_before)

	var world := main.get_node("WorldEnvironment") as WorldEnvironment
	var ambient_ok: bool = (
		world != null
		and world.environment != null
		and absf(world.environment.ambient_light_energy) < 0.001
	)
	print("pitch_black_ok=", ambient_ok)

	var stalker: CharacterBody3D = main.get_node("Monster")
	var slime: CharacterBody3D = main.get_node("Slime")
	var void_body: CharacterBody3D = main.get_node_or_null("Void")
	var stalker_ok: bool = (
		stalker != null
		and stalker.is_in_group("stalker")
		and stalker.get_node_or_null("HealthBar") == null
		and bool(stalker.get("indestructible"))
	)
	var void_ok: bool = (
		void_body != null
		and void_body.is_in_group("void_monster")
		and LevelRules.kind_in_tier(LevelRules.KIND_VOID, LevelRules.TIER_HARD)
		and LevelRules.hard_monster_count(4) == 1
	)
	print("stalker_ok=", stalker_ok, " void_ok=", void_ok)

	var tracker: MonsterTracker = main.monster_tracker()
	var tracked := tracker.alive_bodies().size() if tracker else 0
	var tracker_ok: bool = tracker != null and tracked >= 1
	print("tracker_ok=", tracker_ok, " alive=", tracked)

	slime.visible = true
	slime.set_physics_process(false)
	if slime.has_method("set_off_floor"):
		slime.set_off_floor(false)
	if tracker != null:
		tracker.set_floor(slime, main.get_active_floor())
	slime.global_position = player.global_position + Vector3(1.5, 0.0, 0.0)
	player.health = 100.0
	slime.set("touch_damage", 5.0)
	slime.set("attack_interval", 0.25)
	slime.set("_player_in_touch", true)
	slime.set("_attack_cooldown_left", 0.0)
	slime.set_physics_process(true)
	slime._try_melee_attack()
	var hit_once: bool = is_equal_approx(player.health, 95.0)
	slime._try_melee_attack()
	var gated: bool = is_equal_approx(player.health, 95.0)
	print("melee_cadence_ok=", hit_once and gated, " hp=", player.health)

	var probe := CharacterBody3D.new()
	probe.name = "DespawnProbe"
	var probe_mesh := Node3D.new()
	probe_mesh.name = "MonsterMesh"
	probe.add_child(probe_mesh)
	main.add_child(probe)
	probe.set_script(load("res://scripts/Monster.gd"))
	probe.max_health = 10.0
	probe.health = 10.0
	probe.touch_damage = 0.0
	probe.show_health_bar = false
	probe.global_position = layout["start"] + Vector3(6.0, 0.05, 0.0)
	probe.take_damage(20.0)
	await create_timer(0.5).timeout
	var despawn_ok: bool = not is_instance_valid(probe)
	print("despawn_ok=", despawn_ok)

	var all_ok: bool = (
		library_ok
		and secret_nodes_ok
		and opened_ok
		and ambient_ok
		and stalker_ok
		and void_ok
		and tracker_ok
		and hit_once
		and gated
		and despawn_ok
	)
	print("library_void_tracker_smoke_ok=", all_ok)
	OS.set_environment("NW_LEVEL", "")
	OS.set_environment("NW_LEVEL_SEED", "")
	quit(0 if all_ok else 1)
