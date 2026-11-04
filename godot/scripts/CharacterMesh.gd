class_name CharacterMesh
extends RefCounted

## Hide-break and eject clips arrive later as a sibling of the mesh the scene
## already instances. Foo.glb is replaced by Foo_hb.glb when that file exists.
## The artist also exports the animated source as Foo_animated_hb.glb
## (Tarantula.glb -> Tarantula_animated_hb.glb). The scene keeps the original
## path until one of those files is present.


static func with_hide_anims(path: String) -> String:
	if path.is_empty() or path.ends_with("_hb.glb"):
		return path
	var stem := path.get_basename()
	var same := stem + "_hb.glb"
	if FileAccess.file_exists(same):
		return same
	if not stem.ends_with("_animated"):
		var animated := stem + "_animated_hb.glb"
		if FileAccess.file_exists(animated):
			return animated
	return path


## Swap an instanced character glb for its _hb variant, keeping the node
## name and transform. No change when the variant is absent.
static func upgrade(visual: Node3D) -> void:
	var source := _instanced_glb(visual)
	if source == null:
		return
	var path := String(source.scene_file_path)
	var hb := with_hide_anims(path)
	if hb == path:
		return
	var packed := load(hb) as PackedScene
	if packed == null:
		return
	var replacement := packed.instantiate() as Node3D
	if replacement == null:
		return
	var parent := source.get_parent()
	if parent == null:
		replacement.free()
		return
	var index := source.get_index()
	replacement.name = source.name
	replacement.transform = source.transform
	parent.remove_child(source)
	source.free()
	parent.add_child(replacement)
	parent.move_child(replacement, index)


static func _instanced_glb(visual: Node) -> Node3D:
	if visual == null:
		return null
	if visual is Node3D and String(visual.scene_file_path).ends_with(".glb"):
		return visual as Node3D
	var found: Array[Node] = visual.find_children("*", "Node3D", true, false)
	for node in found:
		if String(node.scene_file_path).ends_with(".glb"):
			return node as Node3D
	return null
