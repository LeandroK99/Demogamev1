class_name TownGenerator
extends RefCounted
## "El pueblo" (fase 61): una plaza en el centro del mapa, una calle norte-sur (el eje de avance
## azul) y una este-oeste que se cruzan en ella, y TOWN_HOUSES_PER_QUADRANT casas en cada cuarto:
## una en la esquina de la plaza, una sobre la calle norte-sur y una sobre la este-oeste. Cada casa
## tiene la puerta hacia su calle (a veces otra atrás), ventanas cada pocos metros y, si es grande,
## paredes interiores con un paso que la dividen en dos o cuatro cuartos. Determinista con la semilla.


## Centro de la plaza (celda de 4 m).
static func center_cell(hf: HeightField) -> Vector2i:
	return Vector2i(hf.size / 2, hf.size / 2)


## Aplana el terreno del pueblo y arma las casas. Devuelve el mapa de edificios.
static func build(hf: HeightField, map_seed: int) -> BuildingMap:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = map_seed + 7727
	var cc: Vector2i = center_cell(hf)
	_flatten(hf, cc, Config.TOWN_RADIUS_CELLS, Config.TOWN_BLEND_CELLS)
	var bm: BuildingMap = BuildingMap.new(hf.size)
	var cm: Vector2i = MicroCover.cell_of(Vector2(cc) * Config.CELL_SIZE)
	var p: int = Config.TOWN_PLAZA_HALF_M
	var s: int = Config.TOWN_STREET_HALF_M
	var lot: int = Config.TOWN_LOT_M
	for q: Vector2i in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		# Origen local (x, y >= 0 alejándose del centro) de cada casa y hacia dónde mira su puerta
		var lots: Array[Dictionary] = [
			{"at": Vector2i(p + 3, p + 3), "door": Vector2i(0, -1)}, # en la esquina de la plaza, la puerta hacia ella
			{"at": Vector2i(s + 3, p + 3 + lot), "door": Vector2i(-1, 0)}, # sobre la calle norte-sur
			{"at": Vector2i(p + 3 + lot, s + 3), "door": Vector2i(0, -1)}, # sobre la calle este-oeste
		]
		for k: int in mini(Config.TOWN_HOUSES_PER_QUADRANT, lots.size()):
			var w: int = rng.randi_range(Config.TOWN_HOUSE_MIN_M.x, Config.TOWN_HOUSE_MAX_M.x)
			var h: int = rng.randi_range(Config.TOWN_HOUSE_MIN_M.y, Config.TOWN_HOUSE_MAX_M.y)
			_house(bm, rng, cm, q, lots[k]["at"], Vector2i(w, h), lots[k]["door"])
	return bm


