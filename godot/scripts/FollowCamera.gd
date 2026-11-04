class_name FollowCamera
extends Camera3D

## Third-person isometric follow. The lens stays behind the player's facing at
## a fixed elevated pitch and eases its yaw to match. It has no look of its
## own: aim input turns the body, and releasing aim leaves that facing in
## place. Orthographic size is unchanged (`Camera3D.size`); distance only
## places the lens, it does not zoom.
##
## A wall side fades when it separates the lens from the player. Each side X
## is the shell pieces the rooms already ship: Wall_X_A, Wall_X_B, Wall_X_L,
## Plug_X, and NoCol_Wallpaper_X0..X3. Untagged wall props (rungs, rugs,
## baseboards, future hiding furniture) join that side by sitting near the
## wall plane of the 12 m room. A segment test only catches a mesh the named
## pass missed.

## Elevation of the view above the horizontal. The inspector slider stays in
## the isometric band.
@export_range(35.0, 45.0, 0.5) var pitch_degrees: float = 40.0
## Slant range from the look point back to the lens, in metres.
@export_range(4.0, 18.0, 0.1) var follow_distance: float = 11.0
## Look-at height above the player's feet.
@export_range(0.4, 2.2, 0.05) var look_height: float = 1.15
## Eases only a large yaw gap (a teleport). While the body turns, the lens
## stays locked behind it, so releasing aim does not leave the view swinging.
@export_range(1.0, 40.0, 0.1) var yaw_smooth: float = 14.0
## How quickly the lens catches the orbit point while the player runs.
@export_range(1.0, 24.0, 0.1) var position_smooth: float = 12.0
## How see-through a blocking wall becomes. 1 cuts it away.
@export_range(0.0, 1.0, 0.01) var occluder_fade: float = 0.9
## How quickly a wall fades in and back.
@export_range(1.0, 24.0, 0.1) var fade_smooth: float = 10.0
## Props within this many metres of a side's outer plane count as that wall.
## Rooms are 12 m across and centred on their node.
@export_range(0.4, 2.5, 0.05) var wall_band: float = 1.35
## Radians of yaw per pixel of mouse motion while the flashlight button is held.
@export_range(0.001, 0.012, 0.0005) var mouse_look_sensitivity: float = 0.0035

@export var player_path: NodePath = NodePath("../Player")
@export var map_path: NodePath = NodePath("../GeneratedMap")

const SIDES: PackedStringArray = ["N", "S", "E", "W"]
const FLOOR_PREFIXES: PackedStringArray = [
	"Floor",
	"NoCol_Floor",
	"NoCol_Debris",
	"NoCol_Doormat",
	"NoCol_FloorRug",
	"Ground",
]
const _BLOCKER_GROUPS: PackedStringArray = [
	"locked_door",
	"steam_barrier",
	"library_door",
	"secret_bookshelf",
	"player",
	"monster",
]

var _yaw: float = 0.0
var _has_yaw: bool = false
var _smooth_focus: Vector3 = Vector3.ZERO
var _has_focus: bool = false
var _map_sig: String = ""
var _rooms: Array[Dictionary] = []
var _safety_meshes: Array[MeshInstance3D] = []
var _fade_now: Dictionary = {}
var _fade_shadow: Dictionary = {}
var _fade_geom: Dictionary = {}


func _ready() -> void:
	current = true
	if projection != PROJECTION_ORTHOGONAL:
		projection = PROJECTION_ORTHOGONAL


func snap() -> void:
	var player := _player()
	if player == null:
		return
	_yaw = _visual_yaw(player)
	_has_yaw = true
	var focus := _focus_point(player)
	_smooth_focus = focus
	_has_focus = true
	global_position = _orbit_position(focus, _yaw)
	if global_position.distance_squared_to(focus) > 0.0001:
		look_at(focus, Vector3.UP)


func invalidate_occluders() -> void:
	_map_sig = ""
	_rooms.clear()
	_safety_meshes.clear()


func _physics_process(delta: float) -> void:
	var player := _player()
	if player == null:
		return
	var target_yaw := _visual_yaw(player)
	if not _has_yaw:
		_yaw = target_yaw
		_has_yaw = true
	else:
		var gap := absf(angle_difference(target_yaw, _yaw))
		# A stick or mouse step is well under this. Locking those keeps the
		# lens on the body when aim is released. Bigger gaps still ease in.
		if gap <= deg_to_rad(40.0):
			_yaw = target_yaw
		else:
			var yaw_t := 1.0 - exp(-yaw_smooth * delta)
			_yaw = lerp_angle(_yaw, target_yaw, clampf(yaw_t, 0.0, 1.0))
	var focus := _focus_point(player)
	# Ease the point we look at when the player runs. The behind-offset is
	# applied after that, so turning does not drag the lens around the arc
	# after aim is released.
	if not _has_focus:
		_smooth_focus = focus
		_has_focus = true
	else:
		var pos_t := 1.0 - exp(-position_smooth * delta)
		_smooth_focus = _smooth_focus.lerp(focus, clampf(pos_t, 0.0, 1.0))
	global_position = _orbit_position(_smooth_focus, _yaw)
	if global_position.distance_squared_to(_smooth_focus) > 0.0001:
		look_at(_smooth_focus, Vector3.UP)
	_fade_occluders(delta, player.global_position, focus)


