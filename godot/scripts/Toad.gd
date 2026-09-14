extends "res://scripts/Monster.gd"

## Easy, passive scavenger. It hops room to room, spends `search_duration`
## seconds looking for the mission item, and swallows it if the item is in
## that room. The item stays in its belly until the toad dies.

@export var search_duration: float = 10.0

var _searching: bool = false
var _search_elapsed: float = 0.0
var _swallowed: PickupItem
var _visited: Dictionary = {}


func _ready() -> void:
	super._ready()
	add_to_group("toad")
	touch_damage = 0.0


func is_searching() -> bool:
	return _searching


func has_mission_item() -> bool:
	return (
		_swallowed != null
		and is_instance_valid(_swallowed)
		and _swallowed.is_swallowed()
	)


func release_swallowed_item() -> void:
	_regurgitate()


func get_search_progress() -> float:
	if not _searching or search_duration <= 0.0:
		return 0.0
	return clampf(_search_elapsed / search_duration, 0.0, 1.0)


func get_ai_mode_name() -> String:
	if _searching and _ai_mode == AiMode.PATROL:
		return "search"
	return "patrol"


func _can_see_player() -> bool:
	return false


func _is_player_in_proximity() -> bool:
	return false


func _allows_chase() -> bool:
	return false


func _on_level_configured() -> void:
	_searching = false
	_search_elapsed = 0.0
	_visited.clear()
	_begin_search_here()


func _on_died() -> void:
	_regurgitate()


func _patrol(delta: float) -> void:
	if _track_nodes.is_empty():
		velocity.x = 0.0
		velocity.z = 0.0
		_animate_walk(_walk_phase, 0.0)
		return

	if _searching:
		_tick_search(delta)
		return

	if _target_node_id.is_empty() or not _track_nodes.has(_target_node_id):
		_choose_patrol_target()

	var to_target := _patrol_target - global_position
	to_target.y = 0.0
	if to_target.length() <= room_arrive_distance:
		_came_from_id = _current_node_id
		_current_node_id = _target_node_id
		if _is_room_node(_current_node_id) and _begin_search_here():
			return
		_choose_patrol_target()
		if _target_node_id == _current_node_id:
			velocity.x = 0.0
			velocity.z = 0.0
			_animate_walk(_walk_phase, 0.0)
			return

	_move_toward(_patrol_target, delta)


func _choose_patrol_target() -> void:
	if _track_nodes.is_empty():
		_target_node_id = ""
		_patrol_target = global_position
		return
	if _current_node_id.is_empty() or not _track_nodes.has(_current_node_id):
		_current_node_id = _nearest_node_id(global_position)
	var dest_id := _next_search_room_id()
	if dest_id.is_empty():
		super._choose_patrol_target()
		return
	if dest_id == _current_node_id:
		_target_node_id = dest_id
		_patrol_target = _track_nodes[dest_id]["position"]
		return
	var start_id := _nearest_node_id(global_position)
	var path := _bfs_path(start_id, dest_id)
	var next_id := dest_id
	if path.size() >= 2:
		next_id = path[1]
	elif path.size() == 1:
		next_id = path[0]
	if next_id.is_empty() or not _track_nodes.has(next_id):
		super._choose_patrol_target()
		return
	_target_node_id = next_id
	_patrol_target = _track_nodes[next_id]["position"]


func _begin_search_here() -> bool:
	var room_id := _current_room_id()
	if room_id.is_empty():
		return false
	_searching = true
	_search_elapsed = 0.0
	_current_node_id = room_id
	_target_node_id = room_id
	_patrol_target = _track_nodes[room_id]["position"]
	_visited[room_id] = true
	velocity.x = 0.0
	velocity.z = 0.0
	_animate_walk(_walk_phase, 0.0)
	return true


func _tick_search(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_search_elapsed += delta
	if visual:
		visual.rotation.y += delta * 0.55
		visual.position.y = 0.02 * absf(sin(_search_elapsed * 3.0))
	_animate_walk(_walk_phase, 0.0)
	if not has_mission_item():
		_try_swallow_item()
	if _search_elapsed >= search_duration:
		_finish_search()


func _finish_search() -> void:
	_searching = false
	_search_elapsed = 0.0
	if visual:
		visual.position.y = 0.0
	if not has_mission_item():
		_try_swallow_item()
	_choose_patrol_target()


func _try_swallow_item() -> void:
	if has_mission_item():
		return
	var item := _mission_in_current_room()
	if item == null or not item.has_method("swallow"):
		return
	if item.swallow():
		_swallowed = item


func _regurgitate() -> void:
	if _swallowed == null or not is_instance_valid(_swallowed):
		_swallowed = null
		return
	if _swallowed.has_method("release_at"):
		_swallowed.release_at(global_position + Vector3(0.0, 0.05, 0.0))
	_swallowed = null


func _mission_in_current_room() -> PickupItem:
	if not is_inside_tree():
		return null
	var room_id := _current_room_id()
	if room_id.is_empty() or not _track_nodes.has(room_id):
		return null
	var center: Vector3 = _track_nodes[room_id]["position"]
	var half := MapGenerator.TILE * 0.48
	for node in get_tree().get_nodes_in_group("pickup"):
		if not (node is PickupItem):
			continue
		var item := node as PickupItem
		if not item.is_mission_item() or item.is_taken() or item.is_swallowed():
			continue
		if (
			absf(item.global_position.x - center.x) <= half
			and absf(item.global_position.z - center.z) <= half
		):
			return item
	return null


func _current_room_id() -> String:
	if _is_room_node(_current_node_id):
		return _current_node_id
	var nearest := _nearest_room_id(global_position)
	if nearest.is_empty():
		return ""
	_current_node_id = nearest
	return nearest


func _is_room_node(node_id: String) -> bool:
	if node_id.is_empty() or not _track_nodes.has(node_id):
		return false
	return String(_track_nodes[node_id].get("kind", "")) == "room"


func _nearest_room_id(pos: Vector3) -> String:
	var best_id := ""
	var best := INF
	for id in _track_nodes:
		if not _is_room_node(String(id)):
			continue
		var node_pos: Vector3 = _track_nodes[id]["position"]
		var d := Vector2(pos.x - node_pos.x, pos.z - node_pos.z).length()
		if d < best:
			best = d
			best_id = String(id)
	return best_id


func _next_search_room_id() -> String:
	var best_unvisited := ""
	var best_unvisited_d := INF
	var best_any := ""
	var best_any_d := INF
	for id in _track_nodes:
		if not _is_room_node(String(id)):
			continue
		if String(id) == _current_node_id:
			continue
		var node_pos: Vector3 = _track_nodes[id]["position"]
		var d := Vector2(global_position.x - node_pos.x, global_position.z - node_pos.z).length()
		if d < best_any_d:
			best_any_d = d
			best_any = String(id)
		if _visited.has(String(id)):
			continue
		if d < best_unvisited_d:
			best_unvisited_d = d
			best_unvisited = String(id)
	if not best_unvisited.is_empty():
		return best_unvisited
	if _visited.size() >= _room_count():
		_visited.clear()
	return best_any


func _room_count() -> int:
	var n := 0
	for id in _track_nodes:
		if _is_room_node(String(id)):
			n += 1
	return n


func debug_finish_search() -> void:
	if not _searching:
		_begin_search_here()
	_search_elapsed = search_duration
	_finish_search()
