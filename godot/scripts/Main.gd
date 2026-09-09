extends Node3D

@onready var camera: Camera3D = $IsoCamera
@onready var player: CharacterBody3D = $Player
@onready var map_root: Node3D = $MansionMap

@export var camera_distance: float = 22.0
@export var camera_height: float = 22.0
@export var follow_lerp: float = 10.0

func _ready() -> void:
	_ensure_collision(map_root)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20.0
	camera.near = 0.05
	camera.far = 250.0
	camera.current = true
	_snap_camera()

func _physics_process(delta: float) -> void:
	# High isometric look similar to the Blender reference render.
	var target := player.global_position + Vector3(camera_distance * 0.55, camera_height, camera_distance)
	camera.global_position = camera.global_position.lerp(target, clampf(follow_lerp * delta, 0.0, 1.0))
	camera.look_at(player.global_position + Vector3(0.0, 0.6, 0.0), Vector3.UP)

func _snap_camera() -> void:
	camera.global_position = player.global_position + Vector3(camera_distance * 0.55, camera_height, camera_distance)
	camera.look_at(player.global_position + Vector3(0.0, 0.6, 0.0), Vector3.UP)

func _ensure_collision(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		# Open door leaves are visual only so the doorway stays walkable.
		if not _is_door_leaf(mi) and not _has_static_body(mi) and mi.mesh != null:
			mi.create_trimesh_collision()
	for child in node.get_children():
		_ensure_collision(child)

func _has_static_body(mi: MeshInstance3D) -> bool:
	for child in mi.get_children():
		if child is StaticBody3D:
			return true
	return false

func _is_door_leaf(mi: MeshInstance3D) -> bool:
	return String(mi.name).ends_with("_Leaf")
