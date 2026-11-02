extends TestBase
## Tests del HeightField procedural.


func _make() -> HeightField:
	var hf: HeightField = HeightField.new()
	hf.generate(Config.SEED)
	return hf


func test_same_seed_same_heights() -> void:
	var a: HeightField = _make()
	var b: HeightField = _make()
	assert_true(a.heights == b.heights, "misma semilla, mismas alturas")


func test_height_range() -> void:
	var hf: HeightField = _make()
	var h_min: float = INF
	var h_max: float = -INF
	for h: float in hf.heights:
		h_min = minf(h_min, h)
		h_max = maxf(h_max, h)
	assert_true(h_min >= 0.0, "altura mínima >= 0 (fue %f)" % h_min)
	assert_true(h_max <= Config.MAX_HEIGHT, "altura máxima <= MAX_HEIGHT (fue %f)" % h_max)


func test_central_ridge_exists() -> void:
	var hf: HeightField = _make()
	var ridge_sum: float = 0.0
	var ridge_n: int = 0
	var edge_sum: float = 0.0
	var edge_n: int = 0
	for y: int in hf.size:
		for x: int in hf.size:
			var h: float = hf.height_at_cell(Vector2i(x, y))
			if absf(float(y) - hf.ridge_center_y(float(x))) <= 3.0:
				ridge_sum += h
				ridge_n += 1
			elif y < 6 or y >= hf.size - 6:
				edge_sum += h
				edge_n += 1
	assert_lt(edge_sum / edge_n, ridge_sum / ridge_n, "la franja de la cresta es más alta que los bordes")


func test_bilinear_matches_cells() -> void:
	var hf: HeightField = _make()
	var c: Vector2i = Vector2i(40, 50)
	assert_true(is_equal_approx(hf.height_at(Vector2(c)), hf.height_at_cell(c)), "height_at en una celda exacta")
	var mid: float = hf.height_at(Vector2(40.5, 50.0))
	var expected: float = (hf.height_at_cell(c) + hf.height_at_cell(Vector2i(41, 50))) * 0.5
	assert_true(is_equal_approx(mid, expected), "interpolación a mitad de celda")


func test_cell_world_roundtrip() -> void:
	var hf: HeightField = _make()
	var c: Vector2i = Vector2i(17, 83)
	assert_eq(hf.world_to_cell(hf.cell_to_world(c)), c, "celda -> mundo -> celda")
