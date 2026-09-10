extends Control

const MAP_TEX := preload("res://assets/ui/ussr-pipboy-map.png")

# Western European-USSR marker on the Pip-Boy map (normalized viewport).
const LEVEL_1_ANCHOR := Vector2(0.195, 0.505)

var _advancing: bool = false
var _level_button: Button
var _reticle: Label
var _blink: float = 0.0


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = UiStyle.PIP_BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.set_offsets_preset(PRESET_FULL_RECT)

	var map := TextureRect.new()
	map.name = "MapImage"
	map.texture = MAP_TEX
	map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(map)
	map.set_anchors_preset(PRESET_FULL_RECT)
	map.set_offsets_preset(PRESET_FULL_RECT)

	_add_scanlines()

	var header := Label.new()
	header.name = "Header"
	header.text = "SELECT  OPERATION"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.apply_label(header, 22, UiStyle.PIP_GREEN, Color(0.0, 0.08, 0.0), 4)
	add_child(header)
	header.set_anchors_preset(PRESET_TOP_WIDE)
	header.offset_left = 0
	header.offset_top = 18
	header.offset_right = 0
	header.offset_bottom = 52

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "Click LEVEL 1 to deploy"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.apply_label(hint, 18, UiStyle.PIP_GREEN, Color(0.0, 0.08, 0.0), 4)
	add_child(hint)
	hint.set_anchors_preset(PRESET_BOTTOM_WIDE)
	hint.offset_left = 0
	hint.offset_top = -48
	hint.offset_right = 0
	hint.offset_bottom = -16

	var marker := Control.new()
	marker.name = "Level1Marker"
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(marker)
	marker.anchor_left = LEVEL_1_ANCHOR.x
	marker.anchor_right = LEVEL_1_ANCHOR.x
	marker.anchor_top = LEVEL_1_ANCHOR.y
	marker.anchor_bottom = LEVEL_1_ANCHOR.y
	marker.offset_left = -90
	marker.offset_right = 90
	marker.offset_top = -58
	marker.offset_bottom = 46

	_reticle = Label.new()
	_reticle.name = "Reticle"
	_reticle.text = "⊕"
	_reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reticle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.apply_label(_reticle, 28, UiStyle.PIP_GREEN, Color(0.0, 0.08, 0.0), 3)
	marker.add_child(_reticle)
	_reticle.set_anchors_preset(PRESET_TOP_WIDE)
	_reticle.offset_left = 0
	_reticle.offset_top = 0
	_reticle.offset_right = 0
	_reticle.offset_bottom = 34

	_level_button = Button.new()
	_level_button.name = "Level1Button"
	_level_button.text = "LEVEL 1"
	_level_button.focus_mode = Control.FOCUS_ALL
	_level_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UiStyle.apply_button_font(_level_button, 22, UiStyle.PIP_GREEN, Color(0.0, 0.08, 0.0), 3)
	_level_button.add_theme_stylebox_override("normal", UiStyle.make_flat(Color(0.02, 0.12, 0.04, 0.92), UiStyle.PIP_GREEN, 2))
	_level_button.add_theme_stylebox_override("hover", UiStyle.make_flat(Color(0.06, 0.28, 0.10, 0.96), Color(0.7, 1.0, 0.7), 2))
	_level_button.add_theme_stylebox_override("pressed", UiStyle.make_flat(Color(0.10, 0.40, 0.14, 1.0), Color.WHITE, 2))
	_level_button.add_theme_stylebox_override("focus", UiStyle.make_flat(Color(0.04, 0.20, 0.08, 0.95), Color(0.7, 1.0, 0.7), 2))
	_level_button.pressed.connect(enter_level_1)
	marker.add_child(_level_button)
	_level_button.set_anchors_preset(PRESET_BOTTOM_WIDE)
	_level_button.offset_left = 8
	_level_button.offset_top = -44
	_level_button.offset_right = -8
	_level_button.offset_bottom = -2
	_level_button.grab_focus()


func _process(delta: float) -> void:
	_blink += delta
	if _reticle:
		_reticle.modulate.a = 0.35 + 0.65 * (0.5 + 0.5 * sin(_blink * 3.4))


func enter_level_1() -> void:
	if _advancing:
		return
	_advancing = true
	SceneFlow.request_change(self, SceneFlow.LEVEL_1, UiStyle.PIP_BG)


func get_level_1_button() -> Button:
	return _level_button


func _add_scanlines() -> void:
	var overlay := ColorRect.new()
	overlay.name = "Scanlines"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	float line = step(0.55, fract(SCREEN_UV.y * 260.0));
	COLOR = vec4(0.0, 0.07, 0.0, line * 0.14);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	overlay.material = mat
	overlay.color = Color(1, 1, 1, 1)
	add_child(overlay)
	overlay.set_anchors_preset(PRESET_FULL_RECT)
	overlay.set_offsets_preset(PRESET_FULL_RECT)
