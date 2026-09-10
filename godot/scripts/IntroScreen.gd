extends Control

@export_file("*.tscn") var next_scene: String
@export var accept_any_input: bool = false

@onready var action_button: Button = $ActionButton
@onready var fade: ColorRect = $Fade

var _transitioning := false

func _ready() -> void:
	action_button.pressed.connect(_advance)
	action_button.grab_focus()
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 0.0, 0.4)

func _unhandled_input(event: InputEvent) -> void:
	if not accept_any_input or _transitioning:
		return
	var should_advance: bool = (
		(event is InputEventKey and event.pressed and not event.echo)
		or (event is InputEventMouseButton and event.pressed)
		or (event is InputEventJoypadButton and event.pressed)
	)
	if should_advance:
		get_viewport().set_input_as_handled()
		_advance()

func _advance() -> void:
	if _transitioning or next_scene.is_empty():
		return
	_transitioning = true
	action_button.disabled = true
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, 0.25)
	await tween.finished
	get_tree().change_scene_to_file(next_scene)
