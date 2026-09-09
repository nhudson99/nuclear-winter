extends CharacterBody3D

## Patrols mansion sections room-by-room, detects nearby players in a radius,
## and also chases on FOV + line of sight. Touching the player deals lethal damage.

@export var move_speed: float = 3.8
@export var gravity: float = 20.0
@export var turn_speed: float = 8.0
@export var detect_range: float = 16.0
@export var proximity_radius: float = 3.0
@export var field_of_view_deg: float = 75.0
@export var eye_height: float = 1.7
@export var lose_sight_grace: float = 1.25
@export var walk_anim_speed: float = 9.0
@export var stride_angle_deg: float = 34.0
@export var max_health: float = 100.0
@export var touch_damage: float = 100.0
@export var health_bar_height: float = 2.35
@export var section_count: int = 3
@export var section_dwell_time: float = 30.0
@export var room_arrive_distance: float = 0.7
@export var touch_radius: float = 0.95

@onready var visual: Node3D = $MonsterMesh

var player: CharacterBody3D
var pivot_arm_l: Node3D
var pivot_arm_r: Node3D
var pivot_leg_l: Node3D
var pivot_leg_r: Node3D
var _walk_phase: float = 0.0
var _seeing_player: bool = false
var _near_player: bool = false
var _time_since_seen: float = 999.0
var _last_seen_pos: Vector3 = Vector3.ZERO
var health: float = 100.0
var _health_bar: HealthBar3D
var _alive: bool = true

# Level footprint in Godot XZ (Blender floor ~12.4 x 18.2, walls x±6 / z -9..+8).
const LEVEL_MIN_X: float = -6.0
const LEVEL_MAX_X: float = 6.0
const LEVEL_MIN_Z: float = -9.0
const LEVEL_MAX_Z: float = 8.0

var _sections: Array = [] # Array of Arrays of room dicts {name, center}
var _section_index: int = 0
var _room_index: int = 0
var _section_timer: float = 0.0
var _patrol_target: Vector3 = Vector3.ZERO
var _item_alerted: bool = false

func _ready() -> void:
	add_to_group("monster")
	health = max_health
	player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player == null:
		player = get_parent().get_node_or_null("Player") as CharacterBody3D
	pivot_arm_l = _find_node_by_name(visual, "Pivot_Arm_L") as Node3D
	pivot_arm_r = _find_node_by_name(visual, "Pivot_Arm_R") as Node3D
	pivot_leg_l = _find_node_by_name(visual, "Pivot_Leg_L") as Node3D
	pivot_leg_r = _find_node_by_name(visual, "Pivot_Leg_R") as Node3D
	_build_sections()
	_section_index = _section_for_position(global_position)
	_room_index = 0
	_section_timer = 0.0
	_refresh_patrol_target()
	_setup_health_bar()
	_setup_touch_area()

func _physics_process(delta: float) -> void:
	if not _alive:
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		_animate_walk(_walk_phase, 0.0)
		return

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody3D
		_patrol(delta)
		_apply_gravity(delta)
		move_and_slide()
		return

	_near_player = _is_player_in_proximity()
	_seeing_player = _near_player or _can_see_player()
	if _seeing_player:
		_time_since_seen = 0.0
		_last_seen_pos = player.global_position
	else:
		_time_since_seen += delta

	var chase := _seeing_player or _time_since_seen <= lose_sight_grace
	if chase:
		var target := player.global_position if _seeing_player else _last_seen_pos
		_move_toward(target, delta)
	else:
		_patrol(delta)

	_apply_gravity(delta)
	move_and_slide()

func take_damage(amount: float) -> void:
	if not _alive or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	if _health_bar:
		_health_bar.set_health(health, max_health)
	if health <= 0.0:
		_alive = false
		velocity = Vector3.ZERO

func is_alive() -> bool:
	return _alive

func get_current_section() -> int:
	return _section_index

func get_section_rooms(section_idx: int) -> Array:
	if section_idx < 0 or section_idx >= _sections.size():
		return []
	return _sections[section_idx]

func configure_patrol_for_test(dwell_time: float, section_idx: int = 0) -> void:
	section_dwell_time = dwell_time
	_section_timer = 0.0
	_section_index = clampi(section_idx, 0, maxi(_sections.size() - 1, 0))
	_room_index = 0
	_time_since_seen = 999.0
	_seeing_player = false
	_near_player = false
	_refresh_patrol_target()

## Called when the player steals the objective: patrols twice as often, detects twice as far.
func alert_item_stolen() -> void:
	if _item_alerted:
		return
	_item_alerted = true
	section_dwell_time *= 0.5
	proximity_radius *= 2.0

func is_item_alerted() -> bool:
	return _item_alerted

