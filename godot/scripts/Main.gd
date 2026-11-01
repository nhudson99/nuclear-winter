extends Node3D

## Playable level. The floorplan is not authored: on load, MapGenerator stitches
## the four Blender room modules into a pseudorandom layout while the loading
## screen reports progress, then the player, monsters, objectives and exit are
## placed from the layout it returns. Difficulty comes from GameProgress.current_level.

signal level_ready(layout: Dictionary)

enum GameState { LOADING, PLAYING, WON, LOST }

const LOADING_SCREEN := preload("res://scenes/LoadingScreen.tscn")
const ARISTOCRAT_SCREEN := preload("res://scenes/AristocratScreen.tscn")
const TOUCH_CONTROLS := preload("res://scripts/TouchControls.gd")
const HOTBAR_SCRIPT := preload("res://scripts/Hotbar.gd")
## 50% more zoom onto the player than the original 20 m ortho height.
const PLAY_CAMERA_SIZE := 20.0 / 1.5
## About 9% ambient (was 0.10) so rooms stay faintly readable with the flashlight off.
const DARK_AMBIENT_ENERGY := 0.09
const SLIME_SCENE_PATH := "res://scenes/Slime.tscn"
const MAX_LIVING_SLIMES := 16
const SLIME_SPLIT_SPREAD := 0.6

@onready var camera: Camera3D = $IsoCamera
@onready var player: CharacterBody3D = $Player
@onready var map_root: Node3D = $GeneratedMap
@onready var monster: CharacterBody3D = $Monster
@onready var slime: CharacterBody3D = get_node_or_null("Slime")
@onready var tank: CharacterBody3D = get_node_or_null("Tank")
@onready var tarantula: CharacterBody3D = get_node_or_null("Tarantula")
@onready var widow: CharacterBody3D = get_node_or_null("Widow")
@onready var toad: CharacterBody3D = get_node_or_null("Toad")

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
var _tarantula_serial: int = 1
var _widow_serial: int = 1
var _toad_serial: int = 1
var _resolved_level: int = 1
var _collected_keys: Dictionary = {}
var _valve_shut: bool = false
var _used_seed: int = 0
var _used_rooms: int = 9
var _active_floor: int = 0
## Built floors kept off the live map. Neighbors of the floor the player is
## standing on stay ready so a stair climb does not rebuild the storey.
var _floor_bundles: Dictionary = {}
var _floor_inflight: Dictionary = {}
var _floor_cache: Node3D
var _floor_swap_busy: bool = false

const PARKED_GROUPS: Array[String] = [
	"stairwell",
	"steam_valve",
	"steam_barrier",
	"locked_door",
	"room_web",
]

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


func get_active_floor() -> int:
	return _active_floor


## True when `floor` (0-based) is built and parked, ready to show without
## generating it again. The floor the player is standing on is not "preloaded".
func is_floor_preloaded(floor: int) -> bool:
	if floor == _active_floor:
		return false
	if not _floor_bundles.has(floor):
		return false
	var bundle: Dictionary = _floor_bundles[floor]
	return bool(bundle.get("ready", false)) and not bool(bundle.get("mounted", false))


func preloaded_room_count(floor: int) -> int:
	if not is_floor_preloaded(floor):
		return 0
	var holder: Node = _floor_bundles[floor]["root"]
	return _count_named_rooms(holder)


func unlock_stage(stage: int) -> void:
	_on_key_collected(stage)


func stairwells() -> Array[Stairwell]:
	var out: Array[Stairwell] = []
	var root := map_root.get_node_or_null("Stairwells") if map_root else null
	if root == null:
		return out
	for child in root.get_children():
		if child is Stairwell:
			out.append(child)
	return out


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

	_used_seed = level_seed if level_seed != 0 else randi()
	var seed_override := OS.get_environment("NW_LEVEL_SEED")
	if seed_override.is_valid_int():
		_used_seed = int(seed_override)
	_resolved_level = resolve_play_level()
	_used_rooms = room_count if room_count > 0 else LevelRules.room_count(_resolved_level)
	_active_floor = 0
	await _load_floor_bundle(0, true)
	if not is_inside_tree():
		return
	_mount_bundle(0)
	_apply_layout(_layout)
	_apply_preview_overrides()
	# Neighbors generate during the tail of the loading screen, then keep
	# going after play starts. The bar stays full; this pass does not drive it.
	_schedule_neighbor_preloads()

	while Time.get_ticks_msec() - started < _min_loading_msec():
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

