class_name SteamValve
extends Node3D

## Interactable wheel. Press E nearby to shut the steam main.

signal shut(valve: SteamValve)

@export var interact_range: float = 2.2

var _closed: bool = false
var _wheel: Node3D
var _lamp: MeshInstance3D
var _prompt: Label3D


func _ready() -> void:
	add_to_group("steam_valve")
	_ensure_prompt()


func configure(wheel: Node3D, lamp: MeshInstance3D) -> void:
	_wheel = wheel
	_lamp = lamp
	_ensure_prompt()


func is_shut() -> bool:
	return _closed


func can_interact(from_pos: Vector3) -> bool:
	if _closed:
		return false
	var to_valve := global_position - from_pos
	to_valve.y = 0.0
	return to_valve.length() <= interact_range


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
	_set_lamp(Color(0.25, 0.85, 0.35), Color(0.2, 1.0, 0.4))
	if _prompt:
		_prompt.visible = false


func _set_lamp(albedo: Color, emission: Color) -> void:
	if _lamp == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = 2.2
	_lamp.material_override = mat


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
	_prompt.modulate = Color(1.0, 0.72, 0.35)
	_prompt.outline_modulate = Color(0, 0, 0)
	_prompt.outline_size = 8
	add_child(_prompt)
