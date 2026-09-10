extends CanvasLayer

## Autoload that owns the fade-to-black transitions between the title, briefing,
## map and gameplay scenes.

const ASH := Color(0.102, 0.102, 0.086)
const CRT := Color(0.047, 0.047, 0.039)
const PHOSPHOR := Color(0.008, 0.031, 0.016)

const TITLE_SCENE := "res://scenes/TitleScreen.tscn"
const BRIEFING_SCENE := "res://scenes/BossBriefing.tscn"
const MAP_SCENE := "res://scenes/WorldMap.tscn"
const LEVEL_1_SCENE := "res://scenes/Main.tscn"

var _overlay: ColorRect
var _changing := false

func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = ColorRect.new()
	_overlay.name = "FadeOverlay"
	_overlay.color = ASH
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.modulate.a = 0.0
	add_child(_overlay)

func fade_in(color: Color = ASH, duration: float = 0.4) -> void:
	_overlay.color = color
	_overlay.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(_overlay, "modulate:a", 0.0, duration)

func goto_scene(path: String, color: Color = ASH, duration: float = 0.28) -> void:
	if _changing:
		return
	_changing = true
	_overlay.color = color
	var tween := create_tween()
	tween.tween_property(_overlay, "modulate:a", 1.0, duration)
	await tween.finished
	get_tree().change_scene_to_file(path)
	_changing = false

## True for the "press any button" style inputs the intro screens listen for.
static func is_any_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventMouseButton:
		return event.pressed
	if event is InputEventJoypadButton:
		return event.pressed
	if event is InputEventScreenTouch:
		return event.pressed
	return false
