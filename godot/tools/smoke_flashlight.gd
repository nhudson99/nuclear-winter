extends SceneTree

## Headless smoke: Level 1 is unlit. Hold flashlight (RMB) to light and aim;
## WASD still moves independently of facing.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed == null:
		push_error("Missing Main.tscn")
		quit(1)
		return
	var main: Node3D = packed.instantiate()
	root.add_child(main)
	if not main.is_level_ready():
		await main.level_ready

	var env_ok := _environment_is_dark(main)
	var sun_ok := _sun_is_off(main)

	var player: CharacterBody3D = main.get_node("Player")
	if player == null:
		push_error("Missing Player")
		quit(1)
		return

	var monster: CharacterBody3D = main.get_node_or_null("Monster")
	if monster:
		monster.set_physics_process(false)
		monster.global_position += Vector3(200.0, 0.0, 200.0)

	var flashlight: SpotLight3D = player.get_flashlight() if player.has_method("get_flashlight") else null
	var fill := player.get_node_or_null("Model/FlashlightFill") as OmniLight3D
	var visual: Node3D = player.get_node_or_null("Model")
	var parented := flashlight != null and visual != null and flashlight.get_parent() == visual
	var starts_off: bool = (
		not player.is_flashlight_on()
		and flashlight != null
		and not flashlight.visible
		and (fill == null or not fill.visible)
	)
	var beam_ok := (
		flashlight != null
		and flashlight.light_energy > 1.0
		and flashlight.spot_range >= 8.0
		and flashlight.spot_angle > 10.0
	)
	var rmb_ok := _flashlight_uses_rmb()
	print(
		"dark_env_ok=", env_ok,
		" sun_off_ok=", sun_ok,
		" flashlight_ok=", flashlight != null,
		" parented_ok=", parented,
		" starts_off=", starts_off,
		" beam_ok=", beam_ok,
		" rmb_ok=", rmb_ok
	)

	Input.action_press("flashlight")
	# physics_frame fires before _physics_process, so one tick is not enough.
	for _i in range(3):
		await physics_frame
	var held_on: bool = player.is_flashlight_on() and flashlight != null and flashlight.visible
	print("hold_on_ok=", held_on)

	Input.action_release("flashlight")
	for _i in range(3):
		await physics_frame
	var released_off: bool = (
		not player.is_flashlight_on()
		and flashlight != null
		and not flashlight.visible
	)
	print("release_off_ok=", released_off)

	# Pin the aim at +X so facing is independent of WASD.
	var expected_yaw := atan2(1.0, 0.0) + PI
	player.set_aim_world_override(player.global_position + Vector3(8.0, 0.0, 0.0))
	Input.action_press("flashlight")
	for _i in range(30):
		await physics_frame
	var aim_err := absf(angle_difference(visual.rotation.y, expected_yaw))
	var aim_ok := aim_err < 0.2
	print("aim_yaw_ok=", aim_ok, " yaw=", visual.rotation.y, " expected=", expected_yaw, " err=", aim_err)

	var pos0 := player.global_position
	Input.action_press("move_up")
	for _i in range(20):
		await physics_frame
	Input.action_release("move_up")
	var moved := player.global_position.distance_to(pos0) > 0.4
	var still_aimed := absf(angle_difference(visual.rotation.y, expected_yaw)) < 0.25
	var walk_yaw := atan2(
		player.global_position.x - pos0.x,
		player.global_position.z - pos0.z
	) + PI
	var not_walk_facing := absf(angle_difference(visual.rotation.y, walk_yaw)) > 0.4
	print(
		"strafe_ok=", moved and still_aimed and not_walk_facing,
		" moved=", moved,
		" still_aimed=", still_aimed,
		" not_walk_facing=", not_walk_facing,
		" walk_yaw=", walk_yaw
	)

	Input.action_release("flashlight")
	player.clear_aim_world_override()
	await physics_frame

	var action_ok := InputMap.has_action("flashlight")
	print("action_ok=", action_ok)

	var all_ok: bool = (
		env_ok
		and sun_ok
		and flashlight != null
		and parented
		and starts_off
		and beam_ok
		and rmb_ok
		and held_on
		and released_off
		and aim_ok
		and moved
		and still_aimed
		and not_walk_facing
		and action_ok
	)
	print("flashlight_smoke_ok=", all_ok)
	quit(0 if all_ok else 1)


func _flashlight_uses_rmb() -> bool:
	if not InputMap.has_action("flashlight"):
		return false
	for event in InputMap.action_get_events("flashlight"):
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
			return true
	return false


func _environment_is_dark(main: Node3D) -> bool:
	var world := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world == null or world.environment == null:
		return false
	var env := world.environment
	var bg_black := env.background_color.r < 0.02 and env.background_color.g < 0.02 and env.background_color.b < 0.02
	var ambient_dim := (
		env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR
		and absf(env.ambient_light_energy - 0.10) < 0.02
	)
	print(
		"env_bg=", env.background_color,
		" ambient_source=", env.ambient_light_source,
		" ambient_energy=", env.ambient_light_energy
	)
	return bg_black and ambient_dim


func _sun_is_off(main: Node3D) -> bool:
	var sun := main.get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		return true
	var off := (not sun.visible) or sun.light_energy <= 0.001
	print("sun_visible=", sun.visible, " sun_energy=", sun.light_energy)
	return off
