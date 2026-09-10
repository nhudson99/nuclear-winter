extends Control

@onready var level_1_button: Button = $Level1Button

var _pulse: Tween = null

func _ready() -> void:
	level_1_button.pressed.connect(_on_level_1_pressed)
	level_1_button.mouse_entered.connect(_stop_pulse)
	level_1_button.mouse_exited.connect(_start_pulse)
	level_1_button.grab_focus()
	_start_pulse()
	SceneFlow.fade_in(SceneFlow.PHOSPHOR, 0.35)

## The marker pulses to draw the eye, but holds steady while it is hovered so
## the hover highlight stays readable.
func _start_pulse() -> void:
	_stop_pulse()
	_pulse = create_tween().set_loops()
	_pulse.tween_property(level_1_button, "modulate:a", 0.55, 0.8).set_trans(Tween.TRANS_SINE)
	_pulse.tween_property(level_1_button, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)

func _stop_pulse() -> void:
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	_pulse = null
	level_1_button.modulate.a = 1.0

func _on_level_1_pressed() -> void:
	SceneFlow.goto_scene(SceneFlow.LEVEL_1_SCENE, SceneFlow.PHOSPHOR)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		SceneFlow.goto_scene(SceneFlow.TITLE_SCENE, SceneFlow.PHOSPHOR)
