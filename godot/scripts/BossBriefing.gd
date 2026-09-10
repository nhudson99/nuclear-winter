extends Control

const BOSS_LINE := "You want to eat? Then get to work"
const CHAR_DELAY := 0.038

@onready var dialogue: Label = $Panel/Dialogue
@onready var continue_prompt: Label = $Panel/ContinuePrompt

var _char_index := 0
var _typing_complete := false

func _ready() -> void:
	dialogue.text = ""
	continue_prompt.modulate.a = 0.0
	SceneFlow.fade_in(SceneFlow.CRT, 0.35)
	_type_line()

func _type_line() -> void:
	while _char_index < BOSS_LINE.length():
		await get_tree().create_timer(CHAR_DELAY).timeout
		if _typing_complete:
			return
		_char_index += 1
		dialogue.text = BOSS_LINE.substr(0, _char_index)
	_finish_typing()

func _finish_typing() -> void:
	if _typing_complete:
		return
	_typing_complete = true
	_char_index = BOSS_LINE.length()
	dialogue.text = BOSS_LINE
	continue_prompt.modulate.a = 1.0
	var tween := create_tween().set_loops()
	tween.tween_property(continue_prompt, "modulate:a", 0.3, 0.7).set_trans(Tween.TRANS_SINE)
	tween.tween_property(continue_prompt, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)

func _unhandled_input(event: InputEvent) -> void:
	if not SceneFlow.is_any_press(event):
		return
	accept_event()
	if not _typing_complete:
		_finish_typing()
		return
	SceneFlow.goto_scene(SceneFlow.MAP_SCENE, SceneFlow.CRT)