func _setup_health_bar() -> void:
	_health_bar = HealthBar3D.new()
	_health_bar.name = "HealthBar"
	_health_bar.fill_color = Color(0.9, 0.2, 0.18, 1.0)
	_health_bar.position = Vector3(0.0, health_bar_height, 0.0)
	add_child(_health_bar)
	_health_bar.set_health(health, max_health)

func _setup_touch_area() -> void:
	var area := Area3D.new()
	area.name = "TouchArea"
	area.collision_layer = 0
	area.collision_mask = 2 # player layer
	area.monitoring = true
	area.monitorable = false
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var sphere := SphereShape3D.new()
	sphere.radius = touch_radius
	shape.shape = sphere
	shape.position = Vector3(0.0, 1.0, 0.0)
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_touch_body_entered)

func _on_touch_body_entered(body: Node3D) -> void:
	if not _alive:
		return
	if body == null or not body.is_in_group("player"):
		return
	if body.has_method("take_damage"):
		body.take_damage(touch_damage)

func _patrol(delta: float) -> void:
	if _sections.is_empty():
		velocity.x = 0.0
		velocity.z = 0.0
		_animate_walk(_walk_phase, 0.0)
		return

	_section_timer += delta
	if _section_timer >= section_dwell_time:
		_section_timer = 0.0
		_section_index = (_section_index + 1) % _sections.size()
		_room_index = 0
		_refresh_patrol_target()

	var rooms: Array = _sections[_section_index]
	if rooms.is_empty():
		velocity.x = 0.0
		velocity.z = 0.0
		_animate_walk(_walk_phase, 0.0)
		return

	var to_target := _patrol_target - global_position
	to_target.y = 0.0
	if to_target.length() <= room_arrive_distance:
		_room_index = (_room_index + 1) % rooms.size()
		_refresh_patrol_target()

	_move_toward(_patrol_target, delta)

func _refresh_patrol_target() -> void:
	if _sections.is_empty():
		_patrol_target = global_position
		return
	var rooms: Array = _sections[_section_index]
	if rooms.is_empty():
		_patrol_target = global_position
		return
	_room_index = clampi(_room_index, 0, rooms.size() - 1)
	var room: Dictionary = rooms[_room_index]
	_patrol_target = room["center"]

func _move_toward(target: Vector3, delta: float) -> void:
	var to_target := target - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	if distance > 0.45:
		var direction := to_target / distance
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

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

func _is_player_in_proximity() -> bool:
	if player == null:
		return false
	if player.has_method("is_alive") and not player.is_alive():
		return false
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	return to_player.length() <= proximity_radius

func _can_see_player() -> bool:
	if player.has_method("is_alive") and not player.is_alive():
		return false
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

func _build_sections() -> void:
	_sections.clear()
	var count := maxi(section_count, 1)
	for _i in count:
		_sections.append([])

	var rooms := _mansion_rooms()
	var depth := (LEVEL_MAX_Z - LEVEL_MIN_Z) / float(count)
	for room in rooms:
		var center: Vector3 = room["center"]
		var idx := int(floor((center.z - LEVEL_MIN_Z) / depth))
		idx = clampi(idx, 0, count - 1)
		_sections[idx].append(room)

	# Guarantee every section has at least one waypoint derived from equal grid cells.
	for i in count:
		if not (_sections[i] as Array).is_empty():
			continue
		var z0 := LEVEL_MIN_Z + depth * float(i)
		var z1 := z0 + depth
		_sections[i].append({
			"name": "section_%d_center" % i,
			"center": Vector3(0.0, 0.05, (z0 + z1) * 0.5),
		})

func _section_for_position(pos: Vector3) -> int:
	var count := maxi(section_count, 1)
	var depth := (LEVEL_MAX_Z - LEVEL_MIN_Z) / float(count)
	var idx := int(floor((pos.z - LEVEL_MIN_Z) / depth))
	return clampi(idx, 0, count - 1)

func _mansion_rooms() -> Array:
	# Centers match the authored mansion rooms (Godot XZ = Blender X, -Y).
	return [
		{"name": "bottom_l", "center": Vector3(-3.0, 0.05, 4.5)},
		{"name": "bottom_r", "center": Vector3(3.0, 0.05, 4.5)},
		{"name": "mid_l", "center": Vector3(-4.1, 0.05, -1.6)},
		{"name": "mid_c", "center": Vector3(0.0, 0.05, -1.6)},
		{"name": "mid_r", "center": Vector3(4.1, 0.05, -1.6)},
		{"name": "top_l", "center": Vector3(-4.1, 0.05, -6.4)},
		{"name": "top_c", "center": Vector3(0.0, 0.05, -6.4)},
		{"name": "top_r", "center": Vector3(4.1, 0.05, -6.4)},
	]

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
