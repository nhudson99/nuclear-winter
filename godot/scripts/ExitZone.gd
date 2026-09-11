extends Area3D

## Exterior exit. Winning requires the player to enter while holding the item.
## After the objective is taken, a green beacon marks the way out.

signal player_escaped(player: Node3D)

var _glow_light: OmniLight3D
var _glow_mesh: MeshInstance3D
var _glow_beam: MeshInstance3D

func _ready() -> void:
	add_to_group("exit")
	collision_layer = 0
	collision_mask = 2 # player
	monitoring = true
	monitorable = false
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_setup_glow()
	set_glow_visible(false)

func _on_body_entered(body: Node3D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	if body.has_method("has_collected_item") and body.has_collected_item():
		player_escaped.emit(body)

func set_glow_visible(enabled: bool) -> void:
	if _glow_light:
		_glow_light.visible = enabled
	if _glow_mesh:
		_glow_mesh.visible = enabled
	if _glow_beam:
		_glow_beam.visible = enabled

func is_glow_visible() -> bool:
	return _glow_light != null and _glow_light.visible

func _setup_glow() -> void:
	_glow_light = OmniLight3D.new()
	_glow_light.name = "ExitGlow"
	_glow_light.light_color = Color(0.25, 1.0, 0.38)
	_glow_light.light_energy = 5.2
	_glow_light.omni_range = 7.0
	_glow_light.omni_attenuation = 0.7
	_glow_light.position = Vector3(0.0, 1.6, 0.0)
	add_child(_glow_light)

	_glow_mesh = MeshInstance3D.new()
	_glow_mesh.name = "ExitGlowMesh"
	var sphere := SphereMesh.new()
	sphere.radius = 0.38
	sphere.height = 0.76
	_glow_mesh.mesh = sphere
	_glow_mesh.position = Vector3(0.0, 1.35, 0.0)
	_glow_mesh.material_override = _glow_material(0.45)
	add_child(_glow_mesh)

	_glow_beam = MeshInstance3D.new()
	_glow_beam.name = "ExitGlowBeam"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.08
	cylinder.bottom_radius = 0.16
	cylinder.height = 3.4
	_glow_beam.mesh = cylinder
	_glow_beam.position = Vector3(0.0, 2.4, 0.0)
	_glow_beam.material_override = _glow_material(0.28)
	add_child(_glow_beam)

func _glow_material(alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.95, 0.32, alpha)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 1.0, 0.35)
	mat.emission_energy_multiplier = 3.8
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat
