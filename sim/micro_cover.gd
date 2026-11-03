class_name MicroCover
extends RefCounted
## Microcobertura a 1 m (MICRO_PER_CELL celdas por cada celda de 4 m): rocas, cráteres, tramos
## de muro, arbustos y troncos. La usan los soldados para la línea de visión (TerrainAnalysis.los_m)
## y para elegir dónde ponerse. Coordenadas en metros del mundo: la celda (x, y) de 4 m está
## centrada en (x, y) * CELL_SIZE, así que la micro-celda de un punto p es floor((p + CELL_SIZE / 2) / MICRO_M).

enum Type { NONE, ROCK, CRATER, WALL, BUSH, TRUNK }

const MICRO_M: float = Config.CELL_SIZE / Config.MICRO_PER_CELL # metros por micro-celda

var size: int = 0 # micro-celdas por lado
var types: PackedByteArray = PackedByteArray()
var heights: PackedFloat32Array = PackedFloat32Array() # altura del obstáculo sobre el terreno (negativa: hundido)


func _init(cells: int) -> void:
	size = cells * Config.MICRO_PER_CELL
	types.resize(size * size)
	types.fill(Type.NONE)
	heights.resize(size * size)
	heights.fill(0.0)


static func type_height(t: int) -> float:
	match t:
		Type.ROCK:
			return Config.MICRO_ROCK_H
		Type.CRATER:
			return -Config.MICRO_CRATER_DEPTH
		Type.WALL:
			return Config.MICRO_WALL_H
		Type.BUSH:
			return Config.MICRO_BUSH_H
		Type.TRUNK:
			return Config.FOREST_TREE_H
	return 0.0


## ¿Protege contra el fuego? (el arbusto oculta pero no frena balas; el cráter protege al de adentro)
static func protects(t: int) -> bool:
	return t == Type.ROCK or t == Type.WALL or t == Type.TRUNK


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size and c.y < size


static func cell_of(p_m: Vector2) -> Vector2i:
	var off: float = Config.CELL_SIZE * 0.5
	return Vector2i(floori((p_m.x + off) / MICRO_M), floori((p_m.y + off) / MICRO_M))


## Centro en metros de una micro-celda.
static func center_m(c: Vector2i) -> Vector2:
	var off: float = Config.CELL_SIZE * 0.5
	return Vector2((float(c.x) + 0.5) * MICRO_M - off, (float(c.y) + 0.5) * MICRO_M - off)


func set_type(c: Vector2i, t: int) -> void:
	if in_bounds(c):
		types[c.y * size + c.x] = t
		heights[c.y * size + c.x] = type_height(t)


func type_at(c: Vector2i) -> int:
	return types[c.y * size + c.x] if in_bounds(c) else Type.NONE


func type_at_m(p_m: Vector2) -> int:
	return type_at(cell_of(p_m))


func height_at_m(p_m: Vector2) -> float:
	var c: Vector2i = cell_of(p_m)
	return heights[c.y * size + c.x] if in_bounds(c) else 0.0


## Genera la microcobertura a partir de la cobertura de 4 m (muros, pozos, bosques)
## y le suma grupos de rocas y cráteres sueltos. Determinista con la semilla.
func generate(map_seed: int, cover: CoverMap) -> void:
	types.fill(Type.NONE)
	heights.fill(0.0)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = map_seed + 104729
	var per: int = Config.MICRO_PER_CELL
	var cells: int = size / per
	for y: int in cells:
		for x: int in cells:
			var c: Vector2i = Vector2i(x, y)
			var base: Vector2i = c * per
			match cover.type_at(c) if cover != null else CoverMap.Type.NONE:
				CoverMap.Type.WALL:
					_wall_in_cell(cover, c, base)
				CoverMap.Type.PIT:
					for dy: int in 2:
						for dx: int in 2:
							set_type(base + Vector2i(1 + dx, 1 + dy), Type.CRATER)
				CoverMap.Type.FOREST:
					if rng.randf() < Config.MICRO_TRUNK_P:
						set_type(base + Vector2i(rng.randi_range(0, per - 1), rng.randi_range(0, per - 1)), Type.TRUNK)
					if _is_forest_edge(cover, c):
						for k: int in Config.MICRO_EDGE_BUSHES:
							set_type(base + Vector2i(rng.randi_range(0, per - 1), rng.randi_range(0, per - 1)), Type.BUSH)
	# Rocas en grupos y cráteres sueltos, fuera de las franjas de despliegue
	var clear: int = (Config.DEPLOY_EDGE_MARGIN + Config.COVER_DEPLOY_CLEAR) * per
	for i: int in Config.MICRO_ROCK_CLUSTERS:
		var center: Vector2i = Vector2i(rng.randi_range(4, size - 5), rng.randi_range(clear, size - 1 - clear))
		for k: int in rng.randi_range(Config.MICRO_ROCKS_MIN, Config.MICRO_ROCKS_MAX):
			var c: Vector2i = center + Vector2i(rng.randi_range(-3, 3), rng.randi_range(-3, 3))
			if type_at(c) == Type.NONE:
				set_type(c, Type.ROCK)
	for i: int in Config.MICRO_CRATERS:
		var c: Vector2i = Vector2i(rng.randi_range(4, size - 5), rng.randi_range(clear, size - 1 - clear))
		if type_at(c) == Type.NONE:
			set_type(c, Type.CRATER)


## Tramo de muro dentro de una celda de 4 m, orientado según los muros vecinos.
func _wall_in_cell(cover: CoverMap, c: Vector2i, base: Vector2i) -> void:
	var per: int = Config.MICRO_PER_CELL
	var mid: int = per / 2
	var dir: Vector2i = Vector2i(1, 0)
	if cover.type_at(c + Vector2i(1, 0)) == CoverMap.Type.WALL or cover.type_at(c - Vector2i(1, 0)) == CoverMap.Type.WALL:
		dir = Vector2i(1, 0)
	elif cover.type_at(c + Vector2i(0, 1)) == CoverMap.Type.WALL or cover.type_at(c - Vector2i(0, 1)) == CoverMap.Type.WALL:
		dir = Vector2i(0, 1)
	elif cover.type_at(c + Vector2i(1, 1)) == CoverMap.Type.WALL or cover.type_at(c - Vector2i(1, 1)) == CoverMap.Type.WALL:
		dir = Vector2i(1, 1)
	elif cover.type_at(c + Vector2i(1, -1)) == CoverMap.Type.WALL or cover.type_at(c - Vector2i(1, -1)) == CoverMap.Type.WALL:
		dir = Vector2i(1, -1)
	for k: int in per:
		var p: Vector2i
		if dir == Vector2i(1, 0):
			p = base + Vector2i(k, mid)
		elif dir == Vector2i(0, 1):
			p = base + Vector2i(mid, k)
		elif dir == Vector2i(1, 1):
			p = base + Vector2i(k, k)
		else:
			p = base + Vector2i(k, per - 1 - k)
		set_type(p, Type.WALL)


static func _is_forest_edge(cover: CoverMap, c: Vector2i) -> bool:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not cover.is_forest(c + d):
			return true
	return false
