class_name SecretBookshelf
extends Node3D

## Invisible interactable on one library bookcase. No glow, no marker, no
## prompt — the player has to hunt the stacks and press E / USE on the right shelf.

signal activated(bookshelf: SecretBookshelf)

@export var interact_range: float = 2.4

var _used: bool = false
var _bookcase: Node3D


func _ready() -> void:
	add_to_group("secret_bookshelf")


func configure(bookcase: Node3D) -> void:
	_bookcase = bookcase
	if bookcase != null:
		global_position = bookcase.global_position


func is_used() -> bool:
	return _used


func can_interact(from_pos: Vector3) -> bool:
	if _used:
		return false
	return interact_distance(from_pos) <= interact_range


func interact_distance(from_pos: Vector3) -> float:
	var to_shelf := global_position - from_pos
	to_shelf.y = 0.0
	return to_shelf.length()


func try_activate() -> bool:
	if _used:
		return false
	_used = true
	activated.emit(self)
	return true
