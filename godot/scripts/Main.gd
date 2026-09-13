extends Node3D

## Playable level. The floorplan is not authored: on load, MapGenerator stitches
## the four Blender room modules into a pseudorandom layout while the loading
## screen reports progress, then the player, monsters, objectives and exit are
## placed from the layout it returns. Difficulty comes from GameProgress.current_level.

signal level_ready(layout: Dictionary)

enum GameState { LOADING, PLAYING, WON, LOST }

const LOADING_SCREEN := preload("res://scenes/LoadingScreen.tscn")
const ARISTOCRAT_SCREEN := preload("res://scenes/AristocratScreen.tscn")
## 50% more zoom onto the player than the original 20 m ortho height.
const PLAY_CAMERA_SIZE := 20.0 / 1.5
## 10% ambient so rooms are faintly readable with the flashlight off.
const DARK_AMBIENT_ENERGY := 0.10
const SLIME_SCENE_PATH := "res://scenes/Slime.tscn"
const MAX_LIVING_SLIMES := 16
const SLIME_SPLIT_SPREAD := 0.6

@onready var camera: Camera3D = $IsoCamera
@onready var player: CharacterBody3D = $Player
@onready var map_root: Node3D = $GeneratedMap
@onready var monster: CharacterBody3D = $Monster
@onready var slime: CharacterBody3D = get_node_or_null("Slime")
@onready var tank: CharacterBody3D = get_node_or_null("Tank")

@export var camera_distance: float = 22.0
@export var camera_height: float = 22.0
@export var follow_lerp: float = 10.0
@export var room_count: int = 0
## Zero reads GameProgress.current_level (or NW_LEVEL). Any other value forces that level.
@export var play_level: int = 0
## Zero draws a fresh layout every run; any other value replays that exact map.
@export var level_seed: int = 0
## Floor on how long the overlay stays up, so generation is readable when the
## map assembles in a handful of frames.
@export var min_loading_seconds: float = 1.2

var _state: GameState = GameState.LOADING
var _status_label: Label
var _objective_label: Label
var _layout: Dictionary = {}
var _loading: CanvasLayer
var _slime_serial: int = 1
var _hare_serial: int = 1
var _tank_serial: int = 1
var _resolved_level: int = 1
var _collected_keys: Dictionary = {}

func _ready() -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = PLAY_CAMERA_SIZE
	camera.near = 0.05
	camera.far = 250.0
	camera.current = true
	_apply_level_lighting()
	_setup_hud()
	_wire_game_loop()
	# Nothing exists to walk around in until generation lands.
	player.lock_input()
	set_monsters_processing(false)
	_build_level()

func _physics_process(delta: float) -> void:
	# High isometric look similar to the Blender reference render.
	var target := player.global_position + Vector3(camera_distance * 0.55, camera_height, camera_distance)
	camera.global_position = camera.global_position.lerp(target, clampf(follow_lerp * delta, 0.0, 1.0))
	camera.look_at(player.global_position + Vector3(0.0, 0.6, 0.0), Vector3.UP)
	if OS.get_environment("NW_PREVIEW_PLAYER") == "1" and _status_label and player.has_method("current_clip"):
		_status_label.text = player.current_clip()

func get_game_state() -> GameState:
	return _state

## Layout returned by MapGenerator; empty until `level_ready` fires.
func get_layout() -> Dictionary:
	return _layout

func is_level_ready() -> bool:
	return _state != GameState.LOADING


func get_play_level() -> int:
	return _resolved_level


func unlock_stage(stage: int) -> void:
	_on_key_collected(stage)


func locked_doors() -> Array[LockedDoor]:
	var out: Array[LockedDoor] = []
	var root := map_root.get_node_or_null("LockedDoors") if map_root else null
	if root == null:
		return out
	for child in root.get_children():
		if child is LockedDoor:
			out.append(child)
	return out


func collected_key_stages() -> Array[int]:
	var stages: Array[int] = []
	for stage in _collected_keys:
		stages.append(int(stage))
	stages.sort()
	return stages


func resolve_play_level() -> int:
	var env := OS.get_environment("NW_LEVEL")
	if env.is_valid_int():
		return LevelRules.clamp_level(int(env))
	if play_level > 0:
		return LevelRules.clamp_level(play_level)
	return LevelRules.clamp_level(GameProgress.current_level)

