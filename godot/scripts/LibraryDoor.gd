class_name LibraryDoor
extends Node3D

## Unused metal double-door path. The library wing gate is a LockedDoor opened
## by the bookcase lever; this class stays for the mesh asset only.

signal opened(door: LibraryDoor)

const WORLD_LAYER := 1
const DOOR_SCENE := "res://assets/props/MetalDoubleDoor.glb"

var from_cell: Vector2i = Vector2i.ZERO
var to_cell: Vector2i = Vector2i.ZERO
var side: String = "E"

var _open: bool = false
var _body: StaticBody3D
var _visual: Node3D


func _ready() -> void:
	add_to_group("library_door")
	if _body == null:
		_build()


func configure(p_from: Vector2i, p_to: Vector2i, p_side: String, size: Vector3) -> void:
	from_cell = p_from
	to_cell = p_to
	side = p_side
	if _body == null:
		_build()
	_fit_size(size)


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	if _body:
		_body.collision_layer = 0
		_body.collision_mask = 0
	if _visual:
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(_visual, "rotation_degrees:y", _visual.rotation_degrees.y + 95.0, 0.85)
		tween.tween_property(_visual, "position:x", _visual.position.x + 0.55, 0.85)
	opened.emit(self)


func _build() -> void:
	_visual = Node3D.new()
	_visual.name = "DoorVisual"
	add_child(_visual)
	if ResourceLoader.exists(DOOR_SCENE):
		var mesh: Node3D = (load(DOOR_SCENE) as PackedScene).instantiate()
		mesh.name = "MetalDoor"
		# Mesh is ~2 m tall centered on origin; lift so the sill sits on the floor.
		mesh.position = Vector3(0.0, 1.0, 0.0)
		_visual.add_child(mesh)
	else:
		var fallback := MeshInstance3D.new()
		fallback.name = "DoorMesh"
		var box := BoxMesh.new()
		box.size = Vector3(0.28, 2.3, 3.2)
		fallback.mesh = box
		fallback.position = Vector3(0.0, 1.15, 0.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.22, 0.24, 0.28)
		mat.metallic = 0.7
		mat.roughness = 0.4
		fallback.material_override = mat
		_visual.add_child(fallback)

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


func _fit_size(size: Vector3) -> void:
	if _body:
		var col := _body.get_node_or_null("Col_Door") as CollisionShape3D
		if col and col.shape is BoxShape3D:
			(col.shape as BoxShape3D).size = size
			col.position.y = size.y * 0.5
	if side == "N" or side == "S":
		rotation_degrees.y = 0.0
	else:
		rotation_degrees.y = 90.0
