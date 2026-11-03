class_name InputController
extends Node
## Selección (clic o recuadro con el izquierdo) y órdenes con el derecho:
## clic = mover; mantener y arrastrar = mover y elegir la orientación final; sobre un rojo = atacar.
## Con Ctrl, la ruta es directa (la más corta) en vez de la más cubierta.
## Con Shift, la orden agrega un tramo (waypoint) al final de la ruta actual.
## V: vigilancia con el sector apuntando al cursor.
## F y después clic derecho: disparar y replegarse desde esa posición.
## G y después clic izquierdo: humo en ese punto. Esc cancela F o G.

const CLICK_PICK_PX: float = 30.0 # radio en píxeles para seleccionar con un clic
const DRAG_MIN_PX: float = 8.0 # menos que esto es un clic, no un recuadro
const PLAYER_SIDE: int = 0
const COLOR_PATH: Color = Color(1.0, 0.9, 0.2)
const COLOR_PATH_DIRECT: Color = Color(1.0, 0.5, 0.1)
const COLOR_WAYPOINT: Color = Color(1.0, 1.0, 1.0)
const COLOR_OVERWATCH: Color = Color(0.4, 1.0, 0.6)
const COLOR_SCOOT: Color = Color(0.9, 0.5, 1.0)
const COLOR_PATH_EXPOSED: Color = Color(1.0, 0.15, 0.1) # tramo de la ruta a la vista de una amenaza conocida
const COLOR_GATE: Color = Color(1.0, 0.3, 0.9) # tramo que espera una condición
const COLOR_ENGAGE: Color = Color(1.0, 0.55, 0.55) # área de enganche (arco + distancia de la ROE)
const OVERWATCH_ARC_STEPS: int = 12
const COLOR_FACING: Color = Color(0.3, 0.9, 1.0)
const COLOR_ATTACK: Color = Color(1.0, 0.25, 0.2)
const FACING_ARROW_CELLS: float = 4.0 # largo de la flecha de orientación

signal selection_changed
signal smoke_placed # la exposición cambió: refrescar overlays

## Orden pendiente de un clic (la tecla ya se apretó): "" = ninguna.
var pending_mode: String = ""

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
var _risk_cache: Dictionary = {} # id -> {key, risk}: la vista previa de riesgo se recalcula solo si cambió la ruta
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
			if mb.pressed and pending_mode == "smoke":
				pending_mode = ""
				_smoke_at(mb.position)
			elif mb.pressed and mb.double_click:
				_dragging = false
				_select_platoon_at(mb.position)
			elif mb.pressed:
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
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_F:
		if world.phase == SimWorld.Phase.PLAN and not selected_ids.is_empty():
			pending_mode = "scoot"
		return
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_G:
		if world.phase == SimWorld.Phase.PLAN and not selected_ids.is_empty():
			pending_mode = "smoke"
		return
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
		pending_mode = ""
		return
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_U:
		if world.phase == SimWorld.Phase.PLAN and not selected_ids.is_empty():
			pending_mode = "suppress"
		return
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_J:
		if world.phase == SimWorld.Phase.PLAN and selected_platoon() != null:
			pending_mode = "bound"
		return
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_K:
		_cycle_gate()
		return
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_X:
		_cycle_pace()
		return
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_N:
		_cycle_formation()
		return
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_Y:
		_cycle_autonomy()
		return
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_T:
		if world.phase == SimWorld.Phase.PLAN and not selected_ids.is_empty():
			pending_mode = "assault"
		return
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_P:
		if world.phase == SimWorld.Phase.PLAN:
			for id: int in selected_ids:
				world.order_evacuate(id)
		return
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_B:
		if world.phase == SimWorld.Phase.PLAN:
			for id: int in selected_ids:
				world.order_withdraw(id)
		return
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_Z:
		_cycle_roe()
		return
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_C:
		_engagement_at(get_viewport().get_mouse_position(), key.shift_pressed)
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


