extends CharacterBody3D

@export var move_speed: float = 5.5
@export var gravity: float = 20.0
@export var turn_speed: float = 12.0
@export var walk_anim_speed: float = 10.0
@export var stride_angle_deg: float = 28.0

@onready var visual: Node3D = $Humanoid

var pivot_arm_l: Node3D
var pivot_arm_r: Node3D
var pivot_leg_l: Node3D
var pivot_leg_r: Node3D
var _walk_phase: float = 0.0

func _ready() -> void:
	pivot_arm_l = _find_node_by_name(visual, "Pivot_Arm_L") as Node3D
	pivot_arm_r = _find_node_by_name(visual, "Pivot_Arm_R") as Node3D
	pivot_leg_l = _find_node_by_name(visual, "Pivot_Leg_L") as Node3D
	pivot_leg_r = _find_node_by_name(visual, "Pivot_Leg_R") as Node3D

func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	input.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")

	# Camera-relative isometric movement.
	var forward := Vector3(-1, 0, -1).normalized()
	var right := Vector3(1, 0, -1).normalized()
	var direction := (right * input.x) + (forward * -input.y)
	if direction.length() > 1.0:
		direction = direction.normalized()

	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	move_and_slide()

	var planar := Vector3(velocity.x, 0.0, velocity.z)
	var speed := planar.length()
	if speed > 0.15:
		var target_yaw := atan2(planar.x, planar.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))
		_walk_phase += delta * walk_anim_speed * clampf(speed / move_speed, 0.35, 1.25)
		_animate_walk(_walk_phase, 1.0)
	else:
		_animate_walk(_walk_phase, 0.0)

func _animate_walk(phase: float, amount: float) -> void:
	var swing := deg_to_rad(stride_angle_deg) * amount * sin(phase)
	if pivot_arm_l:
		pivot_arm_l.rotation.x = -swing
	if pivot_arm_r:
		pivot_arm_r.rotation.x = swing
	if pivot_leg_l:
		pivot_leg_l.rotation.x = swing
	if pivot_leg_r:
		pivot_leg_r.rotation.x = -swing
	if visual:
		visual.position.y = 0.03 * amount * absf(sin(phase * 2.0))

func _find_node_by_name(root: Node, node_name: String) -> Node:
	if root == null:
		return null
	if root.name == node_name:
		return root
	for child in root.get_children():
		var found := _find_node_by_name(child, node_name)
		if found:
			return found
	return null
