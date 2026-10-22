extends SceneTree

## The concept-art Widow is a static mesh in scenes/Widow.tscn.
## Main.tscn still spawns the rigged enemy_widow.glb, which has Idle/Walk/Die.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var concept: PackedScene = load("res://assets/characters/enemy_widow_concept.glb")
	var widow_scene: PackedScene = load("res://scenes/Widow.tscn")
	var loaded_ok := concept != null and widow_scene != null
	print("widow_resources_ok=", loaded_ok)
	if not loaded_ok:
		quit(1)
		return

	var body := widow_scene.instantiate() as CharacterBody3D
	if body == null:
		push_error("Widow.tscn root is not a CharacterBody3D")
		quit(1)
		return
	root.add_child(body)

	var shape_node := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var capsule := shape_node.shape as CapsuleShape3D if shape_node else null
	var capsule_bottom := shape_node.position.y - capsule.height * 0.5 if capsule else 999.0
	var capsule_ok := (
		capsule != null
		and is_equal_approx(capsule.height, 1.8)
		and is_equal_approx(capsule.radius, 0.4)
		and is_equal_approx(capsule_bottom, 0.0)
	)
	print(
		"widow_capsule_ok=", capsule_ok,
		" height=", capsule.height if capsule else -1.0,
		" radius=", capsule.radius if capsule else -1.0,
		" bottom=", capsule_bottom
	)

	var mesh_inst := _find_mesh(body)
	var aabb := mesh_inst.mesh.get_aabb() if mesh_inst and mesh_inst.mesh else AABB()
	var arrays: Array = mesh_inst.mesh.surface_get_arrays(0) if mesh_inst and mesh_inst.mesh else []
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays.size() > Mesh.ARRAY_INDEX else PackedInt32Array()
	var tris := indices.size() / 3
	var mat := mesh_inst.get_active_material(0) if mesh_inst else null
	if mat == null and mesh_inst and mesh_inst.mesh:
		mat = mesh_inst.mesh.surface_get_material(0)
	var std := mat as StandardMaterial3D
	var tex_size := std.albedo_texture.get_size() if std and std.albedo_texture else Vector2.ZERO
	var mesh_ok := (
		mesh_inst != null
		and tris == 38899
		and is_equal_approx(aabb.size.y, 1.8)
		and is_equal_approx(aabb.position.y, 0.0)
		and std != null
		and std.albedo_texture != null
		and is_equal_approx(tex_size.x, 2048.0)
		and is_equal_approx(tex_size.y, 2048.0)
		and is_equal_approx(std.metallic, 0.0)
	)
	print(
		"widow_mesh_ok=", mesh_ok,
		" tris=", tris,
		" height=", aabb.size.y,
		" feet=", aabb.position.y,
		" tex=", tex_size,
		" metallic=", std.metallic if std else -1.0
	)

	var static_ok := _find_anim(body) == null and _find_class(body, "Skeleton3D") == null
	print("widow_static_ok=", static_ok)

	var layer_ok := body.collision_layer == 4 and body.name == "Widow"
	print("widow_body_ok=", layer_ok, " layer=", body.collision_layer)

	var gameplay: PackedScene = load("res://assets/characters/enemy_widow.glb")
	var gameplay_root := gameplay.instantiate() if gameplay else null
	var gameplay_anim := _find_anim(gameplay_root) if gameplay_root else null
	var gameplay_ok := (
		gameplay_anim != null
		and gameplay_anim.has_animation("Idle")
		and gameplay_anim.has_animation("Walk")
		and gameplay_anim.has_animation("Die")
	)
	print("gameplay_widow_still_rigged=", gameplay_ok)

	var main_src := FileAccess.get_file_as_string("res://scenes/Main.tscn")
	var unwired_ok := (
		not main_src.contains("enemy_widow_concept.glb")
		and not main_src.contains("res://scenes/Widow.tscn")
	)
	print("widow_not_wired_into_main=", unwired_ok)

	var all_ok := (
		loaded_ok
		and capsule_ok
		and mesh_ok
		and static_ok
		and layer_ok
		and gameplay_ok
		and unwired_ok
	)
	print("widow_model_smoke_ok=", all_ok)
	if gameplay_root:
		gameplay_root.free()
	body.free()
	quit(0 if all_ok else 1)


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh(child)
		if found:
			return found
	return null


func _find_anim(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_anim(child)
		if found:
			return found
	return null


func _find_class(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node
	for child in node.get_children():
		var found := _find_class(child, type_name)
		if found:
			return found
	return null
