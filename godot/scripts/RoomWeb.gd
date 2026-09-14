class_name RoomWeb
extends Node3D

## A finished (or growing) silk sheet covering one room tile. The player walks
## through it at 25% speed; tarantulas treat it as home turf.

const SILK := Color(0.82, 0.80, 0.74, 0.55)
const SILK_CORE := Color(0.92, 0.90, 0.84, 0.22)

var room_cell: Vector2i = Vector2i.ZERO
var room_center: Vector3 = Vector3.ZERO
var half_extent: float = MapGenerator.TILE * 0.48
var weave_progress: float = 1.0
var is_complete: bool = true

var _lines: MeshInstance3D
var _sheet: MeshInstance3D


func _ready() -> void:
	add_to_group(WebField.GROUP)
	_build_visuals()
	_apply_progress()


func configure(cell: Vector2i, center: Vector3, progress: float = 1.0) -> void:
	room_cell = cell
	room_center = center
	set_progress(progress)
	global_position = Vector3(center.x, 0.06, center.z)


func set_progress(progress: float) -> void:
	weave_progress = clampf(progress, 0.0, 1.0)
	is_complete = weave_progress >= 0.999
	if is_inside_tree():
		_apply_progress()


func covers_point(pos: Vector3) -> bool:
	if not is_complete:
		return false
	return (
		absf(pos.x - room_center.x) <= half_extent
		and absf(pos.z - room_center.z) <= half_extent
	)


func _build_visuals() -> void:
	if _sheet != null:
		return
	_sheet = MeshInstance3D.new()
	_sheet.name = "Sheet"
	var plane := PlaneMesh.new()
	plane.size = Vector2(half_extent * 2.0, half_extent * 2.0)
	plane.orientation = PlaneMesh.FACE_Y
	_sheet.mesh = plane
	var sheet_mat := StandardMaterial3D.new()
	sheet_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sheet_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sheet_mat.albedo_color = SILK_CORE
	sheet_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_sheet.material_override = sheet_mat
	add_child(_sheet)

	_lines = MeshInstance3D.new()
	_lines.name = "Silk"
	_lines.mesh = _make_web_mesh()
	var line_mat := StandardMaterial3D.new()
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color = SILK
	line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_lines.material_override = line_mat
	add_child(_lines)


func _apply_progress() -> void:
	if _sheet:
		_sheet.scale = Vector3.ONE * maxf(0.08, weave_progress)
		var mat := _sheet.material_override as StandardMaterial3D
		if mat:
			var color := SILK_CORE
			color.a = SILK_CORE.a * weave_progress
			mat.albedo_color = color
	if _lines:
		_lines.scale = Vector3.ONE * maxf(0.12, weave_progress)


func _make_web_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var spokes := 14
	var rings := 6
	var radius := half_extent * 0.96
	for i in spokes:
		var angle := TAU * float(i) / float(spokes)
		var tip := Vector3(cos(angle) * radius, 0.01, sin(angle) * radius)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(tip)
	for ring in range(1, rings + 1):
		var r := radius * (float(ring) / float(rings))
		var wobble := 0.04 * float(ring)
		for i in spokes:
			var a0 := TAU * float(i) / float(spokes)
			var a1 := TAU * float(i + 1) / float(spokes)
			var p0 := Vector3(cos(a0) * (r + wobble * sin(a0 * 3.0)), 0.012, sin(a0) * (r + wobble * cos(a0 * 2.0)))
			var p1 := Vector3(cos(a1) * (r + wobble * sin(a1 * 3.0)), 0.012, sin(a1) * (r + wobble * cos(a1 * 2.0)))
			st.add_vertex(p0)
			st.add_vertex(p1)
	# Corner drapes so the silk reads in the isometric view.
	for corner in [
		Vector3(-radius, 0.0, -radius),
		Vector3(radius, 0.0, -radius),
		Vector3(-radius, 0.0, radius),
		Vector3(radius, 0.0, radius),
	]:
		st.add_vertex(corner)
		st.add_vertex(corner + Vector3(0.0, 1.6, 0.0))
		st.add_vertex(corner + Vector3(0.0, 1.6, 0.0))
		st.add_vertex(corner * 0.35 + Vector3(0.0, 0.9, 0.0))
	return st.commit()
