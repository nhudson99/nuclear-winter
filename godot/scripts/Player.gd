extends CharacterBody3D

signal died
signal item_collected
signal key_collected(stage: int)
signal valve_shut
signal stair_used(stair: Node)

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
@export var pistol_damage: float = 10.0
@export var pistol_speed: float = 28.0
## Already authored at 0.4 s. AK is 10 rounds/sec and the shotgun is one shot a second.
@export var pistol_cooldown: float = 0.4
@export var shotgun_pellet_damage: float = 10.0
@export var shotgun_pellets: int = 10
@export var shotgun_speed: float = 26.0
@export var shotgun_cooldown: float = 1.0
@export var ak_damage: float = 25.0
@export var ak_speed: float = 34.0
@export var ak_cooldown: float = 0.1
@export var melee_damage: float = 10.0
@export var melee_range: float = 1.8
@export var melee_cooldown: float = 0.45
@export var melee_dot: float = 0.25

@onready var visual: Node3D = $Model

const LOOPING_CLIPS := ["Idle", "Walk", "Run"]
const TOUCH_CONTROLS := preload("res://scripts/TouchControls.gd")
const BULLET_SCRIPT := preload("res://scripts/Bullet.gd")

var _anim: AnimationPlayer
var _clip: String = ""
var health: float = 100.0
var _health_bar: HealthBar3D
var _alive: bool = true
var _has_item: bool = false
var _input_locked: bool = false
var _flashlight: SpotLight3D
var _flashlight_fill: OmniLight3D
var _flashlight_on: bool = false
var _aim_override_enabled: bool = false
var _aim_override: Vector3 = Vector3.ZERO
var _fire_cooldown: float = 0.0
var _base_move_speed: float = 2.4
var _base_run_speed: float = 5.5
var _base_max_health: float = 100.0
## Frames after a floor change during which another stair cannot fire.
var _stair_grace: int = 0

func current_clip() -> String:
	return _clip


func _ready() -> void:
	add_to_group("player")
	_ensure_key_action("sprint", KEY_SHIFT)
	_ensure_key_action("sneak", KEY_CTRL)
	_ensure_key_action("reload", KEY_R)
	_ensure_key_action("slot_1", KEY_1)
	_ensure_key_action("slot_2", KEY_2)
	_ensure_key_action("slot_3", KEY_3)
	_ensure_mouse_action("flashlight", MOUSE_BUTTON_RIGHT)
	_ensure_mouse_action("fire", MOUSE_BUTTON_LEFT)
	_base_move_speed = move_speed
	_base_run_speed = run_speed
	_base_max_health = max_health
	if not GameProgress.upgrades_changed.is_connected(_apply_loadout):
		GameProgress.upgrades_changed.connect(_apply_loadout)
	_apply_loadout()
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
	_sync_weapon_visual()
	_health_bar = HealthBar3D.new()
	_health_bar.name = "HealthBar"
	_health_bar.fill_color = Color(0.25, 0.9, 0.4, 1.0)
	_health_bar.position = Vector3(0.0, health_bar_height, 0.0)
	add_child(_health_bar)
	_health_bar.set_health(health, max_health)

