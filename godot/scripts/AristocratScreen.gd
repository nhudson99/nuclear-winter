extends Control

const CRT_TEX := preload("res://assets/ui/boss-crt.png")
const PANEL_TEX := preload("res://assets/ui/dialogue-panel.png")
const CHAR_DELAY := 0.038

var _advancing: bool = false
var _typing_complete: bool = false
var _char_index: int = 0
var _accum: float = 0.0
var _dialogue: Label
var _continue: Label
var _blink: float = 0.0
var _line: String = GameProgress.BRIEFING_LINE


func _ready() -> void:
	_line = GameProgress.dialogue_line()
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)

	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = UiStyle.CRT_VOID
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.set_offsets_preset(PRESET_FULL_RECT)

	var crt := TextureRect.new()
	crt.name = "CrtPortrait"
	crt.texture = CRT_TEX
	crt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(crt)
	crt.anchor_left = 0.14
	crt.anchor_right = 0.86
	crt.anchor_top = 0.04
	crt.anchor_bottom = 0.68
	crt.offset_left = 0
	crt.offset_top = 0
	crt.offset_right = 0
	crt.offset_bottom = 0

	var panel_h := 168.0
	var panel := TextureRect.new()
	panel.name = "DialoguePanel"
	panel.texture = PANEL_TEX
	panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel.stretch_mode = TextureRect.STRETCH_SCALE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	panel.anchor_left = 0.07
	panel.anchor_right = 0.93
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0
	panel.offset_right = 0
	panel.offset_top = -(panel_h + 28.0)
	panel.offset_bottom = -28.0

	_dialogue = Label.new()
	_dialogue.name = "DialogueText"
	_dialogue.text = ""
	_dialogue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.apply_label(_dialogue, 32, Color(0.941, 0.922, 0.878), UiStyle.CRT_STROKE, 4)
	panel.add_child(_dialogue)
	_dialogue.set_anchors_preset(PRESET_FULL_RECT)
	_dialogue.offset_left = 48
	_dialogue.offset_top = 36
	_dialogue.offset_right = -88
	_dialogue.offset_bottom = -40

	_continue = Label.new()
	_continue.name = "ContinuePrompt"
	_continue.text = "Press any key to continue"
	_continue.visible = false
	_continue.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_continue.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_continue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.apply_label(_continue, 18, UiStyle.MUTED, UiStyle.CRT_STROKE, 3)
	panel.add_child(_continue)
	_continue.set_anchors_preset(PRESET_BOTTOM_RIGHT)
	_continue.offset_left = -420
	_continue.offset_top = -36
	_continue.offset_right = -48
	_continue.offset_bottom = -14


func _process(delta: float) -> void:
	if not _typing_complete:
		_accum += delta
		while _accum >= CHAR_DELAY and _char_index < _line.length():
			_accum -= CHAR_DELAY
			_char_index += 1
			_dialogue.text = _line.substr(0, _char_index)
		if _char_index >= _line.length():
			_finish_typing()
		return

	_blink += delta
	if _continue:
		_continue.modulate.a = 0.3 + 0.7 * (0.5 + 0.5 * sin(_blink * 2.8))


func _unhandled_input(event: InputEvent) -> void:
	if _is_advance_event(event):
		on_any_input()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		on_any_input()


func on_any_input() -> void:
	if _advancing:
		return
	if not _typing_complete:
		_char_index = _line.length()
		_dialogue.text = _line
		_finish_typing()
		return
	advance()


func finish_typing_now() -> void:
	_char_index = _line.length()
	_dialogue.text = _line
	_finish_typing()


func advance() -> void:
	if _advancing:
		return
	if not _typing_complete:
		finish_typing_now()
		return
	_advancing = true
	GameProgress.aristocrat_mode = GameProgress.AristocratMode.BRIEFING
	SceneFlow.request_change(self, SceneFlow.GAME_MAP, UiStyle.CRT_VOID)


func is_typing_complete() -> bool:
	return _typing_complete


func spoken_line() -> String:
	return _line


func _finish_typing() -> void:
	if _typing_complete:
		return
	_typing_complete = true
	_continue.visible = true
	_continue.modulate.a = 1.0


func _is_advance_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventJoypadButton:
		return event.pressed
	return false
