extends SceneTree

## Headless smoke: Level 1 is unlit, the player has a flashlight, F toggles it.

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

	var flashlight: SpotLight3D = player.get_flashlight() if player.has_method("get_flashlight") else null
	var fill := player.get_node_or_null("Model/FlashlightFill") as OmniLight3D
	var visual: Node3D = player.get_node_or_null("Model")
	var parented := flashlight != null and visual != null and flashlight.get_parent() == visual
	var starts_on: bool = player.is_flashlight_on() and flashlight != null and flashlight.visible
	var fill_on: bool = fill != null and fill.visible
	var beam_ok := (
		flashlight != null
		and flashlight.light_energy > 1.0
		and flashlight.spot_range >= 8.0
		and flashlight.spot_angle > 10.0
	)
	print(
		"dark_env_ok=", env_ok,
		" sun_off_ok=", sun_ok,
		" flashlight_ok=", flashlight != null,
		" parented_ok=", parented,
		" starts_on=", starts_on,
		" fill_ok=", fill_on,
		" beam_ok=", beam_ok
	)

	# Drive _physics_process ourselves so the engine cannot consume the
	# just_pressed edge on the same tick.
	player.set_physics_process(false)

	Input.action_press("flashlight")
	player._physics_process(0.033)
	Input.action_release("flashlight")
	var toggled_off: bool = (
		not player.is_flashlight_on()
		and flashlight != null
		and not flashlight.visible
		and (fill == null or not fill.visible)
	)
	print("toggle_off_ok=", toggled_off)

	Input.action_press("flashlight")
	player._physics_process(0.033)
	Input.action_release("flashlight")
	var toggled_on: bool = player.is_flashlight_on() and flashlight != null and flashlight.visible
	print("toggle_on_ok=", toggled_on)

	# The cone must yaw with the prisoner, not stay world-locked.
	var yaw_ok := false
	if flashlight != null and visual != null:
		visual.rotation.y = 0.0
		await process_frame
		var ahead0 := -flashlight.global_transform.basis.z
		ahead0.y = 0.0
		visual.rotation.y = PI * 0.5
		await process_frame
		var ahead1 := -flashlight.global_transform.basis.z
		ahead1.y = 0.0
		var turned := ahead0.normalized().dot(ahead1.normalized()) < 0.35
		yaw_ok = turned
		print(
			"yaw_follow_ok=", yaw_ok,
			" ahead0=", ahead0,
			" ahead1=", ahead1
		)
	else:
		print("yaw_follow_ok=false")

	# Binding F must work even when project.godot is the only source.
	var action_ok := InputMap.has_action("flashlight")
	print("action_ok=", action_ok)

	var all_ok: bool = (
		env_ok
		and sun_ok
		and flashlight != null
		and parented
		and starts_on
		and fill_on
		and beam_ok
		and toggled_off
		and toggled_on
		and yaw_ok
		and action_ok
	)
	print("flashlight_smoke_ok=", all_ok)
	quit(0 if all_ok else 1)


func _environment_is_dark(main: Node3D) -> bool:
	var world := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world == null or world.environment == null:
		return false
	var env := world.environment
	var bg_black := env.background_color.r < 0.02 and env.background_color.g < 0.02 and env.background_color.b < 0.02
	var ambient_off := (
		env.ambient_light_source == Environment.AMBIENT_SOURCE_DISABLED
		or env.ambient_light_energy <= 0.001
	)
	print(
		"env_bg=", env.background_color,
		" ambient_source=", env.ambient_light_source,
		" ambient_energy=", env.ambient_light_energy
	)
	return bg_black and ambient_off


func _sun_is_off(main: Node3D) -> bool:
	var sun := main.get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		return true
	var off := (not sun.visible) or sun.light_energy <= 0.001
	print("sun_visible=", sun.visible, " sun_energy=", sun.light_energy)
	return off
