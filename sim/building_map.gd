class_name BuildingMap
extends RefCounted
## Edificios a 1 m (fase 60), con la misma grilla que MicroCover: piso, pared, puerta, ventana y
## boquete. Las paredes cortan la vista y las balas hasta el techo (BUILDING_H); la ventana deja
## pasar entre el antepecho y el dintel; la puerta y el boquete, hasta el dintel. Un rayo que baja
## al interior desde más arriba del techo lo atraviesa: se corta. Los soldados caminan por el piso,
## las puertas y los boquetes, nunca a través de una pared o una ventana (A* a 1 m).

enum Type { NONE, FLOOR, WALL, DOOR, WINDOW, BREACH, LOOPHOLE }

var size: int = 0 # micro-celdas por lado
var types: PackedByteArray = PackedByteArray()
var houses: Array[Rect2i] = [] # en micro-celdas, con las paredes de afuera incluidas
var _rects_m: Array[Rect2] = [] # las mismas, en metros
var version: int = 0 # sube con cada cambio (la vista se rehace)
var _astar: AStarGrid2D = null # se arma al primer pedido de ruta (y se rehace si cambia algo)


func _init(cells: int) -> void:
	size = cells * Config.MICRO_PER_CELL
	types.resize(size * size)
	types.fill(Type.NONE)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size and c.y < size


func type_at(c: Vector2i) -> int:
	return types[c.y * size + c.x] if in_bounds(c) else Type.NONE


func type_at_m(p_m: Vector2) -> int:
	return type_at(MicroCover.cell_of(p_m))


func set_type(c: Vector2i, t: int) -> void:
	if in_bounds(c):
		types[c.y * size + c.x] = t
		if _astar != null:
			_astar.set_point_solid(c, not walkable_type(t))


static func walkable_type(t: int) -> bool:
	return t != Type.WALL and t != Type.WINDOW and t != Type.LOOPHOLE


static func is_opening(t: int) -> bool:
	return t == Type.WINDOW or t == Type.DOOR or t == Type.BREACH or t == Type.LOOPHOLE


func walkable_m(p_m: Vector2) -> bool:
	return walkable_type(type_at_m(p_m))


## Casa rectangular (micro-celdas, con la pared de afuera en el borde de rect): piso adentro,
## puertas y ventanas en las celdas de la pared que se indiquen. Devuelve su índice.
func add_house(rect: Rect2i, doors: Array[Vector2i] = [], windows: Array[Vector2i] = []) -> int:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var edge: bool = x == rect.position.x or y == rect.position.y or x == rect.end.x - 1 or y == rect.end.y - 1
			set_type(Vector2i(x, y), Type.WALL if edge else Type.FLOOR)
	for d: Vector2i in doors:
		set_type(d, Type.DOOR)
	for wnd: Vector2i in windows:
		set_type(wnd, Type.WINDOW)
	houses.append(rect)
	var a: Vector2 = MicroCover.center_m(rect.position) - Vector2.ONE * MicroCover.MICRO_M * 0.5
	_rects_m.append(Rect2(a, Vector2(rect.size) * MicroCover.MICRO_M))
	return houses.size() - 1


## Pared interior de a hasta b (micro-celdas, en línea recta horizontal o vertical).
func add_wall(a: Vector2i, b: Vector2i) -> void:
	var d: Vector2i = (b - a).sign()
	var c: Vector2i = a
	while true:
		set_type(c, Type.WALL)
		if c == b:
			break
		c += d


## Índice de la casa que contiene p (metros), o -1.
func house_at_m(p_m: Vector2) -> int:
	for i: int in _rects_m.size():
		if _rects_m[i].has_point(p_m):
			return i
	return -1


## ¿p (metros) está adentro de una casa (sobre el piso, una puerta o un boquete)?
func inside_m(p_m: Vector2) -> bool:
	var t: int = type_at_m(p_m)
	return t == Type.FLOOR or ((t == Type.DOOR or t == Type.BREACH) and house_at_m(p_m) >= 0)


## Hasta qué altura sobre el suelo tapa el tipo t, y desde cuál deja pasar (la abertura).
## Devuelve Vector2(abajo, arriba) de la abertura; sin abertura, (BUILDING_H, BUILDING_H).
static func opening(t: int) -> Vector2:
	match t:
		Type.WINDOW:
			return Vector2(Config.WINDOW_SILL_H, Config.WINDOW_TOP_H)
		Type.DOOR:
			return Vector2(0.0, Config.DOOR_H)
		Type.BREACH:
			return Vector2(Config.BREACH_RUBBLE_H, Config.DOOR_H)
		Type.LOOPHOLE:
			return Vector2(Config.LOOPHOLE_LOW_H, Config.LOOPHOLE_TOP_H)
		Type.WALL:
			return Vector2(Config.BUILDING_H, Config.BUILDING_H)
	return Vector2(0.0, Config.BUILDING_H) # piso: abierto por debajo del techo