func _physics_process(delta: float) -> void:
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	_poll_weapon_input()
	if not _alive or _input_locked:
		set_flashlight_on(false)
		velocity = Vector3.ZERO
		_apply_gravity(delta)
		move_and_slide()
		if _alive:
			_play("Idle", 1.0)
		return

	# RMB or the right stick: light on and yaw lock onto the aim.
	# WASD / the left stick still strafes independently.
	var touch := _touch_controls()
	var stick_aim := _stick_is_aiming(touch)
	var aiming := stick_aim or Input.is_action_pressed("flashlight")
	set_flashlight_on(aiming)

	if Input.is_action_just_pressed("interact"):
		_try_interact()
	# Touch taps are also delivered as mouse clicks. On a phone that click is
	# not an attack; aiming the right stick at a monster is.
	if Input.is_action_just_pressed("fire") and not _click_fire_blocked(touch):
		attack()
	elif _mobile_auto_attack(touch):
		attack()

	var keyboard := Vector2.ZERO
	keyboard.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	keyboard.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	# Stick space is +x right, +y up. Keyboard +y is screen-down.
	var stick := Vector2(keyboard.x, -keyboard.y)
	var touch_running := false
	if touch != null and touch.has_method("move_stick_vector"):
		var touch_stick: Vector2 = touch.move_stick_vector()
		if touch_stick.length_squared() > stick.length_squared():
			stick = touch_stick
			touch_running = touch_stick.length() >= 0.85

	var direction := TOUCH_CONTROLS.stick_to_planar(stick)

	# Digital WASD is otherwise always full speed, which would skip Walk.
	# A full left-stick shove runs, since the touch HUD has no sprint key.
	var gait := run_speed if (Input.is_action_pressed("sprint") or touch_running) else move_speed
	gait *= WebField.player_speed_scale(self)
	velocity.x = direction.x * gait
	velocity.z = direction.z * gait
	_apply_gravity(delta)
	move_and_slide()
	_try_auto_stairs()

	var planar := Vector3(velocity.x, 0.0, velocity.z)
	var speed := planar.length()
	var aim_dir := Vector3.ZERO
	if stick_aim and touch.has_method("aim_planar"):
		aim_dir = touch.aim_planar()
	elif aiming:
		aim_dir = _aim_planar()
	if aim_dir.length() > 0.2:
		_face_planar(aim_dir, delta)
	elif speed > 0.15:
		# glTF forward is -Z, so the yaw that points the model down the travel
		# direction is half a turn from atan2 of the velocity.
		_face_planar(planar, delta)
	if speed > 0.15:
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

func is_input_locked() -> bool:
	return _input_locked

func lock_input() -> void:
	_input_locked = true
	velocity = Vector3.ZERO
	set_flashlight_on(false)

func unlock_input() -> void:
	_input_locked = false

## E / the on-screen USE button. Picks up a nearby objective or uses stairs.
func interact() -> void:
	if not _alive or _input_locked:
		return
	_try_interact()

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

func is_aiming() -> bool:
	return _flashlight_on

func has_pistol() -> bool:
	return GameProgress.has_pistol


func has_weapon() -> bool:
	_ensure_selection()
	return GameProgress.owns_weapon(GameProgress.selected_weapon)


## Desktop attack is LMB. A phone attacks by aiming the right stick at a monster.
## The selected gun fires; otherwise this is a melee swing.
func attack() -> Node3D:
	if has_weapon():
		return fire_weapon()
	return melee_attack()


func melee_attack() -> Node3D:
	if not _alive or _input_locked:
		return null
	if _fire_cooldown > 0.0:
		return null
	_fire_cooldown = melee_cooldown
	var direction := get_aim_direction()
	var hit: Node3D = null
	if not is_inside_tree():
		return self
	for node in get_tree().get_nodes_in_group("monster"):
		if not (node is CharacterBody3D):
			continue
		var body := node as CharacterBody3D
		if body.has_method("is_alive") and not body.is_alive():
			continue
		var to_enemy := body.global_position - global_position
		to_enemy.y = 0.0
		var distance := to_enemy.length()
		if distance > melee_range or distance < 0.01:
			continue
		if to_enemy.normalized().dot(direction) < melee_dot:
			continue
		if body.has_method("take_damage"):
			body.take_damage(melee_damage)
			if hit == null:
				hit = body
	return hit if hit else self

func is_sneaking() -> bool:
	if not GameProgress.has_sneak:
		return false
	if _flashlight_on:
		return false
	return Input.is_action_pressed("sneak")

func get_aim_direction() -> Vector3:
	var touch := _touch_controls()
	if _stick_is_aiming(touch) and touch.has_method("aim_planar"):
		var stick_dir: Vector3 = touch.aim_planar()
		if stick_dir.length_squared() > 0.01:
			return stick_dir
	if _aim_override_enabled:
		var to_point := _aim_override - global_position
		to_point.y = 0.0
		if to_point.length() > 0.05:
			return to_point.normalized()
	if _flashlight:
		var beam := -_flashlight.global_transform.basis.z
		beam.y = 0.0
		if beam.length() > 0.05:
			return beam.normalized()
	if visual:
		var facing := -visual.global_transform.basis.z
		facing.y = 0.0
		if facing.length() > 0.05:
			return facing.normalized()
	return Vector3(0.0, 0.0, -1.0)

