extends RefCounted

## Finds a stand that is not inside v2 furniture and has a clear line back to
## `origin`. Used by smokes that used to assume an empty room centre.


static func offset(world: World3D, origin: Vector3, distance: float) -> Vector3:
	var fallback := origin + Vector3(distance, 0.0, 0.0)
	if world == null:
		return fallback
	var space := world.direct_space_state
	if space == null:
		return fallback
	for i in 24:
		var ang := float(i) * TAU / 24.0
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var there: Vector3 = origin + dir * distance
		there.y = origin.y
		if _free(space, there) and _ray_clear(space, origin, there):
			return there
	return fallback


static func nudge(world: World3D, at: Vector3) -> Vector3:
	if world == null:
		return at
	var space := world.direct_space_state
	if space == null or _free(space, at):
		return at
	for i in 16:
		var ang := float(i) * TAU / 16.0
		for radius in [0.8, 1.4, 2.0]:
			var there: Vector3 = at + Vector3(cos(ang), 0.0, sin(ang)) * float(radius)
			there.y = at.y
			if _free(space, there):
				return there
	return at


## Offset perpendicular to the room-to-room axis, far enough that a straight
## line misses the doorway, and clear of props.
static func lateral(world: World3D, from: Vector3, to: Vector3) -> Vector3:
	var axis := to - from
	axis.y = 0.0
	if axis.length() < 0.1:
		return Vector3(0.0, 0.0, 2.2)
	axis = axis.normalized()
	var side := Vector3(-axis.z, 0.0, axis.x)
	var space := world.direct_space_state if world != null else null
	for dist in [2.2, 2.6, 1.8, 3.0]:
		for sign in [1.0, -1.0]:
			var offset: Vector3 = side * dist * sign
			var a: Vector3 = from + offset
			var b: Vector3 = to + offset
			a.y = from.y
			b.y = to.y
			if space == null or (_free(space, a) and _free(space, b)):
				return offset
	return side * 2.2


static func _free(space: PhysicsDirectSpaceState3D, at: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.34
	shape.height = 1.5
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, at + Vector3(0.0, 0.75, 0.0))
	params.collision_mask = 1
	params.collide_with_areas = false
	params.collide_with_bodies = true
	return space.intersect_shape(params, 1).is_empty()


static func _ray_clear(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(a + Vector3(0.0, 1.1, 0.0), b + Vector3(0.0, 1.1, 0.0))
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space.intersect_ray(query).is_empty()
