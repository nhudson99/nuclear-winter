class_name Stairwell
extends Node3D

## Interactable stair landing. Press E nearby to change floors once the
## matching key has dropped the lock in front of the steps.

signal used(stair: Stairwell)

const DIR_UP := "up"
const DIR_DOWN := "down"

@export var interact_range: float = 2.4
@export var direction: String = DIR_UP
@export var required_stage: int = 0
@export var dest_floor: int = 0
@export var dest_cell: Vector2i = Vector2i.ZERO
@export var from_floor: int = 0
@export var from_cell: Vector2i = Vector2i.ZERO

var _unlocked: bool = true


func _ready() -> void:
	add_to_group("stairwell")


func configure(spec: Dictionary) -> void:
	direction = String(spec.get("direction", DIR_UP))
	required_stage = int(spec.get("required_stage", 0))
	dest_floor = int(spec.get("dest_floor", 0))
	dest_cell = spec.get("dest_cell", Vector2i.ZERO)
	from_floor = int(spec.get("floor", 0))
	from_cell = spec.get("cell", Vector2i.ZERO)
	_unlocked = required_stage <= 0
	name = "Stairwell_%s_%d_%d" % [direction, from_cell.x, from_cell.y]


func is_up() -> bool:
	return direction == DIR_UP


func is_down() -> bool:
	return direction == DIR_DOWN


func is_unlocked() -> bool:
	return _unlocked


func unlock() -> void:
	_unlocked = true


func can_interact(from_pos: Vector3) -> bool:
	var to_stair := global_position - from_pos
	to_stair.y = 0.0
	return to_stair.length() <= interact_range


func can_use() -> bool:
	return _unlocked


func try_use() -> bool:
	if not can_use():
		return false
	used.emit(self)
	return true
