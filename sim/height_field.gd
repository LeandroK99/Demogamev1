class_name HeightField
extends RefCounted
## Grilla de alturas en metros. Índice = y * size + x.

var size: int = Config.GRID_SIZE
var heights: PackedFloat32Array = PackedFloat32Array()

# Parámetros de la cresta central (se fijan en generate)
var _ridge_phase: float = 0.0
var _ridge_h_phase: float = 0.0


func _init(p_size: int = Config.GRID_SIZE) -> void:
	size = p_size
	heights.resize(size * size)
	heights.fill(0.0)


## Genera el terreno procedural: ruido + cresta central garantizada + lomas menores.
func generate(map_seed: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = map_seed
	_ridge_phase = rng.randf() * TAU
	_ridge_h_phase = rng.randf() * TAU

	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = map_seed
	noise.frequency = Config.NOISE_FREQUENCY
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = Config.NOISE_OCTAVES

	# Ruido crudo y su rango para normalizar a 0..1
	var raw: PackedFloat32Array = PackedFloat32Array()
	raw.resize(size * size)
	var n_min: float = INF
	var n_max: float = -INF
	for y: int in size:
		for x: int in size:
			var v: float = noise.get_noise_2d(float(x), float(y))
			raw[y * size + x] = v
			n_min = minf(n_min, v)
			n_max = maxf(n_max, v)
	var n_range: float = maxf(n_max - n_min, 0.0001)

	# Lomas menores: alternan entre la mitad norte y la sur, lejos de la cresta
	var hills: Array[Dictionary] = []
	var hill_count: int = rng.randi_range(2, 3)
	for i: int in hill_count:
		var north: bool = (i % 2) == 0
		var cy: float = rng.randf_range(12.0, 28.0) if north else rng.randf_range(size - 28.0, size - 12.0)
		hills.append({
			"center": Vector2(rng.randf_range(10.0, size - 10.0), cy),
			"h": rng.randf_range(Config.MINOR_HILL_H_MIN, Config.MINOR_HILL_H_MAX),
			"r": rng.randf_range(Config.MINOR_HILL_R_MIN, Config.MINOR_HILL_R_MAX),
		})

	for y: int in size:
		for x: int in size:
			var base: float = (raw[y * size + x] - n_min) / n_range * Config.NOISE_WEIGHT
			var d: float = (float(y) - ridge_center_y(float(x))) / Config.RIDGE_WIDTH
			var relief: float = ridge_height(float(x)) * exp(-d * d)
			for hill: Dictionary in hills:
				var hd: float = Vector2(x, y).distance_to(hill["center"]) / float(hill["r"])
				relief = maxf(relief, float(hill["h"]) * exp(-hd * hd))
			heights[y * size + x] = clampf(base + relief, 0.0, 1.0) * Config.MAX_HEIGHT


## Coordenada y (en celdas) del eje de la cresta central para una x dada.
func ridge_center_y(x: float) -> float:
	var mid: float = size * 0.5
	return mid + (x - mid) * Config.RIDGE_TILT + sin(x * 0.07 + _ridge_phase) * Config.RIDGE_WAVE_AMP


## Altura de la cresta (fracción de MAX_HEIGHT) en una x dada.
func ridge_height(x: float) -> float:
	var t: float = 0.5 + 0.5 * sin(x * 0.05 + _ridge_h_phase)
	return lerpf(Config.RIDGE_MIN_H, Config.RIDGE_MAX_H, t)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size and c.y < size


func height_at_cell(c: Vector2i) -> float:
	var cx: int = clampi(c.x, 0, size - 1)
	var cy: int = clampi(c.y, 0, size - 1)
	return heights[cy * size + cx]


## Para armar mapas sintéticos en los tests.
func set_height(c: Vector2i, h: float) -> void:
	if in_bounds(c):
		heights[c.y * size + c.x] = h


## Interpolación bilineal en coordenadas de celda continuas.
func height_at(p: Vector2) -> float:
	var x: float = clampf(p.x, 0.0, float(size - 1))
	var y: float = clampf(p.y, 0.0, float(size - 1))
	var x0: int = mini(int(floor(x)), size - 2)
	var y0: int = mini(int(floor(y)), size - 2)
	var tx: float = x - float(x0)
	var ty: float = y - float(y0)
	var h00: float = heights[y0 * size + x0]
	var h10: float = heights[y0 * size + x0 + 1]
	var h01: float = heights[(y0 + 1) * size + x0]
	var h11: float = heights[(y0 + 1) * size + x0 + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), ty)


## Diferencia máxima de altura con los 8 vecinos, en metros.
func slope_at(c: Vector2i) -> float:
	var h: float = height_at_cell(c)
	var best: float = 0.0
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var n: Vector2i = c + Vector2i(dx, dy)
			if (dx != 0 or dy != 0) and in_bounds(n):
				best = maxf(best, absf(height_at_cell(n) - h))
	return best


func cell_to_world(c: Vector2i) -> Vector3:
	return Vector3(c.x * Config.CELL_SIZE, height_at_cell(c), c.y * Config.CELL_SIZE)


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x / Config.CELL_SIZE), roundi(p.z / Config.CELL_SIZE))
