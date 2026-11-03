extends TestBase
## Tests de TerrainAnalysis sobre HeightField sintéticos armados a mano.

const N: int = 64


## Loma recta a lo largo de y, centrada en la columna cx, con perfil triangular.
func _ridge_map(cx: int, h: float, falloff: float) -> HeightField:
	var hf: HeightField = HeightField.new(N)
	for y: int in N:
		for x: int in N:
			hf.set_height(Vector2i(x, y), maxf(0.0, h - absf(float(x - cx)) * falloff))
	return hf


func test_los_flat() -> void:
	var ta: TerrainAnalysis = TerrainAnalysis.new(HeightField.new(N))
	assert_true(ta.los(Vector2i(5, 10), Config.EYE_H, Vector2i(55, 10), Config.HULL_H), "llano a 50 celdas")


func test_los_blocked_by_wall() -> void:
	var hf: HeightField = HeightField.new(N)
	for y: int in N:
		hf.set_height(Vector2i(30, y), 10.0)
	var ta: TerrainAnalysis = TerrainAnalysis.new(hf)
	assert_true(not ta.los(Vector2i(5, 10), Config.EYE_H, Vector2i(55, 10), Config.HULL_H), "pared de 10 m")


func test_reverse_slope() -> void:
	var ta: TerrainAnalysis = TerrainAnalysis.new(_ridge_map(30, 6.0, 1.5))
	var observer: Vector2i = Vector2i(10, 32)
	assert_true(ta.los(observer, Config.EYE_H, Vector2i(30, 32), Config.HULL_H), "ve la celda de la cresta")
	assert_true(not ta.los(observer, Config.EYE_H, Vector2i(35, 32), Config.HULL_H), "no ve 5 celdas detrás")


func test_hulldown_candidate_exists() -> void:
	var ta: TerrainAnalysis = TerrainAnalysis.new(_ridge_map(30, 1.8, 0.6))
	var threats: Array[Vector2i] = [Vector2i(10, 32)]
	var cands: Array[Dictionary] = ta.hulldown_candidates(Vector2i(40, 32), threats, Config.HULLDOWN_RADIUS)
	var found: bool = false
	for c: Dictionary in cands:
		if c["hull_hidden"] and c["can_fire"]:
			found = true
			break
	assert_true(found, "hay un candidato con casco oculto que puede disparar")
	assert_true(cands[0]["hull_hidden"] and cands[0]["can_fire"], "el mejor candidato es hull-down")


func test_exposure_flat_in_range() -> void:
	var hf: HeightField = HeightField.new(Config.GRID_SIZE)
	var ta: TerrainAnalysis = TerrainAnalysis.new(hf)
	var threat: Vector2i = Vector2i(48, 48)
	var threats: Array[Vector2i] = [threat]
	var exp_map: PackedFloat32Array = ta.exposure_map(threats)
	var bad: int = 0
	for y: int in hf.size:
		for x: int in hf.size:
			var c: Vector2i = Vector2i(x, y)
			if TerrainAnalysis.dist_m(threat, c) < Config.MAX_RANGE and exp_map[y * hf.size + x] != 1.0:
				bad += 1
	assert_eq(bad, 0, "celdas en rango con exposición distinta de 1")


func test_smoke_blocks_los() -> void:
	var ta: TerrainAnalysis = TerrainAnalysis.new(HeightField.new(64))
	var a: Vector2i = Vector2i(5, 30)
	var b: Vector2i = Vector2i(55, 30)
	assert_true(ta.los(a, Config.EYE_H, b, Config.CENTER_H), "sin humo se ve")
	ta.smoke = [{"center": Vector2(30, 30), "radius": 3.0, "top_h": 8.0}]
	assert_true(not ta.los(a, Config.EYE_H, b, Config.CENTER_H), "la nube en el medio tapa")


func test_smoke_to_the_side_does_not_block() -> void:
	var ta: TerrainAnalysis = TerrainAnalysis.new(HeightField.new(64))
	ta.smoke = [{"center": Vector2(30, 40), "radius": 3.0, "top_h": 8.0}]
	assert_true(ta.los(Vector2i(5, 30), Config.EYE_H, Vector2i(55, 30), Config.CENTER_H), "la nube a un costado no tapa")


func test_high_observer_sees_over_smoke() -> void:
	var ta: TerrainAnalysis = TerrainAnalysis.new(HeightField.new(64))
	ta.smoke = [{"center": Vector2(30, 30), "radius": 3.0, "top_h": 8.0}]
	assert_true(ta.los(Vector2i(5, 30), 20.0, Vector2i(55, 30), 20.0), "por encima del tope se ve")
