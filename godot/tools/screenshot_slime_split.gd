extends SceneTree

## Posed shots of the slime grow-and-split cycle: original size, doubled,
## then two original-sized children.

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
	var slime: CharacterBody3D = main.get_node("Slime")
	main.park_monsters()
	slime.visible = true
	slime.touch_damage = 0.0
	slime.set_physics_process(false)
	slime.global_position = player.global_position + Vector3(-1.8, 0.05, -1.3)
	player.get_node("Model").rotation.y = atan2(-1.0, -1.0) + PI
	player.set_aim_world_override(slime.global_position)
	Input.action_press("flashlight")
	slime.reveal_health_bar()
	slime.reset_growth_cycle()
	slime.debug_set_growth_progress(0.0)
	for _i in range(12):
		await physics_frame
	await create_timer(0.2).timeout
	_snap("godot_slime_split_start.png")

	slime.debug_set_growth_progress(1.0)
	slime.reveal_health_bar()
	for _i in range(8):
		await physics_frame
	await create_timer(0.15).timeout
	_snap("godot_slime_split_grown.png")

	slime.debug_split_now()
	for _i in range(12):
		await physics_frame
	var kids: Array = []
	for node in main.get_tree().get_nodes_in_group("slime"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node.has_method("is_alive") and node.is_alive():
			kids.append(node)
	var midpoint := Vector3.ZERO
	for child in kids:
		child.set_physics_process(false)
		child.touch_damage = 0.0
		child.visible = true
		child.reveal_health_bar()
		midpoint += child.global_position
	if not kids.is_empty():
		midpoint /= float(kids.size())
		player.global_position = midpoint + Vector3(2.6, 0.05, 1.8)
		player.set_aim_world_override(midpoint)
	for _i in range(10):
		await physics_frame
	await create_timer(0.2).timeout
	_snap("godot_slime_split_twins.png")
	print("slime_split_kids=", kids.size())
	Input.action_release("flashlight")
	quit(0)


func _snap(filename: String) -> void:
	var image: Image = get_root().get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, filename]
	var err := image.save_png(path)
	print("screenshot_err=", err, " path=", path, " size=", image.get_width(), "x", image.get_height())
