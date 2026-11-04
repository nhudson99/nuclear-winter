extends CharacterBody3D

## Patrols a generated monster track (room centres linked through doorway
## centres), detects nearby players in a radius, and chases on FOV + line of
## sight, when shot, or while the flashlight beam is on them. A player inside
## a hide spot is concealed: no proximity, sight, flashlight, or melee. A monster
## that was already chasing and could see the entry walks to the spot and
## smashes it. It path-follows the track so walls and furniture do not trap it. After losing detection for
## `lose_sight_grace` seconds it returns to the track. Damage uses an attack
## swing on a cooldown (not instant touch). Dead monsters despawn. Off-floor
## bodies keep patrolling through MonsterTracker.

enum AiMode { PATROL, CHASE, RETURN }

const CharacterMeshScript := preload("res://scripts/CharacterMesh.gd")

@export var move_speed: float = 3.8
@export var gravity: float = 20.0
@export var turn_speed: float = 8.0
@export var detect_range: float = 16.0
@export var proximity_radius: float = 3.0
@export var field_of_view_deg: float = 75.0
@export var eye_height: float = 1.7
## Seconds after losing the player before the monster gives up and returns to
## the main track.
@export var lose_sight_grace: float = 5.0
@export var walk_anim_speed: float = 9.0
@export var stride_angle_deg: float = 34.0
@export var max_health: float = 100.0
@export var touch_damage: float = 100.0
## Seconds between melee swings. Fast monsters (slime) use 0.25; others 0.5.
@export var attack_interval: float = 0.5
@export var fast_attacker: bool = false
@export var health_bar_height: float = 2.35
@export var section_dwell_time: float = 30.0
@export var room_arrive_distance: float = 0.7
@export var touch_radius: float = 0.95
@export var indestructible: bool = false
@export var show_health_bar: bool = true
## Added to travel yaw so imported meshes that rest on -Z face the walk direction.
@export var facing_yaw_offset: float = PI
## Optional AnimationPlayer clips. Empty strings keep the procedural pivot walk.
@export var idle_clip: String = ""
@export var walk_clip: String = ""
@export var hit_clip: String = ""
@export var death_clip: String = ""
@export var attack_clip: String = ""
## One-shot that idle/walk must not cut off (toad swallow, and similar).
@export var action_clip: String = ""
@export var walk_cycle_metres: float = 1.6
## When set, this enemy grows to `grow_scale_target` over `grow_duration`
## seconds (size and max health), then splits into two original-sized copies.
@export var grow_and_split: bool = false
@export var grow_duration: float = 30.0
@export var grow_scale_target: float = 2.0

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
var _health_revealed: bool = false

var _item_alerted: bool = false
var _ai_mode: AiMode = AiMode.PATROL
var _force_detect: bool = false
var _provoked: bool = false
var _stuck_time: float = 0.0

var _track_nodes: Dictionary = {}
var _current_node_id: String = ""
var _came_from_id: String = ""
var _target_node_id: String = ""
var _patrol_target: Vector3 = Vector3.ZERO
var _return_node_id: String = ""
var _rng := RandomNumberGenerator.new()
var _anim: AnimationPlayer
var _clip: String = ""
var _anim_locked: bool = false

var _level_rooms: Array = []
var _level_bounds: AABB = AABB()
var _grow_elapsed: float = 0.0
var _split_started: bool = false
var _growth_bases_ready: bool = false
var _base_max_health: float = 100.0
var _base_eye_height: float = 1.7
var _base_health_bar_height: float = 2.35
var _base_touch_radius: float = 0.95
var _visual_base_scale: Vector3 = Vector3.ONE
var _capsule_node: CollisionShape3D
var _capsule_shape: CapsuleShape3D
var _base_capsule_radius: float = 0.36
var _base_capsule_height: float = 0.85
var _base_capsule_pos: Vector3 = Vector3.ZERO
var _touch_shape_node: CollisionShape3D
var _touch_sphere: SphereShape3D
var _base_touch_sphere_radius: float = 0.95
var _base_touch_pos: Vector3 = Vector3.ZERO
var _player_in_touch: bool = false
var _attack_cooldown_left: float = 0.0
var _breach_spot: Node3D
var _breach_striking: bool = false
var _breach_time_left: float = 0.0
## Unrigged bodies (stalker, void) have no hide_break clip. They lunge instead.
var _breach_lunge: bool = false
var _visual_rest: Vector3 = Vector3.ZERO
var _tracker: MonsterTracker
var _off_floor: bool = false
var _current_floor: int = 0
var _despawn_armed: bool = false

