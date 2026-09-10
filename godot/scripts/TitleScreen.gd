extends Control

@onready var prompt: Label = $Prompt

func _ready() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(prompt, "modulate:a", 0.25, 0.9).set_trans(Tween.TRANS_SINE)
	tween.tween_property(prompt, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	SceneFlow.fade_in(SceneFlow.ASH)

func _unhandled_input(event: InputEvent) -> void:
	if SceneFlow.is_any_press(event):
		accept_event()
		SceneFlow.goto_scene(SceneFlow.BRIEFING_SCENE, SceneFlow.ASH)
