extends Control

@onready var level_1_button: Button = $Level1Button

func _ready() -> void:
	level_1_button.pressed.connect(_on_level_1_pressed)
	level_1_button.grab_focus()

	var tween := create_tween().set_loops()
	tween.tween_property(level_1_button, "modulate:a", 0.55, 0.8).set_trans(Tween.TRANS_SINE)
	tween.tween_property(level_1_button, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)

	SceneFlow.fade_in(SceneFlow.PHOSPHOR, 0.35)

func _on_level_1_pressed() -> void:
	SceneFlow.goto_scene(SceneFlow.LEVEL_1_SCENE, SceneFlow.PHOSPHOR)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		SceneFlow.goto_scene(SceneFlow.TITLE_SCENE, SceneFlow.PHOSPHOR)