func _ready() -> void:
	CharacterMeshScript.upgrade(visual)
	CharacterMeshScript.drop_stray_meshes(visual)
	add_to_group("monster")
	health = max_health
	if fast_attacker or grow_and_split:
		attack_interval = 0.25
	elif attack_interval <= 0.0:
		attack_interval = 0.5
	_rng.randomize()
	player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player == null:
		player = get_parent().get_node_or_null("Player") as CharacterBody3D
	pivot_arm_l = _find_node_by_name(visual, "Pivot_Arm_L") as Node3D
	pivot_arm_r = _find_node_by_name(visual, "Pivot_Arm_R") as Node3D
	pivot_leg_l = _find_node_by_name(visual, "Pivot_Leg_L") as Node3D
	pivot_leg_r = _find_node_by_name(visual, "Pivot_Leg_R") as Node3D
	_setup_animations()
	if show_health_bar and not indestructible:
		_setup_health_bar()
	_setup_touch_area()
	if grow_and_split:
		add_to_group("slime")
		_capture_growth_bases()

func _physics_process(delta: float) -> void:
	if not _alive:
		velocity.x = 0.0
		velocity.z = 0.0
		if not _off_floor:
			_apply_gravity(delta)
			move_and_slide()
		_animate_walk(_walk_phase, 0.0)
		return

	_tick_growth(delta)
	if _split_started or is_queued_for_deletion():
		velocity.x = 0.0
		velocity.z = 0.0
		return

	_attack_cooldown_left = maxf(0.0, _attack_cooldown_left - delta)
	if _breach_spot != null:
		if _tick_hide_breach(delta):
			_finish_move(delta)
			return
	_try_melee_attack()
	_try_use_stairs()

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody3D
		_patrol(delta)
		_finish_move(delta)
		return

	var can_sense := _same_floor_as_player() and not _off_floor and not _player_is_hidden()
	_near_player = can_sense and _is_player_in_proximity()
	var lit := can_sense and _lit_by_flashlight()
	_seeing_player = can_sense and (
		_force_detect or _near_player or _can_see_player() or lit or _provoked
	)
	if _seeing_player and _allows_chase():
		_provoked = false
		_time_since_seen = 0.0
		_last_seen_pos = player.global_position
		if _ai_mode != AiMode.CHASE:
			_on_started_chase()
		_ai_mode = AiMode.CHASE
	else:
		_time_since_seen += delta
		if _ai_mode == AiMode.CHASE and _time_since_seen > lose_sight_grace:
			_begin_return_to_track()

	match _ai_mode:
		AiMode.CHASE:
			var target := player.global_position if _seeing_player else _last_seen_pos
			_chase_along_track(target, delta)
		AiMode.RETURN:
			_return_to_track(delta)
		AiMode.PATROL:
			_patrol(delta)
		_:
			_patrol(delta)

	_finish_move(delta)
	if not _off_floor:
		_update_stuck_recovery(delta)
		_update_health_bar_visibility()
	_refresh_room_cell()

func take_damage(amount: float) -> void:
	if not _alive or amount <= 0.0 or indestructible:
		return
	health = maxf(0.0, health - amount)
	if _health_bar:
		_health_bar.set_health(health, max_health)
	_provoked = true
	_time_since_seen = 0.0
	if player != null and is_instance_valid(player):
		_last_seen_pos = player.global_position
	if health <= 0.0:
		_alive = false
		velocity = Vector3.ZERO
		_drop_breach()
		_anim_locked = true
		_play_clip(death_clip, 1.0)
		_on_died()
		_begin_despawn()
	else:
		_play_clip(hit_clip, 1.0)

func is_alive() -> bool:
	return _alive

func get_ai_mode_name() -> String:
	match _ai_mode:
		AiMode.CHASE:
			return "chase"
		AiMode.RETURN:
			return "return"
		AiMode.PATROL:
			return "patrol"
		_:
			return "patrol"

func get_current_node_id() -> String:
	return _current_node_id

func get_target_node_id() -> String:
	return _target_node_id

func set_force_detect(enabled: bool) -> void:
	_force_detect = enabled

func set_track_rng_seed(seed_value: int) -> void:
	_rng.seed = seed_value

func configure_patrol_for_test(dwell_time: float, _section_idx: int = 0) -> void:
	section_dwell_time = dwell_time
	_ai_mode = AiMode.PATROL
	_reset_detection()
	_came_from_id = ""
	_current_node_id = _nearest_node_id(global_position)
	_choose_patrol_target()

## Called when the player steals the objective: patrols twice as often, detects twice as far.
func alert_item_stolen() -> void:
	if _item_alerted:
		return
	_item_alerted = true
	section_dwell_time *= 0.5
	proximity_radius *= 2.0

func is_item_alerted() -> bool:
	return _item_alerted

## Maps a 0-99 roll onto a cardinal turn. 0-24 left, 25-49 right, 50-74 up, 75-99 down.
static func direction_from_roll(roll: int) -> String:
	var bucket := roll
	if bucket < 0:
		bucket = 0
	if bucket > 99:
		bucket = 99
	if bucket <= 24:
		return MapGenerator.TRACK_LEFT
	if bucket <= 49:
		return MapGenerator.TRACK_RIGHT
	if bucket <= 74:
		return MapGenerator.TRACK_UP
	return MapGenerator.TRACK_DOWN

