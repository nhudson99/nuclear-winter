class_name TouchControls
extends CanvasLayer

## On-screen twin sticks and buttons for touch play.
## Left stick moves (full shove runs). Right stick aims the flashlight and the
## prisoner. USE interacts. ATK swings or fires. Keyboard and mouse keep working;
## a deflected stick wins over WASD while it is held.

const DEADZONE := 0.18
const MOVE_SIZE := 168.0
const AIM_SIZE := 168.0
const BUTTON_SIZE := 100.0
const MARGIN := 28.0
const GAP := 36.0
const HIT_PADDING := 8.0

var move_stick := Vector2.ZERO
var aim_stick := Vector2.ZERO

var _root: Control
var _move: TouchStick
var _aim: TouchStick
var _interact: TouchButton
var _attack: TouchButton
var _move_index := -2
var _aim_index := -2
var _interact_index := -2
var _attack_index := -2

func _ready() -> void:
	layer = 20
	visible = false
	_build()
	_layout()


func _process(_delta: float) -> void:
	var enabled := _controls_enabled()
	if visible != enabled:
		visible = enabled
		if not enabled:
			_release_all()
	if enabled:
		_layout()


func _input(event: InputEvent) -> void:
	if not _controls_enabled():
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			pointer_down(touch.index, touch.position)
		else:
			pointer_up(touch.index)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		pointer_move(drag.index, drag.position)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouse and (event as InputEventMouse).device < 0:
		# Touch already arrived as a screen event. Drop the emulated click so a
		# tap on empty space does not become an LMB attack.
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		var used := false
		if mouse.pressed:
			used = pointer_down(-1, mouse.position)
		else:
			used = pointer_up(-1)
		if used:
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _owns_index(-1):
		pointer_move(-1, (event as InputEventMouseMotion).position)
		get_viewport().set_input_as_handled()


## +x screen-right, +y screen-up, length at most 1. Zero inside the deadzone.
func move_stick_vector() -> Vector2:
	return move_stick


func is_aiming() -> bool:
	return aim_stick.length_squared() > 0.0


func aim_planar() -> Vector3:
	var direction := stick_to_planar(aim_stick)
	if direction.length_squared() < 0.0001:
		return Vector3.ZERO
	return direction.normalized()


## Camera-relative planar direction. +x is screen right, +y is screen up.
## Length is preserved up to 1 so a half-thrown stick walks at half speed.
static func stick_to_planar(stick: Vector2) -> Vector3:
	var right := Vector3(1.0, 0.0, -1.0).normalized()
	var forward := Vector3(-1.0, 0.0, -1.0).normalized()
	var direction := right * stick.x + forward * stick.y
	if direction.length() > 1.0:
		direction = direction.normalized()
	return direction


func set_move_stick(stick: Vector2) -> void:
	move_stick = _clamp_stick(stick)
	if _move:
		_move.set_stick(move_stick)


func set_aim_stick(stick: Vector2) -> void:
	aim_stick = _clamp_stick(stick)
	if _aim:
		_aim.set_stick(aim_stick)


func press_interact() -> void:
	if not _controls_enabled():
		return
	var player := _player()
	if player != null and player.has_method("interact"):
		player.interact()


func press_attack() -> void:
	if not _controls_enabled():
		return
	var player := _player()
	if player != null and player.has_method("attack"):
		player.attack()


## Returns true when the pointer landed on a control.
func pointer_down(index: int, pos: Vector2) -> bool:
	if _hits(_interact, pos):
		_interact_index = index
		_interact.set_held(true)
		press_interact()
		return true
	if _hits(_attack, pos):
		_attack_index = index
		_attack.set_held(true)
		press_attack()
		return true
	if _hits(_move, pos):
		_move_index = index
		_drag_stick(_move, pos, true)
		return true
	if _hits(_aim, pos):
		_aim_index = index
		_drag_stick(_aim, pos, false)
		return true
	return false


func pointer_move(index: int, pos: Vector2) -> void:
	if index == _move_index:
		_drag_stick(_move, pos, true)
	elif index == _aim_index:
		_drag_stick(_aim, pos, false)


## Returns true when this pointer was driving a control.
func pointer_up(index: int) -> bool:
	var used := false
	if index == _move_index:
		_move_index = -2
		set_move_stick(Vector2.ZERO)
		used = true
	if index == _aim_index:
		_aim_index = -2
		set_aim_stick(Vector2.ZERO)
		used = true
	if index == _interact_index:
		_interact_index = -2
		_interact.set_held(false)
		used = true
	if index == _attack_index:
		_attack_index = -2
		_attack.set_held(false)
		used = true
	return used


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.set_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_move = TouchStick.new()
	_move.name = "MoveStick"
	_move.caption = "MOVE"
	_root.add_child(_move)

	_aim = TouchStick.new()
	_aim.name = "AimStick"
	_aim.caption = "AIM"
	_root.add_child(_aim)

	_interact = TouchButton.new()
	_interact.name = "InteractButton"
	_interact.caption = "USE"
	_interact.attack = false
	_root.add_child(_interact)

	_attack = TouchButton.new()
	_attack.name = "AttackButton"
	_attack.caption = "ATK"
	_attack.attack = true
	_root.add_child(_attack)


