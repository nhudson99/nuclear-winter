class_name PickupItem
extends Area3D

## Interactable objective. Player presses interact (E) while nearby to collect it.
## Mission items trigger the escape alarm; keys unlock the matching locked door.

signal picked_up(item: Node3D)

enum Kind { MISSION, KEY }

@export var interact_range: float = 2.2
@export var bob_height: float = 0.12
@export var bob_speed: float = 2.4
@export var kind: Kind = Kind.MISSION
@export var key_stage: int = 0

var _taken: bool = false
var _held: bool = false
var _visual: Node3D
var _base_y: float = 0.55

func _ready() -> void:
	add_to_group("pickup")
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false
	_ensure_visual()
	_apply_kind_visual()
	_base_y = _visual.position.y if _visual else 0.55


func configure(p_kind: Kind, stage: int = 0) -> void:
	kind = p_kind
	key_stage = stage
	if _visual:
		_apply_kind_visual()


func is_mission_item() -> bool:
	return kind == Kind.MISSION


func is_key() -> bool:
	return kind == Kind.KEY

func _process(delta: float) -> void:
	if _taken or _held or _visual == null:
		return
	_visual.position.y = _base_y + bob_height * sin(Time.get_ticks_msec() * 0.001 * bob_speed * TAU)
	_visual.rotation.y += delta * 1.4

func can_interact(from_pos: Vector3) -> bool:
	if _taken or _held:
		return false
	var to_item := global_position - from_pos
	to_item.y = 0.0
	return to_item.length() <= interact_range

func try_pickup() -> bool:
	if _taken or _held:
		return false
	_taken = true
	set_process(false)
	visible = false
	picked_up.emit(self)
	queue_free()
	return true

func is_taken() -> bool:
	return _taken


## Hide the mission item without awarding it to the player. Used by the toad.
func swallow() -> bool:
	if _taken or _held or not is_mission_item():
		return false
	_held = true
	set_process(false)
	visible = false
	return true


func is_swallowed() -> bool:
	return _held


func release_at(world_pos: Vector3) -> void:
	_held = false
	_taken = false
	visible = true
	set_process(true)
	global_position = world_pos
	if _visual:
		_visual.position.y = _base_y


## Clear swallowed / taken flags on a duplicated pickup (keys copy the mission).
func reset_instance_state() -> void:
	_taken = false
	_held = false
	visible = true
	set_process(true)

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
	_apply_kind_visual()


func _apply_kind_visual() -> void:
	if _visual == null:
		return
	var mesh := _visual.get_node_or_null("Mesh") as MeshInstance3D
	var marker := _visual.get_node_or_null("Marker") as MeshInstance3D
	if kind == Kind.KEY:
		if mesh and mesh.material_override is StandardMaterial3D:
			var mat := mesh.material_override as StandardMaterial3D
			mat.albedo_color = Color(0.72, 0.78, 0.88, 1.0)
			mat.emission = Color(0.35, 0.55, 0.95, 1.0)
			mat.emission_energy_multiplier = 1.5
		if marker and marker.material_override is StandardMaterial3D:
			var marker_mat := marker.material_override as StandardMaterial3D
			marker_mat.albedo_color = Color(0.85, 0.9, 1.0, 1.0)
			marker_mat.emission = Color(0.4, 0.65, 1.0, 1.0)
		return
	if mesh and mesh.material_override is StandardMaterial3D:
		var mission := mesh.material_override as StandardMaterial3D
		mission.albedo_color = Color(0.95, 0.78, 0.22, 1.0)
		mission.emission = Color(0.85, 0.55, 0.08, 1.0)
		mission.emission_energy_multiplier = 1.4
	if marker and marker.material_override is StandardMaterial3D:
		var mission_marker := marker.material_override as StandardMaterial3D
		mission_marker.albedo_color = Color(0.2, 0.85, 0.95, 1.0)
		mission_marker.emission = Color(0.15, 0.7, 0.9, 1.0)
