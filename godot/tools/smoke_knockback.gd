extends SceneTree

const Clear := preload("res://tools/smoke_clear.gd")

## A player hit shoves a monster away on the floor plane. The shove replaces
## rather than stacks, bleeds off inside one melee cooldown, and the flashlight
## pin still holds the stalker.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var gp: Node = root.get_node("GameProgress")
	gp.reset_for_tests()
	gp.has_pistol = false

	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed == null:
		push_error("Missing Main.tscn")
		quit(1)
		return
	var main: Node3D = packed.instantiate()
	root.add_child(main)
	if not main.is_level_ready():
		await main.level_ready

	var player: CharacterBody3D = main.get_node("Player")
	var slime: CharacterBody3D = main.get_node("Slime")
	var stalker: CharacterBody3D = main.get_node("Monster")
	player.unlock_input()
	player.set_physics_process(false)
	main.park_monsters()

	var layout: Dictionary = main.get_layout()
	var anchor: Vector3 = layout.get("start", Vector3.ZERO)
	anchor.y = 0.05
	var world := player.get_world_3d()
	anchor = Clear.nudge(world, anchor)
	var ahead := Clear.offset(world, anchor, 2.6)
	var to_ahead := ahead - anchor
	to_ahead.y = 0.0
	if to_ahead.length() < 0.05:
		to_ahead = Vector3(1.0, 0.0, 0.0)
	else:
		to_ahead = to_ahead.normalized()

	var melee := await _shove_case(player, slime, anchor, to_ahead, false)
	print(
		"melee_knock_ok=", melee.ok,
		" along=", melee.along,
		" hp=", melee.health,
		" hit=", melee.hit
	)

	gp.has_pistol = true
	gp.pistol_loaded = 10
	gp.selected_weapon = GameProgress.WeaponId.PISTOL
	var shot := await _shove_case(player, slime, anchor, to_ahead, true)
	print(
		"pistol_knock_ok=", shot.ok,
		" along=", shot.along,
		" hp=", shot.health,
		" hit=", shot.hit
	)

	slime.set_physics_process(false)
	slime.global_position = anchor + to_ahead * 1.15
	slime.health = 40.0
	_face(player, slime.global_position)
	for _i in 5:
		slime.take_damage(1.0)
	var shove: Vector3 = slime._knockback
	var stack_ok := (
		is_equal_approx(shove.length(), slime.knockback_speed)
		and is_equal_approx(float(slime.health), 35.0)
		and shove.normalized().dot(to_ahead) > 0.95
	)
	print("stack_ok=", stack_ok, " speed=", shove.length(), " hp=", slime.health)
	slime._clear_knockback()

	var dark := await _stalker_case(player, stalker, slime, anchor, to_ahead, false)
	print(
		"stalker_dark_ok=", dark.ok,
		" along=", dark.along,
		" hp=", dark.health,
		" lit=", dark.lit
	)
	var pinned := await _stalker_case(player, stalker, slime, anchor, to_ahead, true)
	print(
		"stalker_pin_ok=", pinned.ok,
		" along=", pinned.along,
		" hp=", pinned.health,
		" lit=", pinned.lit
	)

	var all_ok: bool = melee.ok and shot.ok and stack_ok and dark.ok and pinned.ok
	print("knockback_smoke_ok=", all_ok)
	quit(0 if all_ok else 1)


func _shove_case(
	player: CharacterBody3D,
	slime: CharacterBody3D,
	anchor: Vector3,
	to_ahead: Vector3,
	gun: bool
) -> Dictionary:
	var stand := anchor + to_ahead * 1.15
	stand.y = anchor.y
	slime.visible = true
	slime.touch_damage = 0.0
	slime.health = 45.0
	slime.global_position = stand
	slime.velocity = Vector3.ZERO
	slime._clear_knockback()
	player.global_position = anchor
	player.velocity = Vector3.ZERO
	_face(player, stand)
	player.set_flashlight_on(false)
	player._fire_cooldown = 0.0
	slime.set_physics_process(true)
	var before := slime.global_position
	var hit: Node3D = player.attack()
	var along := await _max_along(slime, before, to_ahead, 24)
	slime.set_physics_process(false)
	var hurt: bool = slime.health < 44.0
	var moved: bool = along > 0.35 and along < 1.15
	var connected: bool = (not gun and hit == slime) or gun
	return {
		"ok": connected and hurt and moved,
		"along": along,
		"health": slime.health,
		"hit": hit,
	}


func _stalker_case(
	player: CharacterBody3D,
	stalker: CharacterBody3D,
	slime: CharacterBody3D,
	anchor: Vector3,
	to_ahead: Vector3,
	light: bool
) -> Dictionary:
	var stand := anchor + to_ahead * 1.15
	stand.y = anchor.y
	slime.global_position = anchor + Vector3(80.0, 0.0, 80.0)
	slime.set_physics_process(false)
	stalker.visible = true
	stalker.touch_damage = 0.0
	stalker.global_position = stand
	stalker.velocity = Vector3.ZERO
	stalker._clear_knockback()
	player.global_position = anchor
	var gp: Node = root.get_node("GameProgress")
	gp.has_pistol = false
	gp.selected_weapon = GameProgress.WeaponId.NONE
	_face(player, stand)
	player.set_flashlight_on(light)
	player._fire_cooldown = 0.0
	var lit: bool = player.illuminates_point(stand + Vector3(0.0, 1.2, 0.0))
	var hp_before: float = stalker.health
	stalker.set_physics_process(true)
	var before := stalker.global_position
	var hit: Node3D = player.attack()
	var along := await _max_along(stalker, before, to_ahead, 24)
	stalker.set_physics_process(false)
	var hp_held := is_equal_approx(stalker.health, hp_before)
	var moved: bool = along > 0.35 and along < 1.15
	var stayed: bool = along < 0.08
	var ok: bool = hit == stalker and hp_held and lit == light and (moved if not light else stayed)
	return {"ok": ok, "along": along, "health": stalker.health, "lit": lit}


func _face(player: CharacterBody3D, point: Vector3) -> void:
	var visual := player.get_node("Model") as Node3D
	var to_point := point - player.global_position
	to_point.y = 0.0
	if to_point.length() < 0.05:
		to_point = Vector3(1.0, 0.0, 0.0)
	visual.rotation.y = atan2(to_point.x, to_point.z) + PI
	player.set_aim_world_override(point)


func _max_along(body: Node3D, origin: Vector3, direction: Vector3, frames: int) -> float:
	var best := 0.0
	for _i in frames:
		await physics_frame
		var delta := body.global_position - origin
		delta.y = 0.0
		var along := delta.dot(direction)
		if along > best:
			best = along
	return best