func _build_level() -> void:
	var started := Time.get_ticks_msec()
	_loading = LOADING_SCREEN.instantiate()
	add_child(_loading)

	var generator := MapGenerator.new()
	generator.name = "MapGenerator"
	add_child(generator)
	generator.progress.connect(_loading.set_progress)

	var used_seed := level_seed if level_seed != 0 else randi()
	var seed_override := OS.get_environment("NW_LEVEL_SEED")
	if seed_override.is_valid_int():
		used_seed = int(seed_override)
	_resolved_level = resolve_play_level()
	var used_rooms := room_count if room_count > 0 else LevelRules.room_count(_resolved_level)
	_layout = await generator.generate(map_root, used_seed, used_rooms, _resolved_level)
	generator.queue_free()
	_apply_layout(_layout)
	_apply_preview_overrides()

	while Time.get_ticks_msec() - started < int(min_loading_seconds * 1000.0):
		await get_tree().process_frame

	_loading.snap_to_end()
	await get_tree().process_frame
	await _loading.fade_out()
	_loading = null

	_state = GameState.PLAYING
	player.unlock_input()
	if OS.get_environment("NW_PREVIEW_PLAYER") != "1":
		set_monsters_processing(true)
	level_ready.emit(_layout)

func _apply_layout(layout: Dictionary) -> void:
	player.global_position = layout.get("start", Vector3.ZERO)
	player.velocity = Vector3.ZERO

	_place_enemy_roster(layout)
	_place_objectives(layout)

	var exit_zone := get_node_or_null("ExitZone") as Node3D
	if exit_zone:
		exit_zone.global_position = layout.get("exit", Vector3.ZERO)

	_refresh_objective_hud()
	_snap_camera()


func _place_enemy_roster(layout: Dictionary) -> void:
	var roster: Array = layout.get("enemies", [])
	var templates := {
		LevelRules.KIND_SLIME: slime,
		LevelRules.KIND_HARE: monster,
		LevelRules.KIND_TANK: tank,
	}
	var used := {
		LevelRules.KIND_SLIME: false,
		LevelRules.KIND_HARE: false,
		LevelRules.KIND_TANK: false,
	}
	if roster.is_empty():
		_place_enemy(monster, layout.get("monster", Vector3.ZERO), layout)
		_place_enemy(slime, layout.get("slime", Vector3.ZERO), layout)
		_place_enemy(tank, layout.get("tank", Vector3.ZERO), layout)
		return

	for spec in roster:
		var kind := String(spec.get("kind", LevelRules.KIND_SLIME))
		var template: CharacterBody3D = templates.get(kind, slime)
		if template == null:
			continue
		var body: CharacterBody3D
		if not used[kind]:
			body = template
			used[kind] = true
		else:
			body = template.duplicate() as CharacterBody3D
			body.name = _next_enemy_name(kind)
			add_child(body)
		_place_enemy(body, spec.get("position", Vector3.ZERO), layout)

	for kind in used:
		if used[kind]:
			continue
		var leftover: CharacterBody3D = templates.get(kind, null)
		if leftover == null:
			continue
		_place_enemy(leftover, layout.get("start", Vector3.ZERO), layout)
		leftover.set_physics_process(false)
		leftover.visible = false
		leftover.global_position += Vector3(200.0, 0.0, 200.0)


func _next_enemy_name(kind: String) -> String:
	match kind:
		LevelRules.KIND_SLIME:
			_slime_serial += 1
			return "Slime_%d" % _slime_serial
		LevelRules.KIND_HARE:
			_hare_serial += 1
			return "Hare_%d" % _hare_serial
		LevelRules.KIND_TANK:
			_tank_serial += 1
			return "Tank_%d" % _tank_serial
		_:
			return "Enemy_%d" % (_slime_serial + _hare_serial + _tank_serial)


func _place_objectives(layout: Dictionary) -> void:
	var mission := get_node_or_null("PickupItem") as Area3D
	if mission:
		if mission.has_method("configure"):
			mission.configure(PickupItem.Kind.MISSION)
		mission.global_position = layout.get("objective", Vector3.ZERO)

	for spec in layout.get("keys", []):
		var key := _make_key_pickup(mission)
		key.name = "Key_%d" % int(spec.get("stage", 1))
		if key.has_method("configure"):
			key.configure(PickupItem.Kind.KEY, int(spec.get("stage", 1)))
		add_child(key)
		key.global_position = spec.get("position", Vector3.ZERO)


func _make_key_pickup(template: Area3D) -> Area3D:
	if template:
		var copy := template.duplicate() as Area3D
		return copy
	var item := Area3D.new()
	item.set_script(load("res://scripts/PickupItem.gd"))
	return item