## ¿Las casas cortan la recta de a (altura absoluta ha) a b (hb)? ground: altura del terreno en un
## punto en metros (Callable p -> float).
func blocks(hf: HeightField, a: Vector2, ha: float, b: Vector2, hb: float) -> bool:
	var d: Vector2 = b - a
	var dist: float = d.length()
	if dist < 0.01:
		return false
	var inv_cell: float = 1.0 / Config.CELL_SIZE
	for r: Rect2 in _rects_m:
		var span: Vector2 = _clip(r, a, d)
		if span.x > span.y:
			continue
		var step: float = Config.BUILDING_LOS_STEP / dist
		var t: float = span.x
		var prev_under: bool = true
		var first: bool = true
		while t <= span.y:
			var p: Vector2 = a + d * t
			var c: Vector2i = MicroCover.cell_of(p)
			var ty: int = type_at(c)
			if ty != Type.NONE:
				var rel: float = ha + (hb - ha) * t - hf.height_at(p * inv_cell)
				var under: bool = rel < Config.BUILDING_H
				if under:
					var o: Vector2 = opening(ty)
					if ty == Type.FLOOR:
						if not first and not prev_under:
							return true # bajó al interior atravesando el techo
					elif rel < o.x or rel > o.y:
						return true
				prev_under = under
				first = false
			t += step
	return false


## Tramo [t0, t1] (0..1) de a + d·t dentro del rectángulo (t0 > t1 si no lo toca).
static func _clip(r: Rect2, a: Vector2, d: Vector2) -> Vector2:
	var t0: float = 0.0
	var t1: float = 1.0
	for axis: int in 2:
		var lo: float = r.position[axis]
		var hi: float = r.end[axis]
		if absf(d[axis]) < 0.000001:
			if a[axis] < lo or a[axis] > hi:
				return Vector2(1.0, 0.0)
			continue
		var ta: float = (lo - a[axis]) / d[axis]
		var tb: float = (hi - a[axis]) / d[axis]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	return Vector2(t0, t1)


## ¿Caminar en línea recta de a a b (metros) atraviesa una pared o una ventana? Recorre exacto
## las micro-celdas que toca el tramo (Amanatides-Woo), solo donde pasa por una casa.
func crosses(a: Vector2, b: Vector2) -> bool:
	var d: Vector2 = b - a
	if d.length() < 0.01:
		return not walkable_m(b)
	for r: Rect2 in _rects_m:
		var span: Vector2 = _clip(r.grow(MicroCover.MICRO_M), a, d)
		if span.x > span.y:
			continue
		if _walk_blocked(a + d * span.x, a + d * span.y):
			return true
	return false


func _walk_blocked(p0: Vector2, p1: Vector2) -> bool:
	var off: float = Config.CELL_SIZE * 0.5
	var g0: Vector2 = (p0 + Vector2(off, off)) / MicroCover.MICRO_M # en unidades de micro-celda
	var g1: Vector2 = (p1 + Vector2(off, off)) / MicroCover.MICRO_M
	var c: Vector2i = Vector2i(floori(g0.x), floori(g0.y))
	var end: Vector2i = Vector2i(floori(g1.x), floori(g1.y))
	var d: Vector2 = g1 - g0
	var step: Vector2i = Vector2i(int(signf(d.x)), int(signf(d.y)))
	var t_max: Vector2 = Vector2(INF, INF)
	var t_delta: Vector2 = Vector2(INF, INF)
	for axis: int in 2:
		if absf(d[axis]) > 0.000001:
			var next: float = float(c[axis] + (1 if d[axis] > 0.0 else 0))
			t_max[axis] = (next - g0[axis]) / d[axis]
			t_delta[axis] = 1.0 / absf(d[axis])
	var guard: int = 0
	while true:
		if not walkable_type(type_at(c)):
			return true
		if c == end or guard > 4096 or minf(t_max.x, t_max.y) > 1.0:
			return not walkable_type(type_at(end))
		guard += 1
		if t_max.x < t_max.y:
			c.x += step.x
			t_max.x += t_delta.x
		else:
			c.y += step.y
			t_max.y += t_delta.y
	return false


