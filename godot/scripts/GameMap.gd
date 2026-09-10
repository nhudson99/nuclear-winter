extends Control

const LEVEL_ONE_SCENE := "res://scenes/Main.tscn"

@onready var level_one_button: Button = $LevelOneButton
@onready var fade: ColorRect = $Fade

var _transitioning := false

func _ready() -> void:
	level_one_button.pressed.connect(_open_level_one)
	level_one_button.grab_focus()
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fade_tween := create_tween()
	fade_tween.tween_property(fade, "color:a", 0.0, 0.4)
	var pulse_tween := create_tween().set_loops()
	pulse_tween.tween_property(level_one_button, "modulate:a", 0.62, 0.7)
	pulse_tween.tween_property(level_one_button, "modulate:a", 1.0, 0.7)

func _open_level_one() -> void:
	if _transitioning:
		return
	_transitioning = true
	level_one_button.disabled = true
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, 0.25)
	await tween.finished
	get_tree().change_scene_to_file(LEVEL_ONE_SCENE)
