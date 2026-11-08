extends SceneTree

const CharacterMeshScript := preload("res://scripts/CharacterMesh.gd")
const HideRoomLightScript := preload("res://scripts/HideRoomLight.gd")

## Headless smoke for hide spots: v2/v3 scenes are what the generator instances,
## the door is local +Z, a witnessed chase breaks the spot, and door/monster/
## player clips play when present.

const ROOM_PATHS := {
	"bedroom": "res://scenes/rooms/Bedroom_Decorated_v2.tscn",
	"living_room": "res://scenes/rooms/LivingRoom_Decorated_v2.tscn",
	"office": "res://scenes/rooms/Office_Decorated_v2.tscn",
	"storage": "res://scenes/rooms/Storage_Decorated_v2.tscn",
	"boiler": "res://scenes/rooms/Boiler_Decorated_v3.tscn",
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var paths_ok := _check_paths()
	var rooms_ok := _check_rooms()
	var doors_ok := _check_door_fallback_and_clips()
	var breach_ok := await _check_breach()
	var clips_ok := await _check_warden_and_void()
	var light_ok := await _check_hide_room_light()
	var all_ok: bool = paths_ok and rooms_ok and doors_ok and breach_ok and clips_ok and light_ok
	print("hiding_smoke_ok=", all_ok)
	quit(0 if all_ok else 1)


func _check_paths() -> bool:
	var ok := true
	for type_name in ROOM_PATHS:
		var path := String(MapGenerator.ROOM_SCENES[type_name])
		var want := String(ROOM_PATHS[type_name])
		if path != want:
			print("scene_path_wrong type=", type_name, " got=", path)
			ok = false
	print("scene_paths_ok=", ok)
	return ok


func _check_rooms() -> bool:
	var ok := true
	var container := Node3D.new()
	container.name = "Rooms"
	root.add_child(container)
	var generator := MapGenerator.new()
	root.add_child(generator)
	var expected := {
		"bedroom": 1,
		"living_room": 1,
		"office": 1,
		"storage": 1,
		"boiler": 5,
	}
	var index := 0
	for type_name in expected:
		var cell := Vector2i(index, 0)
		index += 1
		var occupied := {cell: true}
		var room: Node3D = generator._spawn_room(container, cell, type_name, occupied)
		if room == null:
			print("room_missing=", type_name)
			ok = false
			continue
		if room.find_child("PreviewLight", true, false) != null:
			print("preview_light_left=", type_name)
			ok = false
		var spots: Array = room.find_children("*", "HideSpot", true, false)
		var want: int = expected[type_name]
		if spots.size() != want:
			print("hide_count_wrong type=", type_name, " got=", spots.size(), " want=", want)
			ok = false
		for spot in spots:
			if not _door_faces_room(spot as HideSpot, room):
				print("door_axis_wrong type=", type_name, " spot=", (spot as Node).name)
				ok = false
		if type_name == "boiler":
			if MapGenerator.find_child_by_name(room, "ValveUse") == null:
				print("boiler_missing=ValveUse")
				ok = false
			if MapGenerator.find_child_by_name(room, "ValveWheel") == null:
				print("boiler_missing=ValveWheel")
				ok = false
		if not _door_prop_ok(room, type_name):
			ok = false
	var hb_path := String(CharacterMeshScript.with_hide_anims("res://assets/characters/does_not_exist.glb"))
	var hb_ok: bool = hb_path == "res://assets/characters/does_not_exist.glb"
	var tarantula := String(CharacterMeshScript.with_hide_anims("res://assets/characters/Tarantula.glb"))
	var void_kept := String(CharacterMeshScript.with_hide_anims("res://assets/characters/Void_walking.glb"))
	var warden := "res://assets/characters/Meshy_AI_Gulag_Winter_Warden_All_Animations.glb"
	var warden_kept := String(CharacterMeshScript.with_hide_anims(warden))
	hb_ok = hb_ok and tarantula.ends_with("Tarantula_hb.glb")
	hb_ok = hb_ok and void_kept.ends_with("Void_walking.glb")
	hb_ok = hb_ok and warden_kept.ends_with("Meshy_AI_Gulag_Winter_Warden_All_Animations_hb.glb")
	print("hb_fallback_ok=", hb_ok)
	ok = ok and hb_ok
	container.queue_free()
	generator.queue_free()
	print("rooms_ok=", ok)
	return ok


## The hide spot's generator room is the only thing that brightens, and only
## while the player is inside. Ambient, exposure, and fog stay put.
func _check_hide_room_light() -> bool:
	var world := WorldEnvironment.new()
	world.name = "HideLightWorld"
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.0
	env.fog_enabled = false
	env.fog_light_energy = 0.37
	env.fog_density = 0.02
	env.tonemap_exposure = 1.0
	env.adjustment_brightness = 1.0
	world.environment = env
	root.add_child(world)

	var container := Node3D.new()
	container.name = "HideLightRooms"
	root.add_child(container)
	var generator := MapGenerator.new()
	root.add_child(generator)
	var bedroom: Node3D = generator._spawn_room(container, Vector2i(0, 0), "bedroom", {Vector2i(0, 0): true})
	var office: Node3D = generator._spawn_room(container, Vector2i(2, 0), "office", {Vector2i(2, 0): true})
	var player := _make_player()
	root.add_child(player)
	await physics_frame

	var spot := bedroom.find_children("*", "HideSpot", true, false)[0] as HideSpot
	var found: Node3D = HideRoomLightScript.room_of(spot)
	var office_spot := office.find_children("*", "HideSpot", true, false)[0] as HideSpot
	var office_room: Node3D = HideRoomLightScript.room_of(office_spot)
	var bed_mesh := _first_mesh(bedroom)
	var office_mesh := _first_mesh(office)
	var bed_before: int = bed_mesh.layers
	var office_before: int = office_mesh.layers
	player.global_position = spot.entry_global()
	var entered: bool = spot.try_enter(player)
	var light := bedroom.get_node_or_null("HideRoomLight") as OmniLight3D
	var layer: int = HideRoomLightScript.ROOM_LAYER
	var bed_tagged: int = _count_layer(bedroom, layer)
	var office_tagged: int = _count_layer(office, layer)
	var energy := light.light_energy if light != null else -1.0
	var lit := (
		entered
		and found == bedroom
		and office_room == office
		and light != null
		and light.get_parent() == bedroom
		and absf(energy - HideRoomLightScript.HIDE_ENERGY) < 0.001
		and absf(energy - HideRoomLightScript.AUTHORED_FILL_ENERGY * 0.25) < 0.001
		and light.light_cull_mask == layer
		and absf(light.light_indirect_energy) < 0.001
		and absf(light.light_volumetric_fog_energy) < 0.001
		and bedroom.get_node_or_null("PreviewLight") == null
		and office.get_node_or_null("HideRoomLight") == null
		and office.get_node_or_null("PreviewLight") == null
		and bed_tagged > 10
		and office_tagged == 0
		and (bed_mesh.layers & layer) != 0
		and (bed_mesh.layers & bed_before) == bed_before
		and office_mesh.layers == office_before
	)
	var env_while: bool = _env_unchanged(env)
	player.exit_hiding()
	var restored := (
		bedroom.get_node_or_null("HideRoomLight") == null
		and bed_mesh.layers == bed_before
		and office_mesh.layers == office_before
		and _count_layer(bedroom, layer) == 0
	)
	player.global_position = spot.entry_global()
	var forced_in: bool = spot.try_enter(player)
	player.exit_hiding(true)
	var forced_restored := bedroom.get_node_or_null("HideRoomLight") == null and bed_mesh.layers == bed_before
	var env_after: bool = _env_unchanged(env)
	var ok := lit and env_while and restored and forced_in and forced_restored and env_after
	print(
		"hide_room_light_ok=", ok,
		" entered=", entered,
		" room=", found.name if found != null else "",
		" energy=", energy,
		" bed_tagged=", bed_tagged,
		" office_tagged=", office_tagged,
		" restored=", restored,
		" forced=", forced_restored,
		" env=", env_while and env_after
	)
	player.queue_free()
	container.queue_free()
	generator.queue_free()
	world.queue_free()
	return ok


func _env_unchanged(env: Environment) -> bool:
	return (
		absf(env.ambient_light_energy) < 0.001
		and not env.fog_enabled
		and absf(env.fog_light_energy - 0.37) < 0.001
		and absf(env.fog_density - 0.02) < 0.001
		and absf(env.tonemap_exposure - 1.0) < 0.001
		and absf(env.adjustment_brightness - 1.0) < 0.001
	)


func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null


func _count_layer(node: Node, bit: int) -> int:
	var count := 0
	if node is GeometryInstance3D and ((node as GeometryInstance3D).layers & bit) != 0:
		count += 1
	for child in node.get_children():
		count += _count_layer(child, bit)
	return count


func _door_prop_ok(room: Node, type_name: String) -> bool:
	var visuals: Array = room.find_children("HideDoors", "Node3D", true, false)
	var want := 5 if type_name == "boiler" else 1
	if visuals.size() != want:
		print("door_visual_wrong type=", type_name, " got=", visuals.size())
		return false
	var prop_suffix := ""
	match type_name:
		"bedroom":
			prop_suffix = "OldWardrobe_Doors.glb"
		"office", "living_room":
			prop_suffix = "WoodenWardrobe_Doors.glb"
		"storage":
			prop_suffix = "SovietFridge_Doors.glb"
		"boiler":
			prop_suffix = "RustyLocker_Doors.glb"
		_:
			prop_suffix = ""
	var clips := false
	for visual in visuals:
		var prop := String(visual.get_meta("nw_door_prop", ""))
		if not prop.ends_with(prop_suffix):
			print("door_prop_wrong type=", type_name, " prop=", prop)
			return false
		var anim := _anim_under(visual)
		if anim != null and anim.has_animation("DoorOpen") and anim.has_animation("DoorBurst"):
			clips = true
	if not clips:
		print("door_clips_missing=", type_name)
		return false
	var body := room.find_child("RoomCollision", true, false)
	if body == null:
		print("collision_missing=", type_name)
		return false
	for child in body.get_children():
		var label := String(child.name)
		if label.begins_with("Col_Door") or label == "Col_Interior" or label.begins_with("Col_Interior"):
			print("door_collider=", type_name, " ", label)
			return false
	return true


func _anim_under(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _anim_under(child)
		if found != null:
			return found
	return null


func _door_faces_room(spot: HideSpot, room: Node3D) -> bool:
	var host := spot.get_parent() as Node3D
	if host == null:
		return false
	var entry_local := host.to_local(spot.entry_global())
	var inside_local := host.to_local(spot.inside_global())
	if entry_local.z <= inside_local.z + 0.2:
		return false
	var forward := spot.exit_forward()
	var to_center := room.global_position - host.global_position
	to_center.y = 0.0
	if to_center.length() < 0.2 or forward.length() < 0.2:
		return false
	return forward.normalized().dot(to_center.normalized()) > 0.5


func _check_door_fallback_and_clips() -> bool:
	var swing_root := Node3D.new()
	swing_root.name = "SwingRoot"
	root.add_child(swing_root)
	var swing_host := _make_host("HideSpot_Swing")
	swing_root.add_child(swing_host)
	var swing_count := HideSpot.attach_in(swing_root)
	var swing_spot := swing_host.get_node("HideSpotUse") as HideSpot
	var left := swing_host.get_node("Door_L") as Node3D
	var right := swing_host.get_node("Door_R") as Node3D
	swing_spot.on_player_entered()
	var swing_ok := (
		swing_count == 1
		and left.rotation.y > 1.0
		and right.rotation.y < -1.0
	)
	swing_spot.on_occupant_left(null, false)
	swing_ok = swing_ok and absf(left.rotation.y) < 0.01 and absf(right.rotation.y) < 0.01
	print("door_swing_ok=", swing_ok)

	var clip_root := Node3D.new()
	clip_root.name = "ClipRoot"
	root.add_child(clip_root)
	var clip_host := _make_host("HideSpot_Clip")
	clip_root.add_child(clip_host)
	var player := _make_animation_player(["DoorOpen", "DoorBurst"])
	clip_root.add_child(player)
	HideSpot.attach_in(clip_root)
	var clip_spot := clip_host.get_node("HideSpotUse") as HideSpot
	var clip_left := clip_host.get_node("Door_L") as Node3D
	clip_spot.on_player_entered()
	var open_ok := (
		String(player.current_animation) == "DoorOpen"
		and absf(clip_left.rotation.y) < 0.01
	)
	var started := clip_spot.begin_break()
	var burst_ok := started and String(player.current_animation) == "DoorBurst" and absf(clip_left.rotation.y) < 0.01
	var second := not clip_spot.begin_break()
	print("door_clip_ok=", open_ok and burst_ok and second)
	return swing_ok and open_ok and burst_ok and second


func _check_breach() -> bool:
	var floor_body := _make_floor()
	root.add_child(floor_body)
	var host := _make_host("HideSpot_Breach")
	root.add_child(host)
	var door_anim := _make_animation_player(["DoorOpen", "DoorBurst"])
	host.add_child(door_anim)
	HideSpot.attach_in(host)
	var spot := host.get_node("HideSpotUse") as HideSpot

	var player := _make_player()
	root.add_child(player)
	var monster := _make_monster()
	root.add_child(monster)
	await physics_frame

	var entry := spot.entry_global()
	entry.y = 0.0
	player.global_position = entry
	_place_monster(monster, entry + spot.exit_forward() * 2.4, player.global_position)
	var patrol_entered := spot.try_enter(player)
	var patrol_ok: bool = (
		patrol_entered
		and player.is_hidden()
		and not monster.is_breaching_hide()
		and not player.get_node("Model").visible
	)
	await _frames(3)
	var held: Vector3 = player.global_position
	Input.action_press("move_right")
	await _frames(4)
	Input.action_release("move_right")
	var held_ok := player.global_position.distance_squared_to(held) < 0.0001
	player.exit_hiding()
	print("patrol_hide_ok=", patrol_ok and held_ok, " hidden=", player.is_hidden())

	var wall := _make_wall()
	root.add_child(wall)
	var blocked_entry := spot.entry_global()
	blocked_entry.y = 0.0
	player.global_position = blocked_entry
	var blocked_monster_pos := blocked_entry - spot.exit_forward() * 3.0
	_place_monster(monster, blocked_monster_pos, player.global_position)
	wall.global_position = (blocked_monster_pos + blocked_entry) * 0.5
	wall.global_position.y = 1.2
	monster.debug_enter_chase()
	_face_monster(monster, player.global_position)
	await physics_frame
	var blocked_entered := spot.try_enter(player)
	var blocked_ok: bool = blocked_entered and player.is_hidden() and not monster.is_breaching_hide()
	player.exit_hiding()
	wall.queue_free()
	print("blocked_chase_ok=", blocked_ok)

	entry = spot.entry_global()
	entry.y = 0.0
	player.global_position = entry
	_place_monster(monster, entry + spot.exit_forward() * 3.0, player.global_position)
	monster.debug_enter_chase()
	_face_monster(monster, player.global_position)
	monster.touch_damage = 17.0
	var chase_entered := spot.try_enter(player)
	await physics_frame
	var saw_breach: bool = monster.is_breaching_hide()
	player.interact()
	await physics_frame
	var cancel_ok: bool = chase_entered and saw_breach and not player.is_hidden() and not monster.is_breaching_hide()
	print("cancel_breach_ok=", cancel_ok)

	player.global_position = entry
	_place_monster(monster, entry + spot.exit_forward() * 0.4, player.global_position)
	monster.debug_enter_chase()
	_face_monster(monster, player.global_position)
	var health_before: float = player.health
	var forced := spot.try_enter(player)
	var saw_break := false
	var saw_burst := false
	var saw_eject := false
	var frames := 0
	while frames < 90 and player.is_hidden():
		frames += 1
		await physics_frame
		var monster_anim := monster.get_animation_player() as AnimationPlayer
		if monster_anim != null and String(monster_anim.current_animation) == "hide_break":
			saw_break = true
		if String(door_anim.current_animation) == "DoorBurst":
			saw_burst = true
		if player.current_clip() == "hide_ejected":
			saw_eject = true
	var out_ok: bool = (
		forced
		and not player.is_hidden()
		and not monster.is_breaching_hide()
		and player.get_node("Model").visible
		and player.collision_layer == 2
		and player.health == health_before - 17.0
		and player.global_position.distance_to(entry) < 1.2
		and saw_break
		and saw_burst
		and saw_eject
	)
	var lunge_ok: bool = await _check_unrigged_lunge(spot, player, monster)
	var reach_ok: bool = await _check_hide_break_reach()
	print(
		"forced_eject_ok=", out_ok,
		" health=", player.health,
		" break=", saw_break,
		" burst=", saw_burst,
		" eject=", saw_eject,
		" frames=", frames
	)
	return patrol_ok and held_ok and blocked_ok and cancel_ok and out_ok and lunge_ok and reach_ok


func _check_unrigged_lunge(spot: HideSpot, player: CharacterBody3D, rigged: CharacterBody3D) -> bool:
	rigged.set_physics_process(false)
	if player.is_hidden():
		player.exit_hiding(true)
	player.health = 100.0
	var monster := CharacterBody3D.new()
	monster.name = "PlainMonster"
	monster.set_script(load("res://scripts/Monster.gd"))
	monster.collision_layer = 4
	monster.collision_mask = 1
	var visual := Node3D.new()
	visual.name = "MonsterMesh"
	monster.add_child(visual)
	root.add_child(monster)
	await physics_frame
	var entry := spot.entry_global()
	entry.y = 0.0
	player.global_position = entry
	var into := -spot.exit_forward()
	into.y = 0.0
	into = into.normalized()
	_place_monster(monster, entry - into * 0.35, player.global_position)
	monster.debug_enter_chase()
	_face_monster(monster, entry)
	var entered: bool = spot.try_enter(player)
	var max_lift := 0.0
	var max_reach := 0.0
	var face_dot := 0.0
	for _index in 40:
		await physics_frame
		var yaw := visual.rotation.y
		var facing := Vector3(-sin(yaw), 0.0, -cos(yaw))
		face_dot = maxf(face_dot, facing.dot(into))
		var delta := visual.position
		max_lift = maxf(max_lift, delta.y)
		max_reach = maxf(max_reach, delta.dot(into))
		if not player.is_hidden():
			break
	var lunge_ok := entered and face_dot > 0.85 and max_reach > 0.2 and max_lift > 0.05
	print(
		"unrigged_lunge_ok=", lunge_ok,
		" face=", snappedf(face_dot, 0.01),
		" reach=", snappedf(max_reach, 0.01),
		" lift=", snappedf(max_lift, 0.01)
	)
	monster.queue_free()
	if player.is_hidden():
		player.exit_hiding(true)
	return lunge_ok


func _check_hide_break_reach() -> bool:
	var path := "res://assets/characters/Tarantula_hb.glb"
	var packed := load(path) as PackedScene
	if packed == null:
		print("hide_break_reach_ok=false load_failed")
		return false
	var body := packed.instantiate() as Node3D
	root.add_child(body)
	await physics_frame
	var anim := _anim_under(body)
	if anim == null or not anim.has_animation("hide_break") or not anim.has_animation("Walk"):
		print("hide_break_reach_ok=false clips=", anim)
		return false
	var skel := _find_skeleton(body)
	if skel == null:
		print("hide_break_reach_ok=false no_skeleton")
		body.queue_free()
		return false
	anim.play("hide_break")
	var rest := _bone_points(skel)
	anim.seek(0.70, true)
	await physics_frame
	_flush_skeleton(skel)
	var strike := _bone_points(skel)
	var best_name := ""
	var best_shift := 0.0
	var best_y := 0.0
	var best_forward := 0.0
	for bone_name in rest:
		var a: Vector3 = rest[bone_name]
		var b: Vector3 = strike[bone_name]
		var shift := b - a
		var planar := Vector2(shift.x, shift.z).length()
		if planar > best_shift:
			best_shift = planar
			best_name = String(bone_name)
			best_y = b.y
			best_forward = shift.z
	# Door leaves sit about 0.2 m to 1.9 m. The smash should land on that span.
	var height_ok := best_y > 0.55 and best_y < 1.75
	print(
		"hide_break_reach bone=", best_name,
		" height=", snappedf(best_y, 0.01),
		" forward_z=", snappedf(best_forward, 0.01),
		" shift=", snappedf(best_shift, 0.01),
		" height_ok=", height_ok
	)
	body.queue_free()
	return height_ok and best_shift > 0.05


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _flush_skeleton(skel: Skeleton3D) -> void:
	if skel.has_method("force_update_all_bone_transforms"):
		skel.force_update_all_bone_transforms()


func _bone_points(skel: Skeleton3D) -> Dictionary:
	_flush_skeleton(skel)
	var points := {}
	for index in skel.get_bone_count():
		var origin: Vector3 = skel.get_bone_global_pose(index).origin
		points[skel.get_bone_name(index)] = skel.to_global(origin)
	return points


func _check_warden_and_void() -> bool:
	var warden_ok := await _check_warden_eject()
	var void_ok := await _check_void_clips()
	print("warden_void_ok=", warden_ok and void_ok)
	return warden_ok and void_ok


func _check_warden_eject() -> bool:
	var path := "res://assets/characters/Meshy_AI_Gulag_Winter_Warden_All_Animations_hb.glb"
	var packed := load(path) as PackedScene
	if packed == null:
		print("warden_hb_ok=false")
		return false
	var body := CharacterBody3D.new()
	body.set_script(load("res://scripts/Player.gd"))
	var model := Node3D.new()
	model.name = "Model"
	body.add_child(model)
	var character := packed.instantiate() as Node3D
	character.name = "Character"
	model.add_child(character)
	root.add_child(body)
	await physics_frame
	var anim := _anim_under(body)
	var names_ok := (
		anim != null
		and anim.has_animation("Walk")
		and anim.has_animation("Run")
		and anim.has_animation("Idle")
		and anim.has_animation("Die")
		and anim.has_animation("hide_ejected")
	)
	var ico := _find_named(body, "Icosphere")
	var host := _make_host("HideSpot_Warden")
	root.add_child(host)
	HideSpot.attach_in(host)
	var spot := host.get_node("HideSpotUse") as HideSpot
	body.global_position = spot.entry_global()
	var entered: bool = spot.try_enter(body)
	var ejected := false
	if entered:
		body.eject_from_hiding(null, 0.0)
		ejected = body.current_clip() == "hide_ejected" and not body.is_hidden()
	print("warden_hb_ok=", names_ok and ejected and ico == null, " clip=", body.current_clip() if body.has_method("current_clip") else "")
	body.queue_free()
	host.queue_free()
	return names_ok and ejected and ico == null


func _check_void_clips() -> bool:
	var path := "res://assets/characters/Void_full.glb"
	var packed := load(path) as PackedScene
	if packed == null:
		print("void_full_ok=false")
		return false
	var body := packed.instantiate() as Node3D
	root.add_child(body)
	await physics_frame
	CharacterMeshScript.drop_stray_meshes(body)
	var anim := _anim_under(body)
	var names_ok := (
		anim != null
		and anim.has_animation("Walk")
		and anim.has_animation("Run")
		and anim.has_animation("hide_break")
	)
	var walked := false
	var ran := false
	if names_ok:
		walked = _clip_moves(body, anim, "Walk")
		ran = _clip_moves(body, anim, "Run")
	var ico := _find_named(body, "Icosphere")
	print("void_full_ok=", names_ok and walked and ran and ico == null, " walk=", walked, " run=", ran)
	body.queue_free()
	return names_ok and walked and ran and ico == null


func _clip_moves(body: Node, anim: AnimationPlayer, clip_name: String) -> bool:
	var skel := _find_skeleton(body)
	if skel == null:
		return false
	anim.play(clip_name)
	anim.seek(0.0, true)
	var rest := _bone_points(skel)
	anim.seek(0.25, true)
	var later := _bone_points(skel)
	for bone_name in rest:
		var a: Vector3 = rest[bone_name]
		var b: Vector3 = later[bone_name]
		if a.distance_to(b) > 0.02:
			return true
	return false


func _find_named(node: Node, node_name: String) -> Node:
	if String(node.name) == node_name:
		return node
	for child in node.get_children():
		var found := _find_named(child, node_name)
		if found != null:
			return found
	return null


func _make_host(host_name: String) -> MeshInstance3D:
	var host := MeshInstance3D.new()
	host.name = host_name
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 2.0, 0.6)
	host.mesh = box
	for door_name in ["Door_L", "Door_R"]:
		var door := MeshInstance3D.new()
		door.name = door_name
		door.mesh = box
		host.add_child(door)
	return host


func _make_animation_player(clip_names: Array) -> AnimationPlayer:
	var anim := AnimationPlayer.new()
	anim.name = "DoorAnim"
	var library := AnimationLibrary.new()
	for clip_name in clip_names:
		var clip := Animation.new()
		clip.length = 0.4
		library.add_animation(String(clip_name), clip)
	anim.add_animation_library("", library)
	return anim


func _make_player() -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = "Player"
	body.set_script(load("res://scripts/Player.gd"))
	body.collision_layer = 2
	body.collision_mask = 1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.8, 0.0)
	body.add_child(shape)
	var model := Node3D.new()
	model.name = "Model"
	body.add_child(model)
	var anim := _make_animation_player(["hide_ejected"])
	anim.name = "PlayerAnim"
	model.add_child(anim)
	return body


func _make_monster() -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = "Monster"
	body.set_script(load("res://scripts/Monster.gd"))
	body.collision_layer = 4
	body.collision_mask = 1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.4
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.8, 0.0)
	body.add_child(shape)
	var visual := Node3D.new()
	visual.name = "MonsterMesh"
	body.add_child(visual)
	var anim := _make_animation_player(["hide_break"])
	anim.name = "MonsterAnim"
	visual.add_child(anim)
	return body


func _make_floor() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(shape)
	return body


func _make_wall() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Wall"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 3.0, 0.4)
	shape.shape = box
	body.add_child(shape)
	return body


func _place_monster(monster: CharacterBody3D, where: Vector3, look_at: Vector3) -> void:
	where.y = 0.0
	monster.global_position = where
	monster.velocity = Vector3.ZERO
	_face_monster(monster, look_at)


func _face_monster(monster: CharacterBody3D, point: Vector3) -> void:
	var visual := monster.get_node("MonsterMesh") as Node3D
	var dir := point - monster.global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		return
	dir = dir.normalized()
	visual.rotation.y = atan2(-dir.x, -dir.z)


func _frames(count: int) -> void:
	for _index in count:
		await physics_frame
