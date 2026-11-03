class_name CoverMap
extends RefCounted
## Cobertura fina por celda: bosques, muros de piedra y pozos.
## El bosque corta la línea de visión (ver TerrainAnalysis.los) y frena a los tanques;
## toda cobertura reduce los impactos y la detección contra la infantería.

enum Type { NONE, FOREST, WALL, PIT }

var size: int = 0
var types: PackedByteArray = PackedByteArray()


func _init(p_size: int) -> void:
	size = p_size
	types.resize(size * size)
	types.fill(Type.NONE)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size and c.y < size


func type_at(c: Vector2i) -> int:
	return types[c.y * size + c.x] if in_bounds(c) else Type.NONE


func set_type(c: Vector2i, t: int) -> void:
	if in_bounds(c):
		types[c.y * size + c.x] = t


func is_forest(c: Vector2i) -> bool:
	return type_at(c) == Type.FOREST


## Valor de cobertura 0..1 para la infantería en la celda.
func cover_at(c: Vector2i) -> float:
	match type_at(c):
		Type.FOREST:
			return Config.COVER_FOREST
		Type.WALL:
			return Config.COVER_WALL
		Type.PIT:
			return Config.COVER_PIT
	return 0.0


## Genera la cobertura con la semilla, sin tocar las franjas de despliegue
## (DEPLOY_EDGE_MARGIN + COVER_DEPLOY_CLEAR celdas desde el borde norte y sur).
func generate(map_seed: int) -> void:
	types.fill(Type.NONE)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = map_seed + 7919
	var clear: int = Config.DEPLOY_EDGE_MARGIN + Config.COVER_DEPLOY_CLEAR
	var lo: int = clear
	var hi: int = size - 1 - clear
	for i: int in Config.FOREST_COUNT:
		var center: Vector2 = Vector2(rng.randi_range(4, size - 5), rng.randi_range(lo, hi))
		var r: float = rng.randf_range(Config.FOREST_R_MIN, Config.FOREST_R_MAX)
		var ri: int = ceili(r)
		for dy: int in range(-ri, ri + 1):
			for dx: int in range(-ri, ri + 1):
				var c: Vector2i = Vector2i(center) + Vector2i(dx, dy)
				# Borde irregular: el radio varía con el ángulo
				var ang: float = atan2(float(dy), float(dx))
				var rr: float = r * (0.8 + 0.2 * sin(ang * 3.0 + float(i)))
				if Vector2(dx, dy).length() <= rr and c.y >= lo and c.y <= hi:
					set_type(c, Type.FOREST)
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	for i: int in Config.WALL_COUNT:
		var start: Vector2i = Vector2i(rng.randi_range(4, size - 5), rng.randi_range(lo, hi))
		var dir: Vector2i = dirs[rng.randi_range(0, dirs.size() - 1)]
		var length: int = rng.randi_range(Config.WALL_LEN_MIN, Config.WALL_LEN_MAX)
		for k: int in length:
			var c: Vector2i = start + dir * k
			if c.y >= lo and c.y <= hi and type_at(c) == Type.NONE:
				set_type(c, Type.WALL)
	for i: int in Config.PIT_COUNT:
		var c: Vector2i = Vector2i(rng.randi_range(2, size - 3), rng.randi_range(lo, hi))
		if type_at(c) == Type.NONE:
			set_type(c, Type.PIT)


## Bosques en la contrapendiente norte de la cresta central (escenario "La loma").
func add_ridge_forest(hf: HeightField) -> void:
	for x0: int in range(Config.LOMA_FOREST_X_STEP / 2, size, Config.LOMA_FOREST_X_STEP):
		for x: int in range(x0 - Config.LOMA_FOREST_HALF_W, x0 + Config.LOMA_FOREST_HALF_W + 1):
			var ry: int = roundi(hf.ridge_center_y(float(x)))
			for back: int in range(Config.LOMA_FOREST_FROM, Config.LOMA_FOREST_TO + 1):
				set_type(Vector2i(x, ry - back), Type.FOREST)