func _layout() -> void:
	if _root == null:
		return
	var vp := get_viewport().get_visible_rect().size
	if vp.x < 16.0 or vp.y < 16.0:
		return
	_place(_move, Vector2(MARGIN, vp.y - MARGIN - MOVE_SIZE), Vector2(MOVE_SIZE, MOVE_SIZE))
	_place(_aim, Vector2(vp.x - MARGIN - AIM_SIZE, vp.y - MARGIN - AIM_SIZE), Vector2(AIM_SIZE, AIM_SIZE))
	var attack_pos := Vector2(
		vp.x - MARGIN - BUTTON_SIZE,
		vp.y - MARGIN - AIM_SIZE - GAP - BUTTON_SIZE
	)
	_place(_attack, attack_pos, Vector2(BUTTON_SIZE, BUTTON_SIZE))
	_place(_interact, attack_pos - Vector2(BUTTON_SIZE + GAP, 0.0), Vector2(BUTTON_SIZE, BUTTON_SIZE))


func _place(control: Control, pos: Vector2, box: Vector2) -> void:
	control.position = pos
	control.size = box


func _drag_stick(stick: TouchStick, pos: Vector2, is_move: bool) -> void:
	if stick == null:
		return
	var center := stick.get_global_rect().get_center()
	var radius := minf(stick.size.x, stick.size.y) * 0.5
	if radius < 1.0:
		return
	var delta := pos - center
	if delta.length() > radius:
		delta = delta * (radius / delta.length())
	var vector := Vector2(delta.x / radius, -delta.y / radius)
	if is_move:
		set_move_stick(vector)
	else:
		set_aim_stick(vector)


func _hits(control: Control, pos: Vector2) -> bool:
	if control == null or not control.visible:
		return false
	var rect := control.get_global_rect()
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		return false
	var radius := minf(rect.size.x, rect.size.y) * 0.5 + HIT_PADDING
	return rect.get_center().distance_to(pos) <= radius


func _owns_index(index: int) -> bool:
	return (
		index == _move_index
		or index == _aim_index
		or index == _interact_index
		or index == _attack_index
	)


func _release_all() -> void:
	_move_index = -2
	_aim_index = -2
	_interact_index = -2
	_attack_index = -2
	set_move_stick(Vector2.ZERO)
	set_aim_stick(Vector2.ZERO)
	if _interact:
		_interact.set_held(false)
	if _attack:
		_attack.set_held(false)


func _controls_enabled() -> bool:
	var player := _player()
	if player == null:
		return false
	if player.has_method("is_input_locked") and player.is_input_locked():
		return false
	if player.has_method("is_alive") and not player.is_alive():
		return false
	return true


func _player() -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("Player")


func _clamp_stick(stick: Vector2) -> Vector2:
	if stick.length() > 1.0:
		stick = stick.normalized()
	if stick.length() < DEADZONE:
		return Vector2.ZERO
	return stick


class TouchStick extends Control:
	var stick := Vector2.ZERO
	var caption := ""

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func set_stick(value: Vector2) -> void:
		stick = value
		queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 3.0
		if radius < 4.0:
			return
		draw_circle(center, radius, Color(0.008, 0.031, 0.016, 0.58))
		draw_arc(center, radius - 1.5, 0.0, TAU, 64, Color(0.49, 1.0, 0.478, 0.92), 3.0, true)
		var knob_r := radius * 0.36
		var travel := maxf(radius - knob_r - 8.0, 0.0)
		var knob := center + Vector2(stick.x, -stick.y) * travel
		draw_circle(knob, knob_r, Color(0.49, 1.0, 0.478, 0.9))
		draw_arc(knob, maxf(knob_r - 2.0, 1.0), 0.0, TAU, 32, Color(0.91, 0.886, 0.831, 0.95), 2.0, true)
		_draw_caption(center + Vector2(0.0, radius * 0.42), 16)


	func _draw_caption(at: Vector2, font_size: int) -> void:
		if caption.is_empty():
			return
		var font := UiStyle.menu_font()
		var text_size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var baseline := at + Vector2(-text_size.x * 0.5, text_size.y * 0.35)
		draw_string(
			font,
			baseline,
			caption,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color(0.91, 0.886, 0.831, 0.95)
		)


class TouchButton extends Control:
	var caption := ""
	var held := false
	var attack := false

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func set_held(value: bool) -> void:
		if held == value:
			return
		held = value
		queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 3.0
		if radius < 4.0:
			return
		var fill := Color(0.55, 0.16, 0.12, 0.86) if attack else Color(0.09, 0.24, 0.12, 0.86)
		if held:
			fill = fill.lightened(0.28)
		draw_circle(center, radius, fill)
		draw_arc(center, radius - 1.5, 0.0, TAU, 48, Color(0.91, 0.886, 0.831, 0.95), 3.0, true)
		var font := UiStyle.menu_font()
		var font_size := 22
		var text_size := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(
			font,
			center + Vector2(-text_size.x * 0.5, text_size.y * 0.32),
			caption,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color(0.91, 0.886, 0.831, 1.0)
		)