func _apply_layout(layout: Dictionary, arrival_cell = null) -> void:
	if arrival_cell != null:
		player.global_position = _arrival_position(layout, arrival_cell)
	elif int(layout.get("active_floor", 0)) == 0:
		player.global_position = layout.get("start", Vector3.ZERO)
	else:
		player.global_position = _arrival_position(layout, null)
	player.velocity = Vector3.ZERO

	_place_enemy_roster(layout)
	_place_objectives(layout)

	var exit_zone := get_node_or_null("ExitZone") as Node3D
	if exit_zone:
		if int(layout.get("active_floor", 0)) == 0:
			exit_zone.global_position = layout.get("exit", Vector3.ZERO)
			exit_zone.visible = true
		else:
			exit_zone.global_position = Vector3(200.0, 0.0, 200.0)
			exit_zone.visible = false

	_apply_collected_keys()
	if _valve_shut:
		_open_steam_passage()
	_refresh_objective_hud()
	_snap_camera()


func _arrival_position(layout: Dictionary, arrival_cell) -> Vector3:
	for spec in layout.get("stairs", []):
		if arrival_cell != null and spec.get("cell") != arrival_cell:
			continue
		if int(spec.get("floor", -1)) != int(layout.get("active_floor", 0)):
			continue
		var marker: Vector3 = spec.get("position", layout.get("start", Vector3.ZERO))
		var center := marker
		for room in layout.get("rooms", []):
			if room.get("cell") == spec.get("cell"):
				center = room.get("center", marker)
				break
		var to_center := center - marker
		to_center.y = 0.0
		# Step off to the side of the lip. Moving toward the room centre walks
		# down a centred flight and lands inside the 1.35m stair trigger.
		var side := Vector3(to_center.z, 0.0, -to_center.x)
		if side.length() < 0.05:
			side = Vector3(1.0, 0.0, 0.0)
		marker += side.normalized() * 2.2
		marker.y = 0.05
		return marker
	return layout.get("start", Vector3.ZERO)


func _place_enemy_roster(layout: Dictionary) -> void:
	var roster: Array = layout.get("enemies", [])
	var templates := {
		LevelRules.KIND_SLIME: slime,
		LevelRules.KIND_HARE: monster,
		LevelRules.KIND_TANK: tank,
		LevelRules.KIND_TARANTULA: tarantula,
		LevelRules.KIND_WIDOW: widow,
		LevelRules.KIND_TOAD: toad,
	}
	var used := {
		LevelRules.KIND_SLIME: false,
		LevelRules.KIND_HARE: false,
		LevelRules.KIND_TANK: false,
		LevelRules.KIND_TARANTULA: false,
		LevelRules.KIND_WIDOW: false,
		LevelRules.KIND_TOAD: false,
	}
	if roster.is_empty():
		_place_enemy(monster, layout.get("monster", Vector3.ZERO), layout)
		_place_enemy(slime, layout.get("slime", Vector3.ZERO), layout)
		_place_enemy(tank, layout.get("tank", Vector3.ZERO), layout)
		_place_enemy(tarantula, layout.get("tarantula", Vector3.ZERO), layout)
		_place_enemy(widow, layout.get("widow", Vector3.ZERO), layout)
		_place_enemy(toad, layout.get("toad", Vector3.ZERO), layout)
		return

	var active := int(layout.get("active_floor", _active_floor))
	for spec in roster:
		if spec.has("floor") and int(spec.get("floor", 0)) != active:
			continue
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
		# Configure off the map. Doing this on the start cell used to leave a
		# tarantula web under the player after the body was parked.
		leftover.set_physics_process(false)
		leftover.visible = false
		var parked: Vector3 = layout.get("start", Vector3.ZERO) + Vector3(200.0, 0.0, 200.0)
		_place_enemy(leftover, parked, layout)
		leftover.set_physics_process(false)
		leftover.visible = false


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
		LevelRules.KIND_TARANTULA:
			_tarantula_serial += 1
			return "Tarantula_%d" % _tarantula_serial
		LevelRules.KIND_WIDOW:
			_widow_serial += 1
			return "Widow_%d" % _widow_serial
		LevelRules.KIND_TOAD:
			_toad_serial += 1
			return "Toad_%d" % _toad_serial
		_:
			return "Enemy_%d" % (
				_slime_serial + _hare_serial + _tank_serial + _tarantula_serial + _widow_serial + _toad_serial
			)


