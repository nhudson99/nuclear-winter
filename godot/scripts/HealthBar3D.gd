extends Node3D
class_name HealthBar3D

## Billboard HP bar that floats above a character.

@export var bar_width_px: int = 128
@export var bar_height_px: int = 18
@export var world_pixel_size: float = 0.012
@export var fill_color: Color = Color(0.2, 0.85, 0.35, 1.0)
@export var background_color: Color = Color(0.1, 0.1, 0.12, 1.0)
@export var border_color: Color = Color(0.02, 0.02, 0.03, 1.0)

var _sprite: Sprite3D
var _max_health: float = 100.0
var _current_health: float = 100.0

func _ready() -> void:
	_sprite = Sprite3D.new()
	_sprite.name = "BarSprite"
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.shaded = false
	_sprite.double_sided = true
	_sprite.no_depth_test = true
	_sprite.pixel_size = world_pixel_size
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.render_priority = 20
	add_child(_sprite)
	_redraw()

func set_health(current: float, maximum: float = -1.0) -> void:
	if maximum > 0.0:
		_max_health = maximum
	_current_health = clampf(current, 0.0, _max_health)
	_redraw()

func _redraw() -> void:
	if _sprite == null:
		return
	var ratio := 0.0 if _max_health <= 0.0 else clampf(_current_health / _max_health, 0.0, 1.0)
	var img := Image.create(bar_width_px, bar_height_px, false, Image.FORMAT_RGBA8)
	img.fill(border_color)
	var inner := Rect2i(2, 2, bar_width_px - 4, bar_height_px - 4)
	for y in range(inner.position.y, inner.position.y + inner.size.y):
		for x in range(inner.position.x, inner.position.x + inner.size.x):
			img.set_pixel(x, y, background_color)
	var fill_w := int(float(inner.size.x) * ratio)
	for y in range(inner.position.y, inner.position.y + inner.size.y):
		for x in range(inner.position.x, inner.position.x + fill_w):
			img.set_pixel(x, y, fill_color)
	_sprite.texture = ImageTexture.create_from_image(img)