## Picks the next track node from `current_id`. Corridors keep going; intersections
## honour `roll` when that cardinal exit exists.
func pick_next_node_with_roll(current_id: String, came_from_id: String, roll: int) -> String:
	if not _track_nodes.has(current_id):
		return ""
	var exits: Dictionary = _track_nodes[current_id].get("exits", {})
	var neighbor_ids: Array[String] = []
	for dir in MapGenerator.TRACK_DIRS:
		if exits.has(dir):
			neighbor_ids.append(String(exits[dir]))
	if neighbor_ids.is_empty():
		return current_id
	if neighbor_ids.size() == 1:
		return neighbor_ids[0]
	if neighbor_ids.size() == 2 and not came_from_id.is_empty() and neighbor_ids.has(came_from_id):
		for dir in MapGenerator.TRACK_DIRS:
			if exits.has(dir) and String(exits[dir]) != came_from_id:
				return String(exits[dir])
		return came_from_id
	var preferred := direction_from_roll(roll)
	if exits.has(preferred):
		return String(exits[preferred])
	for dir in MapGenerator.TRACK_DIRS:
		if exits.has(dir):
			return String(exits[dir])
	return neighbor_ids[0]

func is_health_bar_revealed() -> bool:
	return _health_revealed

func reveal_health_bar() -> void:
	_update_health_bar_visibility()

func _update_health_bar_visibility() -> void:
	if not show_health_bar or indestructible or _health_bar == null:
		return
	var lit := _lit_by_flashlight()
	_health_revealed = lit
	_health_bar.visible = lit


func _lit_by_flashlight() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if not player.has_method("illuminates_point"):
		return false
	return player.illuminates_point(global_position + Vector3(0.0, 1.2, 0.0))

func _setup_health_bar() -> void:
	var existing := get_node_or_null("HealthBar")
	if existing is HealthBar3D:
		_health_bar = existing
		_health_bar.set_health(health, max_health)
		return
	_health_bar = HealthBar3D.new()
	_health_bar.name = "HealthBar"
	_health_bar.fill_color = Color(0.9, 0.2, 0.18, 1.0)
	_health_bar.position = Vector3(0.0, health_bar_height, 0.0)
	_health_bar.visible = false
	add_child(_health_bar)
	_health_bar.set_health(health, max_health)

func _setup_touch_area() -> void:
	var existing := get_node_or_null("TouchArea") as Area3D
	if existing != null:
		if not existing.body_entered.is_connected(_on_touch_body_entered):
			existing.body_entered.connect(_on_touch_body_entered)
		if not existing.body_exited.is_connected(_on_touch_body_exited):
			existing.body_exited.connect(_on_touch_body_exited)
		return
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
	area.body_exited.connect(_on_touch_body_exited)

func _on_touch_body_entered(body: Node3D) -> void:
	if not _alive:
		return
	if body == null or not body.is_in_group("player"):
		return
	if body.has_method("is_hidden") and body.is_hidden():
		return
	_player_in_touch = true

