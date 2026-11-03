extends TestBase
## Tests de la formación según el terreno: abierta en terreno limpio, fila en el bosque, escalón y línea.

const N: int = 96


func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 4 # un tanque rojo lejos, para que no termine la partida
	world.units[4].pos = Vector2(5, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	world.set_cover(CoverMap.new(N))
	world.set_micro(MicroCover.new(N))
	return world


## Separación media entre cada soldado y el más cercano.
func _mean_gap(u: Unit) -> float:
	var sum: float = 0.0
	for s: Soldier in u.soldiers:
		var best: float = INF
		for o: Soldier in u.soldiers:
			if o != s:
				best = minf(best, Unit.formation_offset(s.index, u.shape, u.echelon_side).distance_to(Unit.formation_offset(o.index, u.shape, u.echelon_side)) * u.spread)
		sum += best
	return sum / float(u.soldiers.size())


func test_open_ground_opens_the_wedge() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	for i: int in 30:
		world.inf.adapt_formation(world, sq)
	assert_eq(sq.shape, Unit.Formation.WEDGE, "cuña")
	assert_eq(sq.spread, Config.FORM_SPREAD_OPEN, "se abre de a poco")
	var open_gap: float = _mean_gap(sq)
	world.cover.set_type(Vector2i(50, 80), CoverMap.Type.FOREST)
	for i: int in 30:
		world.inf.adapt_formation(world, sq)
	assert_eq(sq.spread, 1.0, "cerca del bosque se cierra")
	assert_lt(_mean_gap(sq), open_gap, "más juntos")


func test_forest_becomes_file() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	world.cover.set_type(Vector2i(48, 80), CoverMap.Type.FOREST)
	world.inf.adapt_formation(world, sq)
	assert_eq(sq.shape, Unit.Formation.FILE, "fila india en el bosque")
	assert_eq(sq.formation, Unit.Formation.WEDGE, "la elección del jugador no cambia")


func test_echelon_toward_flank_contact() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	sq.heading = Vector2(0.0, -1.0)
	sq.mind.learn(9, Vector2(48 + 40, 75) * Config.CELL_SIZE, 0, true) # al este
	world.inf.adapt_formation(world, sq)
	assert_eq(sq.shape, Unit.Formation.ECHELON, "escalón")
	assert_eq(sq.echelon_side, 1.0, "hacia la derecha (el este, yendo al norte)")
	assert_lt(0.0, Unit.formation_offset(4, Unit.Formation.ECHELON, 1.0).x, "los de atrás, corridos a la derecha")


func test_contact_ahead_keeps_wedge() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	sq.heading = Vector2(0.0, -1.0)
	sq.mind.learn(9, Vector2(50, 40) * Config.CELL_SIZE, 0, true)
	world.inf.adapt_formation(world, sq)
	assert_eq(sq.shape, Unit.Formation.WEDGE, "de frente, cuña")


func test_line_for_final_assault() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	world.order_move(sq.id, Vector2i(48, 70))
	sq.order = Unit.Order.ASSAULT
	world.inf.adapt_formation(world, sq)
	assert_eq(sq.shape, Unit.Formation.LINE, "a 40 m del objetivo: línea")


func test_player_choice_respected() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	assert_true(world.set_formation(sq.id, Unit.Formation.FILE), "en el plan")
	world.inf.adapt_formation(world, sq)
	assert_eq(sq.shape, Unit.Formation.FILE, "eligió fila: queda en fila")