## Doble clic sobre un tanque: todo su pelotón.
func _select_platoon_at(screen: Vector2) -> void:
	_select_click(screen)
	if selected_ids.is_empty():
		return
	var p: Platoon = world.platoon_of(selected_ids[0])
	if p == null:
		return
	var ids: Array[int] = []
	for uid: int in p.unit_ids():
		if world.get_unit(uid).alive:
			ids.append(uid)
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
	if pending_mode == "scoot":
		pending_mode = ""
		var cells: Dictionary = _formation_cells(world.height_field.world_to_cell(hit as Vector3), Vector2.ZERO)
		for id: int in cells:
			world.order_scoot(id, cells[id])
		return
	if pending_mode == "suppress":
		pending_mode = ""
		var cell: Vector2i = world.height_field.world_to_cell(hit as Vector3)
		for id: int in selected_ids:
			world.order_suppress(id, cell)
		return
	if pending_mode == "bound":
		pending_mode = ""
		var p: Platoon = selected_platoon()
		if p != null:
			world.order_platoon_bound(p.id, world.height_field.world_to_cell(hit as Vector3))
		return
	if pending_mode == "assault":
		pending_mode = ""
		var cells: Dictionary = _formation_cells(world.height_field.world_to_cell(hit as Vector3), Vector2.ZERO)
		for id: int in cells:
			world.order_assault(id, cells[id])
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


## Z: siguiente ROE (libre -> solo si te disparan -> retener) para las seleccionadas,
## partiendo de la de la primera.
func _cycle_roe() -> void:
	var u: Unit = primary_unit()
	if u == null or world.phase != SimWorld.Phase.PLAN:
		return
	var next: int = (u.roe + 1) % Unit.Roe.size()
	for id: int in selected_ids:
		world.set_roe(id, next)


## K: siguiente condición para arrancar el último tramo de las seleccionadas:
## ninguna -> a los 10 s -> a los 20 s -> al haber contacto -> ninguna.
func _cycle_gate() -> void:
	var u: Unit = primary_unit()
	if u == null or world.phase != SimWorld.Phase.PLAN or u.waypoints.is_empty():
		return
	var options: Array[Dictionary] = [{}, SimWorld.gate_time(10.0), SimWorld.gate_time(20.0), SimWorld.gate_contact()]
	var current: Dictionary = u.waypoints.back().get("gate", {})
	var idx: int = 0
	for i: int in options.size():
		if options[i] == current:
			idx = i
	var next: Dictionary = options[(idx + 1) % options.size()]
	for id: int in selected_ids:
		world.gate_leg(id, -1, next)


## X: siguiente ritmo (normal -> rápido -> cauto) para las seleccionadas.
func _cycle_pace() -> void:
	var u: Unit = primary_unit()
	if u == null or world.phase != SimWorld.Phase.PLAN:
		return
	var next: int = (u.pace + 1) % Unit.Pace.size()
	if next == Unit.Pace.CRAWL and not u.is_infantry():
		next = Unit.Pace.NORMAL # los tanques no reptan
	for id: int in selected_ids:
		world.set_pace(id, next)


## N: formación siguiente (cuña, fila india, línea) para las escuadras seleccionadas.
func _cycle_formation() -> void:
	var u: Unit = null
	for id: int in selected_ids:
		if world.get_unit(id).is_infantry():
			u = world.get_unit(id)
			break
	if u == null or world.phase != SimWorld.Phase.PLAN:
		return
	var next: int = (u.formation + 1) % Unit.Formation.size()
	for id: int in selected_ids:
		world.set_formation(id, next)


## Y: autonomía de las escuadras elegidas (estricta, normal, alta).
func _cycle_autonomy() -> void:
	var u: Unit = null
	for id: int in selected_ids:
		if world.get_unit(id).mind != null:
			u = world.get_unit(id)
			break
	if u == null:
		return
	var next: int = (u.mind.autonomy + 1) % SquadMind.Autonomy.size()
	for id: int in selected_ids:
		world.set_autonomy(id, next)