func _player() -> Node3D:
	var node := get_node_or_null(player_path)
	if node is Node3D:
		return node
	return null


func _map() -> Node:
	return get_node_or_null(map_path)


func _visual_yaw(player: Node3D) -> float:
	var visual := player.get_node_or_null("Model") as Node3D
	if visual == null:
		return player.global_rotation.y
	return visual.global_rotation.y


func _focus_point(player: Node3D) -> Vector3:
	return player.global_position + Vector3(0.0, look_height, 0.0)


func _orbit_position(focus: Vector3, yaw: float) -> Vector3:
	var pitch := deg_to_rad(clampf(pitch_degrees, 35.0, 45.0))
	var horiz := follow_distance * cos(pitch)
	var height := follow_distance * sin(pitch)
	# Facing at yaw 0 looks down -Z, so the lens sits on +Z.
	var behind := Vector3(sin(yaw), 0.0, cos(yaw))
	return focus + behind * horiz + Vector3(0.0, height, 0.0)


func _fade_occluders(delta: float, player_pos: Vector3, focus: Vector3) -> void:
	var desired: Dictionary = {}
	var map := _map()
	_rebuild_cache(map)
	for room in _rooms:
		var node := room["node"] as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var origin := node.global_position
		for side in SIDES:
			if not _side_between(global_position, player_pos, origin, side):
				continue
			for geom in room["explicit"][side]:
				_mark(desired, geom)
			for prop in room["props"]:
				var local: Vector3 = prop["local"]
				if _in_wall_band(local, side):
					_mark(desired, prop["geom"])
	_safety_fade(global_position, focus, desired)
	_blend_fades(desired, delta)


func _mark(desired: Dictionary, geom: GeometryInstance3D) -> void:
	if geom == null or not is_instance_valid(geom):
		return
	desired[geom.get_instance_id()] = geom


func _rebuild_cache(map: Node) -> void:
	var sig := _map_signature(map)
	if sig == _map_sig and not _rooms.is_empty():
		return
	_map_sig = sig
	_rooms.clear()
	_safety_meshes.clear()
	if map == null:
		return
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
			if mi.mesh == null or _is_floor_name(String(mi.name)) or _too_broad(mi):
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
	_collect_meshes(map, _safety_meshes)


func _map_signature(map: Node) -> String:
	if map == null:
		return ""
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


func _side_between(cam: Vector3, player_pos: Vector3, origin: Vector3, side: String) -> bool:
	var half := MapGenerator.TILE * 0.5
	var along_z := side == "N" or side == "S"
	var plane := 0.0
	if side == "N":
		plane = origin.z - half
	elif side == "S":
		plane = origin.z + half
	elif side == "E":
		plane = origin.x + half
	elif side == "W":
		plane = origin.x - half
	else:
		return false
	var cam_axis := cam.z if along_z else cam.x
	var player_axis := player_pos.z if along_z else player_pos.x
	if (cam_axis - plane) * (player_axis - plane) >= 0.0:
		return false
	var span := cam_axis - player_axis
	if absf(span) < 0.0001:
		return false
	var t := (plane - player_axis) / span
	var cross := lerpf(player_pos.x if along_z else player_pos.z, cam.x if along_z else cam.z, t)
	var cross_origin := origin.x if along_z else origin.z
	return absf(cross - cross_origin) <= half + 0.4


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


func _safety_fade(cam: Vector3, focus: Vector3, desired: Dictionary) -> void:
	var end := focus
	var span := focus - cam
	var reach := span.length()
	if reach > 0.8:
		end = cam + span * ((reach - 0.55) / reach)
	for mi in _safety_meshes:
		if mi == null or not is_instance_valid(mi) or mi.mesh == null:
			continue
		if desired.has(mi.get_instance_id()):
			continue
		if _is_floor_name(String(mi.name)) or _too_broad(mi) or _is_gameplay_blocker(mi):
			continue
		var aabb := mi.global_transform * mi.get_aabb()
		if aabb.position.y + aabb.size.y < 0.15:
			continue
		if _segment_hits_aabb(cam, end, aabb):
			_mark(desired, mi)


func _blend_fades(desired: Dictionary, delta: float) -> void:
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


func _too_broad(mi: MeshInstance3D) -> bool:
	if mi.mesh == null:
		return true
	var size := mi.get_aabb().size
	return size.x > 8.0 and size.z > 8.0


func _is_gameplay_blocker(node: Node) -> bool:
	var walker := node
	while walker != null:
		for group_name in _BLOCKER_GROUPS:
			if walker.is_in_group(group_name):
				return true
		if String(walker.name).begins_with("LockedDoor"):
			return true
		walker = walker.get_parent()
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


func _segment_hits_aabb(a: Vector3, b: Vector3, aabb: AABB) -> bool:
	var dir := b - a
	var tmin := 0.0
	var tmax := 1.0
	var mn := aabb.position
	var mx := aabb.position + aabb.size
	for axis in 3:
		var origin := a[axis]
		var delta := dir[axis]
		var lo := mn[axis]
		var hi := mx[axis]
		if absf(delta) < 0.0000001:
			if origin < lo or origin > hi:
				return false
			continue
		var inv := 1.0 / delta
		var t1 := (lo - origin) * inv
		var t2 := (hi - origin) * inv
		if t1 > t2:
			var swap := t1
			t1 = t2
			t2 = swap
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return false
	return true