func _place_objectives(layout: Dictionary) -> void:
	var mission := get_node_or_null("PickupItem") as Area3D
	var active := int(layout.get("active_floor", _active_floor))
	var swallowed := _toad_holds_mission()
	if mission:
		if mission.has_method("configure"):
			mission.configure(PickupItem.Kind.MISSION)
		var mission_here: bool = (
			int(layout.get("objective_floor", 0)) == active
			and (player == null or not player.has_collected_item())
			and not swallowed
		)
		if mission_here:
			mission.visible = true
			mission.global_position = layout.get("objective", Vector3.ZERO)
		else:
			mission.visible = false
			mission.global_position = Vector3(200.0, 0.0, 200.0)

	for spec in layout.get("keys", []):
		var stage := int(spec.get("stage", 1))
		if _collected_keys.has(stage):
			continue
		if int(spec.get("floor", 0)) != active:
			continue
		var key := _make_key_pickup(mission)
		key.name = "Key_%d" % stage
		if key.has_method("reset_instance_state"):
			key.reset_instance_state()
		if key.has_method("configure"):
			key.configure(PickupItem.Kind.KEY, stage)
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
	body.visible = true
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


func _toad_holds_mission() -> bool:
	if not is_inside_tree():
		return false
	for node in get_tree().get_nodes_in_group("toad"):
		if node != null and is_instance_valid(node) and node.has_method("has_mission_item"):
			if node.has_mission_item():
				return true
	return false


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
	if player.has_signal("valve_shut") and not player.valve_shut.is_connected(_on_valve_shut):
		player.valve_shut.connect(_on_valve_shut)
	if player.has_signal("stair_used") and not player.stair_used.is_connected(_on_stair_used):
		player.stair_used.connect(_on_stair_used)
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

	var hotbar: Control = HOTBAR_SCRIPT.new()
	hotbar.name = "Hotbar"
	layer.add_child(hotbar)

	var touch: Node = TOUCH_CONTROLS.new()
	touch.name = "TouchControls"
	add_child(touch)
	# The hotbar's first refresh runs before the touch layer exists, so the
	# phone hint (no R key) is decided on this second pass.
	if hotbar.has_method("refresh"):
		hotbar.refresh()

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


func _on_valve_shut() -> void:
	if _state != GameState.PLAYING and _state != GameState.LOADING:
		return
	if _valve_shut:
		_open_steam_passage()
		_refresh_objective_hud()
		return
	_valve_shut = true
	_open_steam_passage()
	_refresh_objective_hud()


func valve_is_shut() -> bool:
	return _valve_shut


func steam_barriers() -> Array[SteamBarrier]:
	var out: Array[SteamBarrier] = []
	for node in get_tree().get_nodes_in_group("steam_barrier"):
		if node is SteamBarrier:
			out.append(node)
	return out


