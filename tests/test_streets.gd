extends TestBase
## Tests de las calles (fase 62): rutas pegadas a las fachadas y cruzar una calle batida.

const N: int = 64
const O := SquadMind.Option


## Dos casas largas (40 m) norte-sur con una calle de 26 m entre medio (celdas x 28 a 33).
func _world(gap_micro: int = 34) -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 4
	world.units[4].pos = Vector2(2, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	world.set_micro(MicroCover.new(N))
	var bm: BuildingMap = BuildingMap.new(N)
	bm.add_house(Rect2i(100, 100, 10, 40))
	bm.add_house(Rect2i(100 + gap_micro, 100, 10, 40))
	world.set_buildings(bm)
	return world


func test_facade_distances() -> void:
	var world: SimWorld = _world()
	assert_eq(world.facade_at(Vector2i(26, 30)), 0, "adentro de la casa")
	assert_eq(world.facade_at(Vector2i(28, 30)), 1, "pegado a la fachada")
	assert_true(world.is_street(Vector2i(30, 30)), "el medio es calle")
	assert_eq(world.facade_at(Vector2i(5, 5)), 255, "lejos del pueblo")


func test_route_hugs_the_facades() -> void:
	var world: SimWorld = _world(16) # calle angosta: celdas 28 a 29
	var sq: Unit = world.add_unit(0, Vector2(29, 40), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.STRICT
	assert_true(world.order_move(sq.id, Vector2i(29, 20)), "orden aceptada")
	var hug: int = 0
	var open: int = 0
	for c: Vector2i in sq.path:
		if c.y > 24 and c.y < 36:
			if world.facade_at(c) == 1:
				hug += 1
			elif world.is_street(c):
				open += 1
	assert_lt(float(open), float(hug), "más pegada a las paredes (%d) que por el medio (%d)" % [hug, open])


func _crossing(world: SimWorld, smoke: bool) -> Unit:
	var sq: Unit = world.add_unit(0, Vector2(28, 30), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.HIGH
	for s: Soldier in sq.soldiers: # en fila pegados a la fachada, del lado de la calle
		s.pos = Vector2(110.0 + float(s.index % 2), 104.0 + float(s.index) * 3.0)
	if not smoke:
		sq.smoke_charges = 0
	world.order_move(sq.id, Vector2i(33, 30), Vector2.ZERO, false)
	world.begin_execute()
	sq.mind.learn(4, Vector2(31, 2) * Config.CELL_SIZE, 1000000, true) # al fondo de la calle: la ve
	sq.mind.reacted[4] = true # contacto viejo: ya reaccionó (sin drill)
	return sq


func test_watched_street_smoke_then_all_cross() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _crossing(world, true)
	var crossed_early: bool = false
	var saw_cross: bool = false
	for i: int in 20:
		world.step()
		if sq.mind.option == O.CROSS:
			saw_cross = true
	assert_true(saw_cross, "decide cruzar la calle")
	assert_eq(str(sq.mind.data.get("phase", "")), "smoke", "primero humo")
	assert_true(not world.smoke_clouds.is_empty(), "hay humo")
	for s: Soldier in sq.soldiers:
		if s.pos.x > 118.0:
			crossed_early = true
	assert_true(not crossed_early, "nadie cruzó antes del humo")
	for i: int in 400:
		world.step()
	var across: int = 0
	for s: Soldier in sq.soldiers:
		if s.pos.x > 118.0:
			across += 1
	assert_eq(sq.cell(), Vector2i(33, 30), "el ancla llegó a la otra vereda")
	assert_lt(6.5, float(across), "cruzaron todos (%d pasaron el medio)" % across)


func test_watched_street_without_smoke_waits() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _crossing(world, false)
	for i: int in 100:
		world.step()
	assert_eq(str(sq.mind.data.get("phase", "")), "wait", "espera")
	for s: Soldier in sq.soldiers:
		assert_lt(s.pos.x, 120.0, "no cruza sin humo")
