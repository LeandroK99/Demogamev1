class_name Overlay
extends Node3D
## Overlays de análisis: 1 = exposición azul, 2 = candidatos hull-down, 3 = líneas de LOS.

const CANDIDATE_COUNT: int = 10
const COLOR_SAFE: Color = Color(0.1, 0.75, 0.2)
const COLOR_MID: Color = Color(0.95, 0.85, 0.1)
const COLOR_EXPOSED: Color = Color(0.9, 0.15, 0.1)

var terrain_view: TerrainView
var analysis: TerrainAnalysis
var threats: Array[Vector2i] = [] # amenazas conocidas por el bando azul
var selected_cell: Vector2i = Vector2i(-1, -1)

var _show_exposure: bool = false
var _show_candidates: bool = false
var _show_los: bool = false
var _exposure_cache: PackedFloat32Array = PackedFloat32Array()
var _markers: Node3D = Node3D.new()
var _lines_mesh: ImmediateMesh = ImmediateMesh.new()
var _line_material: StandardMaterial3D = StandardMaterial3D.new()


func setup(tv: TerrainView, ta: TerrainAnalysis) -> void:
	terrain_view = tv
	analysis = ta
	add_child(_markers)
	var lines: MeshInstance3D = MeshInstance3D.new()
	lines.mesh = _lines_mesh
	add_child(lines)
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.vertex_color_use_as_albedo = true
	_line_material.no_depth_test = true


## Actualiza amenazas y unidad seleccionada; recalcula los overlays activos.
func set_context(p_threats: Array[Vector2i], p_selected: Vector2i) -> void:
	threats = p_threats
	selected_cell = p_selected
	_exposure_cache = PackedFloat32Array()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_1:
			_show_exposure = not _show_exposure
		KEY_2:
			_show_candidates = not _show_candidates
		KEY_3:
			_show_los = not _show_los
		_:
			return
	_refresh()


func _refresh() -> void:
	_refresh_exposure()
	_refresh_candidates()
	_refresh_los()


func _refresh_exposure() -> void:
	if not _show_exposure:
		terrain_view.clear_overlay()
		return
	if _exposure_cache.is_empty():
		_exposure_cache = analysis.exposure_map(threats)
	var colors: PackedColorArray = PackedColorArray()
	colors.resize(_exposure_cache.size())
	for i: int in _exposure_cache.size():
		colors[i] = exposure_color(_exposure_cache[i])
	terrain_view.set_overlay_colors(colors)


## Verde = 0, amarillo = 0,5, rojo = 1.
static func exposure_color(e: float) -> Color:
	if e <= 0.5:
		return COLOR_SAFE.lerp(COLOR_MID, e * 2.0)
	return COLOR_MID.lerp(COLOR_EXPOSED, (e - 0.5) * 2.0)


func _refresh_candidates() -> void:
	for child: Node in _markers.get_children():
		child.queue_free()
	if not _show_candidates or not analysis.height_field.in_bounds(selected_cell):
		return
	var cands: Array[Dictionary] = analysis.hulldown_candidates(selected_cell, threats, Config.HULLDOWN_RADIUS)
	for i: int in mini(CANDIDATE_COUNT, cands.size()):
		var c: Dictionary = cands[i]
		var color: Color = Color.CYAN if (c["hull_hidden"] and c["can_fire"]) else Color.WHITE
		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.top_radius = 1.0
		mesh.bottom_radius = 1.0
		mesh.height = 6.0
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color
		mesh.material = mat
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = analysis.height_field.cell_to_world(c["cell"]) + Vector3.UP * 3.0
		_markers.add_child(mi)


func _refresh_los() -> void:
	_lines_mesh.clear_surfaces()
	var hf: HeightField = analysis.height_field
	if not _show_los or not hf.in_bounds(selected_cell) or threats.is_empty():
		return
	_lines_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _line_material)
	var eye: Vector3 = hf.cell_to_world(selected_cell) + Vector3.UP * Config.EYE_H
	for th: Vector2i in threats:
		var sees: bool = analysis.los(selected_cell, Config.EYE_H, th, Config.CENTER_H)
		_lines_mesh.surface_set_color(Color.GREEN if sees else Color.RED)
		_lines_mesh.surface_add_vertex(eye)
		_lines_mesh.surface_add_vertex(hf.cell_to_world(th) + Vector3.UP * Config.CENTER_H)
	_lines_mesh.surface_end()
