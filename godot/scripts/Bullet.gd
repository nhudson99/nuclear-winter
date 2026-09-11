extends Area3D
class_name Bullet

## Hitscan-adjacent projectile fired along the flashlight aim. 10 damage on monster hit.

const WORLD_MASK := 1
const MONSTER_MASK := 4

var velocity: Vector3 = Vector3.ZERO
var damage: float = 10.0
var lifetime: float = 1.25
var _age: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = WORLD_MASK | MONSTER_MASK
	monitoring = true
	monitorable = false
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_ensure_shape()
	_ensure_visual()


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	_age += delta
	if _age >= lifetime:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if body == null:
		return
	if body.is_in_group("player"):
		return
	if body.is_in_group("monster") and body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()


func _ensure_shape() -> void:
	if get_node_or_null("CollisionShape3D") != null:
		return
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var sphere := SphereShape3D.new()
	sphere.radius = 0.12
	col.shape = sphere
	add_child(col)


func _ensure_visual() -> void:
	if get_node_or_null("Mesh") != null:
		return
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var sphere := SphereMesh.new()
	sphere.radius = 0.08
	sphere.height = 0.16
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.92, 0.45, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.3, 1.0)
	mat.emission_energy_multiplier = 4.0
	mesh.material_override = mat
	add_child(mesh)
