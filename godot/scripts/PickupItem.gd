extends Area3D

## Interactable objective. Player presses interact (E) while nearby to collect it.

signal picked_up(item: Node3D)

@export var interact_range: float = 2.2
@export var bob_height: float = 0.12
@export var bob_speed: float = 2.4

var _taken: bool = false
var _visual: Node3D
var _base_y: float = 0.55

func _ready() -> void:
	add_to_group("pickup")
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false
	_ensure_visual()
	_base_y = _visual.position.y if _visual else 0.55

func _process(delta: float) -> void:
	if _taken or _visual == null:
		return
	_visual.position.y = _base_y + bob_height * sin(Time.get_ticks_msec() * 0.001 * bob_speed * TAU)
	_visual.rotation.y += delta * 1.4

func can_interact(from_pos: Vector3) -> bool:
	if _taken:
		return false
	var to_item := global_position - from_pos
	to_item.y = 0.0
	return to_item.length() <= interact_range

func try_pickup() -> bool:
	if _taken:
		return false
	_taken = true
	set_process(false)
	visible = false
	picked_up.emit(self)
	queue_free()
	return true

func is_taken() -> bool:
	return _taken

func _ensure_visual() -> void:
	_visual = get_node_or_null("Visual") as Node3D
	if _visual != null:
		return

	_visual = Node3D.new()
	_visual.name = "Visual"
	_visual.position = Vector3(0.0, 0.55, 0.0)
	add_child(_visual)

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = Vector3(0.45, 0.45, 0.45)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.78, 0.22, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.85, 0.55, 0.08, 1.0)
	mat.emission_energy_multiplier = 1.4
	mesh.material_override = mat
	_visual.add_child(mesh)

	var marker := MeshInstance3D.new()
	marker.name = "Marker"
	var prism := PrismMesh.new()
	prism.size = Vector3(0.28, 0.35, 0.28)
	marker.mesh = prism
	marker.position = Vector3(0.0, 0.55, 0.0)
	var marker_mat := StandardMaterial3D.new()
	marker_mat.albedo_color = Color(0.2, 0.85, 0.95, 1.0)
	marker_mat.emission_enabled = true
	marker_mat.emission = Color(0.15, 0.7, 0.9, 1.0)
	marker_mat.emission_energy_multiplier = 1.2
	marker.material_override = marker_mat
	_visual.add_child(marker)
