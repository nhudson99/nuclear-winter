extends SceneTree

## Close-ups of the hare (Soglot) in Level 1: idle, walk, attack and death clips.

const OUT_DIR := "/opt/cursor/artifacts"
const SEED := 101


func _initialize() -> void:
	OS.set_environment("NW_LEVEL_SEED", str(SEED))
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main: Node3D = packed.instantiate()
	root.add_child(main)
	if not main.is_level_ready():
		await main.level_ready

	var player: CharacterBody3D = main.get_node("Player")
	var hare: CharacterBody3D = main.get_node("Monster")
	var camera: Camera3D = main.get_node("IsoCamera")
	var layout: Dictionary = main.get_layout()
	var rooms: Array = layout.get("rooms", [])
	main.park_monsters()
	hare.visible = true
	hare.touch_damage = 0.0
	var room: Dictionary = rooms[0] if not rooms.is_empty() else {"center": player.global_position}
	var center: Vector3 = room.get("center", player.global_position)
	hare.global_position = center + Vector3(-0.4, 0.05, 0.0)
	player.global_position = center + Vector3(1.7, 0.05, 1.9)
	player.set_aim_world_override(hare.global_position)
	Input.action_press("flashlight")
	camera.size = 5.2
	main.set_physics_process(false)
	hare.set_physics_process(false)
	_aim_camera(camera, hare.global_position + Vector3(0.0, 0.9, 0.0))

	var anim: AnimationPlayer = hare.get_animation_player()
	if anim == null:
		push_error("Hare has no AnimationPlayer")
		quit(1)
		return
	print("hare_clips=", anim.get_animation_list())

	for _i in range(10):
		await physics_frame
	_shoot(anim, "Idle", 0.9, "godot_hare_idle.png")
	await _settle()
	_shoot(anim, "Walk", 0.2, "godot_hare_walk.png")
	await _settle()
	_shoot(anim, "Attack", 0.55, "godot_hare_attack.png")
	await _settle()
	_shoot(anim, "Die", 1.4, "godot_hare_dead.png")
	await _settle()
	Input.action_release("flashlight")
	quit(0)


func _shoot(anim: AnimationPlayer, clip: String, at: float, filename: String) -> void:
	anim.play(clip)
	anim.seek(at, true)
	anim.pause()
	_pending = filename


var _pending := ""


func _settle() -> void:
	for _i in range(6):
		await process_frame
	await create_timer(0.25).timeout
	_snap(_pending)


func _aim_camera(camera: Camera3D, look: Vector3) -> void:
	camera.global_position = look + Vector3(7.2, 7.2, 7.2)
	camera.look_at(look, Vector3.UP)


func _snap(filename: String) -> void:
	var image: Image = get_root().get_viewport().get_texture().get_image()
	var path := "%s/%s" % [OUT_DIR, filename]
	var err := image.save_png(path)
	print("screenshot_err=", err, " path=", path, " size=", image.get_width(), "x", image.get_height())