func _open_steam_passage() -> void:
	for barrier in steam_barriers():
		barrier.shut_off()
	for node in get_tree().get_nodes_in_group("steam_valve"):
		if node != null and node.has_method("force_closed"):
			node.force_closed()
	var steam: Dictionary = _layout.get("steam", {})
	if not steam.has("from_cell"):
		return
	var floor_of: Dictionary = _layout.get("floors", {})
	var from_cell: Vector2i = steam["from_cell"]
	if int(floor_of.get(from_cell, -1)) != _active_floor:
		steam["blocked"] = false
		_layout["steam"] = steam
		return
	var track: Dictionary = _layout.get("monster_track", {})
	MapGenerator.add_unlocked_door_to_track(
		track,
		from_cell,
		String(steam.get("side", "E")),
		steam["to_cell"],
		int(floor_of.get(from_cell, 0))
	)
	_layout["monster_track"] = track
	steam["blocked"] = false
	_layout["steam"] = steam
	for body in monsters():
		if body.has_method("apply_monster_track"):
			body.apply_monster_track(track)


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
	var stairs_root := map_root.get_node_or_null("Stairwells")
	if stairs_root:
		for child in stairs_root.get_children():
			if child is Stairwell and (child as Stairwell).required_stage == stage:
				(child as Stairwell).unlock()
	var track: Dictionary = _layout.get("monster_track", {})
	var floor_of: Dictionary = _layout.get("floors", {})
	for spec in _layout.get("locks", []):
		if int(spec.get("stage", 0)) != stage:
			continue
		if String(spec.get("kind", MapGenerator.LOCK_KIND_WING)) == MapGenerator.LOCK_KIND_STAIR:
			continue
		var door_floor := int(floor_of.get(spec["from_cell"], _active_floor))
		MapGenerator.add_unlocked_door_to_track(
			track,
			spec["from_cell"],
			String(spec.get("side", "E")),
			spec["to_cell"],
			door_floor
		)
		_layout["monster_track"] = track
		break
	for body in monsters():
		if body.has_method("apply_monster_track"):
			body.apply_monster_track(track)


func _apply_collected_keys() -> void:
	for stage in _collected_keys:
		_unlock_door(int(stage))


func _on_stair_used(stair: Node) -> void:
	if _state != GameState.PLAYING:
		return
	if stair == null or not (stair is Stairwell):
		return
	await change_floor((stair as Stairwell).dest_floor, (stair as Stairwell).dest_cell)


func change_floor(dest_floor: int, dest_cell: Vector2i) -> void:
	if _floor_swap_busy:
		return
	if dest_floor == _active_floor:
		return
	var floor_total := LevelRules.floor_count(_resolved_level)
	if dest_floor < 0 or dest_floor >= floor_total:
		return
	_floor_swap_busy = true
	var playing := _state == GameState.PLAYING
	if playing:
		if player and player.has_method("lock_input"):
			player.lock_input()
		set_monsters_processing(false)
	# Keep the current storey underfoot until the next one is ready, then swap
	# on one frame so the player never drops through a missing floor.
	var show_loading := not _bundle_ready(dest_floor)
	var overlay: Node = null
	if show_loading:
		overlay = LOADING_SCREEN.instantiate()
		add_child(overlay)
		if overlay.has_method("set_progress"):
			overlay.set_progress(0.15, "СМЕНА ЭТАЖА / NEXT FLOOR")
		_loading = overlay
	await _load_floor_bundle(dest_floor, show_loading)
	if not is_inside_tree():
		return
	_park_mounted_floor()
	_mount_bundle(dest_floor)
	_clear_dynamic_combatants()
	_apply_layout(_layout, dest_cell)
	if overlay != null and is_instance_valid(overlay):
		if overlay.has_method("snap_to_end"):
			overlay.snap_to_end()
		if overlay.has_method("fade_out"):
			await overlay.fade_out(0.2)
	if _loading == overlay:
		_loading = null
	_schedule_neighbor_preloads()
	if playing and _state == GameState.PLAYING:
		if player and player.has_method("unlock_input"):
			player.unlock_input()
		if OS.get_environment("NW_PREVIEW_PLAYER") != "1":
			set_monsters_processing(true)
	_floor_swap_busy = false


func _min_loading_msec() -> int:
	var seconds := min_loading_seconds
	if OS.has_feature("mobile"):
		seconds = minf(seconds, 0.4)
	return int(seconds * 1000.0)


func _bundle_ready(floor: int) -> bool:
	return _floor_bundles.has(floor) and bool((_floor_bundles[floor] as Dictionary).get("ready", false))


