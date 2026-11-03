class_name VoidGate
extends Area3D

## Exit from the void dimension. Green beacon so it reads as an objective light
## in otherwise pitch-black space.

signal gate_reached(body: Node3D)

@export var interact_range: float = 2.8

var _glow: OmniLight3D
var _mesh: MeshInstance3D


func _ready() -> void:
	add_to_group("void_gate")
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	monitorable = false
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_ensure_visual()


func _ensure_visual() -> void:
	if _glow != null:
		return
	_glow = OmniLight3D.new()
	_glow.name = "GateGlow"
	_glow.light_color = Color(0.25, 1.0, 0.4)
	_glow.light_energy = 6.0
	_glow.omni_range = 8.0
	_glow.position = Vector3(0.0, 1.4, 0.0)
	add_child(_glow)

	_mesh = MeshInstance3D.new()
	_mesh.name = "GateMesh"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.85
	_mesh.mesh = torus
	_mesh.position = Vector3(0.0, 1.2, 0.0)
	_mesh.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.9, 0.35, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 1.0, 0.4)
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh.material_override = mat
	add_child(_mesh)

	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var sphere := SphereShape3D.new()
	sphere.radius = 1.1
	shape.shape = sphere
	shape.position = Vector3(0.0, 1.0, 0.0)
	add_child(shape)


func _on_body_entered(body: Node3D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	gate_reached.emit(body)
