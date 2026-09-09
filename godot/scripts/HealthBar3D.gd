extends Node3D
class_name HealthBar3D

## Billboard HP bar that floats above a character.

@export var bar_width: float = 1.05
@export var bar_height: float = 0.12
@export var fill_color: Color = Color(0.2, 0.85, 0.35, 1.0)
@export var background_color: Color = Color(0.08, 0.08, 0.1, 0.85)
@export var border_color: Color = Color(0.02, 0.02, 0.03, 0.95)

var _bg: MeshInstance3D
var _fill: MeshInstance3D
var _border: MeshInstance3D
var _max_health: float = 100.0
var _current_health: float = 100.0

func _ready() -> void:
	_border = _make_quad("Border", border_color, Vector3(0.0, 0.0, -0.002))
	_border.scale = Vector3(bar_width + 0.06, bar_height + 0.04, 1.0)
	_bg = _make_quad("Background", background_color, Vector3(0.0, 0.0, -0.001))
	_bg.scale = Vector3(bar_width, bar_height, 1.0)
	_fill = _make_quad("Fill", fill_color, Vector3.ZERO)
	_update_fill()

func set_health(current: float, maximum: float = -1.0) -> void:
	if maximum > 0.0:
		_max_health = maximum
	_current_health = clampf(current, 0.0, _max_health)
	_update_fill()

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Face the camera while staying upright for the ortho iso view.
	var to_cam := cam.global_position - global_position
	to_cam.y = 0.0
	if to_cam.length_squared() < 0.0001:
		return
	look_at(global_position + to_cam.normalized(), Vector3.UP)
	rotate_object_local(Vector3.UP, PI)

func _update_fill() -> void:
	if _fill == null:
		return
	var ratio := 0.0 if _max_health <= 0.0 else clampf(_current_health / _max_health, 0.0, 1.0)
	_fill.scale = Vector3(bar_width * ratio, bar_height, 1.0)
	_fill.position.x = -0.5 * bar_width * (1.0 - ratio)
	_fill.visible = ratio > 0.001

func _make_quad(node_name: String, color: Color, local_pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 10
	mi.material_override = mat
	mi.position = local_pos
	add_child(mi)
	return mi
