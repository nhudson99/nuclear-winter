extends Node3D
class_name Bullet

## Planar shot along the aim. A swept ray hits monsters and walls, so a fast
## frame cannot skip a body, and short enemies still count when the muzzle is
## above their capsule.

const WORLD_MASK := 1
const MONSTER_MASK := 4
const SWEEP_HEIGHTS: Array[float] = [0.4, 0.85, 1.3]
## Side rays, so a shot aimed at a body still connects if the stick is a little off.
const SWEEP_LATERAL := 0.28

var velocity: Vector3 = Vector3.ZERO
var damage: float = 10.0
var lifetime: float = 1.25
var _age: float = 0.0


func _ready() -> void:
	_ensure_visual()


func _physics_process(delta: float) -> void:
	var from := global_position
	var to := from + velocity * delta
	var hit := _closest_hit(from, to)
	if not hit.is_empty():
		global_position = hit.get("position", to)
		_damage_if_monster(hit.get("collider"))
		queue_free()
		return
	global_position = to
	_age += delta
	if _age >= lifetime:
		queue_free()


func _closest_hit(from: Vector3, to: Vector3) -> Dictionary:
	var world := get_world_3d()
	if world == null:
		return {}
	var space := world.direct_space_state
	var best: Dictionary = {}
	var best_dist := INF
	var motion := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var side := Vector3.ZERO
	if motion.length() > 0.001:
		side = Vector3(-motion.z, 0.0, motion.x).normalized() * SWEEP_LATERAL
	var offsets: Array[Vector3] = [Vector3.ZERO, side, -side]
	for height in SWEEP_HEIGHTS:
		for offset in offsets:
			var hit := _ray_hit(space, Vector3(from.x, height, from.z) + offset, Vector3(to.x, height, to.z) + offset)
			if hit.is_empty():
				continue
			var origin := Vector3(from.x, height, from.z) + offset
			var point: Vector3 = hit.get("position", origin)
			var dist := origin.distance_to(point)
			if dist < 0.08 and not _is_monster(hit.get("collider")):
				continue
			if dist < best_dist:
				best_dist = dist
				best = hit
	return best


func _ray_hit(space: PhysicsDirectSpaceState3D, origin: Vector3, target: Vector3) -> Dictionary:
	if origin.distance_squared_to(target) < 0.000001:
		return {}
	var query := PhysicsRayQueryParameters3D.create(origin, target)
	query.collision_mask = WORLD_MASK | MONSTER_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_from_inside = true
	return space.intersect_ray(query)


func _is_monster(collider: Variant) -> bool:
	return collider is Node and (collider as Node).is_in_group("monster")


func _damage_if_monster(collider: Variant) -> void:
	if not _is_monster(collider):
		return
	var body := collider as Node
	if not body.has_method("take_damage"):
		return
	if body.has_method("is_alive") and not body.is_alive():
		return
	body.take_damage(damage)


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