## True when the flashlight is on, the point is inside the cone, and world geometry does not block it.
func illuminates_point(world_pos: Vector3) -> bool:
	if not _flashlight_on or _flashlight == null:
		return false
	var origin := _flashlight.global_position
	var to_target := world_pos - origin
	var distance := to_target.length()
	if distance > flashlight_range or distance < 0.05:
		return false
	var beam := -_flashlight.global_transform.basis.z
	beam.y = 0.0
	var planar := to_target
	planar.y = 0.0
	if beam.length() < 0.001 or planar.length() < 0.05:
		return false
	var angle := rad_to_deg(acos(clampf(beam.normalized().dot(planar / planar.length()), -1.0, 1.0)))
	if angle > flashlight_angle:
		return false
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, world_pos)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	return hit.is_empty()

func fire_weapon() -> Node3D:
	if not _alive or _input_locked:
		return null
	_ensure_selection()
	var weapon := GameProgress.selected_weapon
	if not GameProgress.owns_weapon(weapon):
		return null
	if _fire_cooldown > 0.0:
		return null
	if not GameProgress.consume_round(weapon):
		return null
	match weapon:
		GameProgress.WeaponId.PISTOL:
			_fire_cooldown = pistol_cooldown
			return _spawn_bullet(get_aim_direction(), pistol_damage, pistol_speed)
		GameProgress.WeaponId.SHOTGUN:
			_fire_cooldown = shotgun_cooldown
			return _fire_shotgun()
		GameProgress.WeaponId.AK:
			_fire_cooldown = ak_cooldown
			return _spawn_bullet(get_aim_direction(), ak_damage, ak_speed)
		GameProgress.WeaponId.NONE:
			return null
		_:
			return null


func _fire_shotgun() -> Node3D:
	var aim := get_aim_direction()
	var count := maxi(shotgun_pellets, 1)
	var first: Node3D = null
	for index in count:
		var direction := _pellet_direction(aim, index, count)
		var bullet := _spawn_bullet(direction, shotgun_pellet_damage, shotgun_speed)
		if first == null:
			first = bullet
	return first


## Even fan that stays inside the flashlight cone. The spot angle is the
## half-angle from the beam axis to the rim.
func _pellet_direction(aim: Vector3, index: int, count: int) -> Vector3:
	if count <= 1:
		return aim
	var t := float(index) / float(count - 1)
	var yaw := lerpf(-1.0, 1.0, t) * deg_to_rad(flashlight_angle) * 0.85
	return aim.rotated(Vector3.UP, yaw).normalized()


func _spawn_bullet(direction: Vector3, damage: float, speed: float) -> Node3D:
	var bullet: Node3D = BULLET_SCRIPT.new()
	bullet.name = "Bullet"
	bullet.damage = damage
	# Chest height, not the raised flashlight. The sweep in Bullet still covers
	# shorter bodies the muzzle would otherwise sail over.
	var origin := global_position + Vector3(0.0, 0.85, 0.0) + direction * 0.7
	var host := get_parent()
	if host == null:
		host = self
	host.add_child(bullet)
	bullet.global_position = origin
	bullet.velocity = direction * speed
	return bullet

func movement_speed_scale() -> float:
	return WebField.player_speed_scale(self)


func _apply_loadout() -> void:
	var multiplier := GameProgress.speed_multiplier()
	move_speed = _base_move_speed * multiplier
	run_speed = _base_run_speed * multiplier
	var new_max := float(GameProgress.max_health())
	if _base_max_health > 0.0:
		new_max = _base_max_health + float(GameProgress.health_bonus())
	var was_full := health >= max_health - 0.01
	max_health = new_max
	if was_full:
		health = max_health
	else:
		health = minf(health, max_health)
	if _health_bar:
		_health_bar.set_health(health, max_health)
	_ensure_selection()
	_sync_weapon_visual()


func _ensure_selection() -> void:
	if GameProgress.owns_weapon(GameProgress.selected_weapon):
		return
	var owned := GameProgress.owned_weapons()
	var next: GameProgress.WeaponId = owned[0] if not owned.is_empty() else GameProgress.WeaponId.NONE
	if GameProgress.selected_weapon == next:
		return
	GameProgress.selected_weapon = next


