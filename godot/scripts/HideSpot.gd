class_name HideSpot
extends Node3D

## Wardrobe, fridge, or locker the player can climb into. The prop origin is
## the bottom centre and the door faces local +Z (Blender -Y after glTF
## import). Press E on that face to enter; press E again to step back out.
##
## Door motion prefers AnimationPlayer clips on the prop: `DoorOpen` for a
## normal enter or exit, `DoorBurst` when a monster smashes the spot. If those
## clips are missing, child meshes named `Door` or `Door_*` swing on local Y.
##
## The room generator finds hosts by name. `HideSpot_*` is the contract.
## Boiler v3 still exports its bank as `Locker_1`..`Locker_5`, so those names
## are accepted until the artist renames them.

const HIDE_PREFIX := "HideSpot_"
const LOCKER_PREFIX := "Locker_"
const DOOR_VISUALS := {
	"fridge": "res://assets/props/SovietFridge_Doors.glb",
	"old_wardrobe": "res://assets/props/OldWardrobe_Doors.glb",
	"wooden_wardrobe": "res://assets/props/WoodenWardrobe_Doors.glb",
	"locker": "res://assets/props/RustyLocker_Doors.glb",
}
static var _door_packed: Dictionary = {}
const CLIP_DOOR_OPEN := "DoorOpen"
const CLIP_DOOR_BURST := "DoorBurst"
## Local axis that leaves the shell through the door.
const DOOR_LOCAL := Vector3(0.0, 0.0, 1.0)
## Past the door face, far enough that a 0.3 m capsule is not left inside the box.
const STAND_OFF := 0.75
const INTERIOR_INSET := 0.18
const OPEN_YAW := 1.8326
const BURST_YAW := 2.6180

@export var interact_range: float = 1.65

var _host: Node3D
var _entry_local: Vector3 = Vector3(0.0, 0.0, 1.0)
var _inside_local: Vector3 = Vector3.ZERO
var _occupant: Node
var _prompt: Label3D
var _door_rest: Dictionary = {}
var _doors_swung: bool = false
var _breaking: bool = false


static func attach_in(root: Node) -> int:
	var hosts: Array[Node3D] = []
	_collect_hosts(root, hosts)
	var count := 0
	for host in hosts:
		if _existing_on(host) != null:
			count += 1
			continue
		var spot := HideSpot.new()
		spot.name = "HideSpotUse"
		host.add_child(spot)
		# After _ready has measured the baked shell. The door glb replaces the
		# visible mesh; the room collision box already covers the shell.
		_install_door_visual(host)
		count += 1
	return count


static func _install_door_visual(host: Node3D) -> void:
	if host.get_node_or_null("HideDoors") != null:
		return
	var path := _door_visual_path(host)
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var packed: PackedScene = _door_packed.get(path) as PackedScene
	if packed == null:
		packed = load(path) as PackedScene
		_door_packed[path] = packed
	if packed == null:
		return
	var visual := packed.instantiate() as Node3D
	if visual == null:
		return
	visual.name = "HideDoors"
	visual.set_meta("nw_door_prop", path)
	host.add_child(visual)
	# The baked mesh is the closed shell. Drop it so it does not z-fight the
	# hinged prop. Collision was already cooked from that shell's bounds.
	if host is MeshInstance3D:
		(host as MeshInstance3D).mesh = null


static func _door_visual_path(host: Node) -> String:
	var label := String(host.name)
	if label.begins_with(LOCKER_PREFIX):
		return String(DOOR_VISUALS["locker"])
	if "Fridge" in label:
		return String(DOOR_VISUALS["fridge"])
	if "Wardrobe" in label:
		if _room_kind(host) == "bedroom":
			return String(DOOR_VISUALS["old_wardrobe"])
		return String(DOOR_VISUALS["wooden_wardrobe"])
	return ""


