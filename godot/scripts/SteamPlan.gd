class_name SteamPlan
extends RefCounted

## Chooses the steam puzzle inside the mission wing.
##
## One doorway is the breach. Every other adjacency between the rooms beyond
## that doorway and the rest of the wing is sealed, so the mission item sits
## in a pocket you cannot walk into until the valve is shut. The boiler stays
## on the near side, and the pipe list is a walk from the breach to that valve.

const SIDES: Array[String] = ["N", "S", "E", "W"]

const SIDE_STEPS := {
	"N": Vector2i(0, -1),
	"S": Vector2i(0, 1),
	"E": Vector2i(1, 0),
	"W": Vector2i(-1, 0),
}

const KIND_STAIR := "stair"


static func build(
	cells: Array[Vector2i],
	zone_of: Dictionary,
	floor_of: Dictionary,
	locks: Array,
	stairs: Array
) -> Dictionary:
	if cells.is_empty():
		return {}
	var zone := 0
	for cell in zone_of:
		zone = maxi(zone, int(zone_of[cell]))
	var zone_cells: Array[Vector2i] = []
	for cell in cells:
		if zone_of.is_empty() or int(zone_of.get(cell, 0)) == zone:
			zone_cells.append(cell)
	if zone_cells.size() < 2:
		return {}

	var zone_set := {}
	for cell in zone_cells:
		zone_set[cell] = true
	var stair_cells := {}
	for spec in stairs:
		stair_cells[spec["cell"]] = true
	var exit_cell := _provisional_exit_cell(cells, floor_of)
	var entries := _entries(zone, cells, zone_cells, zone_of, locks)
	var tree := _spanning_tree(entries, zone_set)
	var children: Dictionary = tree["children"]
	var parent_of: Dictionary = tree["parent"]

	var best_score := -1
	var best_tie := 1 << 30
	var best_parent := Vector2i.ZERO
	var best_child := Vector2i.ZERO
	var best_far: Array[Vector2i] = []
	var found := false
	for cell in parent_of:
		var parent = parent_of[cell]
		if parent == null:
			continue
		var child: Vector2i = cell
		var origin: Vector2i = parent
		var far := _subtree(child, children)
		var near_count := zone_cells.size() - far.size()
		if near_count < 2 or far.is_empty():
			continue
		if not _far_is_pocket(far, zone, zone_of, stair_cells, exit_cell):
			continue
		var score := near_count * 1000 - far.size()
		var tie := child.x * 64 + child.y
		if not found or score > best_score or (score == best_score and tie < best_tie):
			found = true
			best_score = score
			best_tie = tie
			best_parent = origin
			best_child = child
			best_far = far
	if not found:
		return {}

	var far_set := {}
	for cell in best_far:
		far_set[cell] = true
	var near_cells: Array[Vector2i] = []
	var near_set := {}
	for cell in zone_cells:
		if far_set.has(cell):
			continue
		near_cells.append(cell)
		near_set[cell] = true

	var boiler := _farthest(best_parent, near_cells, stair_cells)
	var mission := _farthest(best_child, best_far, {exit_cell: true})
	var pipes := _path(best_parent, boiler, near_set)
	var sealed := _seals(best_far, near_set, best_parent, best_child)
	return {
		"from_cell": best_parent,
		"to_cell": best_child,
		"side": _side_between(best_parent, best_child),
		"gallery_cell": best_parent,
		"boiler_cell": boiler,
		"mission_cell": mission,
		"pipe_cells": pipes,
		"near_cells": near_cells,
		"far_cells": best_far,
		"sealed": sealed,
		"floor": int(floor_of.get(boiler, 0)),
		"blocked": true,
	}


static func _entries(
	zone: int,
	cells: Array[Vector2i],
	zone_cells: Array[Vector2i],
	zone_of: Dictionary,
	locks: Array
) -> Array[Vector2i]:
	var entries: Array[Vector2i] = []
	if zone == 0:
		entries.append(cells[0])
		return entries
	for lock in locks:
		if int(lock.get("stage", -1)) != zone:
			continue
		if String(lock.get("kind", "")) == KIND_STAIR:
			continue
		var to: Vector2i = lock["to_cell"]
		if int(zone_of.get(to, -1)) != zone:
			continue
		if entries.has(to):
			continue
		entries.append(to)
	if entries.is_empty():
		entries.append(zone_cells[0])
	return entries


static func _far_is_pocket(
	far: Array[Vector2i],
	zone: int,
	zone_of: Dictionary,
	stair_cells: Dictionary,
	exit_cell: Vector2i
) -> bool:
	var usable := 0
	for cell in far:
		if stair_cells.has(cell):
			return false
		if _touches_outside(cell, zone, zone_of):
			return false
		if cell != exit_cell:
			usable += 1
	return usable >= 1


