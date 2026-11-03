extends TestBase
## Tests de la microcobertura a 1 m y de la línea de visión en metros.

const N: int = 96


func _analysis(mc: MicroCover) -> TerrainAnalysis:
	var a: TerrainAnalysis = TerrainAnalysis.new(HeightField.new(N))
	a.micro = mc
	return a


func test_cell_mapping() -> void:
	var c: Vector2i = MicroCover.cell_of(Vector2(0.0, 0.0))
	assert_eq(c, Vector2i(2, 2), "el centro de la celda (0, 0) cae en la micro-celda (2, 2)")
	assert_true(MicroCover.center_m(c).distance_to(Vector2(0.5, 0.5)) < 0.01, "centro de la micro-celda")


func test_rock_hides_prone_not_crouched() -> void:
	var mc: MicroCover = MicroCover.new(N)
	var target: Vector2 = Vector2(200.0, 200.0)
	mc.set_type(MicroCover.cell_of(target + Vector2(0.0, -1.5)), MicroCover.Type.ROCK) # roca 1,5 m al norte
	var a: TerrainAnalysis = _analysis(mc)
	var shooter: Vector2 = Vector2(200.0, 100.0) # 100 m al norte
	assert_true(not a.los_m(shooter, 1.7, target, 0.25), "cuerpo a tierra detrás de la roca: tapado")
	assert_true(a.los_m(shooter, 1.7, target, 0.8), "agachado: se lo ve")
	assert_true(a.los_m(Vector2(300.0, 200.0), 1.7, target, 0.25), "desde el costado la roca no tapa")


func test_wall_hides_crouched() -> void:
	var mc: MicroCover = MicroCover.new(N)
	var target: Vector2 = Vector2(200.0, 200.0)
	for k: int in range(-3, 4):
		mc.set_type(MicroCover.cell_of(target + Vector2(float(k), -1.5)), MicroCover.Type.WALL)
	var a: TerrainAnalysis = _analysis(mc)
	assert_true(not a.los_m(Vector2(200.0, 120.0), 1.7, target, 0.8), "agachado detrás del muro: tapado")
	assert_true(a.los_m(Vector2(200.0, 120.0), 1.7, target, 1.2), "de pie: se lo ve")


func test_bush_blocks_view() -> void:
	var mc: MicroCover = MicroCover.new(N)
	var target: Vector2 = Vector2(200.0, 200.0)
	mc.set_type(MicroCover.cell_of(target + Vector2(0.0, -2.0)), MicroCover.Type.BUSH)
	assert_true(not _analysis(mc).los_m(Vector2(200.0, 120.0), 1.7, target, 0.8), "el arbusto oculta")
	assert_true(not MicroCover.protects(MicroCover.Type.BUSH), "pero no protege")


func test_own_cell_does_not_block() -> void:
	var mc: MicroCover = MicroCover.new(N)
	var target: Vector2 = Vector2(200.5, 200.5)
	mc.set_type(MicroCover.cell_of(target), MicroCover.Type.ROCK)
	assert_true(_analysis(mc).los_m(Vector2(200.0, 120.0), 1.7, target, 0.25), "la roca en la propia celda no tapa")


func test_crater_lowers_occupant() -> void:
	var mc: MicroCover = MicroCover.new(N)
	var target: Vector2 = Vector2(200.5, 200.5)
	mc.set_type(MicroCover.cell_of(target), MicroCover.Type.CRATER)
	assert_true(mc.height_at_m(target) < 0.0, "el cráter es hundido")


func test_generation_from_cover() -> void:
	var cm: CoverMap = CoverMap.new(N)
	cm.generate(1337)
	var a: MicroCover = MicroCover.new(N)
	var b: MicroCover = MicroCover.new(N)
	a.generate(1337, cm)
	b.generate(1337, cm)
	assert_eq(a.types, b.types, "determinista")
	var counts: Dictionary = {}
	for t: int in a.types:
		counts[t] = int(counts.get(t, 0)) + 1
	for t: int in [MicroCover.Type.ROCK, MicroCover.Type.CRATER, MicroCover.Type.WALL, MicroCover.Type.BUSH, MicroCover.Type.TRUNK]:
		assert_true(int(counts.get(t, 0)) > 0, "hay del tipo %d" % t)