## C: área de enganche hacia el cursor (arco centrado en el cursor y distancia máxima
## hasta él). Shift+C: sin arco y a distancia máxima.
func _engagement_at(screen: Vector2, clear: bool) -> void:
	if selected_ids.is_empty() or world.phase != SimWorld.Phase.PLAN:
		return
	if clear:
		for id: int in selected_ids:
			world.set_engagement(id, Vector2.ZERO, Config.MAX_RANGE)
		return
	var hit: Variant = terrain_view.raycast(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if hit == null:
		return
	var at: Vector2 = Vector2((hit as Vector3).x, (hit as Vector3).z) / Config.CELL_SIZE
	for id: int in selected_ids:
		var u: Unit = world.get_unit(id)
		world.set_engagement(id, at - u.pos, (at - u.pos).length() * Config.CELL_SIZE)


## Humo en el punto bajo el cursor: lo tira la seleccionada más cercana que tenga
## cargas, alcance y línea de visión (una sola granada por orden).
func _smoke_at(screen: Vector2) -> void:
	if world.phase != SimWorld.Phase.PLAN:
		return
	var hit: Variant = terrain_view.raycast(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if hit == null:
		return
	var cell: Vector2i = world.height_field.world_to_cell(hit as Vector3)
	var best: int = -1
	var best_d: float = INF
	for id: int in selected_ids:
		var u: Unit = world.get_unit(id)
		var d: float = Vector2(u.cell()).distance_to(Vector2(cell))
		if u.smoke_charges > 0 and d < best_d and world.can_smoke_at(u, cell):
			best = id
			best_d = d
	if best >= 0 and world.order_smoke(best, cell):
		smoke_placed.emit()


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


## Mover: si la selección es el pelotón entero, la orden se reparte entre sus secciones;
## si no, los tanques se reparten en línea perpendicular a la orientación.
func _issue_move(target: Vector2i, facing: Vector2, covered: bool, append: bool) -> void:
	var p: Platoon = selected_platoon()
	if p != null:
		world.order_platoon_move(p.id, target, facing, covered, append)
		return
	var cells: Dictionary = _formation_cells(target, facing)
	for id: int in cells:
		if not world.order_move(id, cells[id], facing, covered, append):
			world.order_move(id, target, facing, covered, append) # si la celda desplazada no sirve, al punto exacto


## Celda de cada seleccionada (id -> Vector2i) para una orden en línea alrededor de target.
func _formation_cells(target: Vector2i, facing: Vector2) -> Dictionary:
	return world.formation_cells(selected_ids, target, facing)


## Vista previa de riesgo de la ruta de u (ver SimWorld.route_risk), cacheada mientras no cambie.
func risk_for(u: Unit) -> Dictionary:
	if u.path.is_empty() or world.phase != SimWorld.Phase.PLAN:
		return {}
	var key: Array = [u.path.size(), u.path[0], u.path.back(), u.pos, SimWorld.effective_pace(u), u.reversing,
		world.turn, world.threats_for(u.side), world.smoke_clouds.size()]
	var cached: Dictionary = _risk_cache.get(u.id, {})
	if cached.is_empty() or cached["key"] != key:
		cached = {"key": key, "risk": world.route_risk(u.id)}
		_risk_cache[u.id] = cached
	return cached["risk"]


## El pelotón si la selección son exactamente sus tanques vivos (o null).
func selected_platoon() -> Platoon:
	if selected_ids.is_empty():
		return null
	var p: Platoon = world.platoon_of(selected_ids[0])
	if p == null:
		return null
	var alive: Array[int] = []
	for uid: int in p.unit_ids():
		if world.get_unit(uid).alive:
			alive.append(uid)
	if alive.size() != selected_ids.size():
		return null
	for uid: int in alive:
		if not selected_ids.has(uid):
			return null
	return p


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
		var exposed: PackedByteArray = PackedByteArray()
		if selected_ids.has(u.id):
			exposed = risk_for(u).get("exposed", PackedByteArray())
		var cell_idx: int = 0
		if not u.waypoints.is_empty() and u.waypoints[0].has("gate") and not bool(u.waypoints[0].get("gate_open", false)):
			_cross(segs, colors, u.pos, COLOR_GATE) # espera antes de arrancar
		for c: Vector2i in u.path:
			var direct: bool = u.direct_route
			if seg_idx < u.waypoints.size():
				direct = bool(u.waypoints[seg_idx]["direct"])
			var p: Vector3 = _ground(Vector2(c))
			var color: Color = COLOR_PATH_DIRECT if direct else COLOR_PATH
			if cell_idx < exposed.size() and exposed[cell_idx] == 1:
				color = COLOR_PATH_EXPOSED
			cell_idx += 1
			_seg(segs, colors, prev, p, color)
			prev = p
			if seg_idx < u.waypoints.size() and u.waypoints[seg_idx]["cell"] == c:
				seg_idx += 1
				if seg_idx < u.waypoints.size():
					var gated: bool = u.waypoints[seg_idx].has("gate")
					_cross(segs, colors, Vector2(c), COLOR_GATE if gated else COLOR_WAYPOINT) # quiebre entre tramos
		if u.final_heading != Vector2.ZERO and not u.path.is_empty():
			_arrow(segs, colors, Vector2(u.path.back()), u.final_heading, COLOR_FACING)
		if u.order == Unit.Order.OVERWATCH:
			_sector(segs, colors, u, u.overwatch_dir, Config.OVERWATCH_HALF_ANGLE_DEG, Config.MAX_RANGE, COLOR_OVERWATCH)
		if u.fire_arc_dir != Vector2.ZERO and selected_ids.has(u.id):
			_sector(segs, colors, u, u.fire_arc_dir, Config.FIRE_ARC_HALF_ANGLE_DEG, u.max_engage_m, COLOR_ENGAGE)
		if u.order == Unit.Order.SCOOT and not u.scoot_fired and not u.path.is_empty():
			_dashed(segs, colors, Vector2(u.path.back()), Vector2(u.return_cell), COLOR_SCOOT)
		if u.order == Unit.Order.SUPPRESS:
			_dashed(segs, colors, u.pos, Vector2(u.suppress_cell), COLOR_ATTACK)
			_cross(segs, colors, Vector2(u.suppress_cell), COLOR_ATTACK)
		if u.attack_target >= 0 and world.known_enemies[PLAYER_SIDE].has(u.attack_target):
			var cell: Vector2i = world.known_enemies[PLAYER_SIDE][u.attack_target]["cell"]
			_seg(segs, colors, start + Vector3.UP * 2.0, _ground(Vector2(cell)) + Vector3.UP * 2.0, COLOR_ATTACK)
	# Objetivo de la loma: un círculo sobre la cresta
	if world.scenario == SimWorld.Scenario.LOMA:
		var oc: Vector2 = Vector2(world.objective_cell())
		var steps: int = 24
		for i: int in steps:
			var a0: float = TAU * float(i) / float(steps)
			var a1: float = TAU * float(i + 1) / float(steps)
			_seg(segs, colors, _ground(oc + Vector2.from_angle(a0) * Config.LOMA_OBJECTIVE_RADIUS),
				_ground(oc + Vector2.from_angle(a1) * Config.LOMA_OBJECTIVE_RADIUS), COLOR_WAYPOINT)
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


## Abanico desde u.pos: dos bordes y el arco a range_m.
func _sector(segs: PackedVector3Array, colors: PackedColorArray, u: Unit, dir: Vector2, half_deg: float, range_m: float, color: Color) -> void:
	var r: float = range_m / Config.CELL_SIZE
	var half: float = deg_to_rad(half_deg)
	var limit: float = float(world.height_field.size - 1)
	var prev: Vector2 = Vector2.ZERO
	for i: int in OVERWATCH_ARC_STEPS + 1:
		var a: float = -half + 2.0 * half * float(i) / float(OVERWATCH_ARC_STEPS)
		var p: Vector2 = u.pos + dir.rotated(a) * r
		p = Vector2(clampf(p.x, 0.0, limit), clampf(p.y, 0.0, limit))
		if i == 0 or i == OVERWATCH_ARC_STEPS:
			_seg(segs, colors, _ground(u.pos), _ground(p), color)
		if i > 0:
			_seg(segs, colors, _ground(prev), _ground(p), color)
		prev = p


## Línea punteada entre dos celdas (vuelta de disparar y replegarse).
func _dashed(segs: PackedVector3Array, colors: PackedColorArray, a: Vector2, b: Vector2, color: Color) -> void:
	var n: int = maxi(2, roundi(a.distance_to(b)))
	for i: int in range(0, n, 2):
		_seg(segs, colors, _ground(a.lerp(b, float(i) / n)), _ground(a.lerp(b, float(i + 1) / n)), color)
