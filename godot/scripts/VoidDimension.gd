class_name VoidDimension
extends Node

## Overlays the live map with a deep-space material, hides monsters, drips
## 1 HP/sec, and parks a void gate somewhere on the current floor until the
## player walks through it.

signal entered
signal exited

const DAMAGE_PER_SECOND := 1.0

var _active: bool = false
var _damage_accum: float = 0.0
var _saved_materials: Dictionary = {} # instance_id -> Material
var _space_material: StandardMaterial3D
var _gate: VoidGate
var _player: CharacterBody3D
var _main: Node
var _return_pos: Vector3 = Vector3.ZERO


func is_active() -> bool:
	return _active


func configure(main: Node, player: CharacterBody3D) -> void:
	_main = main
	_player = player


func enter(from_pos: Vector3) -> void:
	if _active:
		return
	_active = true
	_damage_accum = 0.0
	_return_pos = from_pos
	_ensure_space_material()
	_paint_map(true)
	_hide_monsters(true)
	_spawn_gate()
	entered.emit()
	set_process(true)


func exit() -> void:
	if not _active:
		return
	_active = false
	set_process(false)
	_paint_map(false)
	_hide_monsters(false)
	if _gate != null and is_instance_valid(_gate):
		_gate.queue_free()
	_gate = null
	if _player != null and is_instance_valid(_player):
		_player.global_position = _return_pos
	exited.emit()


func _process(delta: float) -> void:
	if not _active:
		return
	if _player == null or not is_instance_valid(_player):
		return
	if _player.has_method("is_alive") and not _player.is_alive():
		return
	_damage_accum += delta * DAMAGE_PER_SECOND
	if _damage_accum >= 1.0 and _player.has_method("take_damage"):
		var ticks := int(_damage_accum)
		_damage_accum -= float(ticks)
		_player.take_damage(float(ticks))


func _ensure_space_material() -> void:
	if _space_material != null:
		return
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	img.fill(Color(0.01, 0.015, 0.04))
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	for _i in 420:
		var x := rng.randi_range(0, 255)
		var y := rng.randi_range(0, 255)
		var bright := rng.randf_range(0.55, 1.0)
		img.set_pixel(x, y, Color(bright, bright, rng.randf_range(0.75, 1.0)))
		if rng.randf() < 0.12:
			img.set_pixel(mini(x + 1, 255), y, Color(bright, bright, 1.0))
	var tex := ImageTexture.create_from_image(img)
	_space_material = StandardMaterial3D.new()
	_space_material.albedo_texture = tex
	_space_material.albedo_color = Color(0.55, 0.6, 0.85)
	_space_material.roughness = 1.0
	_space_material.metallic = 0.0
	_space_material.emission_enabled = true
	_space_material.emission_texture = tex
	_space_material.emission_energy_multiplier = 0.35


func _paint_map(enable: bool) -> void:
	if _main == null:
		return
	var map_root: Node = _main.get_node_or_null("GeneratedMap")
	if map_root == null:
		return
	if enable:
		_saved_materials.clear()
		_apply_space(map_root)
	else:
		_restore_space(map_root)
		_saved_materials.clear()


func _apply_space(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		var id := mesh.get_instance_id()
		if not _saved_materials.has(id):
			_saved_materials[id] = mesh.material_override
		mesh.material_override = _space_material
	for child in node.get_children():
		_apply_space(child)


func _restore_space(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		var id := mesh.get_instance_id()
		if _saved_materials.has(id):
			mesh.material_override = _saved_materials[id]
	for child in node.get_children():
		_restore_space(child)


func _hide_monsters(hide: bool) -> void:
	if _main == null or not _main.has_method("monsters"):
		return
	for body in _main.monsters():
		if body == null or not is_instance_valid(body):
			continue
		if hide:
			body.set_meta("nw_void_was_visible", body.visible)
			body.visible = false
			body.set_physics_process(false)
		else:
			var was: bool = true
			if body.has_meta("nw_void_was_visible"):
				was = bool(body.get_meta("nw_void_was_visible"))
				body.remove_meta("nw_void_was_visible")
			body.visible = was
			body.set_physics_process(was)


func _spawn_gate() -> void:
	if _gate != null and is_instance_valid(_gate):
		_gate.queue_free()
	_gate = VoidGate.new()
	_gate.name = "VoidGate"
	_main.add_child(_gate)
	var pos := _pick_gate_position()
	_gate.global_position = pos
	if not _gate.gate_reached.is_connected(_on_gate_reached):
		_gate.gate_reached.connect(_on_gate_reached)


func _pick_gate_position() -> Vector3:
	if _main != null and _main.has_method("get_layout"):
		var layout: Dictionary = _main.get_layout()
		var rooms: Array = layout.get("rooms", [])
		if not rooms.is_empty():
			var start: Vector3 = layout.get("start", _return_pos)
			var best: Vector3 = start
			var best_dist := -1.0
			for room in rooms:
				var center: Vector3 = room.get("center", start)
				var dist := center.distance_to(_return_pos)
				if dist > best_dist:
					best_dist = dist
					best = center
			best.y = 0.05
			return best
	return _return_pos + Vector3(8.0, 0.05, 8.0)


func _on_gate_reached(_body: Node3D) -> void:
	exit()
