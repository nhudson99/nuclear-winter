extends SceneTree

const TouchControlsScript := preload("res://scripts/TouchControls.gd")

## Headless smoke for the on-screen sticks and USE / ATK buttons.
## Left stick moves, a full shove runs, right stick aims the flashlight
## independently of movement, USE collects, ATK damages.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var planar_ok := _planar_matches_camera()
	print("planar_ok=", planar_ok)

	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed == null:
		push_error("Missing Main.tscn")
		quit(1)
		return
	var main: Node3D = packed.instantiate()
	main.min_loading_seconds = 0.0
	main.level_seed = 7
	root.add_child(main)
	if not main.is_level_ready():
		await main.level_ready

	var player: CharacterBody3D = main.get_node_or_null("Player")
	var touch: Node = main.get_node_or_null("TouchControls")
	if player == null or touch == null:
		push_error("Missing Player or TouchControls")
		quit(1)
		return
	if main.has_method("park_monsters"):
		main.park_monsters()

	for _i in range(3):
		await process_frame

	var present_ok: bool = (
		touch.get_node_or_null("Root/MoveStick") != null
		and touch.get_node_or_null("Root/AimStick") != null
		and touch.get_node_or_null("Root/InteractButton") != null
		and touch.get_node_or_null("Root/AttackButton") != null
		and bool(touch.visible)
	)
	var vp := root.get_visible_rect().size
	var move_rect: Rect2 = touch.get_node("Root/MoveStick").get_global_rect()
	var aim_rect: Rect2 = touch.get_node("Root/AimStick").get_global_rect()
	var use_rect: Rect2 = touch.get_node("Root/InteractButton").get_global_rect()
	var atk_rect: Rect2 = touch.get_node("Root/AttackButton").get_global_rect()
	var layout_ok := (
		vp.x > 100.0
		and move_rect.get_center().x < vp.x * 0.35
		and aim_rect.get_center().x > vp.x * 0.65
		and use_rect.get_center().x > vp.x * 0.5
		and atk_rect.get_center().x > use_rect.get_center().x
		and use_rect.get_center().y < aim_rect.get_center().y
		and atk_rect.get_center().y < aim_rect.get_center().y
	)
	print(
		"present_ok=", present_ok,
		" layout_ok=", layout_ok,
		" vp=", vp,
		" move=", move_rect,
		" aim=", aim_rect,
		" use=", use_rect,
		" atk=", atk_rect
	)

	var drag_up := move_rect.get_center() + Vector2(0.0, -70.0)
	var captured := bool(touch.pointer_down(3, move_rect.get_center()))
	touch.pointer_move(3, drag_up)
	var dragged: Vector2 = touch.move_stick_vector()
	var drag_ok := captured and dragged.y > 0.35 and absf(dragged.x) < 0.35
	# A short shove, about 44% of the pad radius, must already be a strong
	# stick. At 1:1 that travel only reaches ~0.44.
	var short := move_rect.get_center() + Vector2(0.0, -move_rect.size.y * 0.22)
	touch.pointer_move(3, short)
	var boosted: Vector2 = touch.move_stick_vector()
	var sensitivity_ok := boosted.y > 0.7 and absf(boosted.x) < 0.25
	touch.pointer_up(3)
	var released_ok: bool = touch.move_stick_vector().length_squared() < 0.0001
	print(
		"drag_ok=", drag_ok,
		" sensitivity_ok=", sensitivity_ok,
		" released_ok=", released_ok,
		" dragged=", dragged,
		" boosted=", boosted
	)

	touch.set_move_stick(Vector2(0.0, 1.0))
	var pos0 := player.global_position
	for _i in range(25):
		await physics_frame
	var delta := player.global_position - pos0
	delta.y = 0.0
	var expected := Vector3(-1.0, 0.0, -1.0).normalized()
	var moved_ok := delta.length() > 0.5 and delta.normalized().dot(expected) > 0.9
	var run_ok := String(player.current_clip()) == "Run"
	print("moved_ok=", moved_ok, " run_ok=", run_ok, " delta=", delta, " clip=", player.current_clip())

	var visual: Node3D = player.get_node("Model")
	touch.set_aim_stick(Vector2(1.0, 0.0))
	var aim_expected: Vector3 = touch.aim_planar()
	var expected_yaw := atan2(aim_expected.x, aim_expected.z) + PI
	for _i in range(30):
		await physics_frame
	var aim_err := absf(angle_difference(visual.rotation.y, expected_yaw))
	var aim_ok: bool = bool(player.is_flashlight_on()) and aim_err < 0.2
	var pos1 := player.global_position
	for _i in range(15):
		await physics_frame
	var strafe := player.global_position - pos1
	strafe.y = 0.0
	var still_aimed := absf(angle_difference(visual.rotation.y, expected_yaw)) < 0.25
	var strafe_ok := strafe.length() > 0.3 and still_aimed
	print(
		"aim_ok=", aim_ok,
		" strafe_ok=", strafe_ok,
		" yaw_err=", aim_err,
		" light=", player.is_flashlight_on(),
		" strafe=", strafe
	)

	touch.set_move_stick(Vector2.ZERO)
	touch.set_aim_stick(Vector2.ZERO)
	for _i in range(3):
		await physics_frame
	var light_off_ok: bool = not bool(player.is_flashlight_on())
	print("light_off_ok=", light_off_ok)

	var monsters: Array = main.monsters() if main.has_method("monsters") else []
	var attack_ok := false
	if monsters.is_empty():
		push_error("No monster to attack")
	else:
		var monster: CharacterBody3D = monsters[0]
		monster.visible = true
		monster.set_physics_process(false)
		monster.touch_damage = 0.0
		touch.set_aim_stick(Vector2(1.0, 0.0))
		await physics_frame
		var aim_dir: Vector3 = touch.aim_planar()
		monster.global_position = player.global_position + aim_dir * 1.15
		var before: float = monster.health
		touch.press_attack()
		attack_ok = monster.health < before - 0.5
		print("attack_ok=", attack_ok, " before=", before, " after=", monster.health)
	touch.set_aim_stick(Vector2.ZERO)

	var pickup: Node3D = main.get_node_or_null("PickupItem")
	var interact_ok := false
	if pickup == null:
		push_error("Missing PickupItem")
	else:
		player.global_position = pickup.global_position
		touch.press_interact()
		interact_ok = player.has_collected_item() or not is_instance_valid(pickup)
		print("interact_ok=", interact_ok, " has_item=", player.has_collected_item())

	var use_press := bool(touch.pointer_down(4, use_rect.get_center()))
	var atk_press := bool(touch.pointer_down(5, atk_rect.get_center()))
	var buttons_ok := use_press and atk_press
	touch.pointer_up(4)
	touch.pointer_up(5)
	print("buttons_ok=", buttons_ok)

	var all_ok: bool = (
		planar_ok
		and present_ok
		and layout_ok
		and drag_ok
		and sensitivity_ok
		and released_ok
		and moved_ok
		and run_ok
		and aim_ok
		and strafe_ok
		and light_off_ok
		and attack_ok
		and interact_ok
		and buttons_ok
	)
	print("touch_controls_smoke_ok=", all_ok)
	quit(0 if all_ok else 1)


func _planar_matches_camera() -> bool:
	var up: Vector3 = TouchControlsScript.stick_to_planar(Vector2(0.0, 1.0))
	var right: Vector3 = TouchControlsScript.stick_to_planar(Vector2(1.0, 0.0))
	var forward := Vector3(-1.0, 0.0, -1.0).normalized()
	var screen_right := Vector3(1.0, 0.0, -1.0).normalized()
	return up.normalized().dot(forward) > 0.99 and right.normalized().dot(screen_right) > 0.99