## Si ir de anchor a p entra en una casa en la que no está anchor (p adentro o del otro lado), el
## punto justo antes de esa casa (la formación no mete ni pasa soldados por casas que la escuadra
## no pisa). Si no, p.
func pull_out(p: Vector2, anchor: Vector2) -> Vector2:
	var d: Vector2 = p - anchor
	if d.length() < 0.01:
		return p
	var t_min: float = 2.0
	var home: int = house_at_m(anchor)
	for i: int in _rects_m.size():
		if i == home:
			continue
		var span: Vector2 = _clip(_rects_m[i], anchor, d)
		if span.x <= span.y:
			t_min = minf(t_min, span.x)
	if t_min > 1.0:
		return p
	return anchor + d * t_min - d.normalized() * MicroCover.MICRO_M * 0.7


## Distancia (metros) de p a la abertura más cercana (ventana, puerta, boquete, aspillera), hasta
## 3 m; INF si no hay.
func opening_dist_m(p: Vector2) -> float:
	var c: Vector2i = MicroCover.cell_of(p)
	var best: float = INF
	for dy: int in range(-3, 4):
		for dx: int in range(-3, 4):
			var q: Vector2i = c + Vector2i(dx, dy)
			if is_opening(type_at(q)):
				best = minf(best, MicroCover.center_m(q).distance_to(p))
	return best


## ¿p está adentro de una casa, al fondo del cuarto (lejos de puertas y ventanas)?
func deep_m(p: Vector2) -> bool:
	return type_at_m(p) == Type.FLOOR and opening_dist_m(p) >= Config.ROOM_DEEP_M


## Rectángulo (metros) de la casa i.
func rect_m(i: int) -> Rect2:
	return _rects_m[i]


## Aspillera (fase 63): abre un agujero bajo en la pared de la casa i que mira hacia threat, lo más
## cerca del eje centro-amenaza, lejos de esquinas, puertas y ventanas. Devuelve el punto (metros)
## del lado de adentro, ROOM_DEEP_M detrás del agujero, o (-1, -1) si no pudo.
func cut_loophole(i: int, threat: Vector2) -> Vector2:
	var r: Rect2i = houses[i]
	var center: Vector2 = _rects_m[i].get_center()
	var to: Vector2 = (threat - center).normalized()
	var best: Vector2i = Vector2i(-1, -1)
	var best_score: float = -INF
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			var c: Vector2i = Vector2i(x, y)
			var edge_x: bool = x == r.position.x or x == r.end.x - 1
			var edge_y: bool = y == r.position.y or y == r.end.y - 1
			if (edge_x and edge_y) or type_at(c) != Type.WALL or not (edge_x or edge_y):
				continue
			var near_opening: bool = false
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if is_opening(type_at(c + o)):
					near_opening = true
			if near_opening:
				continue
			var off: Vector2 = MicroCover.center_m(c) - center
			var score: float = off.normalized().dot(to) * 10.0 - absf(off.normalized().cross(to)) * off.length()
			if score > best_score:
				best_score = score
				best = c
	if best.x < 0:
		return Vector2(-1.0, -1.0)
	set_type(best, Type.LOOPHOLE)
	var out: Vector2 = MicroCover.center_m(best)
	var inward: Vector2 = (center - out)
	inward = Vector2(signf(inward.x), 0.0) if (best.x == r.position.x or best.x == r.end.x - 1) else Vector2(0.0, signf(inward.y))
	return out + inward * (Config.ROOM_DEEP_M + 0.5)


## Micro-celda de pared exterior (o ventana) más cercana a p, hasta BREACH_FIND_M; (-1, -1) si no hay.
func nearest_wall(p: Vector2) -> Vector2i:
	var c: Vector2i = MicroCover.cell_of(p)
	var r: int = ceili(Config.BREACH_FIND_M)
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: float = INF
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			var q: Vector2i = c + Vector2i(dx, dy)
			var t: int = type_at(q)
			if (t == Type.WALL or t == Type.WINDOW) and _outer(q):
				var d: float = MicroCover.center_m(q).distance_to(p)
				if d < best_d:
					best = q
					best_d = d
	return best


## ¿La micro-celda está en el borde de una casa (pared de afuera)?
func _outer(c: Vector2i) -> bool:
	for r: Rect2i in houses:
		if r.has_point(c) and (c.x == r.position.x or c.y == r.position.y or c.x == r.end.x - 1 or c.y == r.end.y - 1):
			return true
	return false


