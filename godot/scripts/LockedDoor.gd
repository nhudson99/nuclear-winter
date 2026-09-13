class_name LockedDoor
extends Node3D

## Physical barrier in a carved doorway. Collecting the matching key calls
## `unlock()`, which drops collision so the player and monsters can pass.

signal unlocked(door: LockedDoor)

const WORLD_LAYER := 1

@export var stage: int = 1

var from_cell: Vector2i = Vector2i.ZERO
var to_cell: Vector2i = Vector2i.ZERO
var side: String = "E"

var _locked: bool = true
var _body: StaticBody3D
var _mesh: MeshInstance3D
var _lock_light: OmniLight3D


func _ready() -> void:
	add_to_group("locked_door")
	if _body == null:
		_build_visual()


func configure(p_stage: int, p_from: Vector2i, p_to: Vector2i, p_side: String, size: Vector3) -> void:
	stage = p_stage
	from_cell = p_from
	to_cell = p_to
	side = p_side
	if _body == null:
		_build_visual()
	_apply_size(size)


func is_locked() -> bool:
	return _locked


func unlock() -> void:
	if not _locked:
		return
	_locked = false
	if _body:
		_body.collision_layer = 0
		_body.collision_mask = 0
	if _mesh:
		_mesh.visible = false
	if _lock_light:
		_lock_light.visible = false
	visible = false
	unlocked.emit(self)


func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "DoorMesh"
	var box := BoxMesh.new()
	box.size = Vector3(0.35, 2.3, 3.4)
	_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.38, 0.16, 0.10)
	mat.metallic = 0.35
	mat.roughness = 0.55
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.12, 0.08)
	mat.emission_energy_multiplier = 0.7
	_mesh.material_override = mat
	_mesh.position = Vector3(0.0, 1.15, 0.0)
	add_child(_mesh)

	_body = StaticBody3D.new()
	_body.name = "DoorCollision"
	_body.collision_layer = WORLD_LAYER
	_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.name = "Col_Door"
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(0.35, 2.3, 3.4)
	shape.shape = box_shape
	shape.position = Vector3(0.0, 1.15, 0.0)
	_body.add_child(shape)
	add_child(_body)

	_lock_light = OmniLight3D.new()
	_lock_light.name = "LockLight"
	_lock_light.light_color = Color(0.95, 0.35, 0.15)
	_lock_light.light_energy = 2.4
	_lock_light.omni_range = 3.6
	_lock_light.position = Vector3(0.0, 1.4, 0.0)
	add_child(_lock_light)


func _apply_size(size: Vector3) -> void:
	if _mesh and _mesh.mesh is BoxMesh:
		(_mesh.mesh as BoxMesh).size = size
		_mesh.position.y = size.y * 0.5
	if _body:
		var col := _body.get_node_or_null("Col_Door") as CollisionShape3D
		if col and col.shape is BoxShape3D:
			(col.shape as BoxShape3D).size = size
			col.position.y = size.y * 0.5
	if _lock_light:
		_lock_light.position.y = size.y * 0.6
