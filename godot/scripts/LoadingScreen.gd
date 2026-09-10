extends CanvasLayer

## Full-screen loading overlay shown while MapGenerator assembles the level.
##
## `set_progress` only moves a target value; the bar eases toward it every frame
## so a generation pass that finishes in a handful of frames still reads as a
## sweep instead of a single jump.

const BAR_WIDTH := 620.0
const BAR_HEIGHT := 26.0
const EASE_SPEED := 3.2
const HAZARD_STRIPES := 26

var _target: float = 0.0
var _shown: float = 0.0
var _blink: float = 0.0
var _bar_fill: ColorRect
var _percent: Label
var _status: Label
var _caret: Label


func _ready() -> void:
	layer = 64
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _process(delta: float) -> void:
	_shown = move_toward(_shown, _target, maxf(EASE_SPEED * delta, absf(_target - _shown) * delta * 4.0))
	if _bar_fill:
		_bar_fill.size.x = BAR_WIDTH * clampf(_shown, 0.0, 1.0)
	if _percent:
		_percent.text = "%3d%%" % int(round(clampf(_shown, 0.0, 1.0) * 100.0))
	_blink += delta
	if _caret:
		_caret.modulate.a = 0.25 + 0.75 * (0.5 + 0.5 * sin(_blink * 5.0))


func set_progress(fraction: float, label: String) -> void:
	_target = clampf(fraction, 0.0, 1.0)
	if not label.is_empty() and _status:
		_status.text = label


func snap_to_end() -> void:
	_target = 1.0
	_shown = 1.0


func fade_out(duration: float = 0.35) -> void:
	var root := get_node_or_null("Root") as Control
	if root == null:
		queue_free()
		return
	var tween := create_tween()
	tween.tween_property(root, "modulate:a", 0.0, duration)
	await tween.finished
	queue_free()


func _build_ui() -> void:
	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.set_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.name = "Background"
	background.color = UiStyle.VOID
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.set_offsets_preset(Control.PRESET_FULL_RECT)

	_add_hazard_band(root, Control.PRESET_TOP_WIDE, 0, 14)
	_add_hazard_band(root, Control.PRESET_BOTTOM_WIDE, -14, 0)

	var title := Label.new()
	title.name = "Title"
	title.text = "ОБЪЕКТ 12"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.apply_label(title, 64, UiStyle.CREAM, UiStyle.STROKE, 6)
	root.add_child(title)
	_stretch_row(title, 0.32, 78)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "ГЕНЕРАЦИЯ ПЛАНИРОВКИ  ·  PROCEDURAL LAYOUT"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.apply_label(subtitle, 20, UiStyle.MUTED, UiStyle.STROKE, 3)
	root.add_child(subtitle)
	_stretch_row(subtitle, 0.44, 28)

	var frame := Panel.new()
	frame.name = "BarFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.055, 0.055, 0.047)
	frame_style.border_color = UiStyle.CREAM
	frame_style.set_border_width_all(2)
	frame.add_theme_stylebox_override("panel", frame_style)
	root.add_child(frame)
	_center_box(frame, 0.56, BAR_WIDTH + 8.0, BAR_HEIGHT + 8.0)

	_bar_fill = ColorRect.new()
	_bar_fill.name = "BarFill"
	_bar_fill.color = Color(0.62, 0.16, 0.13)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_bar_fill)
	_bar_fill.position = Vector2(4.0, 4.0)
	_bar_fill.size = Vector2(0.0, BAR_HEIGHT)

	_percent = Label.new()
	_percent.name = "Percent"
	_percent.text = "  0%"
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_percent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.apply_label(_percent, 26, UiStyle.CREAM, UiStyle.STROKE, 4)
	root.add_child(_percent)
	_stretch_row(_percent, 0.63, 34)

	_status = Label.new()
	_status.name = "Status"
	_status.text = "ИНИЦИАЛИЗАЦИЯ / INITIALISING"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.apply_label(_status, 18, UiStyle.MUTED, UiStyle.STROKE, 3)
	root.add_child(_status)
	_stretch_row(_status, 0.70, 26)

	_caret = Label.new()
	_caret.name = "Caret"
	_caret.text = "▮"
	_caret.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caret.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.apply_label(_caret, 18, Color(0.62, 0.16, 0.13), UiStyle.STROKE, 2)
	root.add_child(_caret)
	_stretch_row(_caret, 0.76, 26)


func _add_hazard_band(parent: Control, preset: int, top: int, bottom: int) -> void:
	var band := Control.new()
	band.name = "Hazard_%d" % preset
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(band)
	band.set_anchors_preset(preset)
	band.offset_left = 0
	band.offset_right = 0
	band.offset_top = top
	band.offset_bottom = bottom
	band.grow_horizontal = Control.GROW_DIRECTION_BOTH

	for index in HAZARD_STRIPES:
		var stripe := ColorRect.new()
		stripe.name = "Stripe_%d" % index
		stripe.color = Color(0.62, 0.16, 0.13) if index % 2 == 0 else Color(0.55, 0.49, 0.14)
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.add_child(stripe)
		var step := 1.0 / float(HAZARD_STRIPES)
		stripe.anchor_left = float(index) * step
		stripe.anchor_right = float(index + 1) * step
		stripe.anchor_top = 0.0
		stripe.anchor_bottom = 1.0
		stripe.offset_left = 0
		stripe.offset_right = 0
		stripe.offset_top = 0
		stripe.offset_bottom = 0


func _stretch_row(control: Control, anchor_y: float, height: float) -> void:
	control.anchor_left = 0.0
	control.anchor_right = 1.0
	control.anchor_top = anchor_y
	control.anchor_bottom = anchor_y
	control.offset_left = 0
	control.offset_right = 0
	control.offset_top = 0
	control.offset_bottom = height


func _center_box(control: Control, anchor_y: float, width: float, height: float) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = anchor_y
	control.anchor_bottom = anchor_y
	control.offset_left = -width * 0.5
	control.offset_right = width * 0.5
	control.offset_top = 0
	control.offset_bottom = height
