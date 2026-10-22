extends SceneTree

## Headless smoke for the hare (Soglot): the imported GLB is skinned, ships all
## five clips, and the AI drives them (walk while moving, hit, attack, die).

const CLIPS := ["Idle", "Walk", "Attack", "Hit", "Die"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main: Node3D = packed.instantiate()
	root.add_child(main)
	if not main.is_level_ready():
		await main.level_ready

	var hare: CharacterBody3D = main.get_node_or_null("Monster")
	var anim: AnimationPlayer = hare.get_animation_player() if hare != null else null
	var clips_ok := anim != null
	if anim != null:
		for clip in CLIPS:
			clips_ok = clips_ok and anim.has_animation(clip)
	var skeleton := _find_skeleton(hare)
	var skinned_ok := skeleton != null and skeleton.get_bone_count() >= 15
	var loops_ok := (
		anim != null
		and anim.get_animation("Idle").loop_mode == Animation.LOOP_LINEAR
		and anim.get_animation("Walk").loop_mode == Animation.LOOP_LINEAR
		and anim.get_animation("Die").loop_mode == Animation.LOOP_NONE
	)
	print("hare_clips_ok=", clips_ok, " skinned_ok=", skinned_ok, " loops_ok=", loops_ok)

	main.park_monsters()
	hare.visible = true
	hare.touch_damage = 0.0
	hare.set_physics_process(false)
	await physics_frame
	var idle_ok: bool = anim.current_animation == "Idle"
	hare._animate_walk(0.0, 1.0)
	var walk_ok: bool = anim.current_animation == "Walk"
	print("hare_idle_ok=", idle_ok, " hare_walk_ok=", walk_ok)

	hare.take_damage(10.0)
	var hit_ok: bool = anim.current_animation == "Hit" and hare.is_alive()
	hare._on_touch_body_entered(main.get_node("Player"))
	var attack_ok: bool = anim.current_animation == "Attack"
	await create_timer(anim.get_animation("Attack").length + 0.2).timeout
	hare.take_damage(1000.0)
	var die_ok: bool = anim.current_animation == "Die" and not hare.is_alive()
	await create_timer(anim.get_animation("Die").length + 0.2).timeout
	var rested_ok: bool = not anim.is_playing() or anim.current_animation == "Die"
	print(
		"hare_hit_ok=", hit_ok,
		" hare_attack_ok=", attack_ok,
		" hare_die_ok=", die_ok,
		" hare_rested_ok=", rested_ok
	)

	var ok: bool = clips_ok and skinned_ok and loops_ok and idle_ok and walk_ok
	ok = ok and hit_ok and attack_ok and die_ok and rested_ok
	print("hare_smoke_ok=", ok)
	quit(0 if ok else 1)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node == null:
		return null
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
