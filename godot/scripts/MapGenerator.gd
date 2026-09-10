class_name MapGenerator
extends Node

## Builds a level out of the four Blender room modules.
##
## A run picks a pseudorandom, always-connected set of grid cells, drops a room
## tile on each one, and opens the doorway between every pair of neighbours by
## deleting the `Plug_<side>` block the Blender modules ship with. Cells facing
## the outside keep their plug, so the map edge stays sealed without needing
## separate wall variants per room.
##
## Generation is a coroutine: it yields a frame per room and reports `progress`
## so the loading screen keeps animating while the map is assembled.

signal progress(fraction: float, label: String)

const TILE := 12.0
## Wall height of the Blender modules; only used to give the level bounds depth.
const ROOM_HEIGHT := 2.4
const WORLD_LAYER := 1
## Smallest box collider edge; Godot complains about degenerate shapes.
const MIN_SHAPE_EDGE := 0.05
## Blender prefixes decoration that should never grow a collider.
const NO_COLLISION_PREFIX := "NoCol_"
## Room floor slab thickness from the Blender modules.
const FLOOR_THICKNESS := 0.1
const GROUND_THICKNESS := 0.6
const GROUND_MARGIN := TILE

const ROOM_TYPES: Array[String] = ["bedroom", "living_room", "office", "storage"]

const ROOM_SCENES := {
	"bedroom": "res://assets/rooms/room_bedroom.glb",
	"living_room": "res://assets/rooms/room_living_room.glb",
	"office": "res://assets/rooms/room_office.glb",
	"storage": "res://assets/rooms/room_storage.glb",
}

const ROOM_LABELS := {
	"bedroom": "СПАЛЬНЯ / BEDROOM",
	"living_room": "ГОСТИНАЯ / LIVING ROOM",
	"office": "КАБИНЕТ / OFFICE",
	"storage": "СКЛАД / STORAGE",
}

const SIDES: Array[String] = ["N", "S", "E", "W"]

const SIDE_STEPS := {
	"N": Vector2i(0, -1),
	"S": Vector2i(0, 1),
	"E": Vector2i(1, 0),
	"W": Vector2i(-1, 0),
}

const OPPOSITE_SIDE := {"N": "S", "S": "N", "E": "W", "W": "E"}


func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(float(cell.x) * TILE, 0.0, float(cell.y) * TILE)


