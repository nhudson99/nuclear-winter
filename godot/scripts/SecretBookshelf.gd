class_name SecretBookshelf
extends Node3D

## Invisible interactable on a library bookcase. No glow, no marker, no
## prompt — the player has to hunt the stacks and press E / USE. Most shelves
## are empty; one hides the lever that opens the wing LockedDoor.

signal activated(bookshelf: SecretBookshelf)

@export var interact_range: float = 2.4

var _used: bool = false
var _holds_lever: bool = false
var _bookcase: Node3D


func _ready() -> void:
	add_to_group("secret_bookshelf")


func configure(bookcase: Node3D, holds_lever: bool = false) -> void:
	_bookcase = bookcase
	_holds_lever = holds_lever
	if bookcase != null:
		global_position = bookcase.global_position


func holds_lever() -> bool:
	return _holds_lever


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


## Returns true only when this shelf hid the lever. Empty shelves still mark
## themselves searched so the player can keep hunting the stacks.
func try_activate() -> bool:
	if _used:
		return false
	_used = true
	if not _holds_lever:
		return false
	activated.emit(self)
	return true