func _sync_weapon_visual() -> void:
	var host: Node3D = visual if visual else self
	if host == null:
		return
	_ensure_weapon_mesh(host, "PistolMesh", Vector3(0.07, 0.12, 0.28), Vector3(0.22, 1.05, -0.18), Color(0.12, 0.12, 0.12))
	_ensure_weapon_mesh(host, "ShotgunMesh", Vector3(0.09, 0.1, 0.62), Vector3(0.24, 1.02, -0.28), Color(0.28, 0.18, 0.1))
	_ensure_weapon_mesh(host, "AkMesh", Vector3(0.08, 0.1, 0.72), Vector3(0.26, 1.04, -0.32), Color(0.16, 0.18, 0.12))
	var show_name := ""
	match GameProgress.selected_weapon:
		GameProgress.WeaponId.PISTOL:
			show_name = "PistolMesh"
		GameProgress.WeaponId.SHOTGUN:
			show_name = "ShotgunMesh"
		GameProgress.WeaponId.AK:
			show_name = "AkMesh"
		GameProgress.WeaponId.NONE:
			show_name = ""
		_:
			show_name = ""
	for mesh_name in ["PistolMesh", "ShotgunMesh", "AkMesh"]:
		var mesh := host.get_node_or_null(mesh_name) as Node3D
		if mesh:
			mesh.visible = mesh_name == show_name and GameProgress.owns_weapon(GameProgress.selected_weapon)


func _ensure_weapon_mesh(host: Node3D, mesh_name: String, size: Vector3, at: Vector3, color: Color) -> void:
	if host.get_node_or_null(mesh_name) != null:
		return
	var mesh := MeshInstance3D.new()
	mesh.name = mesh_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	mesh.rotation_degrees = Vector3(8.0, 0.0, 8.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.65
	mat.roughness = 0.38
	mesh.material_override = mat
	mesh.visible = false
	host.add_child(mesh)


func _poll_weapon_input() -> void:
	if not _alive or _input_locked:
		return
	if Input.is_action_just_pressed("slot_1"):
		GameProgress.select_weapon(GameProgress.WeaponId.PISTOL)
	elif Input.is_action_just_pressed("slot_2"):
		GameProgress.select_weapon(GameProgress.WeaponId.SHOTGUN)
	elif Input.is_action_just_pressed("slot_3"):
		GameProgress.select_weapon(GameProgress.WeaponId.AK)
	if Input.is_action_just_pressed("reload"):
		GameProgress.reload_weapon(GameProgress.selected_weapon)


func _unhandled_input(event: InputEvent) -> void:
	if not _alive or _input_locked:
		return
	if event is InputEventMouseButton and event.pressed:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			GameProgress.cycle_weapon(-1)
			get_viewport().set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			GameProgress.cycle_weapon(1)
			get_viewport().set_input_as_handled()

## Tests and screenshot tools can pin the aim point without a real cursor.
func set_aim_world_override(point: Vector3) -> void:
	_aim_override_enabled = true
	_aim_override = point

func clear_aim_world_override() -> void:
	_aim_override_enabled = false

func _try_interact() -> void:
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
	if best != null and best.has_method("try_pickup"):
		if not best.try_pickup():
			return
		if best.has_method("is_key") and best.is_key():
			var stage := int(best.get("key_stage"))
			key_collected.emit(stage)
			return
		_has_item = true
		item_collected.emit()
		return

	var valve := _nearest_steam_valve()
	if valve != null and valve.has_method("try_shut") and valve.try_shut():
		valve_shut.emit()
		return

	_use_stair(_nearest_stairwell())


func _nearest_steam_valve() -> Node:
	var best: Node = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("steam_valve"):
		if node == null or not is_instance_valid(node):
			continue
		if not node.has_method("can_interact") or not node.can_interact(global_position):
			continue
		var dist := interact_range
		if node.has_method("interact_distance"):
			dist = float(node.interact_distance(global_position))
		elif node is Node3D:
			var to_valve: Vector3 = (node as Node3D).global_position - global_position
			to_valve.y = 0.0
			dist = to_valve.length()
		if dist < best_dist:
			best_dist = dist
			best = node
	return best


func _nearest_stairwell() -> Node:
	var best: Node = null
	var best_dist := interact_range
	for node in get_tree().get_nodes_in_group("stairwell"):
		if node == null or not is_instance_valid(node):
			continue
		if not node.has_method("can_interact") or not node.can_interact(global_position):
			continue
		var to_stair: Vector3 = (node as Node3D).global_position - global_position
		to_stair.y = 0.0
		var dist := to_stair.length()
		if dist <= best_dist:
			best_dist = dist
			best = node
	return best

func _try_auto_stairs() -> void:
	if _stair_grace > 0:
		_stair_grace -= 1
		return
	if not is_on_floor():
		return
	for node in get_tree().get_nodes_in_group("stairwell"):
		if node == null or not is_instance_valid(node):
			continue
		if not node.has_method("feet_on_flight") or not node.feet_on_flight(global_position):
			continue
		_use_stair(node)
		return


func _use_stair(stair: Node) -> void:
	if stair == null or not stair.has_method("try_use"):
		return
	if stair.has_method("can_use") and not stair.can_use():
		return
	if not stair.try_use():
		return
	_stair_grace = 90
	stair_used.emit(stair)


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

func _face_planar(dir: Vector3, delta: float) -> void:
	var target_yaw := atan2(dir.x, dir.z) + PI
	visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))

