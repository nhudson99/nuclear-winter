extends Node3D

## Level 1. The floorplan is not authored: on load, MapGenerator stitches the
## four Blender room modules into a pseudorandom layout while the loading screen
## reports progress, then the player, monster, objective and exit are placed
## from the layout it returns.

signal level_ready(layout: Dictionary)

enum GameState { LOADING, PLAYING, WON, LOST }

const LOADING_SCREEN := preload("res://scenes/LoadingScreen.tscn")

@onready var camera: Camera3D = $IsoCamera
@onready var player: CharacterBody3D = $Player
@onready var map_root: Node3D = $GeneratedMap
@onready var monster: CharacterBody3D = $Monster

@export var camera_distance: float = 22.0
@export var camera_height: float = 22.0
@export var follow_lerp: float = 10.0
@export var room_count: int = 9
## Zero draws a fresh layout every run; any other value replays that exact map.
@export var level_seed: int = 0
## Floor on how long the overlay stays up, so generation is readable when the
## map assembles in a handful of frames.
@export var min_loading_seconds: float = 1.2

var _state: GameState = GameState.LOADING
var _status_label: Label
var _layout: Dictionary = {}
var _loading: CanvasLayer

func _ready() -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20.0
	camera.near = 0.05
	camera.far = 250.0
	camera.current = true
	_setup_hud()
	_wire_game_loop()
	# Nothing exists to walk around in until generation lands.
	player.lock_input()
	monster.set_physics_process(false)
	_build_level()

func _physics_process(delta: float) -> void:
	# High isometric look similar to the Blender reference render.
	var target := player.global_position + Vector3(camera_distance * 0.55, camera_height, camera_distance)
	camera.global_position = camera.global_position.lerp(target, clampf(follow_lerp * delta, 0.0, 1.0))
	camera.look_at(player.global_position + Vector3(0.0, 0.6, 0.0), Vector3.UP)

func get_game_state() -> GameState:
	return _state

## Layout returned by MapGenerator; empty until `level_ready` fires.
func get_layout() -> Dictionary:
	return _layout

func is_level_ready() -> bool:
	return _state != GameState.LOADING

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
	_layout = await generator.generate(map_root, used_seed, room_count)
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
		monster.set_physics_process(true)
	level_ready.emit(_layout)

func _apply_layout(layout: Dictionary) -> void:
	player.global_position = layout.get("start", Vector3.ZERO)
	player.velocity = Vector3.ZERO
	monster.global_position = layout.get("monster", Vector3.ZERO)
	monster.velocity = Vector3.ZERO

	var pickup := get_node_or_null("PickupItem") as Node3D
	if pickup:
		pickup.global_position = layout.get("objective", Vector3.ZERO)
	var exit_zone := get_node_or_null("ExitZone") as Node3D
	if exit_zone:
		exit_zone.global_position = layout.get("exit", Vector3.ZERO)

	monster.configure_level(layout.get("rooms", []), layout.get("bounds", AABB()))
	_snap_camera()

func _apply_preview_overrides() -> void:
	## NW_PREVIEW_PLAYER parks the monster and tightens the iso framing so the
	## player mesh can be reviewed without dying on the first physics tick.
	if OS.get_environment("NW_PREVIEW_PLAYER") != "1":
		return
	if monster:
		monster.set_physics_process(false)
		monster.visible = false
		monster.global_position += Vector3(200.0, 0.0, 200.0)
	camera.size = 8.0
	camera_distance = 8.0
	camera_height = 8.0
	_snap_camera()


func _snap_camera() -> void:
	camera.global_position = player.global_position + Vector3(camera_distance * 0.55, camera_height, camera_distance)
	camera.look_at(player.global_position + Vector3(0.0, 0.6, 0.0), Vector3.UP)

func _wire_game_loop() -> void:
	if player.has_signal("died") and not player.died.is_connected(_on_player_died):
		player.died.connect(_on_player_died)
	if player.has_signal("item_collected") and not player.item_collected.is_connected(_on_item_collected):
		player.item_collected.connect(_on_item_collected)
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

func _on_item_collected() -> void:
	if _state != GameState.PLAYING:
		return
	if monster and monster.has_method("alert_item_stolen"):
		monster.alert_item_stolen()

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
	_end_run("WIN")

func _end_run(message: String) -> void:
	if player and player.has_method("lock_input"):
		player.lock_input()
	if monster:
		monster.set_physics_process(false)
	if _status_label:
		_status_label.text = message
		_status_label.visible = true
