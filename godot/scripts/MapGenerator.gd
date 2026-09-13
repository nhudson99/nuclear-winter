class_name MapGenerator
extends Node

## Builds a level out of the Blender room modules, including up/down stairwells.
##
## A run picks a pseudorandom, always-connected set of grid cells, drops a room
## tile on each one, and opens the doorway between every pair of neighbours by
## deleting the `Plug_<side>` block the Blender modules ship with. Cells facing
## the outside keep their plug, so the map edge stays sealed without needing
## separate wall variants per room.
##
## Generation also lays a monster track: a graph whose nodes sit on every room
## centre and every interior doorway centre, so the monster can patrol and chase
## without walking into walls or furniture.
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
## Unique-cell offset between stacked floors so zone keys never collide.
const FLOOR_STRIDE := 80
const SIDE_STAIR := "STAIR"
const LOCK_KIND_WING := "wing"
const LOCK_KIND_STAIR := "stair"

const ROOM_TYPES: Array[String] = ["bedroom", "living_room", "office", "storage"]
const STAIR_TYPES: Array[String] = ["stairwell_up", "stairwell_down"]

const ROOM_SCENES := {
	"bedroom": "res://assets/rooms/room_bedroom.glb",
	"living_room": "res://assets/rooms/room_living_room.glb",
	"office": "res://assets/rooms/room_office.glb",
	"storage": "res://assets/rooms/room_storage.glb",
	"stairwell_up": "res://assets/rooms/room_stairwell_up.glb",
	"stairwell_down": "res://assets/rooms/room_stairwell_down.glb",
}

const ROOM_LABELS := {
	"bedroom": "СПАЛЬНЯ / BEDROOM",
	"living_room": "ГОСТИНАЯ / LIVING ROOM",
	"office": "КАБИНЕТ / OFFICE",
	"storage": "СКЛАД / STORAGE",
	"stairwell_up": "ЛЕСТНИЦА ВВЕРХ / STAIRS UP",
	"stairwell_down": "ЛЕСТНИЦА ВНИЗ / STAIRS DOWN",
}

const SIDES: Array[String] = ["N", "S", "E", "W"]

const SIDE_STEPS := {
	"N": Vector2i(0, -1),
	"S": Vector2i(0, 1),
	"E": Vector2i(1, 0),
	"W": Vector2i(-1, 0),
}

const OPPOSITE_SIDE := {"N": "S", "S": "N", "E": "W", "W": "E"}

## Cardinal names used by the monster track and intersection rolls.
## Up is north (-Z), down is south (+Z), matching SIDE_STEPS.
const TRACK_LEFT := "left"
const TRACK_RIGHT := "right"
const TRACK_UP := "up"
const TRACK_DOWN := "down"
const TRACK_DIRS: Array[String] = ["left", "right", "up", "down"]
const TRACK_Y := 0.05
## Only east/south sides are stored so each interior doorway is one node.
const TRACK_CANONICAL_SIDES: Array[String] = ["E", "S"]


static func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(float(cell.x) * TILE, 0.0, float(cell.y) * TILE)


static func floor_origin(floor: int) -> Vector2i:
	return Vector2i(0, floor * FLOOR_STRIDE)


static func is_stair_type(type_name: String) -> bool:
	return type_name == LevelRules.TYPE_STAIR_UP or type_name == LevelRules.TYPE_STAIR_DOWN


static func room_track_id(cell: Vector2i) -> String:
	return "room:%d:%d" % [cell.x, cell.y]


static func door_track_id(cell: Vector2i, side: String) -> String:
	return "door:%d:%d:%s" % [cell.x, cell.y, side]


static func door_track_position(cell: Vector2i, side: String) -> Vector3:
	var step: Vector2i = SIDE_STEPS[side]
	return (
		cell_to_world(cell)
		+ Vector3(float(step.x), 0.0, float(step.y)) * (TILE * 0.5)
		+ Vector3(0.0, TRACK_Y, 0.0)
	)


static func cardinal_from_delta(delta: Vector3) -> String:
	if absf(delta.x) >= absf(delta.z):
		return TRACK_RIGHT if delta.x >= 0.0 else TRACK_LEFT
	return TRACK_DOWN if delta.z >= 0.0 else TRACK_UP


## Shortest planar distance from `pos` to any track node or doorway edge.
static func closest_distance_to_track(pos: Vector3, track: Dictionary) -> float:
	var nodes: Dictionary = track.get("nodes", {})
	if nodes.is_empty():
		return INF
	var best := INF
	for id in nodes:
		var node: Dictionary = nodes[id]
		var origin: Vector3 = node["position"]
		best = minf(best, _planar_distance(pos, origin))
		var exits: Dictionary = node.get("exits", {})
		for dir in exits:
			var other_id: String = str(exits[dir])
			if other_id < str(id):
				continue
			if not nodes.has(other_id):
				continue
			var dest: Vector3 = nodes[other_id]["position"]
			best = minf(best, _distance_to_segment(pos, origin, dest))
	return best


static func _planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _distance_to_segment(point: Vector3, a: Vector3, b: Vector3) -> float:
	var px := Vector2(point.x, point.z)
	var pa := Vector2(a.x, a.z)
	var pb := Vector2(b.x, b.z)
	var ab := pb - pa
	var length_sq := ab.length_squared()
	if length_sq <= 0.0001:
		return px.distance_to(pa)
	var t := clampf((px - pa).dot(ab) / length_sq, 0.0, 1.0)
	return px.distance_to(pa + ab * t)