## Una casa en coordenadas locales del cuarto q (origen o, tamaño sz; door: lado de la puerta
## principal, (-1, 0) = el de x chica, (0, -1) = el de y chica).
static func _house(bm: BuildingMap, rng: RandomNumberGenerator, cm: Vector2i, q: Vector2i, o: Vector2i,
		sz: Vector2i, door: Vector2i) -> void:
	var to_world: Callable = func(l: Vector2i) -> Vector2i: return cm + Vector2i(l.x * q.x, l.y * q.y)
	var a: Vector2i = to_world.call(o)
	var b: Vector2i = to_world.call(o + sz - Vector2i.ONE)
	var rect: Rect2i = Rect2i(Vector2i(mini(a.x, b.x), mini(a.y, b.y)), sz)
	var doors: Array[Vector2i] = []
	var windows: Array[Vector2i] = []
	# Puerta principal cerca del medio de su lado (corrida para no dar contra una pared interior);
	# a veces una de atrás
	var mx: int = sz.x / 2
	var my: int = sz.y / 2
	var corridor: bool = sz.x >= Config.TOWN_CORRIDOR_M.x and sz.y >= Config.TOWN_CORRIDOR_M.y
	if door.x != 0:
		# Con pasillo, la puerta del costado da al pasillo
		doors.append(to_world.call(o + Vector2i(0, my - 1 if corridor else maxi(1, my - 2))))
		if rng.randf() < Config.TOWN_BACK_DOOR_P:
			doors.append(to_world.call(o + Vector2i(sz.x - 1, mini(sz.y - 2, my + 2))))
	else:
		doors.append(to_world.call(o + Vector2i(maxi(1, mx - 2), 0)))
		if rng.randf() < Config.TOWN_BACK_DOOR_P:
			doors.append(to_world.call(o + Vector2i(mini(sz.x - 2, mx + 2), sz.y - 1)))
	# Ventanas cada TOWN_WINDOW_EVERY_M por las cuatro paredes (no en esquinas ni junto a la puerta)
	for x: int in range(2, sz.x - 2, Config.TOWN_WINDOW_EVERY_M):
		for y: int in [0, sz.y - 1]:
			windows.append(to_world.call(o + Vector2i(x, y)))
	for y: int in range(2, sz.y - 2, Config.TOWN_WINDOW_EVERY_M):
		for x: int in [0, sz.x - 1]:
			windows.append(to_world.call(o + Vector2i(x, y)))
	var free_windows: Array[Vector2i] = []
	for wnd: Vector2i in windows:
		var near_door: bool = false
		for d: Vector2i in doors:
			if absi(d.x - wnd.x) + absi(d.y - wnd.y) <= 1:
				near_door = true
		if not near_door:
			free_windows.append(wnd)
	bm.add_house(rect, doors, free_windows)
	if corridor:
		_corridor_house(bm, rng, to_world, o, sz, mx, my)
		return
	# Paredes interiores con pasos de 1 m: hasta cuatro cuartos, todos comunicados
	var split_x: bool = sz.x >= Config.TOWN_SPLIT_M
	var split_y: bool = sz.y >= Config.TOWN_SPLIT_M
	if split_x:
		var gap: int = rng.randi_range(1, my - 1) if split_y else rng.randi_range(1, sz.y - 2)
		for y: int in range(1, sz.y - 1):
			if y != gap:
				bm.set_type(to_world.call(o + Vector2i(mx, y)), BuildingMap.Type.WALL)
	if split_y:
		var gaps: Array[int] = [rng.randi_range(1, mx - 1)]
		if split_x:
			gaps.append(rng.randi_range(mx + 1, sz.x - 2))
		for x: int in range(1, sz.x - 1):
			if not gaps.has(x):
				bm.set_type(to_world.call(o + Vector2i(x, my)), BuildingMap.Type.WALL)


## Casa grande con pasillo (fase 69): un pasillo de 2 m a lo largo (filas my - 1 y my) con un cuarto
## a cada lado de cada mitad; cada cuarto da al pasillo por un paso de 1 m.
static func _corridor_house(bm: BuildingMap, rng: RandomNumberGenerator, to_world: Callable, o: Vector2i,
		sz: Vector2i, mx: int, my: int) -> void:
	for wy: int in [my - 2, my + 1]:
		var gaps: Array[int] = [rng.randi_range(1, mx - 1), rng.randi_range(mx + 1, sz.x - 2)]
		for x: int in range(1, sz.x - 1):
			if not gaps.has(x):
				bm.set_type(to_world.call(o + Vector2i(x, wy)), BuildingMap.Type.WALL)
	for y: int in range(1, sz.y - 1):
		if y < my - 2 or y > my + 1:
			bm.set_type(to_world.call(o + Vector2i(mx, y)), BuildingMap.Type.WALL)


## Lleva el terreno a la altura media dentro de radius celdas del centro, con una transición de
## blend celdas.
static func _flatten(hf: HeightField, c: Vector2i, radius: int, blend: int) -> void:
	var sum: float = 0.0
	var n: int = 0
	for y: int in range(c.y - radius, c.y + radius + 1):
		for x: int in range(c.x - radius, c.x + radius + 1):
			if hf.in_bounds(Vector2i(x, y)):
				sum += hf.heights[y * hf.size + x]
				n += 1
	var level: float = sum / float(maxi(n, 1))
	var outer: int = radius + blend
	for y: int in range(c.y - outer, c.y + outer + 1):
		for x: int in range(c.x - outer, c.x + outer + 1):
			if not hf.in_bounds(Vector2i(x, y)):
				continue
			var d: float = maxf(absf(float(x - c.x)), absf(float(y - c.y)))
			var k: float = clampf((float(outer) - d) / float(maxi(blend, 1)), 0.0, 1.0)
			var i: int = y * hf.size + x
			hf.heights[i] = lerpf(hf.heights[i], level, k)


## Rectángulo (celdas de 4 m) que ocupa el pueblo: ahí no hay bosques ni microcobertura suelta.
static func area_cells(hf: HeightField) -> Rect2i:
	var c: Vector2i = center_cell(hf)
	var r: int = Config.TOWN_RADIUS_CELLS
	return Rect2i(c - Vector2i(r, r), Vector2i(2 * r + 1, 2 * r + 1))