## Assembles the level under `container` and returns the layout description
## used to place the player, monster, objective and exit.
func generate(container: Node3D, level_seed: int, room_count: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed

	var wanted := maxi(room_count, 1)
	progress.emit(0.04, "РАЗМЕТКА СЕКТОРА / SURVEYING SECTOR")
	var cells := _plan_cells(rng, wanted)
	var types := _assign_types(rng, cells.size())

	var occupied := {}
	for index in cells.size():
		occupied[cells[index]] = index

	var rooms: Array[Dictionary] = []
	for index in cells.size():
		var cell: Vector2i = cells[index]
		var type_name: String = types[index]
		var room := _spawn_room(container, cell, type_name, occupied)
		if room == null:
			push_error("MapGenerator: could not instantiate room type '%s'" % type_name)
			continue
		rooms.append({
			"index": index,
			"cell": cell,
			"type": type_name,
			"center": cell_to_world(cell),
			"node": room,
		})
		var done := float(index + 1) / float(cells.size())
		progress.emit(0.08 + 0.78 * done, "МОНТАЖ: %s" % ROOM_LABELS.get(type_name, type_name))
		await get_tree().process_frame

	progress.emit(0.9, "ПРОБИВКА ВЫХОДА / CUTTING THE EXIT")
	var start_cell: Vector2i = cells[0]
	var exit_side := _open_exterior_exit(rooms, start_cell, occupied, rng)
	await get_tree().process_frame

	progress.emit(0.96, "РАССТАНОВКА / PLACING ASSETS")
	var layout := _describe_layout(rooms, cells, start_cell, exit_side, level_seed)
	_add_ground(container, layout["bounds"])
	progress.emit(1.0, "ГОТОВО / READY")
	return layout


# --------------------------------------------------------------------------- #
# Layout planning
# --------------------------------------------------------------------------- #


## Grows the floorplan one neighbour at a time from the start cell, which keeps
## every room reachable without a separate connectivity pass.
func _plan_cells(rng: RandomNumberGenerator, count: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [Vector2i.ZERO]
	var occupied := {Vector2i.ZERO: true}
	# Keep the footprint roughly square so the level does not sprawl into a
	# single corridor and the isometric camera never travels too far.
	var max_span := int(ceil(sqrt(float(count)))) + 1

	var attempts := count * 40
	while cells.size() < count and attempts > 0:
		attempts -= 1
		var from: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		var side: String = SIDES[rng.randi_range(0, SIDES.size() - 1)]
		var candidate: Vector2i = from + SIDE_STEPS[side]
		if occupied.has(candidate):
			continue
		if not _fits_span(cells, candidate, max_span):
			continue
		occupied[candidate] = true
		cells.append(candidate)

	# Random growth can stall inside the span limit; finish deterministically so
	# the caller always gets the room count it asked for.
	var scan := 0
	while cells.size() < count and scan < cells.size():
		var from: Vector2i = cells[scan]
		for side in SIDES:
			if cells.size() >= count:
				break
			var candidate: Vector2i = from + SIDE_STEPS[side]
			if occupied.has(candidate):
				continue
			occupied[candidate] = true
			cells.append(candidate)
		scan += 1

	return cells


func _fits_span(cells: Array[Vector2i], candidate: Vector2i, max_span: int) -> bool:
	var min_x: int = candidate.x
	var max_x: int = candidate.x
	var min_y: int = candidate.y
	var max_y: int = candidate.y
	for cell in cells:
		min_x = mini(min_x, cell.x)
		max_x = maxi(max_x, cell.x)
		min_y = mini(min_y, cell.y)
		max_y = maxi(max_y, cell.y)
	return (max_x - min_x + 1) <= max_span and (max_y - min_y + 1) <= max_span


## Deals one of every room type first so a level always shows all four, then
## fills the rest at random and shuffles with the seeded generator.
func _assign_types(rng: RandomNumberGenerator, count: int) -> Array[String]:
	var bag: Array[String] = []
	for type_name in ROOM_TYPES:
		bag.append(type_name)
	while bag.size() < count:
		bag.append(ROOM_TYPES[rng.randi_range(0, ROOM_TYPES.size() - 1)])
	bag.resize(count)

	# Array.shuffle() draws from the global RNG, which would break seed replay.
	for i in range(bag.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := bag[i]
		bag[i] = bag[j]
		bag[j] = swap
	return bag


# --------------------------------------------------------------------------- #
# Room assembly
# --------------------------------------------------------------------------- #


func _spawn_room(
	container: Node3D,
	cell: Vector2i,
	type_name: String,
	occupied: Dictionary
) -> Node3D:
	var path: String = ROOM_SCENES.get(type_name, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null

	var room := packed.instantiate() as Node3D
	if room == null:
		return null
	room.name = "Room_%d_%d_%s" % [cell.x, cell.y, type_name]
	room.position = cell_to_world(cell)
	container.add_child(room)

	for side in SIDES:
		if occupied.has(cell + SIDE_STEPS[side]):
			open_doorway(room, side)

	_build_room_collision(room)
	return room


## Deletes the doorway filler on one side, turning it into a walkable opening.
func open_doorway(room: Node3D, side: String) -> bool:
	var plug := find_child_by_name(room, "Plug_%s" % side)
	if plug == null:
		return false
	plug.get_parent().remove_child(plug)
	plug.queue_free()
	return true


## One static body per room with a box per mesh. The Blender modules are built
## from axis-aligned boxes and cylinders, so mesh bounds are a close fit and far
## cheaper to cook than trimesh collision on a few hundred props.
func _build_room_collision(room: Node3D) -> int:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(room, meshes)

	var body := StaticBody3D.new()
	body.name = "RoomCollision"
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	room.add_child(body)

	var built := 0
	for mesh_instance in meshes:
		if mesh_instance.name.begins_with(NO_COLLISION_PREFIX):
			continue
		if mesh_instance.mesh == null:
			continue
		var bounds := mesh_instance.mesh.get_aabb()
		var box := BoxShape3D.new()
		box.size = Vector3(
			maxf(bounds.size.x, MIN_SHAPE_EDGE),
			maxf(bounds.size.y, MIN_SHAPE_EDGE),
			maxf(bounds.size.z, MIN_SHAPE_EDGE)
		)
		var shape := CollisionShape3D.new()
		shape.name = "Col_%s" % mesh_instance.name
		shape.shape = box
		shape.transform = (
			_transform_relative_to(mesh_instance, room)
			* Transform3D(Basis.IDENTITY, bounds.get_center())
		)
		body.add_child(shape)
		built += 1
	return built


## Ash flats under and around the map, so the exit doorway does not open onto
## the background colour and the player has ground to escape onto. The slab top
## sits flush with the underside of the room floors to avoid coplanar z-fighting.
func _add_ground(container: Node3D, bounds: AABB) -> void:
	var size := Vector3(
		bounds.size.x + GROUND_MARGIN * 2.0,
		GROUND_THICKNESS,
		bounds.size.z + GROUND_MARGIN * 2.0
	)
	var box_mesh := BoxMesh.new()
	box_mesh.size = size

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.17, 0.17, 0.16)
	material.roughness = 0.95

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = box_mesh
	ground.material_override = material
	ground.position = Vector3(
		bounds.position.x + bounds.size.x * 0.5,
		-FLOOR_THICKNESS - GROUND_THICKNESS * 0.5,
		bounds.position.z + bounds.size.z * 0.5
	)
	container.add_child(ground)

	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	shape.name = "Col_Ground"
	shape.shape = box

	var body := StaticBody3D.new()
	body.name = "GroundCollision"
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	body.add_child(shape)
	ground.add_child(body)


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)


func _transform_relative_to(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var walker: Node = node
	while walker != null and walker != ancestor:
		if walker is Node3D:
			result = (walker as Node3D).transform * result
		walker = walker.get_parent()
	return result


static func find_child_by_name(root: Node, node_name: String) -> Node:
	if root == null:
		return null
	if root.name == node_name:
		return root
	for child in root.get_children():
		var found := find_child_by_name(child, node_name)
		if found != null:
			return found
	return null


# --------------------------------------------------------------------------- #
# Spawn points
# --------------------------------------------------------------------------- #


## Knocks the plug out of one outward-facing wall of the start room so the run
## has a way back out into the ash.
func _open_exterior_exit(
	rooms: Array[Dictionary],
	start_cell: Vector2i,
	occupied: Dictionary,
	rng: RandomNumberGenerator
) -> String:
	var free_sides: Array[String] = []
	for side in SIDES:
		if not occupied.has(start_cell + SIDE_STEPS[side]):
			free_sides.append(side)
	if free_sides.is_empty():
		return ""

	# South reads as "the way you came in" under the isometric camera.
	var side: String = "S" if free_sides.has("S") else free_sides[rng.randi_range(0, free_sides.size() - 1)]
	for room in rooms:
		if room["cell"] == start_cell:
			open_doorway(room["node"], side)
			break
	return side


func _describe_layout(
	rooms: Array[Dictionary],
	cells: Array[Vector2i],
	start_cell: Vector2i,
	exit_side: String,
	level_seed: int
) -> Dictionary:
	var min_cell := start_cell
	var max_cell := start_cell
	for cell in cells:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)

	# The objective belongs as deep into the map as the layout allows.
	var objective_cell := start_cell
	var best_distance := -1
	for cell in cells:
		var distance := absi(cell.x - start_cell.x) + absi(cell.y - start_cell.y)
		if distance > best_distance:
			best_distance = distance
			objective_cell = cell

	# The monster starts between the two so it has ground to cover either way.
	var monster_cell := objective_cell
	var target_distance := maxi(best_distance / 2, 1)
	var closest := 1 << 30
	for cell in cells:
		if cell == start_cell:
			continue
		var distance := absi(cell.x - start_cell.x) + absi(cell.y - start_cell.y)
		var delta := absi(distance - target_distance)
		if delta < closest:
			closest = delta
			monster_cell = cell

	var start_center := cell_to_world(start_cell)
	var exit_position := start_center
	if not exit_side.is_empty():
		# Sit in the doorway itself rather than the wall's centre line.
		exit_position += Vector3(SIDE_STEPS[exit_side].x, 0.0, SIDE_STEPS[exit_side].y) * (TILE * 0.5 - 0.4)

	var room_summaries: Array[Dictionary] = []
	for room in rooms:
		room_summaries.append({
			"index": room["index"],
			"cell": room["cell"],
			"type": room["type"],
			"center": room["center"],
		})

	return {
		"seed": level_seed,
		"rooms": room_summaries,
		"start_cell": start_cell,
		"start": start_center + Vector3(0.0, 0.05, 0.0),
		"exit_side": exit_side,
		"exit": exit_position,
		"objective": cell_to_world(objective_cell) + Vector3(0.0, 0.05, 0.0),
		"objective_cell": objective_cell,
		"monster": cell_to_world(monster_cell) + Vector3(0.0, 0.05, 0.0),
		"monster_cell": monster_cell,
		"bounds": AABB(
			Vector3(float(min_cell.x) * TILE - TILE * 0.5, 0.0, float(min_cell.y) * TILE - TILE * 0.5),
			Vector3(
				float(max_cell.x - min_cell.x + 1) * TILE,
				ROOM_HEIGHT,
				float(max_cell.y - min_cell.y + 1) * TILE
			)
		),
	}
