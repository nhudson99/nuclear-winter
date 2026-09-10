extends CanvasLayer

## Autoload that fades between menu / map / level scenes.

const TITLE := "res://scenes/TitleScreen.tscn"
const ARISTOCRAT := "res://scenes/AristocratScreen.tscn"
const GAME_MAP := "res://scenes/GameMap.tscn"
const LEVEL_1 := "res://scenes/Main.tscn"
const DEFAULT_FADE := Color(0.102, 0.102, 0.086)

signal transition_finished(path: String)

var fade_duration: float = 0.28
var busy: bool = false

var _overlay: ColorRect


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = ColorRect.new()
	_overlay.name = "FadeOverlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.color = Color(DEFAULT_FADE, 0.0)
	add_child(_overlay)


func go_to(path: String, fade_color: Color = Color(0.102, 0.102, 0.086)) -> void:
	if busy:
		return
	busy = true
	var clear := Color(fade_color, 0.0)
	var opaque := Color(fade_color, 1.0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	if fade_duration > 0.0:
		_overlay.color = clear
		var fade_out := create_tween()
		fade_out.tween_property(_overlay, "color", opaque, fade_duration)
		await fade_out.finished
	else:
		_overlay.color = opaque

	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("SceneFlow failed to load %s (%s)" % [path, err])

	await get_tree().process_frame

	if fade_duration > 0.0:
		var fade_in := create_tween()
		fade_in.tween_property(_overlay, "color", clear, fade_duration)
		await fade_in.finished

	_overlay.color = clear
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	busy = false
	transition_finished.emit(path)


static func request_change(from: Node, path: String, fade_color: Color) -> void:
	var flow := from.get_node_or_null("/root/SceneFlow")
	if flow:
		flow.go_to(path, fade_color)
		return
	from.get_tree().change_scene_to_file(path)
