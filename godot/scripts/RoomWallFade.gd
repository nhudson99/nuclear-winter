class_name RoomWallFade
extends Node

## Fades the near walls of the room the player is standing in. The isometric
## camera keeps a fixed yaw, so those are the one or two sides whose outward
## face points toward the lens. Leaving the room restores them.

## How see-through a near wall becomes. 1 cuts it away.
@export_range(0.0, 1.0, 0.01) var occluder_fade: float = 0.9
## How quickly a wall fades in and back.
@export_range(1.0, 24.0, 0.1) var fade_smooth: float = 10.0
## Props within this many metres of a side's outer plane count as that wall.
@export_range(0.4, 2.5, 0.05) var wall_band: float = 1.35

const SIDES: PackedStringArray = ["N", "S", "E", "W"]
const FLOOR_PREFIXES: PackedStringArray = [
	"Floor",
	"NoCol_Floor",
	"NoCol_Debris",
	"NoCol_Doormat",
	"NoCol_FloorRug",
	"Ground",
]
## Outward normals. North is -Z, matching MapGenerator.
const _NORMALS := {
	"N": Vector3(0.0, 0.0, -1.0),
	"S": Vector3(0.0, 0.0, 1.0),
	"E": Vector3(1.0, 0.0, 0.0),
	"W": Vector3(-1.0, 0.0, 0.0),
}

var _map_sig: String = ""
var _rooms: Array[Dictionary] = []
var _fade_now: Dictionary = {}
var _fade_shadow: Dictionary = {}
var _fade_geom: Dictionary = {}


func invalidate() -> void:
	_map_sig = ""
	_rooms.clear()


func update_fade(delta: float) -> void:
	var main := get_parent()
	if main == null:
		return
	var player := main.get_node_or_null("Player") as Node3D
	var camera := main.get_node_or_null("IsoCamera") as Camera3D
	var map := main.get_node_or_null("GeneratedMap")
	var desired: Dictionary = {}
	if player != null and camera != null and map != null:
		_rebuild(map)
		var room := _room_containing(player.global_position)
		if not room.is_empty():
			var toward := camera.global_position - player.global_position
			toward.y = 0.0
			if toward.length_squared() > 0.01:
				toward = toward.normalized()
				var shells: Dictionary = room["explicit"]
				for side in SIDES:
					var normal: Vector3 = _NORMALS[side]
					if normal.dot(toward) <= 0.2:
						continue
					for geom in shells[side]:
						_mark(desired, geom)
					for prop in room["props"]:
						var local: Vector3 = prop["local"]
						if _in_wall_band(local, side):
							_mark(desired, prop["geom"])
	_blend(desired, delta)


func _room_containing(point: Vector3) -> Dictionary:
	var half := MapGenerator.TILE * 0.5
	var best: Dictionary = {}
	var best_d := INF
	for room in _rooms:
		var node := room["node"] as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var origin := node.global_position
		var dx := absf(point.x - origin.x)
		var dz := absf(point.z - origin.z)
		if dx > half or dz > half:
			continue
		var dist := dx * dx + dz * dz
		if dist < best_d:
			best_d = dist
			best = room
	return best


func _rebuild(map: Node) -> void:
	var sig := _signature(map)
	if sig == _map_sig and not _rooms.is_empty():
		var sample: Object = _rooms[0]["node"]
		if is_instance_valid(sample):
			return
	_map_sig = sig
	_rooms.clear()
	for child in map.get_children():
		if not (child is Node3D):
			continue
		if MapGenerator.find_child_by_name(child, "Wall_N_A") == null:
			continue
		var explicit := {}
		for side in SIDES:
			var geoms: Array[GeometryInstance3D] = []
			for node_name in _shell_names(side):
				var found := MapGenerator.find_child_by_name(child, node_name)
				if found != null:
					_collect_geoms(found, geoms)
			explicit[side] = geoms
		var props: Array[Dictionary] = []
		var meshes: Array[MeshInstance3D] = []
		_collect_meshes(child, meshes)
		var room := child as Node3D
		for mi in meshes:
			if mi.mesh == null or _is_floor_name(String(mi.name)):
				continue
			var size := mi.get_aabb().size
			if size.x > 8.0 and size.z > 8.0:
				continue
			var aabb := mi.global_transform * mi.get_aabb()
			props.append({
				"geom": mi,
				"local": room.to_local(aabb.get_center()),
			})
		_rooms.append({
			"node": room,
			"explicit": explicit,
			"props": props,
		})


func _signature(map: Node) -> String:
	var parts := PackedStringArray()
	parts.append(str(map.get_child_count()))
	for child in map.get_children():
		parts.append("%s#%d" % [String(child.name), child.get_instance_id()])
	return ",".join(parts)


func _shell_names(side: String) -> PackedStringArray:
	var names := PackedStringArray()
	names.append("Wall_%s_A" % side)
	names.append("Wall_%s_B" % side)
	names.append("Wall_%s_L" % side)
	names.append("Plug_%s" % side)
	for index in 4:
		names.append("NoCol_Wallpaper_%s%d" % [side, index])
	return names


func _in_wall_band(local: Vector3, side: String) -> bool:
	var half := MapGenerator.TILE * 0.5
	var inner := half - wall_band
	var limit := half + 0.35
	if side == "N":
		return local.z <= -inner and absf(local.x) <= limit
	if side == "S":
		return local.z >= inner and absf(local.x) <= limit
	if side == "E":
		return local.x >= inner and absf(local.z) <= limit
	if side == "W":
		return local.x <= -inner and absf(local.z) <= limit
	return false


func _mark(desired: Dictionary, geom: GeometryInstance3D) -> void:
	if geom == null or not is_instance_valid(geom):
		return
	desired[geom.get_instance_id()] = geom


func _blend(desired: Dictionary, delta: float) -> void:
	var weight := clampf(1.0 - exp(-fade_smooth * delta), 0.0, 1.0)
	var ids: Dictionary = {}
	for id in desired:
		ids[id] = true
	for id in _fade_now:
		ids[id] = true
	var drop: Array[int] = []
	for id in ids:
		var geom: GeometryInstance3D = desired.get(id, _fade_geom.get(id)) as GeometryInstance3D
		if geom == null or not is_instance_valid(geom):
			drop.append(int(id))
			continue
		var target := occluder_fade if desired.has(id) else 0.0
		var current: float = float(_fade_now.get(id, 0.0))
		current = lerpf(current, target, weight)
		if not _fade_shadow.has(id):
			_fade_shadow[id] = geom.cast_shadow
		geom.transparency = current
		if current > 0.04:
			geom.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			geom.cast_shadow = int(_fade_shadow[id])
		_fade_now[id] = current
		_fade_geom[id] = geom
		if target <= 0.0 and current < 0.012:
			geom.transparency = 0.0
			geom.cast_shadow = int(_fade_shadow[id])
			drop.append(int(id))
	for id in drop:
		_fade_now.erase(id)
		_fade_shadow.erase(id)
		_fade_geom.erase(id)


func _is_floor_name(node_name: String) -> bool:
	for prefix in FLOOR_PREFIXES:
		if node_name == prefix or node_name.begins_with(prefix):
			return true
	return false


func _collect_geoms(node: Node, into: Array[GeometryInstance3D]) -> void:
	if node is GeometryInstance3D:
		into.append(node)
	for child in node.get_children():
		_collect_geoms(child, into)


func _collect_meshes(node: Node, into: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		into.append(node)
	for child in node.get_children():
		_collect_meshes(child, into)