static func _touches_outside(cell: Vector2i, zone: int, zone_of: Dictionary) -> bool:
	for side in SIDES:
		var nxt: Vector2i = cell + SIDE_STEPS[side]
		if zone_of.has(nxt) and int(zone_of[nxt]) != zone:
			return true
	return false


static func _provisional_exit_cell(cells: Array[Vector2i], floor_of: Dictionary) -> Vector2i:
	var occupied := {}
	for cell in cells:
		if int(floor_of.get(cell, 0)) == 0:
			occupied[cell] = true
	var best: Vector2i = cells[0]
	var best_distance := 1 << 30
	var found := false
	for cell in cells:
		if int(floor_of.get(cell, 0)) != 0:
			continue
		var free := false
		for side in SIDES:
			if not occupied.has(cell + SIDE_STEPS[side]):
				free = true
				break
		if not free:
			continue
		var distance := absi(cell.x - cells[0].x) + absi(cell.y - cells[0].y)
		if distance >= best_distance:
			continue
		best_distance = distance
		best = cell
		found = true
	return best if found else cells[0]


static func _spanning_tree(entries: Array[Vector2i], zone_set: Dictionary) -> Dictionary:
	var parent := {}
	var children := {}
	var seen := {}
	var queue: Array[Vector2i] = []
	for entry in entries:
		if not zone_set.has(entry) or seen.has(entry):
			continue
		seen[entry] = true
		parent[entry] = null
		queue.append(entry)
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for side in SIDES:
			var nxt: Vector2i = cur + SIDE_STEPS[side]
			if not zone_set.has(nxt) or seen.has(nxt):
				continue
			seen[nxt] = true
			parent[nxt] = cur
			if not children.has(cur):
				children[cur] = []
			(children[cur] as Array).append(nxt)
			queue.append(nxt)
	return {"parent": parent, "children": children}


static func _subtree(root: Vector2i, children: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var stack: Array[Vector2i] = [root]
	while not stack.is_empty():
		var cur: Vector2i = stack.pop_back()
		out.append(cur)
		var kids: Array = children.get(cur, [])
		for kid in kids:
			stack.append(kid)
	return out


static func _seals(
	far: Array[Vector2i],
	near_set: Dictionary,
	gallery: Vector2i,
	breach: Vector2i
) -> Array[Dictionary]:
	var sealed: Array[Dictionary] = []
	for cell in far:
		for side in SIDES:
			var nxt: Vector2i = cell + SIDE_STEPS[side]
			if not near_set.has(nxt):
				continue
			if (cell == breach and nxt == gallery) or (cell == gallery and nxt == breach):
				continue
			sealed.append({"a": nxt, "b": cell})
	return sealed


static func _distances(origin: Vector2i, cells: Array) -> Dictionary:
	var allowed := {}
	for cell in cells:
		allowed[cell] = true
	var dist := {origin: 0}
	if not allowed.has(origin):
		return dist
	var queue: Array[Vector2i] = [origin]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for side in SIDES:
			var nxt: Vector2i = cur + SIDE_STEPS[side]
			if not allowed.has(nxt) or dist.has(nxt):
				continue
			dist[nxt] = int(dist[cur]) + 1
			queue.append(nxt)
	return dist


static func _farthest(origin: Vector2i, cells: Array, forbidden: Dictionary) -> Vector2i:
	var dist := _distances(origin, cells)
	var best := origin
	var best_d := -1
	var found := false
	for cell in cells:
		if forbidden.has(cell):
			continue
		var d := int(dist.get(cell, -1))
		if d < 0:
			continue
		var closer_tie: bool = cell.x < best.x or (cell.x == best.x and cell.y < best.y)
		if not found or d > best_d or (d == best_d and closer_tie):
			best = cell
			best_d = d
			found = true
	return best if found else origin


static func _path(start: Vector2i, goal: Vector2i, allowed: Dictionary) -> Array[Vector2i]:
	if start == goal:
		return [start]
	var parent := {}
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var found := false
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == goal:
			found = true
			break
		for side in SIDES:
			var nxt: Vector2i = cur + SIDE_STEPS[side]
			if not allowed.has(nxt) or seen.has(nxt):
				continue
			seen[nxt] = true
			parent[nxt] = cur
			queue.append(nxt)
	if not found:
		return [start]
	var path: Array[Vector2i] = []
	var walker := goal
	while true:
		path.append(walker)
		if walker == start:
			break
		walker = parent[walker]
	path.reverse()
	return path


static func _side_between(a: Vector2i, b: Vector2i) -> String:
	var delta := b - a
	for side in SIDES:
		if SIDE_STEPS[side] == delta:
			return side
	return "E"
