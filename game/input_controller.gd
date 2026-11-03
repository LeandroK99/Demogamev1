class_name InputController
extends Node
## Selección (clic o recuadro con el izquierdo) y órdenes con el derecho:
## clic = mover; mantener y arrastrar = mover y elegir la orientación final; sobre un rojo = atacar.
## Con Ctrl, la ruta es directa (la más corta) en vez de la más cubierta.
## Con Shift, la orden agrega un tramo (waypoint) al final de la ruta actual.
## V: vigilancia con el sector apuntando al cursor.

const CLICK_PICK_PX: float = 30.0 # radio en píxeles para seleccionar con un clic
const DRAG_MIN_PX: float = 8.0 # menos que esto es un clic, no un recuadro
const FORMATION_GAP: int = 3 # celdas entre tanques que reciben la misma orden
const PLAYER_SIDE: int = 0
const COLOR_PATH: Color = Color(1.0, 0.9, 0.2)
const COLOR_PATH_DIRECT: Color = Color(1.0, 0.5, 0.1)
const COLOR_WAYPOINT: Color = Color(1.0, 1.0, 1.0)
const COLOR_OVERWATCH: Color = Color(0.4, 1.0, 0.6)
const OVERWATCH_ARC_STEPS: int = 12
const COLOR_FACING: Color = Color(0.3, 0.9, 1.0)
const COLOR_ATTACK: Color = Color(1.0, 0.25, 0.2)
const FACING_ARROW_CELLS: float = 4.0 # largo de la flecha de orientación

signal selection_changed

var world: SimWorld
var camera: Camera3D
var terrain_view: TerrainView
var unit_views: Array[UnitView] = []
var selected_ids: Array[int] = []

var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _rdragging: bool = false
var _rdrag_start: Vector2 = Vector2.ZERO
var _rdrag_target: Variant = null # punto del terreno donde se apretó el derecho (Vector3)
var _rdrag_facing: Vector2 = Vector2.ZERO # orientación elegida mientras se arrastra
var _rdrag_direct: bool = false # Ctrl apretado al dar la orden: ruta directa
var _rdrag_append: bool = false # Shift apretado al dar la orden: agregar tramo
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
	_paths_material.vertex_color_use_as_albedo = true
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
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_right_pressed(mb.position, mb.ctrl_pressed, mb.shift_pressed)
			elif _rdragging:
				_right_released()
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_H:
		# H: hull-down para las seleccionadas (solo en PLAN)
		if world.phase == SimWorld.Phase.PLAN and not selected_ids.is_empty():
			world.order_hulldown(selected_ids)
		return
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_V:
		_order_overwatch_at(get_viewport().get_mouse_position())
		return
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null and _rdragging:
		_update_facing(mm.position)
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


## Quita de la selección las unidades muertas.
func prune_dead() -> void:
	var ids: Array[int] = []
	for id: int in selected_ids:
		if world.get_unit(id).alive:
			ids.append(id)
	if ids.size() != selected_ids.size():
		_set_selection(ids)


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


