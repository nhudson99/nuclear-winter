class_name SteamBarrier
extends Node3D

## Steam jet filling one carved doorway. `shut_off` drops the collision so the
## player and the monster track can use the opening.

signal shut_off_completed(barrier: SteamBarrier)

const WORLD_LAYER := 1

var from_cell: Vector2i = Vector2i.ZERO
var to_cell: Vector2i = Vector2i.ZERO
var side: String = "E"

var _blocked: bool = true
var _built: bool = false
var _body: StaticBody3D
var _visual: Node3D
var _particles: GPUParticles3D
var _light: OmniLight3D


func _ready() -> void:
	add_to_group("steam_barrier")


func configure(p_from: Vector2i, p_to: Vector2i, p_side: String, size: Vector3) -> void:
	from_cell = p_from
	to_cell = p_to
	side = p_side
	if not _built:
		_build(size)
		_built = true


func is_blocked() -> bool:
	return _blocked


func shut_off() -> void:
	if not _blocked:
		return
	_blocked = false
	if _body:
		_body.collision_layer = 0
		_body.collision_mask = 0
	if _visual:
		_visual.visible = false
	if _particles:
		_particles.emitting = false
		_particles.visible = false
	if _light:
		_light.visible = false
	visible = false
	shut_off_completed.emit(self)


func _build(size: Vector3) -> void:
	_visual = Node3D.new()
	_visual.name = "SteamVisual"
	add_child(_visual)

	var across := size.x >= size.z
	var jet := Vector3(1, 0.25, 0) if across else Vector3(0, 0.25, 1)
	_add_mist_box(Vector3(0, size.y * 0.55, 0), size * Vector3(0.72, 0.7, 0.72), 0.34)
	_add_mist_box(Vector3(0, size.y * 0.78, 0), size * Vector3(0.4, 0.35, 0.4), 0.5)
	_add_stub(size)

	_body = StaticBody3D.new()
	_body.name = "SteamCollision"
	_body.collision_layer = WORLD_LAYER
	_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.name = "Col_Steam"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3(0.0, size.y * 0.5, 0.0)
	_body.add_child(shape)
	add_child(_body)

	_particles = GPUParticles3D.new()
	_particles.name = "SteamJet"
	_particles.amount = 56
	_particles.lifetime = 0.85
	_particles.visibility_aabb = AABB(Vector3(-2.2, 0.0, -2.2), Vector3(4.4, 3.2, 4.4))
	_particles.position = Vector3(0.0, size.y * 0.45, 0.0)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.2, size.y * 0.28, size.z * 0.28) if across else Vector3(size.x * 0.28, size.y * 0.28, 0.2)
	process.direction = jet
	process.spread = 22.0
	process.initial_velocity_min = 1.6
	process.initial_velocity_max = 3.2
	process.gravity = Vector3(0.0, 1.1, 0.0)
	process.scale_min = 0.25
	process.scale_max = 0.7
	process.color = Color(0.9, 0.93, 0.95, 0.65)
	_particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.55)
	var puff := StandardMaterial3D.new()
	puff.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	puff.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	puff.albedo_color = Color(0.88, 0.92, 0.95, 0.75)
	puff.emission_enabled = true
	puff.emission = Color(0.8, 0.86, 0.9)
	puff.emission_energy_multiplier = 1.3
	quad.material = puff
	_particles.draw_pass_1 = quad
	add_child(_particles)

	_light = OmniLight3D.new()
	_light.name = "SteamLight"
	_light.light_color = Color(0.95, 0.78, 0.55)
	_light.light_energy = 2.2
	_light.omni_range = 4.2
	_light.position = Vector3(0.0, size.y * 0.6, 0.0)
	add_child(_light)


func _add_mist_box(pos: Vector3, size: Vector3, alpha: float) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.82, 0.86, 0.9, alpha)
	mat.emission_enabled = true
	mat.emission = Color(0.75, 0.82, 0.88)
	mat.emission_energy_multiplier = 1.5
	mesh.material_override = mat
	_visual.add_child(mesh)


func _add_stub(size: Vector3) -> void:
	var across := size.x >= size.z
	var mesh := MeshInstance3D.new()
	mesh.name = "BurstPipe"
	var box := BoxMesh.new()
	box.size = Vector3(0.55, 0.16, 0.16) if across else Vector3(0.16, 0.16, 0.55)
	mesh.mesh = box
	var along := size.z * 0.28 if across else size.x * 0.28
	mesh.position = Vector3(along, 1.55, 0.0) if across else Vector3(0.0, 1.55, along)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.24, 0.14)
	mat.metallic = 0.45
	mat.roughness = 0.55
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.42, 0.1)
	mat.emission_energy_multiplier = 0.8
	mesh.material_override = mat
	_visual.add_child(mesh)
