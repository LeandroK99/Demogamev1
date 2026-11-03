extends TestBase
## Tests del avance bajo fuego: carreras por parejas, humo para cruzar y cuña dispersa.

const N: int = 96
const O := SquadMind.Option


func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 4 # un tanque rojo lejos, para que no termine la partida
	world.units[4].pos = Vector2(5, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	world.set_micro(MicroCover.new(N))
	return world


func _advancing_under_fire(world: SimWorld) -> Unit:
	var sq: Unit = world.add_unit(0, Vector2(48, 88), Unit.Kind.INFANTRY)
	world.order_move(sq.id, Vector2i(48, 50))
	world.begin_execute()
	sq.mind.learn(4, Vector2(48, 30) * Config.CELL_SIZE, 1000000, true) # contacto a 230 m
	sq.mind.reacted[4] = true # ya reaccionó al contacto...
	sq.mind.drill_end_tick = world.total_ticks # ... recién: ahora avanza
	sq.last_fired_upon_tick = world.total_ticks
	return sq


func test_normal_squad_advances_by_fire_and_movement() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _advancing_under_fire(world)
	world.mind_think_now(sq)
	assert_eq(sq.mind.option, O.BOUND, "autonomía normal: fuego y movimiento")
	assert_true(sq.soldiers[1].hold_pos, "la ametralladora cubre")


func test_rushes_alternate_by_pairs() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _advancing_under_fire(world)
	world.mind_think_now(sq)
	var saw_down: bool = false
	var saw_mixed: bool = false
	for i: int in 150:
		if i % 20 == 0:
			sq.last_fired_upon_tick = world.total_ticks
		world.step()
		var down: int = 0
		var up: int = 0
		for s: Soldier in sq.soldiers:
			if s.team == 1 and s.is_ok():
				if s.down_until > world.total_ticks:
					down += 1
				else:
					up += 1
		saw_down = saw_down or down > 0
		saw_mixed = saw_mixed or (down > 0 and up > 0)
	assert_true(sq.mind.rushing, "bajo fuego, a carreras")
	assert_true(saw_down, "se tiran entre carrera y carrera")
	assert_true(saw_mixed, "unos corren mientras otros están tirados")


func test_smoke_covers_the_advance() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _advancing_under_fire(world)
	world.mind_think_now(sq)
	assert_eq(world.smoke_clouds.size(), 1, "humo al arrancar bajo fuego")
	assert_true(not sq.mind.hold, "y cruza")


func test_wedge_disperses() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 88), Unit.Kind.INFANTRY)
	world.order_move(sq.id, Vector2i(48, 60))
	world.begin_execute()
	for i: int in 150:
		world.step()
	var moved: int = 0
	for s: Soldier in sq.soldiers:
		assert_true(s.jitter.length() <= Config.JITTER_M + 0.01, "hasta 3,5 m de su lugar")
		if s.jitter.length() > 0.5:
			moved += 1
	assert_true(moved >= 5, "la mayoría corridos de su lugar (%d)" % moved)
	for a: Soldier in sq.soldiers:
		for b: Soldier in sq.soldiers:
			if a.index < b.index:
				assert_true(sq.slot_pos_m(a.index).distance_to(sq.slot_pos_m(b.index)) >= Config.JITTER_SEPARATION_M - 0.01, "sin amontonarse")