func _place_enemy(body: CharacterBody3D, where: Vector3, layout: Dictionary) -> void:
	if body == null:
		return
	body.global_position = where
	body.velocity = Vector3.ZERO
	if body.has_method("configure_level"):
		body.configure_level(
			layout.get("rooms", []),
			layout.get("bounds", AABB()),
			layout.get("monster_track", {})
		)


func monsters() -> Array[CharacterBody3D]:
	var out: Array[CharacterBody3D] = []
	for node in get_tree().get_nodes_in_group("monster"):
		if node is CharacterBody3D:
			out.append(node)
	return out


func set_monsters_processing(enabled: bool) -> void:
	for body in monsters():
		if not body.visible:
			body.set_physics_process(false)
			continue
		body.set_physics_process(enabled)


func park_monsters(keep: Node = null) -> void:
	for body in monsters():
		if body == keep:
			continue
		body.set_physics_process(false)
		body.touch_damage = 0.0
		body.visible = false
		body.global_position += Vector3(200.0, 0.0, 200.0)


func living_slime_count() -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("slime"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node.has_method("is_alive") and not node.is_alive():
			continue
		n += 1
	return n


## Spawns two original-sized slimes beside `parent`. Returns false when the
## living-slime cap would be exceeded so the parent can restart its grow cycle.
func spawn_split_slimes(parent: CharacterBody3D) -> bool:
	if parent == null or not is_instance_valid(parent):
		return false
	if living_slime_count() + 1 > MAX_LIVING_SLIMES:
		return false
	if not ResourceLoader.exists(SLIME_SCENE_PATH):
		push_error("Missing %s" % SLIME_SCENE_PATH)
		return false
	var packed: PackedScene = load(SLIME_SCENE_PATH)
	if packed == null:
		return false
	var processing := parent.is_physics_processing()
	for offset in _slime_split_offsets(parent):
		var child: CharacterBody3D = packed.instantiate()
		_slime_serial += 1
		child.name = "Slime_%d" % _slime_serial
		child.set("grow_and_split", true)
		child.set("grow_duration", parent.get("grow_duration"))
		child.set("grow_scale_target", parent.get("grow_scale_target"))
		child.touch_damage = parent.touch_damage
		add_child(child)
		var where := parent.global_position + offset
		where.y = parent.global_position.y
		child.global_position = where
		child.velocity = Vector3.ZERO
		var src_mesh := parent.get_node_or_null("MonsterMesh") as Node3D
		var dst_mesh := child.get_node_or_null("MonsterMesh") as Node3D
		if src_mesh and dst_mesh:
			dst_mesh.rotation.y = src_mesh.rotation.y
		if parent.has_method("copy_split_level_state"):
			parent.copy_split_level_state(child)
		child.set_physics_process(processing)
	return true


func _slime_split_offsets(parent: Node3D) -> Array[Vector3]:
	var mesh := parent.get_node_or_null("MonsterMesh") as Node3D
	var yaw := mesh.rotation.y if mesh else 0.0
	var facing := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3.UP.cross(facing)
	if right.length() < 0.01:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	var offsets: Array[Vector3] = []
	offsets.append(-right * SLIME_SPLIT_SPREAD)
	offsets.append(right * SLIME_SPLIT_SPREAD)
	return offsets

func _apply_preview_overrides() -> void:
	## NW_PREVIEW_PLAYER parks the monster and tightens the iso framing so the
	## player mesh can be reviewed without dying on the first physics tick.
	if OS.get_environment("NW_PREVIEW_PLAYER") != "1":
		return
	park_monsters()
	camera.size = 4.2
	camera_distance = 5.5
	camera_height = 5.5
	_snap_camera()
	_status_label.visible = true
	_status_label.add_theme_font_size_override("font_size", 36)
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_status_label.add_theme_constant_override("margin_top", 24)


func _apply_level_lighting() -> void:
	var world := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world == null or world.environment == null:
		return
	var env := world.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.60, 0.58)
	env.ambient_light_energy = DARK_AMBIENT_ENERGY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED


func _snap_camera() -> void:
	camera.global_position = player.global_position + Vector3(camera_distance * 0.55, camera_height, camera_distance)
	camera.look_at(player.global_position + Vector3(0.0, 0.6, 0.0), Vector3.UP)

