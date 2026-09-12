extends SceneTree

## Headless smoke for the slime and tank: they spawn in distinct rooms, keep
## their own stats, and the slime actually plays its imported clips.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed == null:
		push_error("Missing Main.tscn")
		quit(1)
		return
	var main: Node3D = packed.instantiate()
	root.add_child(main)
	if not main.is_level_ready():
		await main.level_ready

	var monster: CharacterBody3D = main.get_node_or_null("Monster")
	var slime: CharacterBody3D = main.get_node_or_null("Slime")
	var tank: CharacterBody3D = main.get_node_or_null("Tank")
	var nodes_ok := monster != null and slime != null and tank != null
	print("enemy_nodes_ok=", nodes_ok)

	var layout: Dictionary = main.get_layout()
	var start: Vector3 = layout.get("start", Vector3.ZERO)
	var slime_pos: Vector3 = layout.get("slime", Vector3.ZERO)
	var tank_pos: Vector3 = layout.get("tank", Vector3.ZERO)
	var monster_pos: Vector3 = layout.get("monster", Vector3.ZERO)
	var distinct_ok := (
		_planar(slime_pos, start) > 4.0
		and _planar(tank_pos, start) > 4.0
		and _planar(slime_pos, tank_pos) > 1.0
		and _planar(slime_pos, monster_pos) > 1.0
	)
	print(
		"enemy_spawns_ok=", distinct_ok,
		" slime_from_start=", _planar(slime_pos, start),
		" tank_from_start=", _planar(tank_pos, start)
	)

	var slime_stats_ok: bool = (
		slime != null
		and slime.max_health < 80.0
		and slime.move_speed > monster.move_speed
		and slime.touch_damage < 80.0
		and slime.idle_clip == "idle"
		and slime.walk_clip == "moving"
	)
	print(
		"slime_stats_ok=", slime_stats_ok,
		" hp=", slime.max_health if slime else -1.0,
		" speed=", slime.move_speed if slime else -1.0
	)

	var tank_stats_ok: bool = (
		tank != null
		and tank.max_health > 200.0
		and tank.move_speed < monster.move_speed
		and is_equal_approx(tank.touch_damage, 100.0)
		and tank.walk_clip == "Walk"
	)
	print(
		"tank_stats_ok=", tank_stats_ok,
		" hp=", tank.max_health if tank else -1.0,
		" speed=", tank.move_speed if tank else -1.0
	)

	var slime_anim: AnimationPlayer = null
	if slime and slime.has_method("get_animation_player"):
		slime_anim = slime.get_animation_player()
	var slime_clips := PackedStringArray()
	if slime_anim:
		for clip_name in slime_anim.get_animation_list():
			slime_clips.append(clip_name)
	var slime_anim_ok := (
		slime_anim != null
		and slime_clips.has("idle")
		and slime_clips.has("moving")
		and slime_clips.has("death")
		and slime_clips.has("attack")
	)
	print("slime_anim_ok=", slime_anim_ok, " clips=", slime_clips)

	var tank_anim: AnimationPlayer = null
	if tank and tank.has_method("get_animation_player"):
		tank_anim = tank.get_animation_player()
	var tank_clips := PackedStringArray()
	if tank_anim:
		for clip_name in tank_anim.get_animation_list():
			tank_clips.append(clip_name)
	var tank_anim_ok := (
		tank_anim != null
		and tank_clips.has("Idle")
		and tank_clips.has("Walk")
		and tank_clips.has("Die")
	)
	print("tank_anim_ok=", tank_anim_ok, " clips=", tank_clips)

	# Slime should actually be playing a locomotion or idle clip after configure.
	await physics_frame
	var slime_playing: bool = slime_anim != null and slime_anim.is_playing()
	print("slime_playing_ok=", slime_playing, " clip=", slime_anim.current_animation if slime_anim else "")

	var grouped := (
		monster.is_in_group("monster")
		and slime.is_in_group("monster")
		and tank.is_in_group("monster")
	)
	print("enemy_group_ok=", grouped)

	var all_ok: bool = (
		nodes_ok
		and distinct_ok
		and slime_stats_ok
		and tank_stats_ok
		and slime_anim_ok
		and tank_anim_ok
		and slime_playing
		and grouped
	)
	print("enemies_smoke_ok=", all_ok)
	quit(0 if all_ok else 1)


func _planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
