extends TestBase
## Tests de supresión, moral y la orden de suprimir.

const N: int = 96


## Llano sin IA, sin los tanques del despliegue (salvo el rojo 4, lejos y sin recarga).
func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 4
	world.units[4].pos = Vector2(5, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	return world


func _quiet(u: Unit) -> void:
	u.reload_left = 1000.0
	u.reload2_left = 1000.0


func test_misses_still_suppress() -> void:
	var world: SimWorld = _world()
	var a: Unit = world.add_unit(0, Vector2(48, 60), Unit.Kind.INFANTRY)
	var b: Unit = world.add_unit(1, Vector2(48, 45), Unit.Kind.INFANTRY)
	_quiet(b)
	b.moving = true
	world.update_detection()
	world.begin_execute()
	world.p_hit_max = 0.0 # nunca aciertan
	for i: int in 30:
		b.moving = true
		world.inf.fire_squad(world, a)
		for s: Soldier in a.soldiers:
			s.reload_left = 0.0
	assert_true(b.suppression >= Config.SUPPRESSED, "suprimida (%.0f)" % b.suppression)
	assert_true(b.prone, "cuerpo a tierra")
	assert_eq(b.hp, Config.INF_MEN, "sin bajas")


func test_suppressed_squad_does_not_advance() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	world.order_move(sq.id, Vector2i(48, 60))
	sq.set_suppression(80.0, 0)
	world.begin_execute()
	for i: int in 10:
		world.step()
	assert_eq(sq.pos, Vector2(48, 80), "suprimida no avanza")
	for i: int in 200: # la supresión baja sola
		world.step()
	assert_lt(sq.suppression, Config.SUPPRESSED, "la supresión bajó")
	assert_true(sq.pos.y < 80.0, "y siguió avanzando")


func test_casualties_break_morale_and_squad_withdraws() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 60), Unit.Kind.INFANTRY)
	world.known_enemies[0][4] = {"cell": Vector2i(48, 30), "last_seen_turn": world.turn}
	world.units[4].pos = Vector2(48, 30)
	for i: int in 6:
		world._damage(sq)
	assert_true(sq.morale < Config.MORALE_BREAK + 30.0, "moral baja (%.0f)" % sq.morale)
	sq.morale = 10.0
	world._lose_morale(sq, 1.0)
	assert_true(sq.broken, "quebrada")
	world.start_plan()
	assert_eq(sq.order, Unit.Order.WITHDRAW, "se retira sola")
	assert_true(not world.order_move(sq.id, Vector2i(48, 40)), "no acepta órdenes")


func test_morale_recovers_and_rallies() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 60), Unit.Kind.INFANTRY)
	sq.morale = 20.0
	sq.broken = true
	world._end_turn()
	world._end_turn()
	assert_true(sq.morale >= Config.MORALE_RALLY, "recupera moral (%.0f)" % sq.morale)
	assert_true(not sq.broken, "se rehace")


func test_suppress_area_without_visible_target() -> void:
	var world: SimWorld = _world()
	var tank: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.TANK)
	var hidden: Unit = world.add_unit(1, Vector2(48, 40), Unit.Kind.INFANTRY) # 160 m, cuerpo a tierra: no se la ve
	_quiet(hidden)
	hidden.prone = true
	hidden.still_time = 100.0
	world.update_detection()
	assert_true(not world.visible_enemies[0].has(hidden.id), "no se la ve")
	assert_true(world.order_suppress(tank.id, Vector2i(49, 41)), "orden de suprimir aceptada")
	world.begin_execute()
	for i: int in 60:
		world.step()
	assert_true(hidden.suppression >= Config.SUPPRESSED, "la zona batida la suprime (%.0f)" % hidden.suppression)
	var area_shots: int = 0
	for e: Dictionary in world.shot_events:
		if int(e["target"]) < 0:
			area_shots += 1
	assert_true(area_shots > 1, "tiró a la zona")


func test_pinned_squad_does_not_fire() -> void:
	var world: SimWorld = _world()
	var a: Unit = world.add_unit(0, Vector2(48, 60), Unit.Kind.INFANTRY)
	var b: Unit = world.add_unit(1, Vector2(48, 50), Unit.Kind.INFANTRY)
	_quiet(b)
	b.moving = true
	a.set_suppression(95.0, 0)
	world.update_detection()
	world.begin_execute()
	world.step()
	assert_eq(world.shot_events.size(), 0, "inmovilizada: no tira")


func test_buttoned_tank_sees_less() -> void:
	var world: SimWorld = _world()
	var tank: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.TANK)
	var red: Unit = world.units[4]
	red.pos = Vector2(48, 30) # 200 m, quieto con casco visible: se lo ve hasta 220 m
	world.update_detection()
	assert_true(world.visible_enemies[0].has(4), "lo ve")
	tank.suppression = 60.0
	world.update_detection()
	assert_true(not world.visible_enemies[0].has(4), "abotonado no lo ve")


func test_gate_suppressed() -> void:
	var world: SimWorld = _world()
	var a: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	var enemy: Unit = world.add_unit(1, Vector2(48, 40), Unit.Kind.INFANTRY)
	_quiet(enemy)
	world.order_move(a.id, Vector2i(48, 70))
	world.gate_leg(a.id, 0, SimWorld.gate_suppressed(enemy.id))
	world.begin_execute()
	world.step()
	assert_true(a.waiting, "espera a que el enemigo esté suprimido")
	enemy.set_suppression(70.0, world.total_ticks)
	world.step()
	assert_true(not a.waiting, "arranca")