## Abre un boquete de BREACH_WIDTH en la pared de c (a lo largo de la pared, no en las esquinas).
func breach(c: Vector2i) -> void:
	var along: Vector2i = Vector2i(1, 0)
	for r: Rect2i in houses:
		if r.has_point(c) and (c.x == r.position.x or c.x == r.end.x - 1):
			along = Vector2i(0, 1)
	var cells: Array[Vector2i] = [c]
	for k: int in range(1, Config.BREACH_WIDTH):
		var q: Vector2i = c + along * (k if k % 2 == 1 else -k)
		if type_at(q) == Type.WALL or type_at(q) == Type.WINDOW:
			cells.append(q)
	for q: Vector2i in cells:
		set_type(q, Type.BREACH)
	version += 1


## Punto (metros) del lado de afuera de la micro-celda de pared c, a d metros.
func outside_of(c: Vector2i, d: float) -> Vector2:
	var p: Vector2 = MicroCover.center_m(c)
	for i: int in houses.size():
		if houses[i].has_point(c):
			var out: Vector2 = Vector2.ZERO
			if c.x == houses[i].position.x:
				out = Vector2(-1, 0)
			elif c.x == houses[i].end.x - 1:
				out = Vector2(1, 0)
			elif c.y == houses[i].position.y:
				out = Vector2(0, -1)
			else:
				out = Vector2(0, 1)
			return p + out * d
	return p


## Punto caminable más cercano a p (hasta 3 m); p si ya lo es.
func nearest_walkable_m(p: Vector2) -> Vector2:
	if walkable_m(p):
		return p
	var c: Vector2i = MicroCover.cell_of(p)
	for r: int in range(1, 4):
		var best: Vector2 = p
		var best_d: float = INF
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				var q: Vector2i = c + Vector2i(dx, dy)
				if in_bounds(q) and walkable_type(type_at(q)):
					var m: Vector2 = MicroCover.center_m(q)
					if m.distance_to(p) < best_d:
						best = m
						best_d = m.distance_to(p)
		if best_d < INF:
			return best
	return p


## Ruta caminable de a a b (metros), sin el punto de partida; acortada con tramos rectos que no
## atraviesan paredes. Vacía si no hay.
func route(a: Vector2, b: Vector2) -> PackedVector2Array:
	_ensure_astar()
	var ca: Vector2i = MicroCover.cell_of(nearest_walkable_m(a))
	var cb: Vector2i = MicroCover.cell_of(nearest_walkable_m(b))
	var out: PackedVector2Array = PackedVector2Array()
	if not in_bounds(ca) or not in_bounds(cb) or _astar.is_point_solid(ca) or _astar.is_point_solid(cb):
		return out
	var ids: Array[Vector2i] = _astar.get_id_path(ca, cb)
	if ids.is_empty():
		return out
	var pts: PackedVector2Array = PackedVector2Array()
	for c: Vector2i in ids:
		pts.append(MicroCover.center_m(c))
	pts[pts.size() - 1] = b if walkable_m(b) else pts[pts.size() - 1]
	# Tirar del hilo: desde cada punto, el más lejano al que se llega derecho
	var from: Vector2 = a
	var i: int = 0
	while i < pts.size():
		var j: int = pts.size() - 1
		while j > i and crosses(from, pts[j]):
			j -= 1
		out.append(pts[j])
		from = pts[j]
		i = j + 1
	return out


func _ensure_astar() -> void:
	if _astar != null:
		return
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, size, size)
	_astar.cell_size = Vector2(1.0, 1.0)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	for r: Rect2i in houses:
		for y: int in range(r.position.y, r.end.y):
			for x: int in range(r.position.x, r.end.x):
				var c: Vector2i = Vector2i(x, y)
				_astar.set_point_solid(c, not walkable_type(type_at(c)))


## Celdas de 4 m que pisa alguna casa (para que el tanque no las cruce).
func footprint_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen: Dictionary = {}
	var per: int = Config.MICRO_PER_CELL
	for r: Rect2i in houses:
		for y: int in range(r.position.y, r.end.y):
			for x: int in range(r.position.x, r.end.x):
				# micro-celda (x, y) -> celda de 4 m: la celda c abarca micro [c*per - per/2, c*per + per/2)
				var c: Vector2i = Vector2i(floori(float(x + per / 2) / per), floori(float(y + per / 2) / per))
				if not seen.has(c):
					seen[c] = true
					out.append(c)
	return out
