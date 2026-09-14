extends "res://scripts/Monster.gd"

## Medium spider that webs rooms for 30 seconds, then moves on. Players are
## slowed 75% in finished webs. The tarantula itself is 25% faster on silk
## and will still chase a seen player off the web. Losing focus sends it to
## the nearest unwebbed room to spin a new one.

@export var weave_duration: float = 30.0
@export var web_move_bonus: float = 0.25

var _weaving: bool = false
var _weave_elapsed: float = 0.0
var _weave_cell: Vector2i = Vector2i.ZERO
var _weave_center: Vector3 = Vector3.ZERO
var _growing_web: RoomWeb
var _travel_room_id: String = ""


func _ready() -> void:
	super._ready()
	add_to_group("tarantula")


func is_weaving() -> bool:
	return _weaving


func get_weave_progress() -> float:
	if not _weaving or weave_duration <= 0.0:
		return 0.0
	return clampf(_weave_elapsed / weave_duration, 0.0, 1.0)


func debug_finish_weave() -> void:
	if not _weaving:
		_start_weave_at_current_room()
	_weave_elapsed = weave_duration
	_finish_weave()


func get_ai_mode_name() -> String:
	if _weaving and _ai_mode == AiMode.PATROL:
		return "weave"
	return super.get_ai_mode_name()


func _effective_move_speed() -> float:
	var speed := move_speed
	if is_inside_tree() and WebField.covers_point(get_tree(), global_position):
		speed *= 1.0 + web_move_bonus
	return speed


func _on_level_configured() -> void:
	_abandon_weave(false)
	_start_weave_at_current_room()


func _on_started_chase() -> void:
	_abandon_weave(false)


func _begin_return_to_track() -> void:
	_abandon_weave(false)
	_ai_mode = AiMode.RETURN
	_return_node_id = _nearest_unwebbed_room_id(global_position)
	if _return_node_id.is_empty():
		_return_node_id = _nearest_node_id(global_position)


func _on_returned_to_track() -> void:
	if _start_weave_at_current_room():
		return
	_choose_patrol_target()


func _patrol(delta: float) -> void:
	if _track_nodes.is_empty():
		velocity.x = 0.0
		velocity.z = 0.0
		_animate_walk(_walk_phase, 0.0)
		return

	if _weaving:
		_tick_weave(delta)
		return

	if _target_node_id.is_empty() or not _track_nodes.has(_target_node_id):
		_choose_patrol_target()

	var to_target := _patrol_target - global_position
	to_target.y = 0.0
	if to_target.length() <= room_arrive_distance:
		_came_from_id = _current_node_id
		_current_node_id = _target_node_id
		if _is_room_node(_current_node_id) and _start_weave_at_current_room():
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
	var dest_id := _nearest_unwebbed_room_id(global_position)
	if dest_id.is_empty():
		super._choose_patrol_target()
		_travel_room_id = ""
		return
	_travel_room_id = dest_id
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


func _start_weave_at_current_room() -> bool:
	var room_id := _current_room_id()
	if room_id.is_empty():
		return false
	var cell: Vector2i = _track_nodes[room_id].get("cell", Vector2i.ZERO)
	if WebField.is_cell_webbed(get_tree() if is_inside_tree() else null, cell):
		return false
	_weaving = true
	_weave_elapsed = 0.0
	_weave_cell = cell
	_weave_center = _track_nodes[room_id]["position"]
	_current_node_id = room_id
	_target_node_id = room_id
	_patrol_target = _weave_center
	_spawn_growing_web()
	velocity.x = 0.0
	velocity.z = 0.0
	_animate_walk(_walk_phase, 0.0)
	return true


func _tick_weave(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_weave_elapsed += delta
	if visual:
		visual.rotation.y += delta * 0.7
		visual.position.y = 0.03 * absf(sin(_weave_elapsed * 4.0))
	_animate_walk(_walk_phase, 0.15)
	if _growing_web and is_instance_valid(_growing_web):
		_growing_web.set_progress(get_weave_progress())
	if _weave_elapsed >= weave_duration:
		_finish_weave()


func _finish_weave() -> void:
	if _growing_web and is_instance_valid(_growing_web):
		_growing_web.set_progress(1.0)
		_growing_web = null
	else:
		_spawn_finished_web(_weave_cell, _weave_center)
	_weaving = false
	_weave_elapsed = 0.0
	if visual:
		visual.position.y = 0.0
	_choose_patrol_target()


func _abandon_weave(keep_partial: bool) -> void:
	if _growing_web and is_instance_valid(_growing_web) and not keep_partial:
		_growing_web.queue_free()
	_growing_web = null
	_weaving = false
	_weave_elapsed = 0.0
	if visual:
		visual.position.y = 0.0


func _spawn_growing_web() -> void:
	if _growing_web and is_instance_valid(_growing_web):
		return
	_growing_web = _make_web(_weave_cell, _weave_center, 0.05)


func _spawn_finished_web(cell: Vector2i, center: Vector3) -> void:
	if WebField.is_cell_webbed(get_tree() if is_inside_tree() else null, cell):
		return
	_make_web(cell, center, 1.0)


func _make_web(cell: Vector2i, center: Vector3, progress: float) -> RoomWeb:
	var host := _web_host()
	if host == null:
		return null
	var web := RoomWeb.new()
	web.name = "Web_%d_%d" % [cell.x, cell.y]
	host.add_child(web)
	web.configure(cell, center, progress)
	return web


func _web_host() -> Node:
	var main := get_parent()
	if main == null:
		return null
	var map_root: Node = main.get_node_or_null("GeneratedMap")
	if map_root == null:
		return main
	var webs := map_root.get_node_or_null("Webs")
	if webs == null:
		webs = Node3D.new()
		webs.name = "Webs"
		map_root.add_child(webs)
	return webs


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


func _nearest_unwebbed_room_id(pos: Vector3) -> String:
	var tree := get_tree() if is_inside_tree() else null
	var best_id := ""
	var best := INF
	for id in _track_nodes:
		if not _is_room_node(String(id)):
			continue
		var cell: Vector2i = _track_nodes[id].get("cell", Vector2i.ZERO)
		if WebField.is_cell_webbed(tree, cell):
			continue
		var node_pos: Vector3 = _track_nodes[id]["position"]
		var d := Vector2(pos.x - node_pos.x, pos.z - node_pos.z).length()
		if String(id) == _current_node_id and _weaving:
			d += 1000.0
		if d < best:
			best = d
			best_id = String(id)
	return best_id
