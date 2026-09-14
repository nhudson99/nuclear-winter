class_name WebField
extends RefCounted

## Shared lookup for tarantula webs. Player speed is cut by 75% inside a
## finished web; tarantulas gain 25% move speed in any web.

const PLAYER_REMAINING := 0.25
const TARANTULA_BONUS := 1.25
const GROUP := "room_web"


static func webs_in(tree: SceneTree) -> Array:
	if tree == null:
		return []
	return tree.get_nodes_in_group(GROUP)


static func covers_point(tree: SceneTree, pos: Vector3) -> bool:
	for node in webs_in(tree):
		if not is_instance_valid(node):
			continue
		if node.has_method("covers_point") and node.covers_point(pos):
			return true
	return false


static func is_cell_webbed(tree: SceneTree, cell: Vector2i) -> bool:
	for node in webs_in(tree):
		if not is_instance_valid(node):
			continue
		if node.get("room_cell") == cell and bool(node.get("is_complete")):
			return true
	return false


static func player_speed_scale(body: Node3D) -> float:
	if body == null or not body.is_inside_tree():
		return 1.0
	if covers_point(body.get_tree(), body.global_position):
		return PLAYER_REMAINING
	return 1.0


static func tarantula_speed_scale(body: Node3D) -> float:
	if body == null or not body.is_inside_tree():
		return 1.0
	if covers_point(body.get_tree(), body.global_position):
		return TARANTULA_BONUS
	return 1.0