func _load_floor_bundle(floor: int, report_progress: bool) -> Dictionary:
	if _bundle_ready(floor):
		return _floor_bundles[floor]
	if _floor_inflight.has(floor):
		while _floor_inflight.has(floor) and is_inside_tree():
			await get_tree().process_frame
		return _floor_bundles.get(floor, {})
	_floor_inflight[floor] = true
	var holder := Node3D.new()
	holder.name = "FloorBundle_%d" % floor
	holder.visible = false
	# In the tree so stair and valve placement can read global transforms,
	# but dormant so the hidden storey does not collide or take interact.
	holder.set_meta("nw_dormant", true)
	var cache := _ensure_floor_cache()
	cache.add_child(holder)
	var generator := MapGenerator.new()
	generator.name = "MapGenerator_%d" % floor
	add_child(generator)
	if report_progress and _loading != null and _loading.has_method("set_progress"):
		generator.progress.connect(_loading.set_progress)
	var layout: Dictionary = await generator.generate(
		holder, _used_seed, _used_rooms, _resolved_level, floor
	)
	if is_instance_valid(generator):
		generator.queue_free()
	if not is_inside_tree():
		return {}
	_silence_parked_branch(holder)
	holder.visible = false
	var bundle := {
		"root": holder,
		"layout": layout,
		"ready": true,
		"mounted": false,
	}
	_floor_bundles[floor] = bundle
	_floor_inflight.erase(floor)
	return bundle


func _mount_bundle(floor: int) -> void:
	var bundle: Dictionary = _floor_bundles[floor]
	var holder: Node = bundle["root"]
	var parked := holder.is_inside_tree()
	var children: Array[Node] = []
	for child in holder.get_children():
		children.append(child)
	for child in children:
		holder.remove_child(child)
		map_root.add_child(child)
		if parked:
			_restore_parked_branch(child)
	bundle["mounted"] = true
	_floor_bundles[floor] = bundle
	_layout = bundle["layout"]
	_active_floor = floor


func _park_mounted_floor() -> void:
	if not _floor_bundles.has(_active_floor):
		return
	var bundle: Dictionary = _floor_bundles[_active_floor]
	if not bool(bundle.get("mounted", false)):
		return
	var holder: Node = bundle["root"]
	_silence_parked_branch(map_root)
	var cache := _ensure_floor_cache()
	if holder.get_parent() == null:
		cache.add_child(holder)
	holder.visible = false
	var children: Array[Node] = []
	for child in map_root.get_children():
		children.append(child)
	for child in children:
		map_root.remove_child(child)
		holder.add_child(child)
	bundle["mounted"] = false
	bundle["layout"] = _layout
	_floor_bundles[_active_floor] = bundle


func _ensure_floor_cache() -> Node3D:
	if _floor_cache != null and is_instance_valid(_floor_cache):
		return _floor_cache
	_floor_cache = Node3D.new()
	_floor_cache.name = "FloorCache"
	_floor_cache.visible = false
	add_child(_floor_cache)
	return _floor_cache


func _schedule_neighbor_preloads() -> void:
	_evict_distant_floors()
	var wanted: Array[int] = LevelRules.neighbor_floors(_resolved_level, _active_floor)
	if wanted.is_empty():
		return
	_preload_queue(wanted)


func _preload_queue(floors: Array[int]) -> void:
	# One storey at a time. Building two neighbors together stalls a phone.
	await get_tree().process_frame
	for floor in floors:
		if not is_inside_tree():
			return
		if _bundle_ready(floor) or _floor_inflight.has(floor):
			continue
		if floor != _active_floor and floor not in LevelRules.neighbor_floors(_resolved_level, _active_floor):
			continue
		await _load_floor_bundle(floor, false)
		if not is_inside_tree():
			return
		if floor != _active_floor and floor not in LevelRules.neighbor_floors(_resolved_level, _active_floor):
			_drop_floor(floor)


func _evict_distant_floors() -> void:
	var keep := {_active_floor: true}
	for floor in LevelRules.neighbor_floors(_resolved_level, _active_floor):
		keep[floor] = true
	for key in _floor_bundles.keys():
		var floor := int(key)
		if keep.has(floor) or _floor_inflight.has(floor):
			continue
		_drop_floor(floor)


func _drop_floor(floor: int) -> void:
	if floor == _active_floor or not _floor_bundles.has(floor):
		return
	var bundle: Dictionary = _floor_bundles[floor]
	if bool(bundle.get("mounted", false)):
		return
	_floor_bundles.erase(floor)
	var root: Node = bundle.get("root")
	if root != null and is_instance_valid(root):
		root.queue_free()