func _on_touch_body_exited(body: Node3D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	_player_in_touch = false


func _try_melee_attack() -> void:
	if not _alive or _off_floor or touch_damage <= 0.0:
		return
	if not _player_in_touch or not _allows_attack():
		return
	if not _same_floor_as_player():
		return
	if _attack_cooldown_left > 0.0:
		return
	if player == null or not is_instance_valid(player):
		return
	if player.has_method("is_alive") and not player.is_alive():
		return
	if _player_is_hidden():
		return
	_attack_cooldown_left = attack_interval
	_play_clip(attack_clip, 1.0)
	if player.has_method("take_damage"):
		player.take_damage(touch_damage)


func _allows_attack() -> bool:
	return true


func _finish_move(delta: float) -> void:
	if _off_floor:
		# Abstract slide along the track — no collision on parked floors.
		global_position.x += velocity.x * delta
		global_position.z += velocity.z * delta
		velocity.y = 0.0
		return
	_apply_gravity(delta)
	move_and_slide()


func bind_tracker(tracker: MonsterTracker) -> void:
	_tracker = tracker


func set_off_floor(off: bool) -> void:
	_off_floor = off
	visible = not off
	# Keep ticking so patrol continues on other floors.
	set_physics_process(true)
	if off:
		_player_in_touch = false
		collision_layer = 0
		collision_mask = 0
	else:
		collision_layer = 4
		collision_mask = 1


func is_off_floor() -> bool:
	return _off_floor


func on_tracker_floor_changed(
	floor: int,
	track: Dictionary,
	rooms: Array,
	bounds: AABB
) -> void:
	_current_floor = floor
	configure_level(rooms, bounds, track)


func _same_floor_as_player() -> bool:
	if _tracker == null:
		return not _off_floor
	var main := get_tree().get_first_node_in_group("main_level")
	if main != null and main.has_method("get_active_floor"):
		return _tracker.get_floor(self) == int(main.get_active_floor())
	return not _off_floor


func _refresh_room_cell() -> void:
	if _tracker == null or _track_nodes.is_empty():
		return
	if _current_node_id.is_empty() or not _track_nodes.has(_current_node_id):
		return
	var info: Dictionary = _track_nodes[_current_node_id]
	if info.has("cell"):
		_tracker.set_room(self, info["cell"])


func _try_use_stairs() -> void:
	if _tracker == null:
		return
	var stairs: Array = _tracker.stairs_for(_tracker.get_floor(self))
	if stairs.is_empty():
		return
	for spec in stairs:
		if int(spec.get("required_stage", 0)) > 0:
			# Locked stairs stay closed for monsters until unlocked in layout.
			# Stairwell.unlock is per-instance; prefer the live node when present.
			pass
		var landing: Vector3 = spec.get("position", Vector3.ZERO)
		var to_stair := landing - global_position
		to_stair.y = 0.0
		if to_stair.length() > 1.35:
			continue
		var dest_floor := int(spec.get("dest_floor", _current_floor))
		if dest_floor == _tracker.get_floor(self):
			continue
		# Honour locked stairwells still closed in the live scene.
		if not _stair_unlocked(spec):
			continue
		_tracker.set_floor(self, dest_floor)
		global_position = landing + Vector3(0.0, 0.05, 0.0)
		_current_node_id = ""
		_target_node_id = ""
		_ai_mode = AiMode.PATROL
		return


func _stair_unlocked(spec: Dictionary) -> bool:
	var required := int(spec.get("required_stage", 0))
	if required <= 0:
		return true
	var main := get_tree().get_first_node_in_group("main_level")
	if main != null and main.has_method("collected_key_stages"):
		var stages: Array = main.collected_key_stages()
		return stages.has(required)
	# Live stairwell nodes carry unlock state for the mounted floor.
	for node in get_tree().get_nodes_in_group("stairwell"):
		if node == null or not is_instance_valid(node):
			continue
		if not node.has_method("is_unlocked"):
			continue
		if int(node.get("required_stage")) != required:
			continue
		if int(node.get("from_floor")) != int(spec.get("floor", -1)):
			continue
		return bool(node.is_unlocked())
	return false


func _begin_despawn() -> void:
	if _despawn_armed:
		return
	_despawn_armed = true
	_player_in_touch = false
	if _tracker != null:
		_tracker.mark_dead(self)
	# Short beat so a death clip can start, then remove the corpse.
	var tree := get_tree()
	if tree != null:
		tree.create_timer(0.35).timeout.connect(_despawn_now)
	else:
		_despawn_now()


func _despawn_now() -> void:
	if is_instance_valid(self):
		queue_free()

func _reset_detection() -> void:
	_time_since_seen = 999.0
	_seeing_player = false
	_near_player = false
	_force_detect = false
	_provoked = false

func _patrol(delta: float) -> void:
	if _track_nodes.is_empty():
		velocity.x = 0.0
		velocity.z = 0.0
		_animate_walk(_walk_phase, 0.0)
		return

	if _target_node_id.is_empty() or not _track_nodes.has(_target_node_id):
		_choose_patrol_target()

	var to_target := _patrol_target - global_position
	to_target.y = 0.0
	if to_target.length() <= room_arrive_distance:
		_came_from_id = _current_node_id
		_current_node_id = _target_node_id
		_choose_patrol_target()
		if _target_node_id == _current_node_id:
			velocity.x = 0.0
			velocity.z = 0.0
			_animate_walk(_walk_phase, 0.0)
			return

	_move_toward(_patrol_target, delta)

func _choose_patrol_target() -> void:
	if _track_nodes.is_empty():
		_target_node_id = ""
		_patrol_target = global_position
		return
	if _current_node_id.is_empty() or not _track_nodes.has(_current_node_id):
		_current_node_id = _nearest_node_id(global_position)
	if _current_node_id.is_empty():
		_target_node_id = ""
		_patrol_target = global_position
		return

	var exits: Dictionary = _track_nodes[_current_node_id].get("exits", {})
	var next_id := ""
	if _is_intersection(_current_node_id, _came_from_id):
		for _i in 32:
			var roll := _rng.randi_range(0, 99)
			var preferred := direction_from_roll(roll)
			if exits.has(preferred):
				next_id = String(exits[preferred])
				break
		if next_id.is_empty():
			next_id = pick_next_node_with_roll(_current_node_id, _came_from_id, _rng.randi_range(0, 99))
	else:
		next_id = pick_next_node_with_roll(_current_node_id, _came_from_id, 0)

	if next_id.is_empty() or not _track_nodes.has(next_id):
		_target_node_id = _current_node_id
		_patrol_target = global_position
		return
	_target_node_id = next_id
	_patrol_target = _track_nodes[next_id]["position"]

func _is_intersection(node_id: String, came_from_id: String) -> bool:
	if not _track_nodes.has(node_id):
		return false
	var exits: Dictionary = _track_nodes[node_id].get("exits", {})
	var count := 0
	for dir in MapGenerator.TRACK_DIRS:
		if exits.has(dir):
			count += 1
	if count >= 3:
		return true
	return count >= 2 and came_from_id.is_empty()

func _begin_return_to_track() -> void:
	_ai_mode = AiMode.RETURN
	_return_node_id = _nearest_node_id(global_position)

func _return_to_track(delta: float) -> void:
	if _return_node_id.is_empty() or not _track_nodes.has(_return_node_id):
		_return_node_id = _nearest_node_id(global_position)
	if _return_node_id.is_empty():
		_ai_mode = AiMode.PATROL
		_choose_patrol_target()
		return
	var dest: Vector3 = _track_nodes[_return_node_id]["position"]
	var to_dest := dest - global_position
	to_dest.y = 0.0
	if to_dest.length() <= room_arrive_distance:
		_current_node_id = _return_node_id
		_came_from_id = ""
		_ai_mode = AiMode.PATROL
		_on_returned_to_track()
		return
	_move_toward_rejoin(dest, delta)

func _chase_along_track(dest: Vector3, delta: float) -> void:
	if _track_nodes.is_empty():
		_move_toward(dest, delta)
		return
	var goal_id := _nearest_node_id(dest)
	var start_id := _nearest_node_id(global_position)
	if goal_id.is_empty() or start_id.is_empty() or start_id == goal_id:
		_move_toward(dest, delta)
		return
	var path := _bfs_path(start_id, goal_id)
	var next_id := goal_id
	if path.size() >= 2:
		next_id = path[1]
	if not _track_nodes.has(next_id):
		_move_toward(dest, delta)
		return
	_current_node_id = start_id
	_target_node_id = next_id
	_move_toward(_track_nodes[next_id]["position"], delta)

func _move_toward_rejoin(target: Vector3, delta: float) -> void:
	var dx := target.x - global_position.x
	var dz := target.z - global_position.z
	if absf(dx) > room_arrive_distance and absf(dz) > room_arrive_distance:
		if absf(dx) >= absf(dz):
			_move_toward(Vector3(global_position.x, global_position.y, target.z), delta)
		else:
			_move_toward(Vector3(target.x, global_position.y, global_position.z), delta)
		return
	_move_toward(target, delta)


func _effective_move_speed() -> float:
	return move_speed


func _on_level_configured() -> void:
	pass


func _allows_chase() -> bool:
	return true


func _on_started_chase() -> void:
	pass


func _on_died() -> void:
	# Subclasses hook here (toad regurgitation, and similar). Base despawn is
	# armed from take_damage after this returns.
	pass


func _on_returned_to_track() -> void:
	_choose_patrol_target()


func _move_toward(target: Vector3, delta: float) -> void:
	var to_target := target - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	if distance > 0.45:
		var direction := to_target / distance
		var speed := _effective_move_speed()
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		# Mesh faces -Z at rest (Blender +Y); add PI so the creature looks toward travel.
		var target_yaw := atan2(direction.x, direction.z) + facing_yaw_offset
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

func debug_enter_chase() -> void:
	_ai_mode = AiMode.CHASE
	_time_since_seen = 0.0
	_last_seen_pos = global_position


func _update_stuck_recovery(delta: float) -> void:
	if _ai_mode == AiMode.CHASE and is_on_wall():
		_stuck_time += delta
		if _stuck_time >= 0.45:
			_current_node_id = _nearest_node_id(global_position)
			_stuck_time = 0.0
	else:
		_stuck_time = 0.0

func _player_is_hidden() -> bool:
	return (
		player != null
		and is_instance_valid(player)
		and player.has_method("is_hidden")
		and player.is_hidden()
	)


func _is_player_in_proximity() -> bool:
	if player == null:
		return false
	if _player_is_hidden():
		return false
	if player.has_method("is_alive") and not player.is_alive():
		return false
	if not _same_floor_as_player():
		return false
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	return to_player.length() <= proximity_radius

## True when this monster is chasing and can see the player enter a hide spot.
## Sight is the usual cone and ray, checked before the player is marked hidden.
func saw_player_enter_hiding() -> bool:
	if not _alive or _ai_mode != AiMode.CHASE:
		return false
	return _has_clear_sight()


## Walk to the spot, play hide_break when that clip exists, then smash it open.
func commit_hide_breach(spot: Node3D) -> void:
	if spot == null or not _alive:
		return
	_breach_spot = spot
	_breach_striking = false
	_breach_time_left = 0.0
	_ai_mode = AiMode.CHASE
	_time_since_seen = 0.0


func is_breaching_hide() -> bool:
	return _breach_spot != null and is_instance_valid(_breach_spot)


func _tick_hide_breach(delta: float) -> bool:
	if not is_instance_valid(_breach_spot) or not _breach_still_valid():
		_drop_breach()
		return false
	var dest := _breach_spot.global_position
	if _breach_spot.has_method("entry_global"):
		dest = _breach_spot.entry_global()
	if not _breach_striking:
		var to_dest := dest - global_position
		to_dest.y = 0.0
		if to_dest.length() > 0.8:
			_move_toward(dest, delta)
			return true
		if _breach_spot.has_method("begin_break") and not _breach_spot.begin_break():
			velocity = Vector3.ZERO
			return true
		_breach_striking = true
		velocity = Vector3.ZERO
		_face_point(dest)
		_play_hide_break()
		_breach_time_left = _hide_break_duration()
		return true
	velocity = Vector3.ZERO
	_face_point(dest)
	_animate_walk(_walk_phase, 0.0)
	_apply_breach_lunge()
	_breach_time_left -= delta
	if _breach_time_left > 0.0:
		return true
	_force_player_from_hide()
	_drop_breach()
	return false


func _breach_still_valid() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if not player.has_method("is_hidden") or not player.is_hidden():
		return false
	if player.has_method("hiding_spot"):
		return player.hiding_spot() == _breach_spot
	return true


func _force_player_from_hide() -> void:
	if player != null and player.has_method("eject_from_hiding"):
		player.eject_from_hiding(self, touch_damage)


func _drop_breach() -> void:
	var spot := _breach_spot
	_breach_spot = null
	_breach_striking = false
	_breach_time_left = 0.0
	if _breach_lunge and visual != null:
		visual.position = _visual_rest
	_breach_lunge = false
	if spot != null and is_instance_valid(spot) and spot.has_method("cancel_break"):
		spot.cancel_break()


func _play_hide_break() -> void:
	if _anim != null and _anim.has_animation("hide_break"):
		_breach_lunge = false
		_play_clip("hide_break", 1.0)
		return
	# No rigged smash. Lunge into the door while DoorBurst plays on the prop.
	_breach_lunge = true
	_visual_rest = visual.position if visual != null else Vector3.ZERO
	_play_clip(attack_clip, 1.0)


func _hide_break_duration() -> float:
	if _anim != null and _anim.has_animation("hide_break"):
		return maxf(_anim.get_animation("hide_break").length, 0.35)
	return 0.7


## Reach into the door, around the leaf's height, then shake. Used when the
## mesh has no hide_break clip (stalker, void).
func _apply_breach_lunge() -> void:
	if not _breach_lunge or visual == null or _breach_spot == null:
		return
	var duration := _hide_break_duration()
	var t := 1.0 - clampf(_breach_time_left / duration, 0.0, 1.0)
	var lunge := 0.0
	if t < 0.3:
		lunge = -0.1 * (t / 0.3)
	elif t < 0.55:
		lunge = lerpf(-0.1, 0.42, (t - 0.3) / 0.25)
	else:
		lunge = lerpf(0.42, 0.0, (t - 0.55) / 0.45)
	var into := Vector3.ZERO
	if _breach_spot.has_method("exit_forward"):
		into = -(_breach_spot.exit_forward())
	into.y = 0.0
	if into.length() < 0.01:
		into = Vector3(0.0, 0.0, -1.0)
	else:
		into = into.normalized()
	var shake := sin(t * TAU * 5.0) * 0.035 * sin(t * PI)
	# Door leaves sit around a metre up. A small lift keeps the shove off the floor.
	var lift := sin(clampf((t - 0.25) / 0.4, 0.0, 1.0) * PI) * 0.18
	var sideways := Vector3(-into.z, 0.0, into.x)
	visual.position = _visual_rest + into * lunge + sideways * shake + Vector3(0.0, lift, 0.0)


func _face_point(point: Vector3) -> void:
	if visual == null:
		return
	var dir := point - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		return
	visual.rotation.y = atan2(dir.x, dir.z) + facing_yaw_offset


func _can_see_player() -> bool:
	if _player_is_hidden():
		return false
	return _has_clear_sight()


func _has_clear_sight() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if player.has_method("is_alive") and not player.is_alive():
		return false
	if player.has_method("is_sneaking") and player.is_sneaking():
		return false
	if not _same_floor_as_player() or _off_floor:
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

	var world := get_world_3d()
	if world == null or world.direct_space_state == null:
		return true
	var space := world.direct_space_state
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

## Adopts a generated floorplan: rooms and the monster track from MapGenerator.
func configure_level(rooms: Array, bounds: AABB, track: Dictionary = {}) -> void:
	_level_rooms = rooms.duplicate(true)
	_level_bounds = bounds
	_track_nodes = track.get("nodes", {}).duplicate(true)
	if _track_nodes.is_empty():
		_track_nodes = _track_from_rooms(rooms)
	_ai_mode = AiMode.PATROL
	_reset_detection()
	_came_from_id = ""
	_current_node_id = _nearest_node_id(global_position)
	_choose_patrol_target()
	_on_level_configured()


func apply_monster_track(track: Dictionary) -> void:
	_track_nodes = track.get("nodes", {}).duplicate(true)
	if _current_node_id == "" or not _track_nodes.has(_current_node_id):
		_current_node_id = _nearest_node_id(global_position)
	if _target_node_id != "" and not _track_nodes.has(_target_node_id):
		_choose_patrol_target()


func copy_split_level_state(child: CharacterBody3D) -> void:
	if child.has_method("configure_level"):
		child.configure_level(_level_rooms, _level_bounds, {"nodes": _track_nodes})
	if _item_alerted and child.has_method("alert_item_stolen"):
		child.alert_item_stolen()
	child.set("player", player)


func get_growth_scale() -> float:
	if not grow_and_split or grow_duration <= 0.0:
		return 1.0
	var t := clampf(_grow_elapsed / grow_duration, 0.0, 1.0)
	return lerpf(1.0, grow_scale_target, t)


func reset_growth_cycle() -> void:
	_grow_elapsed = 0.0
	_split_started = false
	if grow_and_split:
		add_to_group("slime")
		if not _growth_bases_ready:
			_capture_growth_bases()
		_apply_growth(0.0)


func debug_set_growth_progress(t: float) -> void:
	if not grow_and_split:
		return
	if not _growth_bases_ready:
		_capture_growth_bases()
	var clamped := clampf(t, 0.0, 1.0)
	_grow_elapsed = clamped * maxf(grow_duration, 0.001)
	_apply_growth(clamped)


func debug_split_now() -> void:
	_try_split()


func _tick_growth(delta: float) -> void:
	if not grow_and_split or _split_started:
		return
	if grow_duration <= 0.0:
		return
	if not _growth_bases_ready:
		_capture_growth_bases()
	_grow_elapsed += delta
	var t := clampf(_grow_elapsed / grow_duration, 0.0, 1.0)
	_apply_growth(t)
	if t >= 1.0:
		_try_split()


func _capture_growth_bases() -> void:
	if grow_and_split:
		add_to_group("slime")
	if _growth_bases_ready:
		return
	_base_max_health = max_health
	_base_eye_height = eye_height
	_base_health_bar_height = health_bar_height
	_base_touch_radius = touch_radius
	_visual_base_scale = visual.scale if visual else Vector3.ONE
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null and col.shape is CapsuleShape3D:
		_capsule_node = col
		_capsule_shape = (col.shape as CapsuleShape3D).duplicate()
		col.shape = _capsule_shape
		_base_capsule_radius = _capsule_shape.radius
		_base_capsule_height = _capsule_shape.height
		_base_capsule_pos = col.position
	var touch := get_node_or_null("TouchArea")
	if touch:
		var shape_node := touch.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape_node != null and shape_node.shape is SphereShape3D:
			_touch_shape_node = shape_node
			_touch_sphere = (shape_node.shape as SphereShape3D).duplicate()
			shape_node.shape = _touch_sphere
			_base_touch_sphere_radius = _touch_sphere.radius
			_base_touch_pos = shape_node.position
	_growth_bases_ready = true


func _apply_growth(t: float) -> void:
	if not _growth_bases_ready:
		return
	var factor := lerpf(1.0, grow_scale_target, clampf(t, 0.0, 1.0))
	if visual:
		visual.scale = _visual_base_scale * factor
	if _capsule_shape != null and _capsule_node != null:
		_capsule_shape.radius = _base_capsule_radius * factor
		_capsule_shape.height = maxf(_base_capsule_height * factor, _capsule_shape.radius * 2.0)
		_capsule_node.position = _base_capsule_pos * factor
	if _touch_sphere != null and _touch_shape_node != null:
		_touch_sphere.radius = _base_touch_sphere_radius * factor
		_touch_shape_node.position = _base_touch_pos * factor
	touch_radius = _base_touch_radius * factor
	eye_height = _base_eye_height * factor
	if _health_bar:
		_health_bar.position = Vector3(0.0, _base_health_bar_height * factor, 0.0)
	var new_max := _base_max_health * factor
	var gained := new_max - max_health
	max_health = new_max
	health = clampf(health + gained, 0.0, max_health)
	if _health_bar:
		_health_bar.set_health(health, max_health)


func _try_split() -> void:
	if _split_started or not _alive:
		return
	var host := get_parent()
	if host != null and host.has_method("spawn_split_slimes"):
		if host.spawn_split_slimes(self):
			_split_started = true
			velocity = Vector3.ZERO
			queue_free()
			return
	reset_growth_cycle()

func _track_from_rooms(rooms: Array) -> Dictionary:
	var nodes := {}
	for room in rooms:
		var center: Vector3 = room.get("center", Vector3.ZERO)
		var cell: Vector2i = room.get("cell", Vector2i.ZERO)
		var id := MapGenerator.room_track_id(cell)
		nodes[id] = {
			"id": id,
			"kind": "room",
			"cell": cell,
			"position": Vector3(center.x, MapGenerator.TRACK_Y, center.z),
			"exits": {},
		}
	return nodes

func _nearest_node_id(pos: Vector3) -> String:
	var best_id := ""
	var best := INF
	for id in _track_nodes:
		var node_pos: Vector3 = _track_nodes[id]["position"]
		var d := Vector2(pos.x - node_pos.x, pos.z - node_pos.z).length()
		if d < best:
			best = d
			best_id = String(id)
	return best_id

func _bfs_path(start_id: String, goal_id: String) -> Array[String]:
	var result: Array[String] = []
	if start_id == goal_id:
		result.append(start_id)
		return result
	if not _track_nodes.has(start_id) or not _track_nodes.has(goal_id):
		return result
	var q: Array[String] = [start_id]
	var prev := {start_id: ""}
	var head := 0
	while head < q.size():
		var cur := q[head]
		head += 1
		var exits: Dictionary = _track_nodes[cur].get("exits", {})
		for dir in MapGenerator.TRACK_DIRS:
			if not exits.has(dir):
				continue
			var nxt := String(exits[dir])
			if prev.has(nxt):
				continue
			prev[nxt] = cur
			if nxt == goal_id:
				return _reconstruct_path(prev, start_id, goal_id)
			q.append(nxt)
	result.append(start_id)
	return result

func _reconstruct_path(prev: Dictionary, start_id: String, goal_id: String) -> Array[String]:
	var rev: Array[String] = []
	var walker := goal_id
	while walker != "":
		rev.append(walker)
		if walker == start_id:
			break
		walker = str(prev.get(walker, ""))
	rev.reverse()
	return rev

func _setup_animations() -> void:
	_anim = _find_animation_player(visual)
	if _anim == null:
		return
	# Rigged imports often ship a gait and no idle. Hold the gait's first
	# frame so a standing enemy does not keep looping its walk.
	if idle_clip != "" and not _anim.has_animation(idle_clip) and _anim.has_animation(walk_clip):
		_add_held_frame(idle_clip, walk_clip)
	for clip_name in [idle_clip, walk_clip]:
		if clip_name != "" and _anim.has_animation(clip_name):
			_anim.get_animation(clip_name).loop_mode = Animation.LOOP_LINEAR
	if not _anim.animation_finished.is_connected(_on_animation_finished):
		_anim.animation_finished.connect(_on_animation_finished)
	_play_clip(idle_clip, 1.0)


func _library_for(clip: String) -> AnimationLibrary:
	for lib_name in _anim.get_animation_library_list():
		var lib := _anim.get_animation_library(lib_name)
		if lib != null and lib.has_animation(clip):
			return lib
	return null


func _add_held_frame(dest: String, source: String) -> void:
	if _anim.has_animation(dest) or not _anim.has_animation(source):
		return
	var held := (_anim.get_animation(source).duplicate(true)) as Animation
	for track in held.get_track_count():
		var count := held.track_get_key_count(track)
		for index in range(count - 1, 0, -1):
			held.track_remove_key(track, index)
	held.length = 0.001
	held.loop_mode = Animation.LOOP_LINEAR
	var lib := _library_for(source)
	if lib != null:
		lib.add_animation(dest, held)


func _is_one_shot(clip: String) -> bool:
	return clip != "" and (
		clip == hit_clip or clip == attack_clip or clip == action_clip or clip == "hide_break"
	)


func _play_clip(clip: String, speed: float) -> void:
	if _anim == null or clip.is_empty() or not _anim.has_animation(clip):
		return
	if _anim_locked and clip != death_clip:
		return
	if _is_one_shot(clip):
		if _clip == clip:
			return
	elif _clip == clip:
		if is_equal_approx(_anim.speed_scale, speed):
			return
	_clip = clip
	_anim.play(clip, 0.12, speed)


func _on_animation_finished(anim_name: StringName) -> void:
	if String(anim_name) == death_clip:
		return
	_clip = ""
	var moving := Vector2(velocity.x, velocity.z).length() > 0.2
	_play_clip(walk_clip if moving else idle_clip, 1.0)


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


func get_animation_player() -> AnimationPlayer:
	return _anim


func _animate_walk(phase: float, amount: float) -> void:
	if _anim != null and not walk_clip.is_empty() and _anim.has_animation(walk_clip):
		if _anim_locked:
			return
		if amount > 0.15:
			var speed := 1.0
			if walk_cycle_metres > 0.0:
				var cycle_seconds := _anim.get_animation(walk_clip).length
				speed = clampf(move_speed * cycle_seconds / walk_cycle_metres, 0.4, 2.2)
			_play_clip(walk_clip, speed)
		elif not _is_one_shot(_clip):
			_play_clip(idle_clip, 1.0)
		return
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
