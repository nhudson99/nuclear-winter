extends SceneTree

## Follow camera: elevated pitch behind the player, camera-relative walk,
## and per-side wall fade (shell pieces, wallpaper, nearby props, safety mesh).

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
	player.velocity = Vector3.ZERO

	var room := _closest_room(map, player.global_position)
	if room == null:
		push_error("No room with Wall_N_A")
		quit(1)
		return
	player.global_position = room.global_position + Vector3(0.0, 0.05, 0.0)
	visual.rotation.y = 0.0
	if cam.has_method("snap"):
		cam.snap()

	var look := -cam.global_transform.basis.z
	var horiz := Vector2(look.x, look.z).length()
	var pitch := rad_to_deg(atan2(-look.y, horiz))
	var pitch_ok := pitch >= 35.0 and pitch <= 45.0
	var facing := Vector3(0.0, 0.0, -1.0)
	var behind := cam.global_position - player.global_position
	behind.y = 0.0
	var behind_ok := behind.length() > 2.0 and behind.normalized().dot(-facing) > 0.9
	print("pitch_ok=", pitch_ok, " pitch=", pitch, " behind_ok=", behind_ok, " behind=", behind)

	var south_shell := _side_geoms(room, "S")
	var north_shell := _side_geoms(room, "N")
	var shell_found := not south_shell.is_empty() and not north_shell.is_empty()
	for _i in 24:
		await physics_frame
	var south_faded := _faded(south_shell)
	var north_clear := _clear(north_shell)
	var paper := _first_geom(MapGenerator.find_child_by_name(room, "NoCol_Wallpaper_S0"))
	var plug := _first_geom(MapGenerator.find_child_by_name(room, "Plug_S"))
	var paper_ok := paper != null and paper.transparency > 0.55
	# Exterior plugs stay; an open doorway has already deleted Plug_S.
	var plug_ok := plug == null or plug.transparency > 0.55
	print(
		"shell_found=", shell_found,
		" south_faded=", south_faded,
		" north_clear=", north_clear,
		" paper_ok=", paper_ok,
		" plug_ok=", plug_ok,
		" south_alpha=", _alpha(south_shell),
		" north_alpha=", _alpha(north_shell)
	)

	var sconce := _box(room, "TestSconce", Vector3(0.0, 1.3, 5.15), Vector3(0.4, 0.6, 0.4))
	# Tall enough to meet the elevated camera-to-player segment, inside the room.
	var safety := _box(room, "SafetyCrate", Vector3(0.0, 3.0, 2.2), Vector3(0.5, 3.4, 0.5))
	var idle := _box(room, "IdleCrate", Vector3(2.4, 1.4, 2.4), Vector3(0.45, 0.7, 0.45))
	if cam.has_method("invalidate_occluders"):
		cam.invalidate_occluders()
	visual.rotation.y = 0.0
	player.global_position = room.global_position + Vector3(0.0, 0.05, 0.0)
	if cam.has_method("snap"):
		cam.snap()
	for _i in 24:
		await physics_frame
	var prop_ok := sconce.transparency > 0.55
	var safety_ok := safety.transparency > 0.55
	var idle_ok := idle.transparency < 0.12
	print(
		"prop_ok=", prop_ok, " sconce=", sconce.transparency,
		" safety_ok=", safety_ok, " safety=", safety.transparency,
		" idle_ok=", idle_ok, " idle=", idle.transparency
	)

	visual.rotation.y = atan2(1.0, 0.0) + PI
	player.global_position = room.global_position + Vector3(0.0, 0.05, 0.0)
	if cam.has_method("snap"):
		cam.snap()
	for _i in 24:
		await physics_frame
	var west_shell := _side_geoms(room, "W")
	var turned_ok := _faded(west_shell) and _clear(south_shell)
	var prop_cleared := sconce.transparency < 0.15 and safety.transparency < 0.15
	var west_behind := cam.global_position.x < player.global_position.x - 2.0
	print(
		"turned_ok=", turned_ok,
		" west_alpha=", _alpha(west_shell),
		" south_alpha=", _alpha(south_shell),
		" prop_cleared=", prop_cleared,
		" west_behind=", west_behind
	)

	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	visual.rotation.y = atan2(fwd.x, fwd.z) + PI
	if cam.has_method("snap"):
		cam.snap()
	fwd = -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var pos0 := player.global_position
	Input.action_press("move_up")
	for _i in 14:
		await physics_frame
	Input.action_release("move_up")
	var delta := player.global_position - pos0
	delta.y = 0.0
	var move_ok := delta.length() > 0.25 and delta.normalized().dot(fwd) > 0.85
	print("move_ok=", move_ok, " delta=", delta, " fwd=", fwd)

	Input.action_press("flashlight")
	await physics_frame
	var motion := InputEventMouseMotion.new()
	motion.device = 0
	motion.relative = Vector2(80.0, 0.0)
	var yaw_before := visual.rotation.y
	Input.parse_input_event(motion)
	# The motion is flushed on a later idle frame; give physics time after that.
	for _i in 8:
		await process_frame
	Input.action_release("flashlight")
	var look_ok := absf(angle_difference(visual.rotation.y, yaw_before)) > 0.08
	print("look_ok=", look_ok, " yaw_before=", yaw_before, " yaw=", visual.rotation.y)
	await physics_frame

	var touch := main.get_node_or_null("TouchControls")
	var latch_ok := false
	if touch != null and touch.has_method("set_aim_stick") and touch.has_method("aim_planar"):
		visual.rotation.y = 0.0
		if cam.has_method("snap"):
			cam.snap()
		touch.set_aim_stick(Vector2(1.0, 0.0))
		var first: Vector3 = touch.aim_planar()
		for _i in 18:
			await physics_frame
		var later: Vector3 = touch.aim_planar()
		latch_ok = first.length() > 0.5 and first.normalized().dot(later.normalized()) > 0.99
		touch.set_aim_stick(Vector2.ZERO)
		print("latch_ok=", latch_ok, " first=", first, " later=", later)
	else:
		push_error("Missing aim stick")

	var all_ok := (
		pitch_ok
		and behind_ok
		and shell_found
		and south_faded
		and north_clear
		and paper_ok
		and plug_ok
		and prop_ok
		and safety_ok
		and idle_ok
		and turned_ok
		and prop_cleared
		and west_behind
		and move_ok
		and look_ok
		and latch_ok
	)
	print("follow_camera_smoke_ok=", all_ok)
	quit(0 if all_ok else 1)


func _closest_room(map: Node, point: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for child in map.get_children():
		if not (child is Node3D):
			continue
		if MapGenerator.find_child_by_name(child, "Wall_N_A") == null:
			continue
		var at := (child as Node3D).global_position
		var d := at.distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = child
	return best


func _side_geoms(room: Node, side: String) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	for suffix in ["A", "B", "L"]:
		var node := MapGenerator.find_child_by_name(room, "Wall_%s_%s" % [side, suffix])
		var geom := _first_geom(node)
		if geom != null:
			out.append(geom)
	var paper := MapGenerator.find_child_by_name(room, "NoCol_Wallpaper_%s0" % side)
	var paper_geom := _first_geom(paper)
	if paper_geom != null:
		out.append(paper_geom)
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


func _box(room: Node3D, node_name: String, local_pos: Vector3, size: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = local_pos
	room.add_child(mesh)
	return mesh