func _silence_parked_branch(node: Node) -> void:
	var kept: Array[String] = []
	for group in PARKED_GROUPS:
		if node.is_in_group(group):
			kept.append(group)
			node.remove_from_group(group)
	if not kept.is_empty():
		node.set_meta("nw_parked_groups", kept)
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		if not body.has_meta("nw_parked_layer"):
			body.set_meta("nw_parked_layer", body.collision_layer)
			body.set_meta("nw_parked_mask", body.collision_mask)
		body.collision_layer = 0
		body.collision_mask = 0
	for child in node.get_children():
		_silence_parked_branch(child)


func _restore_parked_branch(node: Node) -> void:
	if node.has_meta("nw_parked_groups"):
		var groups: Array = node.get_meta("nw_parked_groups")
		for group in groups:
			node.add_to_group(String(group))
		node.remove_meta("nw_parked_groups")
	if node is CollisionObject3D and node.has_meta("nw_parked_layer"):
		var body := node as CollisionObject3D
		body.collision_layer = int(body.get_meta("nw_parked_layer"))
		body.collision_mask = int(body.get_meta("nw_parked_mask"))
		body.remove_meta("nw_parked_layer")
		body.remove_meta("nw_parked_mask")
	for child in node.get_children():
		_restore_parked_branch(child)


func _count_named_rooms(node: Node) -> int:
	var count := 0
	if String(node.name).begins_with("Room_"):
		count += 1
	for child in node.get_children():
		count += _count_named_rooms(child)
	return count


func _clear_dynamic_combatants() -> void:
	for body in monsters():
		if body == monster or body == slime or body == tank or body == tarantula or body == widow or body == toad:
			continue
		if is_instance_valid(body):
			if body.has_method("release_swallowed_item"):
				body.release_swallowed_item()
			body.queue_free()
	for node in get_tree().get_nodes_in_group("pickup"):
		if node == null or not is_instance_valid(node):
			continue
		if String(node.name) == "PickupItem":
			continue
		node.queue_free()


func _refresh_objective_hud() -> void:
	if _objective_label == null:
		return
	var lines: PackedStringArray = []
	var floors := int(_layout.get("floor_count", 1))
	if floors > 1:
		lines.append("LEVEL %d  FLOOR %d/%d" % [_resolved_level, _active_floor + 1, floors])
	else:
		lines.append("LEVEL %d" % _resolved_level)
	for spec in _layout.get("objectives", LevelRules.objectives(_resolved_level)):
		var kind := String(spec.get("kind", ""))
		var done := false
		if kind == LevelRules.KIND_KEY:
			done = _collected_keys.has(int(spec.get("stage", 0)))
		elif kind == LevelRules.KIND_VALVE:
			done = _valve_shut or _layout.get("steam", {}).is_empty()
		elif kind == LevelRules.KIND_MISSION:
			done = player != null and player.has_collected_item()
		var mark := "x" if done else " "
		var label := String(spec.get("label", kind))
		if kind == LevelRules.KIND_MISSION and not done and _toad_holds_mission():
			label += " (swallowed by a toad)"
		lines.append("[%s] %s" % [mark, label])
	_objective_label.text = "\n".join(lines)

func _on_player_died() -> void:
	if _state != GameState.PLAYING:
		return
	_state = GameState.LOST
	_begin_defeat()

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
	_show_aristocrat_overlay("VictoryOverlay")

func _begin_defeat() -> void:
	if player and player.has_method("lock_input"):
		player.lock_input()
	set_monsters_processing(false)
	GameProgress.aristocrat_mode = GameProgress.AristocratMode.DEFEAT
	_show_aristocrat_overlay("DefeatOverlay")

func _show_aristocrat_overlay(layer_name: String) -> void:
	if get_node_or_null(layer_name) != null:
		return
	var layer := CanvasLayer.new()
	layer.name = layer_name
	layer.layer = 64
	add_child(layer)
	var screen: Control = ARISTOCRAT_SCREEN.instantiate()
	screen.name = "AristocratScreen"
	layer.add_child(screen)