static func _room_kind(node: Node) -> String:
	var walker := node
	while walker != null:
		var label := String(walker.name)
		if label.begins_with("Room_"):
			var rest := label.trim_prefix("Room_")
			var bits := rest.split("_")
			if bits.size() >= 3:
				return "_".join(bits.slice(2))
		walker = walker.get_parent()
	return ""


static func is_hide_host(node: Node) -> bool:
	if node == null:
		return false
	var label := String(node.name)
	if label.begins_with("NoCol_"):
		return false
	if label.begins_with(HIDE_PREFIX):
		return true
	if not label.begins_with(LOCKER_PREFIX):
		return false
	var suffix := label.substr(LOCKER_PREFIX.length())
	return not suffix.is_empty() and suffix.is_valid_int()


func _ready() -> void:
	add_to_group("hide_spot")
	_host = get_parent() as Node3D
	_measure_shell()
	_ensure_prompt()


func is_occupied() -> bool:
	return _occupant != null and is_instance_valid(_occupant)


func entry_global() -> Vector3:
	if _host == null:
		return global_position
	return _host.global_transform * _entry_local


func inside_global() -> Vector3:
	if _host == null:
		return global_position
	return _host.global_transform * _inside_local


## Horizontal direction out through the door, in world space.
func exit_forward() -> Vector3:
	if _host == null:
		return Vector3(0.0, 0.0, 1.0)
	var forward := _host.global_transform.basis * DOOR_LOCAL
	forward.y = 0.0
	if forward.length() < 0.001:
		return Vector3(0.0, 0.0, 1.0)
	return forward.normalized()


func can_interact(from_pos: Vector3) -> bool:
	if is_occupied():
		return false
	return interact_distance(from_pos) <= interact_range


func interact_distance(from_pos: Vector3) -> float:
	var to_entry := entry_global() - from_pos
	to_entry.y = 0.0
	return to_entry.length()


func try_enter(body: Node3D) -> bool:
	if not _can_accept(body):
		return false
	if not body.enter_hiding(self, inside_global()):
		return false
	_occupant = body
	return true


func on_player_entered() -> void:
	if _play_door_clip(CLIP_DOOR_OPEN):
		return
	_swing_doors(OPEN_YAW)


## True the first time a monster starts the smash. A second monster waits.
func begin_break() -> bool:
	if _breaking:
		return false
	_breaking = true
	if not _play_door_clip(CLIP_DOOR_BURST):
		_swing_doors(BURST_YAW)
	return true


func is_being_broken() -> bool:
	return _breaking


func cancel_break() -> void:
	_breaking = false


func on_occupant_left(body: Node, forced: bool = false) -> void:
	if _occupant == body:
		_occupant = null
	_breaking = false
	if forced:
		return
	if _play_door_clip(CLIP_DOOR_OPEN):
		return
	_restore_doors()


func _can_accept(body: Node3D) -> bool:
	if body == null or is_occupied():
		return false
	if body.has_method("is_alive") and not body.is_alive():
		return false
	if body.has_method("is_input_locked") and body.is_input_locked():
		return false
	if body.has_method("is_hidden") and body.is_hidden():
		return false
	if not body.has_method("enter_hiding"):
		return false
	return can_interact(body.global_position)


func _measure_shell() -> void:
	var box := _shell_aabb()
	var center := box.get_center()
	var face_z := box.position.z + box.size.z
	var back_z := box.position.z
	var feet_y := box.position.y
	_entry_local = Vector3(center.x, feet_y, face_z) + DOOR_LOCAL * STAND_OFF
	var inside_z := face_z - maxf(INTERIOR_INSET, minf(0.22, box.size.z * 0.35))
	inside_z = clampf(inside_z, back_z + 0.05, face_z - 0.05)
	_inside_local = Vector3(center.x, feet_y, inside_z)


