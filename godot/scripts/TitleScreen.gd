extends Control

const TITLE_TEX := preload("res://assets/ui/title-screen.png")

var _advancing: bool = false
var _prompt: Label
var _blink: float = 0.0


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)

	var bg := TextureRect.new()
	bg.name = "Background"
	bg.texture = TITLE_TEX
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.set_offsets_preset(PRESET_FULL_RECT)

	_add_ash()

	_prompt = Label.new()
	_prompt.name = "Prompt"
	_prompt.text = "Press Any Button"
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiStyle.apply_label(_prompt, 28, UiStyle.CREAM, UiStyle.STROKE, 5)
	_prompt.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	add_child(_prompt)
	_prompt.set_anchors_preset(PRESET_BOTTOM_LEFT)
	_prompt.offset_left = 28
	_prompt.offset_top = -42
	_prompt.offset_right = 480
	_prompt.offset_bottom = -8


func _process(delta: float) -> void:
	_blink += delta
	if _prompt:
		_prompt.modulate.a = 0.25 + 0.75 * (0.5 + 0.5 * sin(_blink * 2.4))


func _unhandled_input(event: InputEvent) -> void:
	if _is_advance_event(event):
		advance()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		advance()


func advance() -> void:
	if _advancing:
		return
	_advancing = true
	SceneFlow.request_change(self, SceneFlow.ARISTOCRAT, UiStyle.VOID)


func _is_advance_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventJoypadButton:
		return event.pressed
	return false


func _add_ash() -> void:
	var view := get_viewport_rect().size
	var particles := CPUParticles2D.new()
	particles.name = "Ash"
	particles.amount = 90
	particles.lifetime = 9.0
	particles.preprocess = 5.0
	particles.explosiveness = 0.0
	particles.randomness = 0.4
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(maxf(view.x * 0.5, 320.0), 10.0)
	particles.position = Vector2(view.x * 0.5, -16.0)
	particles.direction = Vector2(0.15, 1.0)
	particles.spread = 22.0
	particles.gravity = Vector2(0, 14)
	particles.initial_velocity_min = 16.0
	particles.initial_velocity_max = 40.0
	particles.scale_amount_min = 0.3
	particles.scale_amount_max = 0.85
	particles.color = Color(0.8, 0.78, 0.72, 0.55)
	particles.texture = _ash_texture()
	particles.z_index = 1
	add_child(particles)


func _ash_texture() -> Texture2D:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 8:
		for x in 8:
			var d := Vector2(float(x) - 3.5, float(y) - 3.5).length()
			if d < 3.0:
				img.set_pixel(x, y, Color(0.85, 0.83, 0.78, 1.0 - d / 3.4))
	return ImageTexture.create_from_image(img)
