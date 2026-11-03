class_name MonsterTracker
extends Node

## Owns the living roster across every floor. Floor swaps no longer despawn
## monsters: each entry keeps its kind, floor, room cell and body, and off-floor
## bodies keep ticking along that floor's monster track.

signal floor_changed(body: CharacterBody3D, from_floor: int, to_floor: int)
signal monster_despawned(body: CharacterBody3D)

var _entries: Dictionary = {} # instance_id -> Dictionary
var _floor_tracks: Dictionary = {} # floor -> track Dictionary
var _floor_rooms: Dictionary = {} # floor -> Array
var _floor_stairs: Dictionary = {} # floor -> Array
var _floor_bounds: Dictionary = {} # floor -> AABB


func clear() -> void:
	_entries.clear()
	_floor_tracks.clear()
	_floor_rooms.clear()
	_floor_stairs.clear()
	_floor_bounds.clear()


func remember_floor_layout(floor: int, layout: Dictionary) -> void:
	_floor_tracks[floor] = layout.get("monster_track", {})
	_floor_rooms[floor] = layout.get("rooms", [])
	_floor_stairs[floor] = layout.get("stairs", [])
	_floor_bounds[floor] = layout.get("bounds", AABB())


func track_for(floor: int) -> Dictionary:
	return _floor_tracks.get(floor, {})


func rooms_for(floor: int) -> Array:
	return _floor_rooms.get(floor, [])


func stairs_for(floor: int) -> Array:
	return _floor_stairs.get(floor, [])


func bounds_for(floor: int) -> AABB:
	return _floor_bounds.get(floor, AABB())


func register(body: CharacterBody3D, kind: String, floor: int, room_cell: Vector2i = Vector2i.ZERO) -> void:
	if body == null or not is_instance_valid(body):
		return
	var id := body.get_instance_id()
	_entries[id] = {
		"body": body,
		"kind": kind,
		"floor": floor,
		"room_cell": room_cell,
		"alive": true,
	}
	if body.has_method("bind_tracker"):
		body.bind_tracker(self)


func unregister(body: CharacterBody3D) -> void:
	if body == null:
		return
	_entries.erase(body.get_instance_id())


func mark_dead(body: CharacterBody3D) -> void:
	if body == null:
		return
	var id := body.get_instance_id()
	if not _entries.has(id):
		return
	var entry: Dictionary = _entries[id]
	entry["alive"] = false
	_entries[id] = entry
	monster_despawned.emit(body)


func set_floor(body: CharacterBody3D, floor: int) -> void:
	if body == null:
		return
	var id := body.get_instance_id()
	if not _entries.has(id):
		return
	var entry: Dictionary = _entries[id]
	var previous := int(entry.get("floor", 0))
	if previous == floor:
		return
	entry["floor"] = floor
	_entries[id] = entry
	if body.has_method("on_tracker_floor_changed"):
		body.on_tracker_floor_changed(floor, track_for(floor), rooms_for(floor), bounds_for(floor))
	floor_changed.emit(body, previous, floor)


func get_floor(body: CharacterBody3D) -> int:
	if body == null:
		return 0
	var entry = _entries.get(body.get_instance_id(), null)
	if entry == null:
		return 0
	return int(entry.get("floor", 0))


func set_room(body: CharacterBody3D, cell: Vector2i) -> void:
	if body == null:
		return
	var id := body.get_instance_id()
	if not _entries.has(id):
		return
	var entry: Dictionary = _entries[id]
	entry["room_cell"] = cell
	_entries[id] = entry


func get_room(body: CharacterBody3D) -> Vector2i:
	if body == null:
		return Vector2i.ZERO
	var entry = _entries.get(body.get_instance_id(), null)
	if entry == null:
		return Vector2i.ZERO
	return entry.get("room_cell", Vector2i.ZERO)


func get_kind(body: CharacterBody3D) -> String:
	if body == null:
		return ""
	var entry = _entries.get(body.get_instance_id(), null)
	if entry == null:
		return ""
	return String(entry.get("kind", ""))


func is_alive(body: CharacterBody3D) -> bool:
	if body == null:
		return false
	var entry = _entries.get(body.get_instance_id(), null)
	if entry == null:
		return false
	return bool(entry.get("alive", false))


func all_bodies() -> Array[CharacterBody3D]:
	var out: Array[CharacterBody3D] = []
	_prune()
	for id in _entries:
		var entry: Dictionary = _entries[id]
		var body: CharacterBody3D = entry.get("body")
		if body != null and is_instance_valid(body):
			out.append(body)
	return out


func alive_bodies() -> Array[CharacterBody3D]:
	var out: Array[CharacterBody3D] = []
	for body in all_bodies():
		var entry: Dictionary = _entries[body.get_instance_id()]
		if bool(entry.get("alive", false)):
			out.append(body)
	return out


func monsters_on_floor(floor: int) -> Array[CharacterBody3D]:
	var out: Array[CharacterBody3D] = []
	for body in alive_bodies():
		if get_floor(body) == floor:
			out.append(body)
	return out


func entries() -> Array:
	_prune()
	var out: Array = []
	for id in _entries:
		out.append((_entries[id] as Dictionary).duplicate())
	return out


func sync_active_floor(active_floor: int) -> void:
	for body in all_bodies():
		var on_floor := get_floor(body) == active_floor
		if body.has_method("set_off_floor"):
			body.set_off_floor(not on_floor)
		else:
			body.visible = on_floor
			body.set_physics_process(true)


func _prune() -> void:
	var doomed: Array[int] = []
	for id in _entries:
		var entry: Dictionary = _entries[id]
		var body: CharacterBody3D = entry.get("body")
		if body == null or not is_instance_valid(body):
			doomed.append(int(id))
	for id in doomed:
		_entries.erase(id)
