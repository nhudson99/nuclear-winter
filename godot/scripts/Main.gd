extends Node3D

enum GameState { PLAYING, WON, LOST }

@onready var camera: Camera3D = $IsoCamera
@onready var player: CharacterBody3D = $Player
@onready var map_root: Node3D = $MansionMap
@onready var monster: CharacterBody3D = $Monster

@export var camera_distance: float = 22.0
@export var camera_height: float = 22.0
@export var follow_lerp: float = 10.0

var _state: GameState = GameState.PLAYING
var _status_label: Label

func _ready() -> void:
	_ensure_collision(map_root)
	var furniture := get_node_or_null("Furniture")
	if furniture:
		_ensure_collision(furniture)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20.0
	camera.near = 0.05
	camera.far = 250.0
	camera.current = true
	_snap_camera()
	_setup_hud()
	_wire_game_loop()

func _physics_process(delta: float) -> void:
	# High isometric look similar to the Blender reference render.
	var target := player.global_position + Vector3(camera_distance * 0.55, camera_height, camera_distance)
	camera.global_position = camera.global_position.lerp(target, clampf(follow_lerp * delta, 0.0, 1.0))
	camera.look_at(player.global_position + Vector3(0.0, 0.6, 0.0), Vector3.UP)

func get_game_state() -> GameState:
	return _state

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

func _ensure_collision(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var has_static := false
		for child in mi.get_children():
			if child is StaticBody3D:
				has_static = true
				break
		if not has_static and mi.mesh != null:
			mi.create_trimesh_collision()
	for child in node.get_children():
		_ensure_collision(child)
