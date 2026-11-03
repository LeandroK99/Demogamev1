extends TestBase
## Tests de la cobertura fina: bosques, muros y pozos.

const N: int = 96


func _world(cm: CoverMap) -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 0 or u.id == 4
	world.units[4].pos = Vector2(5, 2)
	world.units[4].reload_left = 1000.0
	world.set_cover(cm)
	return world


## Bosque rectangular de x0..x1, y0..y1.
func _forest(cm: CoverMap, x0: int, x1: int, y0: int, y1: int) -> void:
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			cm.set_type(Vector2i(x, y), CoverMap.Type.FOREST)


func test_forest_blocks_los_after_two_cells() -> void:
	var cm: CoverMap = CoverMap.new(N)
	_forest(cm, 40, 56, 40, 50)
	var world: SimWorld = _world(cm)
	var a: TerrainAnalysis = world.analysis
	assert_true(not a.los(Vector2i(48, 70), 2.4, Vector2i(48, 30), 1.6), "atravesar 11 celdas de bosque corta")
	assert_true(a.los(Vector2i(48, 70), 2.4, Vector2i(48, 51), 1.6), "al borde del bosque se ve")
	assert_true(a.los(Vector2i(48, 70), 2.4, Vector2i(48, 49), 1.6), "una celda adentro todavía se ve")
	assert_true(a.los(Vector2i(10, 70), 2.4, Vector2i(10, 30), 1.6), "por afuera del bosque se ve")


func test_cover_reduces_hits_and_detection() -> void:
	var cm: CoverMap = CoverMap.new(N)
	cm.set_type(Vector2i(48, 50), CoverMap.Type.PIT)
	var world: SimWorld = _world(cm)
	var shooter: Unit = world.add_unit(0, Vector2(48, 60), Unit.Kind.INFANTRY)
	var open_sq: Unit = world.add_unit(1, Vector2(40, 50), Unit.Kind.INFANTRY)
	var pit_sq: Unit = world.add_unit(1, Vector2(48, 50), Unit.Kind.INFANTRY)
	var p_open: float = world.hit_probability(shooter, open_sq, Unit.Weapon.RIFLES)
	var p_pit: float = world.hit_probability(shooter, pit_sq, Unit.Weapon.RIFLES)
	assert_lt(p_pit, p_open * 0.5, "en el pozo recibe muchos menos impactos")
	assert_lt(world.infantry_spot_range(pit_sq), world.infantry_spot_range(open_sq), "y se la detecta más cerca")


func test_tank_slower_in_forest() -> void:
	var cm: CoverMap = CoverMap.new(N)
	_forest(cm, 40, 56, 40, 50)
	var world: SimWorld = _world(cm)
	assert_lt(world.speed_at(Vector2i(48, 45)), world.speed_at(Vector2i(48, 60)), "el tanque va más lento en el bosque")
	assert_eq(world.speed_at(Vector2i(48, 45), Unit.Kind.INFANTRY), world.speed_at(Vector2i(48, 60), Unit.Kind.INFANTRY), "la infantería no")


func test_take_position_prefers_cover() -> void:
	var cm: CoverMap = CoverMap.new(N)
	for x: int in range(44, 53):
		cm.set_type(Vector2i(x, 60), CoverMap.Type.WALL)
	var world: SimWorld = _world(cm)
	var sq: Unit = world.add_unit(0, Vector2(48, 64), Unit.Kind.INFANTRY)
	world.units[4].pos = Vector2(48, 30)
	world.known_enemies[0][4] = {"cell": Vector2i(48, 30), "last_seen_turn": world.turn}
	world.invalidate_exposure()
	var ids: Array[int] = [sq.id]
	world.order_hulldown(ids)
	assert_eq(cm.type_at(world.destination(sq)), CoverMap.Type.WALL, "toma posición en el muro (%s)" % world.destination(sq))


func test_generation_is_deterministic() -> void:
	var a: CoverMap = CoverMap.new(N)
	var b: CoverMap = CoverMap.new(N)
	a.generate(1337)
	b.generate(1337)
	assert_eq(a.types, b.types, "misma semilla, misma cobertura")
	var forest: int = 0
	for t: int in a.types:
		if t == CoverMap.Type.FOREST:
			forest += 1
	assert_true(forest > 50, "hay bosque (%d celdas)" % forest)
	for x: int in N:
		assert_eq(a.type_at(Vector2i(x, N - 1 - Config.DEPLOY_EDGE_MARGIN)), CoverMap.Type.NONE, "despliegue libre")