func _shell_aabb() -> AABB:
	if _host is MeshInstance3D:
		var mesh := (_host as MeshInstance3D).mesh
		if mesh != null:
			return mesh.get_aabb()
	var merged := AABB()
	var found := false
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(_host, meshes)
	for mesh_instance in meshes:
		if mesh_instance.mesh == null:
			continue
		var local_box := _aabb_in_host(mesh_instance)
		if not found:
			merged = local_box
			found = true
		else:
			merged = merged.merge(local_box)
	if not found:
		return AABB(Vector3(-0.3, 0.0, -0.3), Vector3(0.6, 1.8, 0.6))
	return merged


func _aabb_in_host(mesh_instance: MeshInstance3D) -> AABB:
	var bounds := mesh_instance.mesh.get_aabb()
	var xf := Transform3D.IDENTITY
	var walker: Node = mesh_instance
	while walker != null and walker != _host:
		if walker is Node3D:
			xf = (walker as Node3D).transform * xf
		walker = walker.get_parent()
	return xf * bounds


func _play_door_clip(clip_name: String) -> bool:
	var anim := _door_animation()
	if anim == null or not anim.has_animation(clip_name):
		return false
	anim.play(clip_name)
	return true


func _door_animation() -> AnimationPlayer:
	var local := _animation_with_door_clip(_host)
	if local != null:
		return local
	if _host == null:
		return null
	var parent := _host.get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		if child == _host:
			continue
		var anim := _animation_with_door_clip(child)
		if anim != null:
			return anim
	return null


func _animation_with_door_clip(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		var anim := node as AnimationPlayer
		if anim.has_animation(CLIP_DOOR_OPEN) or anim.has_animation(CLIP_DOOR_BURST):
			return anim
	for child in node.get_children():
		var found := _animation_with_door_clip(child)
		if found != null:
			return found
	return null


func _swing_doors(amount: float) -> void:
	var doors := _door_nodes()
	if doors.is_empty():
		return
	_remember_doors(doors)
	_doors_swung = true
	for door in doors:
		var rest: Vector3 = _door_rest[door]
		door.rotation = Vector3(rest.x, rest.y + amount * _door_sign(String(door.name)), rest.z)


func _restore_doors() -> void:
	if not _doors_swung:
		return
	for door in _door_nodes():
		if _door_rest.has(door):
			door.rotation = _door_rest[door]
	_doors_swung = false


func _remember_doors(doors: Array[Node3D]) -> void:
	for door in doors:
		if not _door_rest.has(door):
			_door_rest[door] = door.rotation


func _door_nodes() -> Array[Node3D]:
	var found: Array[Node3D] = []
	if _host != null:
		_collect_doors(_host, found)
	return found


func _collect_doors(node: Node, found: Array[Node3D]) -> void:
	for child in node.get_children():
		if child == self:
			continue
		if child is Node3D and _is_door_name(String(child.name)):
			found.append(child as Node3D)
		if child is Node3D:
			_collect_doors(child, found)


func _is_door_name(label: String) -> bool:
	return label == "Door" or label.begins_with("Door_")


func _door_sign(label: String) -> float:
	var lower := label.to_lower()
	if lower.ends_with("_r") or lower.ends_with("_right"):
		return -1.0
	return 1.0


func _ensure_prompt() -> void:
	if _prompt != null:
		return
	_prompt = Label3D.new()
	_prompt.name = "HidePrompt"
	_prompt.text = "E"
	_prompt.font_size = 48
	_prompt.pixel_size = 0.004
	_prompt.position = _entry_local + Vector3(0.0, 1.15, 0.0)
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.modulate = Color(0.75, 0.9, 1.0)
	_prompt.outline_modulate = Color(0, 0, 0)
	_prompt.outline_size = 8
	add_child(_prompt)


static func _collect_hosts(node: Node, hosts: Array[Node3D]) -> void:
	if node is Node3D and is_hide_host(node):
		hosts.append(node as Node3D)
		return
	for child in node.get_children():
		_collect_hosts(child, hosts)


static func _existing_on(host: Node) -> Node:
	for child in host.get_children():
		if child is HideSpot:
			return child
	return null


static func _collect_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, meshes)
