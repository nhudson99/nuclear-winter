extends CharacterBody3D

## Chases the player when they are inside FOV and have clear line of sight.

@export var move_speed: float = 3.8
@export var gravity: float = 20.0
@export var turn_speed: float = 8.0
@export var detect_range: float = 16.0
@export var field_of_view_deg: float = 75.0
@export var eye_height: float = 1.7
@export var lose_sight_grace: float = 1.25
@export var walk_anim_speed: float = 9.0
@export var stride_angle_deg: float = 34.0

@onready var visual: Node3D = $MonsterMesh

var player: CharacterBody3D
var pivot_arm_l: Node3D
var pivot_arm_r: Node3D
var pivot_leg_l: Node3D
var pivot_leg_r: Node3D
var _walk_phase: float = 0.0
var _seeing_player: bool = false
var _time_since_seen: float = 999.0
var _last_seen_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	add_to_group("monster")
	player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player == null:
		player = get_parent().get_node_or_null("Player") as CharacterBody3D
	pivot_arm_l = _find_node_by_name(visual, "Pivot_Arm_L") as Node3D
	pivot_arm_r = _find_node_by_name(visual, "Pivot_Arm_R") as Node3D
	pivot_leg_l = _find_node_by_name(visual, "Pivot_Leg_L") as Node3D
	pivot_leg_r = _find_node_by_name(visual, "Pivot_Leg_R") as Node3D

func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody3D
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		_animate_walk(_walk_phase, 0.0)
		return

	_seeing_player = _can_see_player()
	if _seeing_player:
		_time_since_seen = 0.0
		_last_seen_pos = player.global_position
	else:
		_time_since_seen += delta

	var chase := _seeing_player or _time_since_seen <= lose_sight_grace
	var target := player.global_position if _seeing_player else _last_seen_pos
	var to_target := target - global_position
	to_target.y = 0.0
	var distance := to_target.length()

	if chase and distance > 0.45:
		var direction := to_target.normalized()
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
		# Mesh faces -Z at rest (Blender +Y); add PI so the creature looks toward travel.
		var target_yaw := atan2(direction.x, direction.z) + PI
		visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))
		_walk_phase += delta * walk_anim_speed
		_animate_walk(_walk_phase, 1.0)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_animate_walk(_walk_phase, 0.0)

	_apply_gravity(delta)
	move_and_slide()

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

func _can_see_player() -> bool:
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()
	if distance > detect_range or distance < 0.05:
		return false

	# Mesh rests facing -Z; world look direction is local -Z after yaw.
	var facing := Vector3(-sin(visual.rotation.y), 0.0, -cos(visual.rotation.y))
	var dir := to_player / distance
	var angle := rad_to_deg(acos(clampf(facing.dot(dir), -1.0, 1.0)))
	if angle > field_of_view_deg * 0.5:
		return false

	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0.0, eye_height, 0.0)
	var dest := player.global_position + Vector3(0.0, 1.0, 0.0)
	var query := PhysicsRayQueryParameters3D.create(origin, dest)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	# World geometry only — ignore player/monster capsules.
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	return hit.is_empty()

func _animate_walk(phase: float, amount: float) -> void:
	var swing := deg_to_rad(stride_angle_deg) * amount * sin(phase)
	if pivot_arm_l:
		pivot_arm_l.rotation.x = -swing * 1.15
	if pivot_arm_r:
		pivot_arm_r.rotation.x = swing * 1.15
	if pivot_leg_l:
		pivot_leg_l.rotation.x = swing
	if pivot_leg_r:
		pivot_leg_r.rotation.x = -swing
	if visual:
		visual.position.y = 0.04 * amount * absf(sin(phase * 2.0))

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
