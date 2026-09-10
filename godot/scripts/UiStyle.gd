class_name UiStyle
extends RefCounted

const CREAM := Color(0.91, 0.886, 0.831)
const MUTED := Color(0.784, 0.769, 0.722)
const VOID := Color(0.102, 0.102, 0.086)
const CRT_VOID := Color(0.047, 0.047, 0.039)
const PIP_BG := Color(0.008, 0.031, 0.016)
const PIP_GREEN := Color(0.49, 1.0, 0.478)
const PIP_GREEN_DIM := Color(0.22, 0.55, 0.22)
const STROKE := Color(0.102, 0.102, 0.086)
const CRT_STROKE := Color(0.08, 0.08, 0.063)

const FONT := preload("res://assets/ui/RussoOne-Regular.ttf")

static var _menu_font: FontVariation


static func menu_font() -> Font:
	if _menu_font == null:
		_menu_font = FontVariation.new()
		_menu_font.base_font = FONT
		_menu_font.spacing_glyph = 1
		_menu_font.spacing_space = 16
	return _menu_font


static func apply_label(
	label: Label,
	size_px: int,
	color: Color,
	outline: Color = STROKE,
	outline_px: int = 3
) -> void:
	label.add_theme_font_override("font", menu_font())
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", outline)
	label.add_theme_constant_override("outline_size", outline_px)


static func apply_button_font(button: Button, size_px: int, color: Color, outline: Color, outline_px: int) -> void:
	button.add_theme_font_override("font", menu_font())
	button.add_theme_font_size_override("font_size", size_px)
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", color.lightened(0.2))
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", color.lightened(0.15))
	button.add_theme_color_override("font_outline_color", outline)
	button.add_theme_constant_override("outline_size", outline_px)


static func make_flat(bg: Color, border: Color, border_w: int = 2) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_w)
	box.set_corner_radius_all(2)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box
