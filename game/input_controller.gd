class_name InputController
extends Node
## Selección (clic o recuadro con el izquierdo) y órdenes de mover (clic derecho).

const CLICK_PICK_PX: float = 30.0 # radio en píxeles para seleccionar con un clic
const DRAG_MIN_PX: float = 8.0 # menos que esto es un clic, no un recuadro
const FORMATION_GAP: int = 3 # celdas entre tanques que reciben la misma orden
const PLAYER_SIDE: int = 0

signal selection_changed

var world: SimWorld
var camera: Camera3D
var terrain_view: TerrainView
var unit_views: Array[UnitView] = []
var selected_ids: Array[int] = []

var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _box: ColorRect = ColorRect.new()
var _paths_mesh: ImmediateMesh = ImmediateMesh.new()
var _paths_material: StandardMaterial3D = StandardMaterial3D.new()


func setup(p_world: SimWorld, p_camera: Camera3D, tv: TerrainView, views: Array[UnitView]) -> void:
	world = p_world
	camera = p_camera
	terrain_view = tv
	unit_views = views
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_box.color = Color(1.0, 0.9, 0.2, 0.2)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.visible = false
	layer.add_child(_box)
	var paths: MeshInstance3D = MeshInstance3D.new()
	paths.mesh = _paths_mesh
	add_child(paths)
	_paths_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_paths_material.albedo_color = Color(1.0, 0.9, 0.2)
	_paths_material.no_depth_test = true


func _unhandled_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_start = mb.position
			elif _dragging:
				_dragging = false
				_box.visible = false
				if mb.position.distance_to(_drag_start) < DRAG_MIN_PX:
					_select_click(mb.position)
				else:
					_select_box(Rect2(_drag_start, Vector2.ZERO).expand(mb.position))
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_order_move(mb.position)
		return
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null and _dragging and mm.position.distance_to(_drag_start) >= DRAG_MIN_PX:
		var r: Rect2 = Rect2(_drag_start, Vector2.ZERO).expand(mm.position)
		_box.position = r.position
		_box.size = r.size
		_box.visible = true


func _process(_delta: float) -> void:
	_draw_paths()


func _screen_pos(view: UnitView) -> Variant:
	var p: Vector3 = view.global_position + Vector3.UP * 1.5
	if camera.is_position_behind(p):
		return null
	return camera.unproject_position(p)


func _own_views() -> Array[UnitView]:
	var out: Array[UnitView] = []
	for v: UnitView in unit_views:
		if v.unit.side == PLAYER_SIDE and v.unit.alive:
			out.append(v)
	return out


func _select_click(screen: Vector2) -> void:
	var best: UnitView = null
	var best_d: float = CLICK_PICK_PX
	for v: UnitView in _own_views():
		var sp: Variant = _screen_pos(v)
		if sp != null and (sp as Vector2).distance_to(screen) < best_d:
			best_d = (sp as Vector2).distance_to(screen)
			best = v
	var ids: Array[int] = []
	if best != null:
		ids.append(best.unit.id)
	_set_selection(ids)


func _select_box(rect: Rect2) -> void:
	var ids: Array[int] = []
	for v: UnitView in _own_views():
		var sp: Variant = _screen_pos(v)
		if sp != null and rect.has_point(sp as Vector2):
			ids.append(v.unit.id)
	_set_selection(ids)


func _set_selection(ids: Array[int]) -> void:
	selected_ids = ids
	for v: UnitView in unit_views:
		v.selected = ids.has(v.unit.id)
	selection_changed.emit()


## Primera unidad seleccionada (o null).
func primary_unit() -> Unit:
	return world.get_unit(selected_ids[0]) if not selected_ids.is_empty() else null


func _order_move(screen: Vector2) -> void:
	if selected_ids.is_empty():
		return
	var hit: Variant = terrain_view.raycast(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if hit == null:
		return
	var target: Vector2i = world.height_field.world_to_cell(hit as Vector3)
	# Formación en línea: ordenar por x actual y repartir a lo ancho del destino
	var ids: Array[int] = selected_ids.duplicate()
	ids.sort_custom(func(a: int, b: int) -> bool: return world.get_unit(a).pos.x < world.get_unit(b).pos.x)
	var n: int = ids.size()
	var limit: int = world.height_field.size - 1
	for i: int in n:
		var dx: int = roundi((float(i) - float(n - 1) * 0.5) * FORMATION_GAP)
		var cell: Vector2i = Vector2i(clampi(target.x + dx, 0, limit), target.y)
		if not world.order_move(ids[i], cell):
			world.order_move(ids[i], target) # si la celda desplazada no sirve, al punto exacto


## Ruta planificada de cada tanque propio, como una línea sobre el terreno.
func _draw_paths() -> void:
	_paths_mesh.clear_surfaces()
	var hf: HeightField = world.height_field
	var any: bool = false
	for u: Unit in world.units:
		if u.side != PLAYER_SIDE or not u.alive or u.path.is_empty():
			continue
		if not any:
			_paths_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _paths_material)
			any = true
		var prev: Vector3 = Vector3(u.pos.x * Config.CELL_SIZE, hf.height_at(u.pos) + 0.5, u.pos.y * Config.CELL_SIZE)
		for c: Vector2i in u.path:
			var p: Vector3 = hf.cell_to_world(c) + Vector3.UP * 0.5
			_paths_mesh.surface_add_vertex(prev)
			_paths_mesh.surface_add_vertex(p)
			prev = p
	if any:
		_paths_mesh.surface_end()
