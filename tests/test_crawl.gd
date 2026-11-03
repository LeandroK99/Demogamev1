extends TestBase
## Tests de reptar: lento, cuerpo a tierra, no se lo ve como en marcha; la clavada sigue reptando.

const N: int = 96


func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 4 # un tanque rojo lejos, para que no termine la partida
	world.units[4].pos = Vector2(5, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	world.set_micro(MicroCover.new(N))
	return world


func test_crawl_pace_is_slow_and_prone() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	assert_true(world.set_pace(sq.id, Unit.Pace.CRAWL), "ritmo reptar")
	world.order_move(sq.id, Vector2i(48, 60))
	world.begin_execute()
	var y0: float = sq.pos_m().y
	for i: int in 100:
		world.step()
	var moved: float = y0 - sq.pos_m().y
	assert_lt(moved, 4.0, "a 0,3 m/s: unos 3 m en 10 s (%.1f)" % moved)
	assert_lt(0.8, moved, "pero avanza")
	var s: Soldier = sq.soldiers[4]
	assert_eq(s.posture, Soldier.Posture.PRONE, "cuerpo a tierra")
	assert_eq(InfantrySim.soldier_spot_range(world, sq, s), Config.INF_SPOT_PRONE, "se lo detecta como quieto y cuerpo a tierra")


func test_tanks_do_not_crawl() -> void:
	var world: SimWorld = _world()
	var tank: Unit = world.add_unit(0, Vector2(30, 80))
	world.set_pace(tank.id, Unit.Pace.CRAWL)
	assert_eq(tank.pace, Unit.Pace.NORMAL, "el tanque no repta")


func test_pinned_squad_keeps_crawling() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	world.order_move(sq.id, Vector2i(48, 40))
	world.begin_execute()
	sq.mind.next_think_tick = 1000000 # que no elija otra cosa: solo el reflejo
	sq.set_suppression(90.0, 1000000)
	var y0: float = sq.pos_m().y
	for i: int in roundi(Config.CRAWL_AFTER_SECONDS / Config.TICK) - 5:
		world.step()
	assert_true(not sq.mind.crawling, "primero, al suelo")
	assert_lt(absf(sq.pos_m().y - y0), 0.5, "quieta")
	for i: int in 150:
		world.step()
	assert_true(sq.mind.crawling, "después repta")
	assert_lt(sq.pos_m().y, y0 - 1.5, "y se sigue acercando")
	assert_eq(SimWorld.effective_pace(sq), Unit.Pace.CRAWL, "reptando")


func test_strict_squad_stays_pinned() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.STRICT
	world.order_move(sq.id, Vector2i(48, 40))
	world.begin_execute()
	sq.set_suppression(90.0, 1000000)
	for i: int in 100:
		world.step()
	assert_true(not sq.mind.crawling, "estricta: se queda clavada")