## Assembles the level under `container` and returns the layout description
## used to place the player, monsters, objectives and exit.
##
## `level` drives locked wings and the enemy roster. Level 1 is a single
## open floorplan (`room_count` rooms). Higher levels pack at most two wings
## per floor; stairwell rooms sit behind the next key and only the active
## floor is instantiated so later levels stay cheap to load.
func generate(
	container: Node3D,
	level_seed: int,
	room_count: int,
	level: int = 1,
	active_floor: int = 0
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed

	var play_level := LevelRules.clamp_level(level)
	var zone_counts: Array[int] = LevelRules.zone_room_counts(play_level)
	if play_level <= 1:
		zone_counts = [maxi(room_count, 1)]

	progress.emit(0.04, "РАЗМЕТКА СЕКТОРА / SURVEYING SECTOR")
	var planned := _plan_floored_level(rng, zone_counts)
	var cells: Array[Vector2i] = planned["cells"]
	var floor_of: Dictionary = planned["floor_of"]
	var types := _assign_types(rng, cells.size())
	var type_of := {}
	for index in cells.size():
		type_of[cells[index]] = types[index]
	_apply_stair_types(type_of, planned["stairs"])

	var occupied := {}
	for index in cells.size():
		occupied[cells[index]] = index

	var wanted_floor := clampi(active_floor, 0, maxi(LevelRules.floor_count(play_level) - 1, 0))
	var to_spawn := 0
	for cell in cells:
		if int(floor_of.get(cell, 0)) == wanted_floor:
			to_spawn += 1

	var rooms: Array[Dictionary] = []
	var spawned := 0
	for index in cells.size():
		var cell: Vector2i = cells[index]
		var type_name: String = String(type_of.get(cell, ROOM_TYPES[0]))
		var room_floor := int(floor_of.get(cell, 0))
		var room: Node3D = null
		if room_floor == wanted_floor:
			room = _spawn_room(container, cell, type_name, occupied, floor_of)
			if room == null:
				push_error("MapGenerator: could not instantiate room type '%s'" % type_name)
			spawned += 1
			var done := float(spawned) / float(maxi(to_spawn, 1))
			progress.emit(0.08 + 0.78 * done, "МОНТАЖ: %s" % ROOM_LABELS.get(type_name, type_name))
			await get_tree().process_frame
		rooms.append({
			"index": index,
			"cell": cell,
			"local_cell": _local_cell(cell, floor_of),
			"floor": room_floor,
			"type": type_name,
			"center": _world_of(cell, floor_of),
			"node": room,
		})

	progress.emit(0.9, "ПРОБИВКА ВЫХОДА / CUTTING THE EXIT")
	var start_cell: Vector2i = cells[0]
	var exit_info := {}
	if wanted_floor == 0:
		exit_info = _open_exterior_exit(rooms, start_cell, occupied, rng, floor_of)
	await get_tree().process_frame

	progress.emit(0.96, "РАССТАНОВКА / PLACING ASSETS")
	planned["active_floor"] = wanted_floor
	var layout := _describe_layout(
		rooms,
		cells,
		start_cell,
		exit_info,
		level_seed,
		play_level,
		planned,
		rng
	)
	_add_locked_doors(container, layout, wanted_floor)
	_add_stairwells(container, layout, wanted_floor)
	_add_ground(container, layout["bounds"])
	_add_monster_track(container, layout["monster_track"])
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


func _local_cell(cell: Vector2i, floor_of: Dictionary) -> Vector2i:
	return cell - floor_origin(int(floor_of.get(cell, 0)))


func _world_of(cell: Vector2i, floor_of: Dictionary) -> Vector3:
	return cell_to_world(_local_cell(cell, floor_of))


func _floor_occupied(occupied: Dictionary, floor_of: Dictionary, floor: int) -> Dictionary:
	var out := {}
	for cell in occupied:
		if int(floor_of.get(cell, 0)) == floor:
			out[cell] = occupied[cell]
	return out


## Packs zones onto floors (max two wings each) and links storeys with stairs.
func _plan_floored_level(rng: RandomNumberGenerator, zone_counts: Array[int]) -> Dictionary:
	var cells: Array[Vector2i] = []
	var zone_of := {}
	var floor_of := {}
	var locks: Array[Dictionary] = []
	var stairs: Array[Dictionary] = []
	if zone_counts.is_empty():
		return {
			"cells": cells,
			"zone_of": zone_of,
			"floor_of": floor_of,
			"locks": locks,
			"stairs": stairs,
		}

	var groups: Array[Dictionary] = []
	var zone_index := 0
	var floor_idx := 0
	while zone_index < zone_counts.size():
		var group_zones: Array[int] = []
		var group_counts: Array[int] = []
		for _i in LevelRules.MAX_WINGS_PER_FLOOR:
			if zone_index >= zone_counts.size():
				break
			group_zones.append(zone_index)
			group_counts.append(maxi(zone_counts[zone_index], 1))
			zone_index += 1
		groups.append({"floor": floor_idx, "zones": group_zones, "counts": group_counts})
		floor_idx += 1

	var cells_by_floor := {}
	for spec in groups:
		var fl: int = spec["floor"]
		var origin := floor_origin(fl)
		var local: Dictionary = _plan_zoned_cells(rng, spec["counts"])
		var remap := {}
		var spec_zones: Array = spec["zones"]
		for i in spec_zones.size():
			remap[i] = spec_zones[i]
		var these: Array[Vector2i] = []
		for local_cell in local["cells"]:
			var cell: Vector2i = local_cell + origin
			cells.append(cell)
			these.append(cell)
			var local_zone := int(local["zone_of"][local_cell])
			zone_of[cell] = remap[local_zone]
			floor_of[cell] = fl
		cells_by_floor[fl] = these
		for lock in local["locks"]:
			var dest_local := int(lock.get("stage", 1))
			locks.append({
				"stage": int(remap.get(dest_local, dest_local)),
				"from_cell": lock["from_cell"] + origin,
				"to_cell": lock["to_cell"] + origin,
				"side": lock["side"],
				"kind": LOCK_KIND_WING,
			})

	for spec in groups:
		var fl: int = spec["floor"]
		if fl >= groups.size() - 1:
			continue
		var spec_zones: Array = spec["zones"]
		var next_zones: Array = groups[fl + 1]["zones"]
		var last_zone: int = spec_zones[spec_zones.size() - 1]
		var next_zone: int = next_zones[0]
		var up_pool := _cells_in_zone(cells, zone_of, last_zone)
		var reserved := {}
		if not cells.is_empty():
			reserved[cells[0]] = true
		var next_cells: Array = cells_by_floor.get(fl + 1, [])
		var down_cell: Vector2i = next_cells[0] if not next_cells.is_empty() else Vector2i.ZERO
		reserved[down_cell] = true
		var up_cell := _pick_stair_cell(up_pool, reserved)
		locks.append({
			"stage": next_zone,
			"from_cell": up_cell,
			"to_cell": down_cell,
			"side": SIDE_STAIR,
			"kind": LOCK_KIND_STAIR,
		})
		stairs.append({
			"direction": Stairwell.DIR_UP,
			"cell": up_cell,
			"floor": fl,
			"dest_floor": fl + 1,
			"dest_cell": down_cell,
			"required_stage": next_zone,
		})
		stairs.append({
			"direction": Stairwell.DIR_DOWN,
			"cell": down_cell,
			"floor": fl + 1,
			"dest_floor": fl,
			"dest_cell": up_cell,
			"required_stage": 0,
		})

	return {
		"cells": cells,
		"zone_of": zone_of,
		"floor_of": floor_of,
		"locks": locks,
		"stairs": stairs,
	}


func _pick_stair_cell(pool: Array, reserved: Dictionary) -> Vector2i:
	for i in range(pool.size() - 1, -1, -1):
		var cell: Vector2i = pool[i]
		if not reserved.has(cell):
			return cell
	return pool[0] if not pool.is_empty() else Vector2i.ZERO


func _apply_stair_types(type_of: Dictionary, stairs: Array) -> void:
	for spec in stairs:
		var cell: Vector2i = spec["cell"]
		if String(spec.get("direction", "")) == Stairwell.DIR_UP:
			type_of[cell] = LevelRules.TYPE_STAIR_UP
		else:
			type_of[cell] = LevelRules.TYPE_STAIR_DOWN


## Grows one connected zone per entry in `zone_counts`. Neighbouring zones
## share exactly one doorway, which the caller turns into a locked door.
func _plan_zoned_cells(rng: RandomNumberGenerator, zone_counts: Array[int]) -> Dictionary:
	var cells: Array[Vector2i] = []
	var zone_of := {}
	var locks: Array[Dictionary] = []
	if zone_counts.is_empty():
		return {"cells": cells, "zone_of": zone_of, "locks": locks}

	if zone_counts.size() == 1:
		var single: Array[Vector2i] = _plan_cells(rng, maxi(zone_counts[0], 1))
		for cell in single:
			cells.append(cell)
			zone_of[cell] = 0
		return {"cells": cells, "zone_of": zone_of, "locks": locks}

	var total := 0
	for count in zone_counts:
		total += maxi(count, 1)
	var max_span := int(ceil(sqrt(float(total)))) + 2 + zone_counts.size()

	var first_zone: Array[Vector2i] = _plan_cells_limited(rng, maxi(zone_counts[0], 1), max_span)
	for cell in first_zone:
		cells.append(cell)
		zone_of[cell] = 0

	for zone_index in range(1, zone_counts.size()):
		var wanted := maxi(zone_counts[zone_index], 1)
		var prev_cells: Array[Vector2i] = []
		for cell in cells:
			if int(zone_of[cell]) == zone_index - 1:
				prev_cells.append(cell)
		var attach := _pick_zone_attachment(rng, cells, prev_cells, max_span)
		if attach.is_empty():
			max_span += 4
			attach = _pick_zone_attachment(rng, cells, prev_cells, max_span)
		if attach.is_empty():
			attach = _force_zone_attachment(cells, prev_cells)
		if attach.is_empty():
			push_error("MapGenerator: could not attach locked zone %d" % zone_index)
			break

		var occupied := {}
		for cell in cells:
			occupied[cell] = true
		var grown: Array[Vector2i] = _grow_isolated_zone(
			rng,
			attach["to"],
			wanted,
			occupied,
			max_span
		)
		for cell in grown:
			cells.append(cell)
			zone_of[cell] = zone_index

	# Recompute locks from the final neighbourhood so an extra accidental
	# abutment cannot bypass a key.
	locks = _locks_from_zones(cells, zone_of)
	return {"cells": cells, "zone_of": zone_of, "locks": locks}


func _locks_from_zones(cells: Array[Vector2i], zone_of: Dictionary) -> Array[Dictionary]:
	var locks: Array[Dictionary] = []
	var seen := {}
	for cell in cells:
		var zone := int(zone_of.get(cell, 0))
		for side in SIDES:
			var neighbor: Vector2i = cell + SIDE_STEPS[side]
			if not zone_of.has(neighbor):
				continue
			var other := int(zone_of[neighbor])
			if other <= zone:
				continue
			var key := edge_key(cell, neighbor)
			if seen.has(key):
				continue
			seen[key] = true
			locks.append({
				"stage": other,
				"from_cell": cell,
				"to_cell": neighbor,
				"side": side,
			})
	return locks


func _plan_cells_limited(rng: RandomNumberGenerator, count: int, max_span: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [Vector2i.ZERO]
	var occupied := {Vector2i.ZERO: true}
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


## New wings may only touch the previous wing at the locked doorway, otherwise
## the player could walk around the lock.
func _pick_zone_attachment(
	rng: RandomNumberGenerator,
	cells: Array[Vector2i],
	prev_cells: Array[Vector2i],
	max_span: int
) -> Dictionary:
	var occupied := {}
	for cell in cells:
		occupied[cell] = true
	var candidates: Array[Dictionary] = []
	var pool: Array[Vector2i] = prev_cells if not prev_cells.is_empty() else cells
	for from in pool:
		for side in SIDES:
			var candidate: Vector2i = from + SIDE_STEPS[side]
			if occupied.has(candidate):
				continue
			if not _fits_span(cells, candidate, max_span):
				continue
			if _occupied_neighbor_count(candidate, occupied) != 1:
				continue
			candidates.append({"from": from, "to": candidate, "side": side})
	if candidates.is_empty():
		return {}
	return candidates[rng.randi_range(0, candidates.size() - 1)]


func _force_zone_attachment(cells: Array[Vector2i], prev_cells: Array[Vector2i]) -> Dictionary:
	var occupied := {}
	for cell in cells:
		occupied[cell] = true
	var pool: Array[Vector2i] = prev_cells if not prev_cells.is_empty() else cells
	for from in pool:
		for side in SIDES:
			var candidate: Vector2i = from + SIDE_STEPS[side]
			if occupied.has(candidate):
				continue
			if _occupied_neighbor_count(candidate, occupied) != 1:
				continue
			return {"from": from, "to": candidate, "side": side}
	for from in pool:
		for side in SIDES:
			var candidate: Vector2i = from + SIDE_STEPS[side]
			if occupied.has(candidate):
				continue
			return {"from": from, "to": candidate, "side": side}
	return {}


func _grow_isolated_zone(
	rng: RandomNumberGenerator,
	seed_cell: Vector2i,
	count: int,
	foreign: Dictionary,
	max_span: int
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [seed_cell]
	var occupied := foreign.duplicate()
	occupied[seed_cell] = true
	var all_cells: Array[Vector2i] = []
	for cell in foreign:
		all_cells.append(cell)
	all_cells.append(seed_cell)

	var attempts := count * 60
	while cells.size() < count and attempts > 0:
		attempts -= 1
		var from: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		var side: String = SIDES[rng.randi_range(0, SIDES.size() - 1)]
		var candidate: Vector2i = from + SIDE_STEPS[side]
		if occupied.has(candidate):
			continue
		if not _fits_span(all_cells, candidate, max_span):
			continue
		if _touches_foreign(candidate, foreign, cells):
			continue
		occupied[candidate] = true
		cells.append(candidate)
		all_cells.append(candidate)

	var scan := 0
	while cells.size() < count and scan < cells.size():
		var from: Vector2i = cells[scan]
		for side in SIDES:
			if cells.size() >= count:
				break
			var candidate: Vector2i = from + SIDE_STEPS[side]
			if occupied.has(candidate):
				continue
			if _touches_foreign(candidate, foreign, cells):
				continue
			occupied[candidate] = true
			cells.append(candidate)
			all_cells.append(candidate)
		scan += 1

	# Last resort: walk a corridor away from the existing map so the wing
	# still reaches the requested room count.
	var walker := cells[cells.size() - 1]
	var guard := 0
	while cells.size() < count and guard < count * 8:
		guard += 1
		var placed := false
		for side in SIDES:
			var candidate: Vector2i = walker + SIDE_STEPS[side]
			if occupied.has(candidate):
				continue
			if _touches_foreign(candidate, foreign, cells):
				continue
			occupied[candidate] = true
			cells.append(candidate)
			walker = candidate
			placed = true
			break
		if not placed:
			walker += Vector2i(0, 1)
	return cells


func _occupied_neighbor_count(cell: Vector2i, occupied: Dictionary) -> int:
	var n := 0
	for side in SIDES:
		if occupied.has(cell + SIDE_STEPS[side]):
			n += 1
	return n


func _touches_foreign(candidate: Vector2i, foreign: Dictionary, zone_cells: Array[Vector2i]) -> bool:
	var zone := {}
	for cell in zone_cells:
		zone[cell] = true
	for side in SIDES:
		var neighbor: Vector2i = candidate + SIDE_STEPS[side]
		if foreign.has(neighbor) and not zone.has(neighbor):
			return true
	return false


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


## Deals the room types in whole cycles, so every level shows all four and no
## type can dominate; the cycle order is shuffled first so which types get the
## leftover slots still varies by seed.
func _assign_types(rng: RandomNumberGenerator, count: int) -> Array[String]:
	var bag: Array[String] = []
	while bag.size() < count:
		var cycle: Array[String] = ROOM_TYPES.duplicate()
		_shuffle(cycle, rng)
		for type_name in cycle:
			if bag.size() >= count:
				break
			bag.append(type_name)
	_shuffle(bag, rng)
	return bag


## Array.shuffle() draws from the global RNG, which would break seed replay.
func _shuffle(values: Array[String], rng: RandomNumberGenerator) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := values[i]
		values[i] = values[j]
		values[j] = swap


# --------------------------------------------------------------------------- #
# Room assembly
# --------------------------------------------------------------------------- #


func _spawn_room(
	container: Node3D,
	cell: Vector2i,
	type_name: String,
	occupied: Dictionary,
	floor_of: Dictionary = {}
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
	room.position = _world_of(cell, floor_of)
	container.add_child(room)

	var room_floor := int(floor_of.get(cell, 0))
	var floor_cells := _floor_occupied(occupied, floor_of, room_floor)
	for side in SIDES:
		if floor_cells.has(cell + SIDE_STEPS[side]):
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
# Monster track
# --------------------------------------------------------------------------- #


## Graph of room centres linked through the centre of every interior doorway.
## Each node stores cardinal exits (`left` / `right` / `up` / `down`) so the
## monster can roll a turn at intersections. Locked edges are omitted until
## `add_unlocked_door_to_track` stitches them in.
func build_monster_track(
	rooms: Array,
	occupied: Dictionary,
	locked_edges: Dictionary = {},
	floor_of: Dictionary = {}
) -> Dictionary:
	var nodes := {}
	for room in rooms:
		var cell: Vector2i = room["cell"]
		var id := room_track_id(cell)
		nodes[id] = {
			"id": id,
			"kind": "room",
			"cell": cell,
			"position": _world_of(cell, floor_of) + Vector3(0.0, TRACK_Y, 0.0),
			"exits": {},
		}

	for room in rooms:
		var cell: Vector2i = room["cell"]
		for side in TRACK_CANONICAL_SIDES:
			var neighbor: Vector2i = cell + SIDE_STEPS[side]
			if not occupied.has(neighbor):
				continue
			if locked_edges.has(edge_key(cell, neighbor)):
				continue
			var door_id := door_track_id(cell, side)
			nodes[door_id] = {
				"id": door_id,
				"kind": "door",
				"cell": cell,
				"side": side,
				"position": door_track_position(_local_cell(cell, floor_of), side),
				"exits": {},
			}
			_link_track_nodes(nodes, room_track_id(cell), door_id)
			_link_track_nodes(nodes, door_id, room_track_id(neighbor))

	return {"nodes": nodes}


static func edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y <= b.y):
		return "%d:%d|%d:%d" % [a.x, a.y, b.x, b.y]
	return "%d:%d|%d:%d" % [b.x, b.y, a.x, a.y]


## Opens a previously locked doorway on an existing track so patrols can cross.
static func add_unlocked_door_to_track(
	track: Dictionary,
	from_cell: Vector2i,
	side: String,
	to_cell: Vector2i,
	floor: int = 0
) -> String:
	if side == SIDE_STAIR:
		return ""
	var nodes: Dictionary = track.get("nodes", {})
	var cell := from_cell
	var canon_side := side
	if not TRACK_CANONICAL_SIDES.has(side):
		cell = to_cell
		canon_side = String(OPPOSITE_SIDE.get(side, "E"))
	var door_id := door_track_id(cell, canon_side)
	var local_cell := cell - floor_origin(floor)
	if not nodes.has(door_id):
		nodes[door_id] = {
			"id": door_id,
			"kind": "door",
			"cell": cell,
			"side": canon_side,
			"position": door_track_position(local_cell, canon_side),
			"exits": {},
		}
	_link_track_nodes(nodes, room_track_id(from_cell), door_id)
	_link_track_nodes(nodes, door_id, room_track_id(to_cell))
	track["nodes"] = nodes
	return door_id


static func _link_track_nodes(nodes: Dictionary, a_id: String, b_id: String) -> void:
	if not nodes.has(a_id) or not nodes.has(b_id):
		return
	var from_pos: Vector3 = nodes[a_id]["position"]
	var to_pos: Vector3 = nodes[b_id]["position"]
	var ab := cardinal_from_delta(to_pos - from_pos)
	var ba := cardinal_from_delta(from_pos - to_pos)
	(nodes[a_id]["exits"] as Dictionary)[ab] = b_id
	(nodes[b_id]["exits"] as Dictionary)[ba] = a_id


func _add_monster_track(container: Node3D, track: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "MonsterTrack"
	container.add_child(root)
	var nodes: Dictionary = track.get("nodes", {})
	for id in nodes:
		var info: Dictionary = nodes[id]
		var marker := Marker3D.new()
		marker.name = str(id).replace(":", "_")
		marker.position = info["position"]
		marker.set_meta("track_id", id)
		marker.set_meta("kind", String(info.get("kind", "")))
		root.add_child(marker)


# --------------------------------------------------------------------------- #
# Spawn points
# --------------------------------------------------------------------------- #


## Knocks the plug out of one outward-facing wall so the run has a way back out
## into the ash. Usually that is the start room, but growth can bury the start
## cell in the middle of the map, so the nearest room with an outward-facing wall
## is used instead. Some room always has one.
func _open_exterior_exit(
	rooms: Array[Dictionary],
	start_cell: Vector2i,
	occupied: Dictionary,
	rng: RandomNumberGenerator,
	floor_of: Dictionary = {}
) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := 1 << 30
	var floor_cells := _floor_occupied(occupied, floor_of, 0)
	for room in rooms:
		if room.get("node") == null:
			continue
		var cell: Vector2i = room["cell"]
		if int(floor_of.get(cell, 0)) != 0:
			continue
		var distance := absi(cell.x - start_cell.x) + absi(cell.y - start_cell.y)
		if distance >= best_distance:
			continue
		var free_sides: Array[String] = []
		for side in SIDES:
			if not floor_cells.has(cell + SIDE_STEPS[side]):
				free_sides.append(side)
		if free_sides.is_empty():
			continue
		best_distance = distance
		# South reads as "the way you came in" under the isometric camera.
		var side: String = (
			"S" if free_sides.has("S")
			else free_sides[rng.randi_range(0, free_sides.size() - 1)]
		)
		best = {"cell": cell, "side": side, "node": room["node"]}

	if best.is_empty():
		push_error("MapGenerator: no room has an outward-facing wall for the exit")
		return {}
	open_doorway(best["node"], best["side"])
	return {"cell": best["cell"], "side": best["side"]}


func _add_locked_doors(container: Node3D, layout: Dictionary, active_floor: int = 0) -> void:
	var locks: Array = layout.get("locks", [])
	var floor_of: Dictionary = layout.get("floors", {})
	var root := Node3D.new()
	root.name = "LockedDoors"
	container.add_child(root)
	for spec in locks:
		var from_cell: Vector2i = spec["from_cell"]
		if int(floor_of.get(from_cell, 0)) != active_floor:
			continue
		var door := LockedDoor.new()
		var to_cell: Vector2i = spec["to_cell"]
		door.name = "LockedDoor_%d_%d_%d" % [int(spec.get("stage", 1)), from_cell.x, from_cell.y]
		var side: String = spec["side"]
		var size := _door_size_for_side(side)
		if String(spec.get("kind", LOCK_KIND_WING)) == LOCK_KIND_STAIR:
			door.position = _stair_door_position(layout, spec)
		else:
			door.position = (_world_of(from_cell, floor_of) + _world_of(to_cell, floor_of)) * 0.5
		root.add_child(door)
		door.configure(int(spec.get("stage", 1)), from_cell, to_cell, side, size)
		spec["position"] = door.global_position if door.is_inside_tree() else door.position
		spec["node_name"] = door.name


func _add_stairwells(container: Node3D, layout: Dictionary, active_floor: int) -> void:
	var stairs: Array = layout.get("stairs", [])
	if stairs.is_empty():
		return
	var root := Node3D.new()
	root.name = "Stairwells"
	container.add_child(root)
	for spec in stairs:
		if int(spec.get("floor", 0)) != active_floor:
			continue
		var stair := Stairwell.new()
		stair.configure(spec)
		stair.position = spec.get("position", Vector3.ZERO)
		root.add_child(stair)
		spec["node_name"] = stair.name


func _stair_door_position(layout: Dictionary, spec: Dictionary) -> Vector3:
	var from_cell: Vector2i = spec["from_cell"]
	for room in layout.get("rooms", []):
		if room.get("cell") != from_cell:
			continue
		var node: Node3D = room.get("node") as Node3D
		if node:
			var marker := find_child_by_name(node, "StairUse")
			if marker is Node3D:
				return (marker as Node3D).global_position
		return room.get("center", _world_of(from_cell, layout.get("floors", {})))
	return _world_of(from_cell, layout.get("floors", {}))


func _door_size_for_side(side: String) -> Vector3:
	if side == SIDE_STAIR:
		return Vector3(1.9, 2.2, 0.28)
	if side == "E" or side == "W":
		return Vector3(0.42, 2.3, 3.5)
	return Vector3(3.5, 2.3, 0.42)


func _describe_layout(
	rooms: Array[Dictionary],
	cells: Array[Vector2i],
	start_cell: Vector2i,
	exit_info: Dictionary,
	level_seed: int,
	level: int = 1,
	planned: Dictionary = {},
	rng: RandomNumberGenerator = null
) -> Dictionary:
	var exit_cell: Vector2i = exit_info.get("cell", start_cell)
	var exit_side: String = exit_info.get("side", "")
	var zone_of: Dictionary = planned.get("zone_of", {})
	var floor_of: Dictionary = planned.get("floor_of", {})
	if zone_of.is_empty():
		for cell in cells:
			zone_of[cell] = 0
	if floor_of.is_empty():
		for cell in cells:
			floor_of[cell] = 0
	var locks: Array = planned.get("locks", []).duplicate(true)
	var stairs: Array = planned.get("stairs", []).duplicate(true)
	var active_floor := int(planned.get("active_floor", 0))
	var last_zone := 0
	for cell in zone_of:
		last_zone = maxi(last_zone, int(zone_of[cell]))

	# Mission item lives in the deepest wing. On level 1 that is simply the
	# room furthest from the exit; on later levels it is the last locked zone.
	var last_zone_cells := _cells_in_zone(cells, zone_of, last_zone)
	var reserved := {start_cell: true}
	if exit_cell != Vector2i.ZERO or not exit_side.is_empty():
		reserved[exit_cell] = true
	for spec in stairs:
		reserved[spec["cell"]] = true
	var objective_cell := _pick_item_cell(last_zone_cells, start_cell, exit_cell, reserved)
	reserved[objective_cell] = true

	var key_specs: Array[Dictionary] = []
	for lock in locks:
		var stage := int(lock.get("stage", 1))
		var key_zone := stage - 1
		var key_cells := _cells_in_zone(cells, zone_of, key_zone)
		var avoid := reserved.duplicate()
		avoid[lock["from_cell"]] = true
		avoid[lock["to_cell"]] = true
		var key_cell := _pick_item_cell(key_cells, start_cell, lock["from_cell"], avoid)
		reserved[key_cell] = true
		lock["key_cell"] = key_cell
		key_specs.append({
			"stage": stage,
			"cell": key_cell,
			"position": _world_of(key_cell, floor_of) + Vector3(0.0, 0.05, 0.0),
			"zone": key_zone,
			"floor": int(floor_of.get(key_cell, 0)),
		})

	var enemies := _place_enemy_roster(
		cells, start_cell, objective_cell, zone_of, floor_of, level, reserved, rng
	)
	var slime_cell := _first_enemy_cell(enemies, LevelRules.KIND_SLIME, start_cell)
	var monster_cell := _first_enemy_cell(enemies, LevelRules.KIND_HARE, objective_cell)
	var tank_cell := _first_enemy_cell(enemies, LevelRules.KIND_TANK, objective_cell)

	var start_center := _world_of(start_cell, floor_of)
	var exit_position := _world_of(exit_cell, floor_of)
	if not exit_side.is_empty():
		# Sit in the doorway itself rather than the wall's centre line.
		exit_position += Vector3(SIDE_STEPS[exit_side].x, 0.0, SIDE_STEPS[exit_side].y) * (TILE * 0.5 - 0.4)

	var room_summaries: Array[Dictionary] = []
	for room in rooms:
		var cell: Vector2i = room["cell"]
		room_summaries.append({
			"index": room["index"],
			"cell": cell,
			"local_cell": room.get("local_cell", _local_cell(cell, floor_of)),
			"type": room["type"],
			"center": room["center"],
			"zone": int(zone_of.get(cell, 0)),
			"floor": int(floor_of.get(cell, room.get("floor", 0))),
			"node": room.get("node"),
		})

	var stair_specs: Array[Dictionary] = []
	for spec in stairs:
		var stair_cell: Vector2i = spec["cell"]
		var marker := _stair_use_position(rooms, stair_cell, floor_of)
		var filled := spec.duplicate(true)
		filled["position"] = marker
		filled["zone"] = int(zone_of.get(stair_cell, 0))
		stair_specs.append(filled)

	var occupied := {}
	var active_rooms: Array[Dictionary] = []
	var local_min := Vector2i(1 << 20, 1 << 20)
	var local_max := Vector2i(-(1 << 20), -(1 << 20))
	var have_active := false
	for room in rooms:
		var cell: Vector2i = room["cell"]
		if int(floor_of.get(cell, 0)) != active_floor:
			continue
		occupied[cell] = true
		active_rooms.append(room)
		var local: Vector2i = room.get("local_cell", _local_cell(cell, floor_of))
		local_min.x = mini(local_min.x, local.x)
		local_min.y = mini(local_min.y, local.y)
		local_max.x = maxi(local_max.x, local.x)
		local_max.y = maxi(local_max.y, local.y)
		have_active = true
	if not have_active:
		local_min = Vector2i.ZERO
		local_max = Vector2i.ZERO
	var locked_edges := {}
	for lock in locks:
		if String(lock.get("kind", LOCK_KIND_WING)) == LOCK_KIND_STAIR:
			continue
		if int(floor_of.get(lock["from_cell"], 0)) != active_floor:
			continue
		locked_edges[edge_key(lock["from_cell"], lock["to_cell"])] = true

	return {
		"seed": level_seed,
		"level": level,
		"active_floor": active_floor,
		"floor_count": LevelRules.floor_count(level),
		"rooms": room_summaries,
		"start_cell": start_cell,
		"start": start_center + Vector3(0.0, 0.05, 0.0),
		"exit_side": exit_side,
		"exit_cell": exit_cell,
		"exit": exit_position,
		"objective": _world_of(objective_cell, floor_of) + Vector3(0.0, 0.05, 0.0),
		"objective_cell": objective_cell,
		"objective_floor": int(floor_of.get(objective_cell, 0)),
		"monster": _world_of(monster_cell, floor_of) + Vector3(0.0, 0.05, 0.0),
		"monster_cell": monster_cell,
		"slime": _world_of(slime_cell, floor_of) + Vector3(0.0, 0.05, 0.0),
		"slime_cell": slime_cell,
		"tank": _world_of(tank_cell, floor_of) + Vector3(0.0, 0.05, 0.0),
		"tank_cell": tank_cell,
		"enemies": enemies,
		"keys": key_specs,
		"locks": locks,
		"stairs": stair_specs,
		"zones": zone_of,
		"floors": floor_of,
		"objectives": LevelRules.objectives(level),
		"monster_track": build_monster_track(active_rooms, occupied, locked_edges, floor_of),
		"bounds": AABB(
			Vector3(float(local_min.x) * TILE - TILE * 0.5, 0.0, float(local_min.y) * TILE - TILE * 0.5),
			Vector3(
				float(local_max.x - local_min.x + 1) * TILE,
				ROOM_HEIGHT,
				float(local_max.y - local_min.y + 1) * TILE
			)
		),
	}


func _stair_use_position(rooms: Array, cell: Vector2i, floor_of: Dictionary) -> Vector3:
	for room in rooms:
		if room.get("cell") != cell:
			continue
		var node: Node3D = room.get("node") as Node3D
		if node:
			var marker := find_child_by_name(node, "StairUse")
			if marker is Node3D:
				return (marker as Node3D).global_position
		return room.get("center", _world_of(cell, floor_of)) + Vector3(0.0, 0.9, 0.0)
	return _world_of(cell, floor_of) + Vector3(0.0, 0.9, 0.0)


func _cells_in_zone(cells: Array[Vector2i], zone_of: Dictionary, zone: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in cells:
		if int(zone_of.get(cell, 0)) == zone:
			out.append(cell)
	return out if not out.is_empty() else cells


func _pick_item_cell(
	candidates: Array,
	start_cell: Vector2i,
	away_from: Vector2i,
	forbidden: Dictionary
) -> Vector2i:
	var best: Vector2i = start_cell
	var found := false
	var best_score := -1
	for cell in candidates:
		if forbidden.has(cell):
			continue
		if cell == start_cell and candidates.size() > 1:
			continue
		var from_away := absi(cell.x - away_from.x) + absi(cell.y - away_from.y)
		var from_start := absi(cell.x - start_cell.x) + absi(cell.y - start_cell.y)
		var score := from_away * 100 + from_start
		if not found or score > best_score:
			best = cell
			best_score = score
			found = true
	if found:
		return best
	for cell in candidates:
		if cell != start_cell:
			return cell
	return candidates[0] if not candidates.is_empty() else start_cell


func _place_enemy_roster(
	cells: Array[Vector2i],
	start_cell: Vector2i,
	objective_cell: Vector2i,
	zone_of: Dictionary,
	floor_of: Dictionary,
	level: int,
	reserved: Dictionary = {},
	rng: RandomNumberGenerator = null
) -> Array[Dictionary]:
	var kinds := LevelRules.monster_kinds(level)
	var last_zone := 0
	for cell in zone_of:
		last_zone = maxi(last_zone, int(zone_of[cell]))
	var forbidden := reserved.duplicate()
	forbidden[start_cell] = true
	var enemies: Array[Dictionary] = []
	var randomize := LevelRules.randomize_monster_spawns(level) and rng != null
	for kind in kinds:
		var pool: Array[Vector2i] = cells
		var near := true
		var anchor := start_cell
		match kind:
			LevelRules.KIND_SLIME:
				pool = _cells_in_zone(cells, zone_of, 0)
				near = true
				anchor = start_cell
			LevelRules.KIND_HARE:
				var mid_zone := last_zone / 2
				pool = _cells_in_zone(cells, zone_of, mid_zone)
				near = false
				anchor = start_cell
			LevelRules.KIND_TANK:
				pool = _cells_in_zone(cells, zone_of, last_zone)
				near = true
				anchor = objective_cell
			_:
				push_error("MapGenerator: unknown monster kind '%s'" % kind)
		var cell := (
			_pick_random_spawn_cell(pool, forbidden, rng)
			if randomize
			else _pick_spawn_cell(pool, forbidden, anchor, near)
		)
		if forbidden.has(cell) or cell == start_cell:
			cell = (
				_pick_random_spawn_cell(cells, forbidden, rng)
				if randomize
				else _pick_spawn_cell(cells, forbidden, objective_cell, true)
			)
		forbidden[cell] = true
		enemies.append({
			"kind": kind,
			"cell": cell,
			"position": _world_of(cell, floor_of) + Vector3(0.0, 0.05, 0.0),
			"zone": int(zone_of.get(cell, 0)),
			"floor": int(floor_of.get(cell, 0)),
		})
	return enemies


func _pick_random_spawn_cell(
	cells: Array,
	forbidden: Dictionary,
	rng: RandomNumberGenerator
) -> Vector2i:
	var options: Array[Vector2i] = []
	for cell in cells:
		if forbidden.has(cell):
			continue
		options.append(cell)
	if options.is_empty():
		return _pick_spawn_cell(cells, forbidden, Vector2i.ZERO, true)
	return options[rng.randi_range(0, options.size() - 1)]


func _first_enemy_cell(enemies: Array, kind: String, fallback: Vector2i) -> Vector2i:
	for spec in enemies:
		if String(spec.get("kind", "")) == kind:
			return spec["cell"]
	return fallback


## Picks a leftover room. `near_anchor` prefers the closest unused cell to
## `anchor`; otherwise the furthest unused cell is used (the Tank camps the back).
func _pick_spawn_cell(cells: Array, forbidden: Dictionary, anchor: Vector2i, near_anchor: bool) -> Vector2i:
	var best: Vector2i = anchor
	var found := false
	var best_score := 0
	for cell in cells:
		if forbidden.has(cell):
			continue
		var dist := absi(cell.x - anchor.x) + absi(cell.y - anchor.y)
		var score := -dist if near_anchor else dist
		if not found or score > best_score:
			best = cell
			best_score = score
			found = true
	return best if found else anchor