func _touch_controls() -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("TouchControls")

func _stick_is_aiming(touch: Node) -> bool:
	return touch != null and touch.has_method("is_aiming") and bool(touch.is_aiming())


func _click_fire_blocked(touch: Node) -> bool:
	if touch == null:
		return false
	if touch.has_method("uses_mobile_combat") and bool(touch.uses_mobile_combat()):
		return true
	if touch.has_method("blocks_click_fire") and bool(touch.blocks_click_fire()):
		return true
	return false


func _mobile_auto_attack(touch: Node) -> bool:
	if not _stick_is_aiming(touch):
		return false
	if touch == null or not touch.has_method("uses_mobile_combat"):
		return false
	if not bool(touch.uses_mobile_combat()):
		return false
	return _monster_in_sights()


## True when the aim ray crosses a living monster. Guns use a narrow body
## radius out to the flashlight; melee uses the swing cone.
func _monster_in_sights() -> bool:
	if not is_inside_tree():
		return false
	var direction := get_aim_direction()
	if direction.length_squared() < 0.01:
		return false
	var armed := has_weapon()
	for node in get_tree().get_nodes_in_group("monster"):
		if not (node is CharacterBody3D):
			continue
		var body := node as CharacterBody3D
		if body.has_method("is_alive") and not body.is_alive():
			continue
		var to_enemy := body.global_position - global_position
		to_enemy.y = 0.0
		var distance := to_enemy.length()
		if distance < 0.05:
			continue
		if armed:
			var along := to_enemy.dot(direction)
			if along < 0.35 or along > flashlight_range:
				continue
			if (to_enemy - direction * along).length() > 0.5:
				continue
			if not _shot_lane_clear(body.global_position, along):
				continue
			return true
		if distance > melee_range:
			continue
		if to_enemy.normalized().dot(direction) < melee_dot:
			continue
		return true
	return false


func _shot_lane_clear(target: Vector3, reach: float) -> bool:
	var world := get_world_3d()
	if world == null:
		return true
	var space := world.direct_space_state
	for height in Bullet.SWEEP_HEIGHTS:
		var origin := Vector3(global_position.x, height, global_position.z)
		var end := Vector3(target.x, height, target.z)
		var query := PhysicsRayQueryParameters3D.create(origin, end)
		query.collision_mask = 1
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return true
		var point: Vector3 = hit.get("position", end)
		if origin.distance_to(point) > reach - 0.35:
			return true
	return false

func _aim_planar() -> Vector3:
	var point := _aim_world_point()
	var to_point := point - global_position
	to_point.y = 0.0
	return to_point

func _aim_world_point() -> Vector3:
	if _aim_override_enabled:
		return _aim_override
	var camera := get_viewport().get_camera_3d() if get_viewport() else null
	if camera == null:
		return global_position
	var screen := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(screen)
	var ray := camera.project_ray_normal(screen)
	if absf(ray.y) < 0.0001:
		return global_position
	var distance := (global_position.y - origin.y) / ray.y
	if distance < 0.0:
		return global_position
	return origin + ray * distance

func _ensure_key_action(action: String, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	_ensure_action_event(action, event)

func _ensure_mouse_action(action: String, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	_ensure_action_event(action, event)

func _ensure_action_event(action: String, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey and event is InputEventKey:
			if (existing as InputEventKey).physical_keycode == (event as InputEventKey).physical_keycode:
				return
		elif existing is InputEventMouseButton and event is InputEventMouseButton:
			if (existing as InputEventMouseButton).button_index == (event as InputEventMouseButton).button_index:
				return
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
	set_flashlight_on(false)

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
