class_name SteamValve
extends Node3D

## Boiler control. Press E or USE nearby to shut the steam main. The orange
## indicator turns green and the steam jet clears.

signal shut(valve: SteamValve)

const SHUT_ALBEDO := Color(0.22, 0.85, 0.32)
const SHUT_EMISSION := Color(0.15, 1.0, 0.38)
const LIVE_GLOW := Color(1.0, 0.42, 0.1)
const SHUT_GLOW := Color(0.2, 1.0, 0.35)
const INDICATOR_NAMES := {
	"NoCol_ValveLamp": true,
	"NoCol_Gauge_1": true,
	"NoCol_CabinetLamp": true,
	"NoCol_ManifoldHeat": true,
}

@export var interact_range: float = 3.2

var _closed: bool = false
var _wheel: Node3D
var _lamp: MeshInstance3D
var _panel: Node3D
var _prompt: Label3D
var _glow: OmniLight3D
var _panel_glow: OmniLight3D
var _status: MeshInstance3D
var _spots: Array[Node3D] = []


func _ready() -> void:
	add_to_group("steam_valve")
	_ensure_prompt()


func configure(wheel: Node3D, lamp: MeshInstance3D) -> void:
	_wheel = wheel
	_lamp = lamp
	_spots = [self]
	if wheel != null:
		_spots.append(wheel)
	if lamp != null:
		_spots.append(lamp)
	var room := _room_of(lamp if lamp != null else wheel)
	var board := _find_named(room, "GaugeBoard")
	if board is Node3D:
		_panel = board as Node3D
		_spots.append(_panel)
	for gauge_name in ["NoCol_Gauge_0", "NoCol_Gauge_1"]:
		var gauge := _find_named(room, gauge_name)
		if gauge is Node3D:
			_spots.append(gauge as Node3D)
	_ensure_glow()
	_ensure_prompt()
	if _prompt != null:
		var prompt_at := _panel_light_position()
		prompt_at.y += 0.55
		_prompt.global_position = prompt_at


func is_shut() -> bool:
	return _closed


func indicator_is_green() -> bool:
	if not _closed or _glow == null:
		return false
	if not _color_is_green(_glow.light_color):
		return false
	if _panel_glow != null and not _color_is_green(_panel_glow.light_color):
		return false
	if _status != null:
		var mat := _status.material_override as StandardMaterial3D
		if mat == null or not _color_is_green(mat.emission):
			return false
	return true


func can_interact(from_pos: Vector3) -> bool:
	if _closed:
		return false
	return interact_distance(from_pos) <= interact_range


func interact_distance(from_pos: Vector3) -> float:
	var best := INF
	for spot in _spots:
		if spot == null or not is_instance_valid(spot):
			continue
		var to_spot := spot.global_position - from_pos
		to_spot.y = 0.0
		best = minf(best, to_spot.length())
	return best


func try_shut() -> bool:
	if _closed:
		return false
	_close_visual()
	shut.emit(self)
	return true


## Floor reloads spawn a fresh wheel after the valve was already closed.
func force_closed() -> void:
	if _closed:
		return
	_close_visual()


func _close_visual() -> void:
	_closed = true
	if _wheel:
		_wheel.global_rotate(Vector3.UP, PI * 0.5)
	_paint_map()
	_set_glow(true)
	_clear_steam()
	if _prompt:
		_prompt.visible = false


func _paint_map() -> void:
	var root := _map_root()
	if root == null:
		_paint_mesh(_lamp, 7.0)
		return
	_paint_node(root)