## Derecho apretado: sobre un rojo conocido ataca; si no, empieza la orden de mover.
func _right_pressed(screen: Vector2, direct: bool, append: bool) -> void:
	# Órdenes solo en la fase PLAN
	if selected_ids.is_empty() or world.phase != SimWorld.Phase.PLAN:
		return
	var enemy: UnitView = _enemy_at(screen)
	if enemy != null:
		for id: int in selected_ids:
			world.order_attack(id, enemy.unit.id)
		return
	var hit: Variant = terrain_view.raycast(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if hit == null:
		return
	_rdragging = true
	_rdrag_start = screen
	_rdrag_target = hit
	_rdrag_facing = Vector2.ZERO
	_rdrag_direct = direct
	_rdrag_append = append


## Mientras se arrastra: la orientación apunta del destino hacia el punto bajo el mouse.
func _update_facing(screen: Vector2) -> void:
	if screen.distance_to(_rdrag_start) < DRAG_MIN_PX:
		_rdrag_facing = Vector2.ZERO
		return
	var hit: Variant = terrain_view.raycast(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if hit == null:
		return
	var d: Vector3 = (hit as Vector3) - (_rdrag_target as Vector3)
	var flat: Vector2 = Vector2(d.x, d.z)
	_rdrag_facing = flat.normalized() if flat.length() > 0.5 else Vector2.ZERO


func _right_released() -> void:
	_rdragging = false
	var target: Vector2i = world.height_field.world_to_cell(_rdrag_target as Vector3)
	_issue_move(target, _rdrag_facing, not _rdrag_direct, _rdrag_append)
	_rdrag_facing = Vector2.ZERO


## V: cada seleccionada vigila el sector que apunta desde ella hacia el punto bajo el cursor.
func _order_overwatch_at(screen: Vector2) -> void:
	if selected_ids.is_empty() or world.phase != SimWorld.Phase.PLAN:
		return
	var hit: Variant = terrain_view.raycast(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if hit == null:
		return
	var at: Vector2 = Vector2((hit as Vector3).x, (hit as Vector3).z) / Config.CELL_SIZE
	for id: int in selected_ids:
		var u: Unit = world.get_unit(id)
		world.order_overwatch(id, at - u.pos)


## Rojo visible o fantasma bajo el cursor (o null).
func _enemy_at(screen: Vector2) -> UnitView:
	var best: UnitView = null
	var best_d: float = CLICK_PICK_PX
	for v: UnitView in unit_views:
		if v.unit.side == PLAYER_SIDE or not v.unit.alive or not v.visible:
			continue
		var sp: Variant = _screen_pos(v)
		if sp != null and (sp as Vector2).distance_to(screen) < best_d:
			best_d = (sp as Vector2).distance_to(screen)
			best = v
	return best


## Mover en línea: los tanques se reparten perpendiculares a la orientación
## (o a lo ancho si no hay orientación), ordenados por su posición actual.
func _issue_move(target: Vector2i, facing: Vector2, covered: bool, append: bool) -> void:
	var perp: Vector2 = Vector2(-facing.y, facing.x) if facing != Vector2.ZERO else Vector2(1.0, 0.0)
	var ids: Array[int] = selected_ids.duplicate()
	ids.sort_custom(func(a: int, b: int) -> bool:
		return world.get_unit(a).pos.dot(perp) < world.get_unit(b).pos.dot(perp))
	var n: int = ids.size()
	var limit: int = world.height_field.size - 1
	for i: int in n:
		var off: Vector2 = perp * (float(i) - float(n - 1) * 0.5) * FORMATION_GAP
		var c: Vector2i = Vector2i((Vector2(target) + off).round())
		var cell: Vector2i = Vector2i(clampi(c.x, 0, limit), clampi(c.y, 0, limit))
		if not world.order_move(ids[i], cell, facing, covered, append):
			world.order_move(ids[i], target, facing, covered, append) # si la celda desplazada no sirve, al punto exacto


## Rutas planificadas (amarillo cubierta, naranja directa), orientación final (celeste) y blanco de ataque (rojo).
func _draw_paths() -> void:
	_paths_mesh.clear_surfaces()
	var hf: HeightField = world.height_field
	var segs: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	for u: Unit in world.units:
		if u.side != PLAYER_SIDE or not u.alive:
			continue
		var start: Vector3 = _ground(u.pos)
		var prev: Vector3 = start
		var seg_idx: int = 0
		for c: Vector2i in u.path:
			var direct: bool = u.direct_route
			if seg_idx < u.waypoints.size():
				direct = bool(u.waypoints[seg_idx]["direct"])
			var p: Vector3 = _ground(Vector2(c))
			_seg(segs, colors, prev, p, COLOR_PATH_DIRECT if direct else COLOR_PATH)
			prev = p
			if seg_idx < u.waypoints.size() and u.waypoints[seg_idx]["cell"] == c:
				seg_idx += 1
				if seg_idx < u.waypoints.size():
					_cross(segs, colors, Vector2(c), COLOR_WAYPOINT) # quiebre entre tramos
		if u.final_heading != Vector2.ZERO and not u.path.is_empty():
			_arrow(segs, colors, Vector2(u.path.back()), u.final_heading, COLOR_FACING)
		if u.order == Unit.Order.OVERWATCH:
			_sector(segs, colors, u)
		if u.attack_target >= 0 and world.known_enemies[PLAYER_SIDE].has(u.attack_target):
			var cell: Vector2i = world.known_enemies[PLAYER_SIDE][u.attack_target]["cell"]
			_seg(segs, colors, start + Vector3.UP * 2.0, _ground(Vector2(cell)) + Vector3.UP * 2.0, COLOR_ATTACK)
	# Vista previa mientras se arrastra el derecho
	if _rdragging and _rdrag_facing != Vector2.ZERO:
		var t: Vector3 = _rdrag_target as Vector3
		_arrow(segs, colors, Vector2(t.x, t.z) / Config.CELL_SIZE, _rdrag_facing, COLOR_FACING)
	if segs.is_empty():
		return
	_paths_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _paths_material)
	for i: int in segs.size():
		_paths_mesh.surface_set_color(colors[i])
		_paths_mesh.surface_add_vertex(segs[i])
	_paths_mesh.surface_end()


func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x * Config.CELL_SIZE, world.height_field.height_at(p) + 0.5, p.y * Config.CELL_SIZE)


func _seg(segs: PackedVector3Array, colors: PackedColorArray, a: Vector3, b: Vector3, color: Color) -> void:
	segs.append(a)
	segs.append(b)
	colors.append(color)
	colors.append(color)


## Flecha desde la celda (continua) at en la dirección dir de la grilla.
func _arrow(segs: PackedVector3Array, colors: PackedColorArray, at: Vector2, dir: Vector2, color: Color) -> void:
	var tip_cell: Vector2 = at + dir * FACING_ARROW_CELLS
	var base: Vector3 = _ground(at)
	var tip: Vector3 = _ground(tip_cell)
	_seg(segs, colors, base, tip, color)
	for side: float in [-1.0, 1.0]:
		var wing: Vector2 = tip_cell - dir * 1.2 + Vector2(-dir.y, dir.x) * side * 0.8
		_seg(segs, colors, tip, _ground(wing), color)


## Cruz pequeña sobre una celda (marca de waypoint).
func _cross(segs: PackedVector3Array, colors: PackedColorArray, at: Vector2, color: Color) -> void:
	for d: Vector2 in [Vector2(1.0, 1.0), Vector2(1.0, -1.0)]:
		_seg(segs, colors, _ground(at - d), _ground(at + d), color)


## Abanico del sector de vigilancia: dos bordes y el arco a MAX_RANGE.
func _sector(segs: PackedVector3Array, colors: PackedColorArray, u: Unit) -> void:
	var r: float = Config.MAX_RANGE / Config.CELL_SIZE
	var half: float = deg_to_rad(Config.OVERWATCH_HALF_ANGLE_DEG)
	var limit: float = float(world.height_field.size - 1)
	var prev: Vector2 = Vector2.ZERO
	for i: int in OVERWATCH_ARC_STEPS + 1:
		var a: float = -half + 2.0 * half * float(i) / float(OVERWATCH_ARC_STEPS)
		var p: Vector2 = u.pos + u.overwatch_dir.rotated(a) * r
		p = Vector2(clampf(p.x, 0.0, limit), clampf(p.y, 0.0, limit))
		if i == 0 or i == OVERWATCH_ARC_STEPS:
			_seg(segs, colors, _ground(u.pos), _ground(p), COLOR_OVERWATCH)
		if i > 0:
			_seg(segs, colors, _ground(prev), _ground(p), COLOR_OVERWATCH)
		prev = p
