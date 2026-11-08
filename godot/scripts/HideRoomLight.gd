class_name HideRoomLight
extends OmniLight3D

## While the player is inside a hide spot, light only the room that contains
## that spot. MapGenerator deletes each module's PreviewLight (warm fill,
## energy 1.4, sitting 2.1 m up at the tile centre) so play stays pitch black.
## This lamp is 25% of that fill. It is masked to the room's own meshes, so
## the next room, the world ambient, exposure, and fog stay where they were.
## Leaving the spot removes the lamp and puts those mesh layers back.

const NODE_NAME := "HideRoomLight"
## Authored on scenes/rooms/*_Decorated.tscn as PreviewLight.
const AUTHORED_FILL_ENERGY := 1.4
const BRIGHTNESS_LIFT := 0.25
const HIDE_ENERGY := AUTHORED_FILL_ENERGY * BRIGHTNESS_LIFT
const FILL_COLOR := Color(1.0, 0.88, 0.62, 1.0)
const FILL_HEIGHT := 2.1
## Past the far corner of a 12 m tile (about 8.7 m from a lamp at chest height)
## so the lift covers the whole room. The cull mask, not the range, is what
## keeps neighbouring rooms dark.
const FILL_RANGE := 14.0
## Visual layer 20. Nothing else in the level uses render layers.
const ROOM_LAYER_BIT := 19
const ROOM_LAYER := 1 << ROOM_LAYER_BIT

var _layers: Array[Dictionary] = []
var _dismissed: bool = false


static func restore(from: Node) -> void:
	var room := room_of(from)
	if room == null:
		return
	var light := room.get_node_or_null(NODE_NAME)
	if light == null or not light.has_method("dismiss"):
		return
	light.call("dismiss")


## Generator rooms are named Room_<x>_<y>_<type>. The glTF child is just "Room".
static func room_of(node: Node) -> Node3D:
	var walker := node
	while walker != null:
		if walker is Node3D and _is_room_root(String(walker.name)):
			return walker as Node3D
		walker = walker.get_parent()
	return null


static func _is_room_root(label: String) -> bool:
	if not label.begins_with("Room_"):
		return false
	var bits := label.split("_")
	if bits.size() < 4:
		return false
	return bits[1].is_valid_int() and bits[2].is_valid_int()


func configure() -> void:
	light_color = FILL_COLOR
	light_energy = HIDE_ENERGY
	omni_range = FILL_RANGE
	# Flat across the tile. A preview-style falloff would leave the corners,
	# where the wardrobes stand, almost as black as the rest of the map.
	omni_attenuation = 0.0
	shadow_enabled = false
	light_cull_mask = ROOM_LAYER
	light_indirect_energy = 0.0
	light_volumetric_fog_energy = 0.0
	position = Vector3(0.0, FILL_HEIGHT, 0.0)


func _ready() -> void:
	configure()
	var room := get_parent()
	if room != null:
		_tag(room)


func dismiss() -> void:
	if _dismissed:
		return
	_dismissed = true
	_restore_layers()
	light_energy = 0.0
	visible = false
	var parent := get_parent()
	if parent != null:
		parent.remove_child(self)
	queue_free()


func _exit_tree() -> void:
	_restore_layers()


func _tag(node: Node) -> void:
	if node is GeometryInstance3D:
		var geo := node as GeometryInstance3D
		_layers.append({"node": geo, "layers": geo.layers})
		geo.layers = geo.layers | ROOM_LAYER
	for child in node.get_children():
		_tag(child)


func _restore_layers() -> void:
	if _layers.is_empty():
		return
	for entry in _layers:
		var geo: Object = entry["node"]
		if geo is GeometryInstance3D and is_instance_valid(geo):
			(geo as GeometryInstance3D).layers = int(entry["layers"])
	_layers.clear()
