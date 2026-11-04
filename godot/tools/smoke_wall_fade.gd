extends SceneTree

## Fixed isometric camera, original stick axes, and near-wall fade only
## while the player is inside a room.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var gp: Node = root.get_node_or_null("GameProgress")
	if gp != null and gp.has_method("reset_for_tests"):
		gp.reset_for_tests()

	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed == null:
		push_error("Missing Main.tscn")
		quit(1)
		return
	var main: Node3D = packed.instantiate()
	main.set("min_loading_seconds", 0.0)
	main.set("level_seed", 4)
	root.add_child(main)
	if main.has_method("is_level_ready") and not main.is_level_ready():
		await main.level_ready
	if main.has_method("park_monsters"):
		main.park_monsters()

	var player: CharacterBody3D = main.get_node("Player")
	var visual: Node3D = player.get_node("Model")
	var cam: Camera3D = main.get_node("IsoCamera")
	var map: Node = main.get_node("GeneratedMap")
	var fade := main.get_node_or_null("RoomWallFade")
	player.velocity = Vector3.ZERO

	visual.rotation.y = 2.2
	for _i in 8:
		await physics_frame
	var offset := cam.global_position - player.global_position
	offset.y = 0.0
	var expected_offset := Vector3(0.55, 0.0, 1.0).normalized()
	var fixed_ok := offset.length() > 5.0 and offset.normalized().dot(expected_offset) > 0.98
	var axes: Vector3 = TouchControls.stick_to_planar(Vector2(0.0, 1.0))
	var legacy := Vector3(-1.0, 0.0, -1.0).normalized()
	var axes_ok := axes.normalized().dot(legacy) > 0.99
	print("fixed_ok=", fixed_ok, " axes_ok=", axes_ok, " axes=", axes)

	var rooms := _rooms(map)
	if rooms.size() < 2 or fade == null:
		push_error("Need two rooms and RoomWallFade")
		quit(1)
		return
	var room: Node3D = rooms[0]
	var other: Node3D = rooms[1]
	player.global_position = room.global_position + Vector3(0.0, 0.05, 0.0)
	visual.rotation.y = 1.7
	if main.has_method("_snap_camera"):
		main._snap_camera()
	var sconce := _box(room, "TestSconce", Vector3(0.0, 1.3, 5.2))
	var idle := _box(room, "IdleCrate", Vector3(0.4, 1.2, 0.4))
	if fade.has_method("invalidate"):
		fade.invalidate()
	for _i in 24:
		await physics_frame
	var south := _side_geoms(room, "S")
	var east := _side_geoms(room, "E")
	var north := _side_geoms(room, "N")
	var west := _side_geoms(room, "W")
	var paper := _first_geom(MapGenerator.find_child_by_name(room, "NoCol_Wallpaper_S0"))
	var near_ok := _faded(south) and _faded(east) and paper != null and paper.transparency > 0.55
	var far_ok := _clear(north) and _clear(west)
	var prop_ok := sconce.transparency > 0.55 and idle.transparency < 0.12
	print(
		"near_ok=", near_ok,
		" far_ok=", far_ok,
		" prop_ok=", prop_ok,
		" south=", _alpha(south),
		" east=", _alpha(east),
		" north=", _alpha(north),
		" sconce=", sconce.transparency,
		" idle=", idle.transparency
	)

	player.global_position = other.global_position + Vector3(0.0, 0.05, 0.0)
	for _i in 24:
		await physics_frame
	var restored := _clear(south) and _clear(east) and sconce.transparency < 0.15
	var other_near := _faded(_side_geoms(other, "S")) and _faded(_side_geoms(other, "E"))
	var other_far := _clear(_side_geoms(other, "N")) and _clear(_side_geoms(other, "W"))
	print(
		"restored=", restored,
		" other_near=", other_near,
		" other_far=", other_far,
		" south_after=", _alpha(south)
	)

	player.global_position = Vector3(400.0, 0.05, 400.0)
	for _i in 24:
		await physics_frame
	var outside := _clear(_side_geoms(other, "S")) and _clear(_side_geoms(other, "E"))
	print("outside_ok=", outside)

	var all_ok := (
		fixed_ok
		and axes_ok
		and near_ok
		and far_ok
		and prop_ok
		and restored
		and other_near
		and other_far
		and outside
	)
	print("wall_fade_smoke_ok=", all_ok)
	quit(0 if all_ok else 1)


func _rooms(map: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for child in map.get_children():
		if child is Node3D and MapGenerator.find_child_by_name(child, "Wall_N_A") != null:
			out.append(child)
	return out


func _side_geoms(room: Node, side: String) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	for suffix in ["A", "B", "L"]:
		var geom := _first_geom(MapGenerator.find_child_by_name(room, "Wall_%s_%s" % [side, suffix]))
		if geom != null:
			out.append(geom)
	return out


func _first_geom(node: Node) -> GeometryInstance3D:
	if node == null:
		return null
	if node is GeometryInstance3D:
		return node
	for child in node.get_children():
		var found := _first_geom(child)
		if found != null:
			return found
	return null


func _faded(geoms: Array[GeometryInstance3D]) -> bool:
	if geoms.is_empty():
		return false
	for geom in geoms:
		if geom.transparency < 0.55:
			return false
	return true


func _clear(geoms: Array[GeometryInstance3D]) -> bool:
	for geom in geoms:
		if geom.transparency > 0.15:
			return false
	return true


func _alpha(geoms: Array[GeometryInstance3D]) -> float:
	if geoms.is_empty():
		return -1.0
	return geoms[0].transparency


func _box(room: Node3D, node_name: String, local_pos: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 0.6, 0.4)
	mesh.mesh = box
	mesh.position = local_pos
	room.add_child(mesh)
	return mesh