func _wire_game_loop() -> void:
	if player.has_signal("died") and not player.died.is_connected(_on_player_died):
		player.died.connect(_on_player_died)
	if player.has_signal("item_collected") and not player.item_collected.is_connected(_on_item_collected):
		player.item_collected.connect(_on_item_collected)
	if player.has_signal("key_collected") and not player.key_collected.is_connected(_on_key_collected):
		player.key_collected.connect(_on_key_collected)
	var exit_zone := get_node_or_null("ExitZone")
	if exit_zone and exit_zone.has_signal("player_escaped"):
		if not exit_zone.player_escaped.is_connected(_on_player_escaped):
			exit_zone.player_escaped.connect(_on_player_escaped)

func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.visible = false
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_status_label.add_theme_font_size_override("font_size", 96)
	_status_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_status_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_status_label.add_theme_constant_override("outline_size", 10)
	layer.add_child(_status_label)

	_objective_label = Label.new()
	_objective_label.name = "ObjectiveLabel"
	_objective_label.visible = true
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_objective_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_objective_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_objective_label.offset_left = 18
	_objective_label.offset_top = 16
	_objective_label.offset_right = 520
	_objective_label.offset_bottom = 220
	_objective_label.add_theme_font_size_override("font_size", 18)
	_objective_label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.72, 1.0))
	_objective_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_objective_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_objective_label)

func _on_item_collected() -> void:
	if _state != GameState.PLAYING:
		return
	for body in monsters():
		if body.has_method("alert_item_stolen"):
			body.alert_item_stolen()
	var exit_zone := get_node_or_null("ExitZone")
	if exit_zone and exit_zone.has_method("set_glow_visible"):
		exit_zone.set_glow_visible(true)
	_refresh_objective_hud()


func _on_key_collected(stage: int) -> void:
	if _state != GameState.PLAYING:
		return
	_collected_keys[stage] = true
	_unlock_door(stage)
	_refresh_objective_hud()


func _unlock_door(stage: int) -> void:
	var doors_root := map_root.get_node_or_null("LockedDoors")
	if doors_root:
		for child in doors_root.get_children():
			if child is LockedDoor and (child as LockedDoor).stage == stage:
				(child as LockedDoor).unlock()
	var track: Dictionary = _layout.get("monster_track", {})
	for spec in _layout.get("locks", []):
		if int(spec.get("stage", 0)) != stage:
			continue
		MapGenerator.add_unlocked_door_to_track(
			track,
			spec["from_cell"],
			String(spec.get("side", "E")),
			spec["to_cell"]
		)
		_layout["monster_track"] = track
		break
	for body in monsters():
		if body.has_method("apply_monster_track"):
			body.apply_monster_track(track)


func _refresh_objective_hud() -> void:
	if _objective_label == null:
		return
	var lines: PackedStringArray = []
	lines.append("LEVEL %d" % _resolved_level)
	for spec in _layout.get("objectives", LevelRules.objectives(_resolved_level)):
		var kind := String(spec.get("kind", ""))
		var done := false
		if kind == LevelRules.KIND_KEY:
			done = _collected_keys.has(int(spec.get("stage", 0)))
		elif kind == LevelRules.KIND_MISSION:
			done = player != null and player.has_collected_item()
		var mark := "x" if done else " "
		lines.append("[%s] %s" % [mark, String(spec.get("label", kind))])
	_objective_label.text = "\n".join(lines)

func _on_player_died() -> void:
	if _state != GameState.PLAYING:
		return
	_state = GameState.LOST
	_end_run("GAME OVER")

func _on_player_escaped(_body: Node3D) -> void:
	if _state != GameState.PLAYING:
		return
	if player == null or not player.has_collected_item():
		return
	_state = GameState.WON
	_begin_victory()

func _begin_victory() -> void:
	if player and player.has_method("lock_input"):
		player.lock_input()
	set_monsters_processing(false)
	GameProgress.award_escape()
	GameProgress.advance_level()
	GameProgress.aristocrat_mode = GameProgress.AristocratMode.VICTORY
	_show_victory_aristocrat()

func _show_victory_aristocrat() -> void:
	if get_node_or_null("VictoryOverlay") != null:
		return
	var layer := CanvasLayer.new()
	layer.name = "VictoryOverlay"
	layer.layer = 64
	add_child(layer)
	var screen: Control = ARISTOCRAT_SCREEN.instantiate()
	screen.name = "AristocratScreen"
	layer.add_child(screen)

func _end_run(message: String) -> void:
	if player and player.has_method("lock_input"):
		player.lock_input()
	set_monsters_processing(false)
	if _status_label:
		_status_label.text = message
		_status_label.visible = true
