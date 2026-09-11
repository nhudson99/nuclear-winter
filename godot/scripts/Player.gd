extends CharacterBody3D

signal died
signal item_collected

@export var move_speed: float = 2.4
@export var run_speed: float = 5.5
@export var gravity: float = 20.0
@export var turn_speed: float = 12.0
@export var max_health: float = 100.0
@export var health_bar_height: float = 2.1
@export var interact_range: float = 2.2
## Ground covered by one full cycle of each clip. Playback is scaled to match
## it so the boots do not skate across the floor.
@export var walk_cycle_metres: float = 1.45
@export var run_cycle_metres: float = 2.3
@export var run_threshold: float = 3.0
## Spot range in metres. One room tile is 12 m; this reaches the far wall and
## a little into the next doorway.
@export var flashlight_range: float = 16.0
@export var flashlight_angle: float = 28.0
@export var flashlight_energy: float = 8.0
@export var flashlight_fill_energy: float = 0.45

@onready var visual: Node3D = $Model

const LOOPING_CLIPS := ["Idle", "Walk", "Run"]

var _anim: AnimationPlayer
var _clip: String = ""
var health: float = 100.0
var _health_bar: HealthBar3D
var _alive: bool = true
var _has_item: bool = false
var _input_locked: bool = false
var _flashlight: SpotLight3D
var _flashlight_fill: OmniLight3D
var _flashlight_on: bool = true

func current_clip() -> String:
	return _clip


func _ready() -> void:
	add_to_group("player")
	_ensure_action("sprint", KEY_SHIFT)
	_ensure_action("flashlight", KEY_F)
	health = max_health
	_anim = _find_animation_player(visual)
	if _anim:
		# The glTF importer leaves every clip one-shot; the locomotion cycles
		# have to be told they loop.
		for clip_name in LOOPING_CLIPS:
			if _anim.has_animation(clip_name):
				_anim.get_animation(clip_name).loop_mode = Animation.LOOP_LINEAR
		_play("Idle", 1.0)
	_setup_flashlight()
	_health_bar = HealthBar3D.new()
	_health_bar.name = "HealthBar"
	_health_bar.fill_color = Color(0.25, 0.9, 0.4, 1.0)
	_health_bar.position = Vector3(0.0, health_bar_height, 0.0)
	add_child(_health_bar)
	_health_bar.set_health(health, max_health)

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("flashlight"):
		set_flashlight_on(not _flashlight_on)

	if not _alive or _input_locked:
		velocity = Vector3.ZERO
		_apply_gravity(delta)
		move_and_slide()
		if _alive:
			_play("Idle", 1.0)
		return

	if Input.is_action_just_pressed("interact"):
		_try_interact()

	var input := Vector2.ZERO
	input.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")

	# Camera-relative isometric movement.
	var forward := Vector3(-1, 0, -1).normalized()
	var right := Vector3(1, 0, -1).normalized()
	var direction := (right * input.x) + (forward * -input.y)
	if direction.length() > 1.0:
		direction = direction.normalized()

	# Digital WASD is otherwise always full speed, which would skip Walk.
	var gait := run_speed if Input.is_action_pressed("sprint") else move_speed
	velocity.x = direction.x * gait
	velocity.z = direction.z * gait
	_apply_gravity(delta)
	move_and_slide()

	var planar := Vector3(velocity.x, 0.0, velocity.z)
	var speed := planar.length()
	if speed > 0.15:
		# glTF forward is -Z, so the yaw that points the model down the travel
		# direction is half a turn from atan2 of the velocity.
		var target_yaw := atan2(planar.x, planar.z) + PI
		visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))
		var clip := "Run" if speed >= run_threshold else "Walk"
		var metres: float = run_cycle_metres if clip == "Run" else walk_cycle_metres
		_play(clip, _cycle_speed(clip, speed, metres))
	else:
		_play("Idle", 1.0)

func take_damage(amount: float) -> void:
	if not _alive or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	if _health_bar:
		_health_bar.set_health(health, max_health)
	if health <= 0.0:
		_alive = false
		velocity = Vector3.ZERO
		_play("Die", 1.0)
		died.emit()

func is_alive() -> bool:
	return _alive

func has_collected_item() -> bool:
	return _has_item

func lock_input() -> void:
	_input_locked = true
	velocity = Vector3.ZERO

func unlock_input() -> void:
	_input_locked = false

func is_flashlight_on() -> bool:
	return _flashlight_on

func set_flashlight_on(enabled: bool) -> void:
	_flashlight_on = enabled
	if _flashlight:
		_flashlight.visible = enabled
	if _flashlight_fill:
		_flashlight_fill.visible = enabled

func get_flashlight() -> SpotLight3D:
	return _flashlight

func _try_interact() -> void:
	if _has_item:
		return
	var best: Node = null
	var best_dist := interact_range
	for node in get_tree().get_nodes_in_group("pickup"):
		if node == null or not is_instance_valid(node):
			continue
		if not node.has_method("can_interact") or not node.can_interact(global_position):
			continue
		var to_item: Vector3 = (node as Node3D).global_position - global_position
		to_item.y = 0.0
		var dist := to_item.length()
		if dist <= best_dist:
			best_dist = dist
			best = node
	if best == null or not best.has_method("try_pickup"):
		return
	if best.try_pickup():
		_has_item = true
		item_collected.emit()

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

func _play(clip: String, speed: float) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	_anim.speed_scale = speed
	if _clip == clip:
		return
	_clip = clip
	_anim.play(clip, 0.15, speed)

func _cycle_speed(clip: String, speed: float, cycle_metres: float) -> float:
	if _anim == null or not _anim.has_animation(clip) or cycle_metres <= 0.0:
		return 1.0
	var cycle_seconds := _anim.get_animation(clip).length
	return clampf(speed * cycle_seconds / cycle_metres, 0.35, 2.5)

func _ensure_action(action: String, keycode: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)

func _setup_flashlight() -> void:
	# Parent to the yawing model so the cone follows facing. glTF forward is
	# -Z, which is also the default SpotLight3D beam direction.
	var host: Node3D = visual if visual else self
	_flashlight = SpotLight3D.new()
	_flashlight.name = "Flashlight"
	_flashlight.light_color = Color(1.0, 0.95, 0.78)
	_flashlight.light_energy = flashlight_energy
	_flashlight.spot_range = flashlight_range
	_flashlight.spot_angle = flashlight_angle
	_flashlight.spot_attenuation = 0.55
	_flashlight.shadow_enabled = true
	_flashlight.shadow_bias = 0.04
	# Chest height, a few centimetres forward of the torso so the beam does
	# not start inside the prisoner mesh.
	_flashlight.position = Vector3(0.12, 1.35, -0.18)
	_flashlight.rotation_degrees = Vector3(-16.0, 0.0, 0.0)
	host.add_child(_flashlight)

	# Without a fill, the beam origin sits in front of the chest and the
	# prisoner is a silhouette against the lit floor.
	_flashlight_fill = OmniLight3D.new()
	_flashlight_fill.name = "FlashlightFill"
	_flashlight_fill.light_color = Color(1.0, 0.95, 0.78)
	_flashlight_fill.light_energy = flashlight_fill_energy
	_flashlight_fill.omni_range = 2.8
	_flashlight_fill.omni_attenuation = 1.4
	_flashlight_fill.position = Vector3(0.0, 1.1, 0.0)
	host.add_child(_flashlight_fill)
	set_flashlight_on(true)

func _find_animation_player(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null
