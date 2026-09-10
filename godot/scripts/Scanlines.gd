extends Control

## CRT scanline overlay drawn on top of the pip-boy map.

@export var line_color := Color(0.0, 0.066, 0.0)
@export var spacing := 3.0
@export var thickness := 1.0

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var y := 0.0
	while y < size.y:
		draw_rect(Rect2(0.0, y, size.x, thickness), line_color)
		y += spacing
