extends "res://scripts/Monster.gd"

## Mid-tier void entity. Fires a void laser; a hit pulls the player into the
## void dimension instead of dealing normal contact damage.

@export var laser_range: float = 11.0
@export var laser_cooldown: float = 3.2
@export var laser_charge: float = 0.45
@export var laser_damage_fallback: float = 12.0

var _laser_cooldown_left: float = 1.5
var _laser_charging: bool = false
var _laser_charge_left: float = 0.0
var _beam: MeshInstance3D
var _beam_light: OmniLight3D


func _ready() -> void:
	super._ready()
	add_to_group("void_monster")
	attack_interval = 0.5
	_ensure_beam()


func _on_level_configured() -> void:
	super._on_level_configured()
	_laser_cooldown_left = 1.2


func _physics_process(delta: float) -> void:
	if not _alive:
		super._physics_process(delta)
		return
	if _off_floor or _void_suppressed():
		_hide_beam()
		super._physics_process(delta)
		return

	_laser_cooldown_left = maxf(0.0, _laser_cooldown_left - delta)
	if _laser_charging:
		_laser_charge_left -= delta
		_aim_beam_at_player()
		if _laser_charge_left <= 0.0:
			_fire_laser()
			_laser_charging = false
			_laser_cooldown_left = laser_cooldown
		_apply_gravity(delta)
		move_and_slide()
		return

	if (
		_allows_chase()
		and _same_floor_as_player()
		and _laser_cooldown_left <= 0.0
		and _player_in_laser_range()
		and _can_see_player()
	):
		_laser_charging = true
		_laser_charge_left = laser_charge
		velocity.x = 0.0
		velocity.z = 0.0
		_show_beam()
		_aim_beam_at_player()
		_play_clip(attack_clip, 1.0)
		_apply_gravity(delta)
		move_and_slide()
		return

	_hide_beam()
	super._physics_process(delta)


func _allows_attack() -> bool:
	# Contact swings are secondary; the laser is the main threat.
	return true


func _player_in_laser_range() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	return to_player.length() <= laser_range


func _fire_laser() -> void:
	_aim_beam_at_player()
	if player == null or not is_instance_valid(player):
		_hide_beam()
		return
	if not _player_in_laser_range() or not _can_see_player():
		_hide_beam()
		return
	var main := get_tree().get_first_node_in_group("main_level")
	if main != null and main.has_method("enter_void_dimension"):
		main.enter_void_dimension(player.global_position)
	elif player.has_method("take_damage"):
		player.take_damage(laser_damage_fallback)
	_hide_beam()


func _void_suppressed() -> bool:
	var main := get_tree().get_first_node_in_group("main_level")
	if main != null and main.has_method("is_in_void") and main.is_in_void():
		return true
	return false


func _ensure_beam() -> void:
	if _beam != null:
		return
	_beam = MeshInstance3D.new()
	_beam.name = "VoidLaser"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.06
	cylinder.bottom_radius = 0.06
	cylinder.height = 1.0
	_beam.mesh = cylinder
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.1, 0.85, 0.75)
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.15, 1.0)
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam.material_override = mat
	_beam.visible = false
	add_child(_beam)

	_beam_light = OmniLight3D.new()
	_beam_light.name = "VoidLaserLight"
	_beam_light.light_color = Color(0.55, 0.2, 1.0)
	_beam_light.light_energy = 3.5
	_beam_light.omni_range = 4.0
	_beam_light.visible = false
	add_child(_beam_light)


func _show_beam() -> void:
	if _beam:
		_beam.visible = true
	if _beam_light:
		_beam_light.visible = true


func _hide_beam() -> void:
	if _beam:
		_beam.visible = false
	if _beam_light:
		_beam_light.visible = false


func _aim_beam_at_player() -> void:
	if _beam == null or player == null or not is_instance_valid(player):
		return
	var origin := global_position + Vector3(0.0, 1.35, 0.0)
	var target := player.global_position + Vector3(0.0, 1.1, 0.0)
	var delta := target - origin
	var length := delta.length()
	if length < 0.05:
		return
	_beam.global_position = origin + delta * 0.5
	_beam.look_at(target, Vector3.UP)
	_beam.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	if _beam.mesh is CylinderMesh:
		(_beam.mesh as CylinderMesh).height = length
	if _beam_light:
		_beam_light.global_position = origin + delta * 0.35