func _paint_node(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		var label := String(mesh.name)
		if label.begins_with("SteamPipe_"):
			_cool_pipe(mesh)
		elif INDICATOR_NAMES.has(label):
			var energy := 8.0 if label == "NoCol_ValveLamp" or label == "NoCol_Gauge_1" else 4.0
			_paint_mesh(mesh, energy)
	for child in node.get_children():
		_paint_node(child)


func _paint_mesh(mesh: MeshInstance3D, energy: float) -> void:
	if mesh == null:
		return
	var mat := _emissive_material(SHUT_ALBEDO, SHUT_EMISSION, energy)
	_apply_material(mesh, mat)
	if String(mesh.name) == "NoCol_ValveLamp" or String(mesh.name) == "NoCol_Gauge_1":
		mesh.scale = Vector3(2.2, 2.2, 2.2)


func _cool_pipe(mesh: MeshInstance3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.38, 0.36)
	mat.metallic = 0.45
	mat.roughness = 0.55
	mat.emission_enabled = true
	mat.emission = Color(0.05, 0.16, 0.1)
	mat.emission_energy_multiplier = 0.15
	_apply_material(mesh, mat)


func _apply_material(mesh: MeshInstance3D, mat: Material) -> void:
	mesh.material_override = mat
	if mesh.mesh == null:
		return
	for surface in mesh.mesh.get_surface_count():
		mesh.set_surface_override_material(surface, mat)


func _emissive_material(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = albedo
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = energy
	return mat


func _ensure_glow() -> void:
	if _glow != null:
		return
	_glow = _make_glow("ValveGlow")
	if _lamp != null:
		_glow.global_position = _lamp.global_position
	else:
		_glow.position = Vector3(0.0, 1.2, 0.0)
	var panel_at := _panel_light_position()
	_panel_glow = _make_glow("PanelGlow")
	_panel_glow.global_position = panel_at
	_status = MeshInstance3D.new()
	_status.name = "PanelStatusLight"
	var bulb := SphereMesh.new()
	bulb.radius = 0.22
	bulb.height = 0.44
	_status.mesh = bulb
	_status.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_status)
	_status.global_position = panel_at
	_set_glow(false)


func _panel_light_position() -> Vector3:
	var anchor := _panel if _panel != null else _lamp
	if anchor == null:
		return global_position + Vector3(0.0, 1.35, 0.0)
	var at := anchor.global_position
	var room := _room_of(anchor)
	if room is Node3D:
		var outward: Vector3 = at - (room as Node3D).global_position
		outward.y = 0.0
		if outward.length() > 0.2:
			at -= outward.normalized() * 0.35
	at.y = maxf(at.y, 1.35)
	return at


func _make_glow(node_name: String) -> OmniLight3D:
	var glow := OmniLight3D.new()
	glow.name = node_name
	glow.shadow_enabled = false
	glow.omni_attenuation = 0.6
	add_child(glow)
	return glow


func _set_glow(shut: bool) -> void:
	var color := SHUT_GLOW if shut else LIVE_GLOW
	var energy := 8.0 if shut else 3.2
	var reach := 8.0 if shut else 4.5
	for glow in [_glow, _panel_glow]:
		if glow == null:
			continue
		glow.light_color = color
		glow.light_energy = energy
		glow.omni_range = reach
	if _status != null:
		var albedo := SHUT_ALBEDO if shut else Color(1.0, 0.28, 0.1)
		var emission := SHUT_EMISSION if shut else LIVE_GLOW
		_status.material_override = _emissive_material(albedo, emission, 6.0 if shut else 3.0)


func _clear_steam() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("steam_barrier"):
		if node != null and node.has_method("shut_off"):
			node.shut_off()


func _color_is_green(color: Color) -> bool:
	return color.g > color.r and color.g > 0.6


func _ensure_prompt() -> void:
	if _prompt != null:
		return
	_prompt = Label3D.new()
	_prompt.name = "ValvePrompt"
	_prompt.text = "E"
	_prompt.font_size = 48
	_prompt.pixel_size = 0.004
	_prompt.position = Vector3(0.0, 0.85, 0.0)
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.modulate = Color(1.0, 0.55, 0.18)
	_prompt.outline_modulate = Color(0, 0, 0)
	_prompt.outline_size = 8
	add_child(_prompt)


func _map_root() -> Node:
	var node: Node = self
	while node != null:
		if String(node.name) == "GeneratedMap":
			return node
		node = node.get_parent()
	return get_parent()


func _room_of(marker: Node) -> Node:
	var node := marker
	while node != null:
		if String(node.name).begins_with("Room_"):
			return node
		node = node.get_parent()
	return null


func _find_named(root: Node, node_name: String) -> Node:
	if root == null:
		return null
	if String(root.name) == node_name:
		return root
	for child in root.get_children():
		var found := _find_named(child, node_name)
		if found != null:
			return found
	return null
