extends SceneTree

## Headless smoke: zoom, dim ambient, hidden monster HP until flashlight,
## pistol damage, sneak sight immunity, speed bonus, exit glow.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var gp: Node = root.get_node("GameProgress")
	gp.reset_for_tests()
	gp.has_pistol = true
	gp.has_shotgun = true
	gp.has_ak = true
	gp.pistol_loaded = 10
	gp.pistol_reserve = 20
	gp.shotgun_loaded = 8
	gp.shotgun_reserve = 8
	gp.ak_loaded = 30
	gp.ak_reserve = 30
	gp.selected_weapon = GameProgress.WeaponId.PISTOL
	gp.has_sneak = true
	gp.speed_ranks = 1
	gp.health_ranks = 1

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
	var monster: CharacterBody3D = main.get_node("Monster")
	var exit_zone: Area3D = main.get_node("ExitZone")
	var pickup: Area3D = main.get_node_or_null("PickupItem")
	monster.set_physics_process(false)
	monster.touch_damage = 0.0
	if main.has_method("park_monsters"):
		main.park_monsters(monster)

	var zoom_ok := is_equal_approx(main.camera.size, 20.0 / 1.5)
	print("zoom_ok=", zoom_ok, " camera_size=", main.camera.size)

	var world := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var env := world.environment if world else null
	var ambient_ok := (
		env != null
		and env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR
		and absf(env.ambient_light_energy - 0.09) < 0.005
	)
	print(
		"ambient_ok=", ambient_ok,
		" source=", env.ambient_light_source if env else -1,
		" energy=", env.ambient_light_energy if env else -1.0
	)

	var speed_ok := is_equal_approx(player.move_speed, 2.4 * 1.05) and is_equal_approx(player.run_speed, 5.5 * 1.05)
	var health_rank_ok := is_equal_approx(player.max_health, 110.0) and is_equal_approx(player.health, 110.0)
	print("speed_bonus_ok=", speed_ok, " walk=", player.move_speed, " run=", player.run_speed)
	print("health_rank_ok=", health_rank_ok, " max=", player.max_health, " hp=", player.health)

	var bar: Node3D = monster.get_node_or_null("HealthBar")
	var hidden_ok: bool = bar != null and not bar.visible and not monster.is_health_bar_revealed()
	print("hp_hidden_ok=", hidden_ok)

	var start: Vector3 = main.get_layout()["start"]
	player.global_position = start + Vector3(0.0, 0.05, 0.0)
	monster.global_position = start + Vector3(4.0, 0.05, 0.0)
	var visual: Node3D = player.get_node("Model")
	visual.rotation.y = atan2(1.0, 0.0) + PI
	player.set_aim_world_override(monster.global_position)
	var camera_before: float = main.camera.size
	var pickup_visible_before: bool = pickup != null and pickup.visible
	player.set_flashlight_on(true)
	var focus_skipped: bool = (
		is_equal_approx(main.camera.size, camera_before)
		and pickup != null
		and pickup.visible
		and pickup_visible_before
	)
	print("flashlight_focus_skipped=", focus_skipped, " pickup_visible=", pickup.visible if pickup else false)
	await physics_frame
	monster._update_health_bar_visibility()
	var revealed_ok: bool = monster.is_health_bar_revealed() and bar.visible
	print(
		"hp_revealed_ok=", revealed_ok,
		" illuminates=", player.illuminates_point(monster.global_position + Vector3(0.0, 1.2, 0.0))
	)
	player.set_flashlight_on(false)
	monster._update_health_bar_visibility()
	var hides_ok: bool = not monster.is_health_bar_revealed() and not bar.visible
	print("hp_hides_without_beam_ok=", hides_ok)

	monster.health = 100.0
	# Fast enough that a discrete area step skips a body. The sweep must still hit.
	player.pistol_speed = 90.0
	var fired: Node3D = player.fire_weapon()
	var spawned: bool = fired != null
	for _i in 20:
		await physics_frame
	var pistol_ok: bool = spawned and is_equal_approx(float(monster.health), 90.0)
	print("pistol_hit_ok=", pistol_ok, " hp=", monster.health, " spawned=", spawned)

	var slime: CharacterBody3D = main.get_node("Slime")
	slime.visible = true
	slime.set_physics_process(false)
	slime.touch_damage = 0.0
	monster.global_position = start + Vector3(80.0, 0.05, 80.0)
	slime.global_position = start + Vector3(4.0, 0.05, 0.0)
	player.global_position = start + Vector3(0.0, 0.05, 0.0)
	player.set_aim_world_override(slime.global_position)
	player._fire_cooldown = 0.0
	var slime_before: float = slime.health
	var slime_shot: Node3D = player.fire_weapon()
	var slime_spawned := slime_shot != null
	for _i in 20:
		await physics_frame
	var slime_ok: bool = slime_spawned and slime.health < slime_before - 0.5
	print("slime_hit_ok=", slime_ok, " hp=", slime.health, " before=", slime_before)

	var wall := StaticBody3D.new()
	wall.name = "BulletWall"
	wall.collision_layer = 1
	wall.collision_mask = 0
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(0.4, 2.4, 4.0)
	wall_shape.shape = wall_box
	wall_shape.position = Vector3(0.0, 1.2, 0.0)
	wall.add_child(wall_shape)
	main.add_child(wall)
	player.global_position = start + Vector3(0.0, 0.05, 0.0)
	wall.global_position = start + Vector3(2.0, 0.0, 0.0)
	slime.global_position = start + Vector3(4.0, 0.05, 0.0)
	player.set_aim_world_override(slime.global_position)
	await physics_frame
	player._fire_cooldown = 0.0
	var blocked_before: float = slime.health
	var blocked_shot: Node3D = player.fire_weapon()
	var blocked_spawned := blocked_shot != null
	for _i in 20:
		await physics_frame
	var wall_ok: bool = blocked_spawned and is_equal_approx(slime.health, blocked_before)
	print("bullet_wall_ok=", wall_ok, " hp=", slime.health)
	wall.free()

	var mesh: Node3D = monster.get_node("MonsterMesh")
	monster.proximity_radius = 0.15
	monster.detect_range = 16.0
	player.global_position = start + Vector3(5.0, 0.05, 0.0)
	monster.global_position = start + Vector3(0.0, 0.05, 0.0)
	mesh.rotation.y = atan2(1.0, 0.0) + PI
	player.set_flashlight_on(false)
	Input.action_press("sneak")
	await physics_frame
	var sneak_hidden: bool = player.is_sneaking() and not monster._can_see_player()
	Input.action_release("sneak")
	await physics_frame
	var seen_without: bool = monster._can_see_player()
	print(
		"sneak_ok=", sneak_hidden and seen_without,
		" sneaking=", sneak_hidden,
		" seen_after=", seen_without
	)

	var glow_off: bool = not exit_zone.is_glow_visible()
	player.global_position = pickup.global_position + Vector3(0.8, 0.0, 0.0)
	await create_timer(0.05).timeout
	Input.action_press("interact")
	await create_timer(0.05).timeout
	player._physics_process(0.033)
	Input.action_release("interact")
	await create_timer(0.05).timeout
	var glow_on: bool = player.has_collected_item() and exit_zone.is_glow_visible()
	print("exit_glow_ok=", glow_off and glow_on, " had_item=", player.has_collected_item())

	var hotbar = main.get_node_or_null("HUD/Hotbar")
	var hotbar_ok: bool = (
		hotbar != null
		and hotbar.slot_count() == 3
		and hotbar.slot_node(GameProgress.WeaponId.PISTOL) != null
		and hotbar.slot_node(GameProgress.WeaponId.SHOTGUN) != null
		and hotbar.slot_node(GameProgress.WeaponId.AK) != null
		and hotbar.is_slot_selected(GameProgress.WeaponId.PISTOL)
		and hotbar.ammo_text(GameProgress.WeaponId.PISTOL) == "7/20"
	)
	print("hotbar_ok=", hotbar_ok, " slots=", hotbar.slot_count() if hotbar else -1, " ammo=", hotbar.ammo_text(GameProgress.WeaponId.PISTOL) if hotbar else "")

	# just_pressed stays latched until the next frame, so each slot press has to
	# be consumed before the next one or a leftover slot_3 reselects the AK.
	Input.action_press("slot_3")
	await physics_frame
	Input.action_release("slot_3")
	await physics_frame
	var slot_ak: bool = gp.selected_weapon == GameProgress.WeaponId.AK and hotbar.is_slot_selected(GameProgress.WeaponId.AK)
	print("hotbar_slot3_ok=", slot_ak)

	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	player._unhandled_input(wheel)
	var scrolled: bool = gp.selected_weapon == GameProgress.WeaponId.SHOTGUN
	print("hotbar_scroll_ok=", scrolled, " selected=", gp.selected_weapon)

	gp.select_weapon(GameProgress.WeaponId.PISTOL)
	gp.pistol_loaded = 3
	gp.pistol_reserve = 12
	# physics_frame is emitted before _physics_process, and action_press arms
	# the next physics tick. Two waits let that tick reload before we read ammo.
	Input.action_press("reload")
	await physics_frame
	await physics_frame
	Input.action_release("reload")
	var reload_ok: bool = gp.pistol_loaded == 10 and gp.pistol_reserve == 5 and hotbar.ammo_text(GameProgress.WeaponId.PISTOL) == "10/5"
	print("reload_ok=", reload_ok, " loaded=", gp.pistol_loaded, " reserve=", gp.pistol_reserve, " label=", hotbar.ammo_text(GameProgress.WeaponId.PISTOL))

	Input.action_press("slot_2")
	await physics_frame
	Input.action_release("slot_2")
	await physics_frame
	monster.health = 100.0
	monster.global_position = start + Vector3(4.0, 0.05, 0.0)
	player.global_position = start + Vector3(0.0, 0.05, 0.0)
	player.set_aim_world_override(monster.global_position)
	player._fire_cooldown = 0.0
	var before_bullets := _bullet_count(main)
	var shotgun_shot: Node3D = player.fire_weapon()
	var spawned_pellets := _bullet_count(main) - before_bullets
	var spread_ok := _pellets_inside_cone(player, main)
	var shotgun_hit: bool = shotgun_shot != null and monster.health < 100.0
	for _i in 8:
		await physics_frame
	shotgun_hit = shotgun_shot != null and monster.health < 100.0
	var rates_ok: bool = (
		is_equal_approx(player.pistol_cooldown, 0.4)
		and is_equal_approx(player.ak_cooldown, 0.1)
		and is_equal_approx(player.shotgun_cooldown, 1.0)
		and player.shotgun_pellets == 10
		and is_equal_approx(player.shotgun_pellet_damage, 10.0)
		and is_equal_approx(player.ak_damage, 25.0)
	)
	print(
		"shotgun_ok=", spawned_pellets == 10 and spread_ok and shotgun_hit and rates_ok,
		" pellets=", spawned_pellets,
		" spread=", spread_ok,
		" hp=", monster.health
	)

	gp.select_weapon(GameProgress.WeaponId.AK)
	player._fire_cooldown = 0.0
	monster.health = 100.0
	var ak_shot: Node3D = player.fire_weapon()
	# Freed bullets compare equal to null, so remember the spawn before they land.
	# 10 rounds/sec is 0.1s. Waiting a dozen frames would let that cooldown expire.
	var ak_spawned: bool = ak_shot != null
	var ak_blocked: bool = player.fire_weapon() == null
	for _i in 12:
		await physics_frame
	var ak_ok: bool = ak_spawned and is_equal_approx(float(monster.health), 75.0)
	print("ak_ok=", ak_ok and ak_blocked, " hp=", monster.health, " spawned=", ak_spawned, " blocked=", ak_blocked)

	monster.global_position = start + Vector3(4.0, 0.05, 0.0)
	player.global_position = start + Vector3(0.0, 0.05, 0.0)
	# +X is away from the player, so sight stays false and only shot/beam aggro.
	mesh.rotation.y = -PI * 0.5
	monster.proximity_radius = 0.1
	monster.detect_range = 0.4
	monster.configure_patrol_for_test(30.0)
	monster.set_physics_process(true)
	Input.action_release("flashlight")
	player.set_flashlight_on(false)
	await physics_frame
	var calm: bool = monster.get_ai_mode_name() == "patrol"
	monster.take_damage(1.0)
	await physics_frame
	var shot_chase: bool = monster.get_ai_mode_name() == "chase"
	monster.configure_patrol_for_test(30.0)
	monster.health = 80.0
	mesh.rotation.y = -PI * 0.5
	visual.rotation.y = atan2(1.0, 0.0) + PI
	player.set_aim_world_override(monster.global_position)
	Input.action_press("flashlight")
	player.set_flashlight_on(true)
	await physics_frame
	var lit_chase: bool = monster.get_ai_mode_name() == "chase"
	monster._update_health_bar_visibility()
	var lit_bar: bool = monster.is_health_bar_revealed()
	Input.action_release("flashlight")
	player.set_flashlight_on(false)
	monster._update_health_bar_visibility()
	var dark_bar: bool = not monster.is_health_bar_revealed()
	monster.set_physics_process(false)
	print(
		"aggro_ok=", calm and shot_chase and lit_chase,
		" calm=", calm,
		" shot=", shot_chase,
		" light=", lit_chase,
		" bar_lit=", lit_bar,
		" bar_dark=", dark_bar
	)

	var all_ok: bool = (
		zoom_ok
		and ambient_ok
		and speed_ok
		and health_rank_ok
		and hidden_ok
		and revealed_ok
		and hides_ok
		and focus_skipped
		and pistol_ok
		and slime_ok
		and wall_ok
		and sneak_hidden
		and seen_without
		and glow_off
		and glow_on
		and hotbar_ok
		and slot_ak
		and scrolled
		and reload_ok
		and spawned_pellets == 10
		and spread_ok
		and shotgun_hit
		and rates_ok
		and ak_ok
		and ak_blocked
		and calm
		and shot_chase
		and lit_chase
		and lit_bar
		and dark_bar
	)
	print("loadout_smoke_ok=", all_ok)
	quit(0 if all_ok else 1)


func _bullet_count(main: Node) -> int:
	var count := 0
	for child in main.get_children():
		if child is Bullet:
			count += 1
	return count


func _pellets_inside_cone(player: CharacterBody3D, main: Node) -> bool:
	var aim: Vector3 = player.get_aim_direction()
	if aim.length() < 0.01:
		return false
	var saw := false
	for child in main.get_children():
		if not (child is Bullet):
			continue
		var bullet := child as Bullet
		var travel := bullet.velocity
		if travel.length() < 0.01:
			return false
		var angle := rad_to_deg(acos(clampf(aim.normalized().dot(travel.normalized()), -1.0, 1.0)))
		if angle > player.flashlight_angle + 0.05:
			return false
		saw = true
	return saw
