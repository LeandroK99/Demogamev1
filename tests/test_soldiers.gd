extends TestBase
## Tests de los soldados: roles, formaciones, marcha en formación, espera de rezagados y bajas.

const N: int = 96


## Llano sin IA: solo los tanques 0 y 4 vivos, lejos y sin disparar.
func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 0 or u.id == 4
	world.units[0].pos = Vector2(5, 90)
	world.units[4].pos = Vector2(90, 2)
	world.units[0].reload_left = 1000.0
	world.units[4].reload_left = 1000.0
	return world


func _run(world: SimWorld, ticks: int) -> void:
	world.begin_execute()
	for i: int in ticks:
		world.step()


func _max_slot_error(sq: Unit) -> float:
	var worst: float = 0.0
	for s: Soldier in sq.soldiers:
		if s.is_ok():
			worst = maxf(worst, s.pos.distance_to(sq.slot_pos_m(s.index)))
	return worst


func test_squad_has_nine_soldiers_with_roles() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(40, 80), Unit.Kind.INFANTRY)
	assert_eq(sq.soldiers.size(), Config.INF_MEN, "9 soldados")
	assert_eq(sq.soldiers[0].role, Soldier.Role.LEADER, "jefe")
	assert_eq(sq.soldiers[1].role, Soldier.Role.MG, "ametralladora")
	assert_eq(sq.soldiers[3].role, Soldier.Role.AT, "antitanque")
	assert_lt(_max_slot_error(sq), 0.01, "arrancan en su lugar")
	# Cuña: el jefe adelante (al norte, rumbo azul) y el resto detrás
	for s: Soldier in sq.soldiers:
		if s.index > 0:
			assert_true(s.pos.y > sq.soldiers[0].pos.y, "detrás del jefe")


func test_formations_shape() -> void:
	var file_off: Vector2 = Unit.formation_offset(4, Unit.Formation.FILE)
	assert_eq(file_off.x, 0.0, "fila: todos en el eje")
	assert_eq(file_off.y, 4.0 * Config.SOLDIER_SPACING, "fila: uno detrás del otro")
	var line_off: Vector2 = Unit.formation_offset(4, Unit.Formation.LINE)
	assert_eq(line_off.y, 0.0, "línea: todos a la par")
	assert_eq(absf(line_off.x), 2.0 * Config.SOLDIER_SPACING, "línea: separados")
	var w1: Vector2 = Unit.formation_offset(1, Unit.Formation.WEDGE)
	var w2: Vector2 = Unit.formation_offset(2, Unit.Formation.WEDGE)
	assert_eq(w1.x, -w2.x, "cuña simétrica")


func test_squad_moves_in_formation() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(40, 80), Unit.Kind.INFANTRY)
	world.order_move(sq.id, Vector2i(40, 60))
	world.begin_execute()
	var worst: float = 0.0
	for i: int in 600:
		world.step()
		worst = maxf(worst, _max_slot_error(sq))
	assert_eq(sq.cell(), Vector2i(40, 60), "llegó")
	assert_lt(worst, Config.SOLDIER_LAG_M + 1.0, "nadie se separa de la formación")
	assert_lt(_max_slot_error(sq), MicroCover.MICRO_M, "todos en su lugar al llegar (en la micro-celda más cercana)")


func test_file_formation_follows_path() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(40, 80), Unit.Kind.INFANTRY)
	world.set_formation(sq.id, Unit.Formation.FILE)
	world.order_move(sq.id, Vector2i(40, 60))
	_run(world, 600)
	for s: Soldier in sq.soldiers:
		assert_lt(absf(s.pos.x - 40.0 * Config.CELL_SIZE), 0.5, "en fila sobre el eje x = 40")


func test_anchor_waits_for_laggard() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(40, 80), Unit.Kind.INFANTRY)
	world.order_move(sq.id, Vector2i(40, 60))
	sq.soldiers[5].pos += Vector2(20.0, 0.0) # rezagado
	var start: Vector2 = sq.pos
	_run(world, 10)
	assert_eq(sq.pos, start, "el ancla espera")
	_run(world, 300)
	assert_true(sq.pos.y < start.y - 1.0, "después sigue")


func test_hits_wound_or_kill_soldiers() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(40, 80), Unit.Kind.INFANTRY)
	for i: int in 4:
		world._damage(sq)
	var wounded: int = 0
	var dead: int = 0
	for s: Soldier in sq.soldiers:
		if s.state == Soldier.State.WOUNDED:
			wounded += 1
		elif s.state == Soldier.State.DEAD:
			dead += 1
	assert_eq(wounded + dead, 4, "4 bajas")
	assert_eq(sq.hp, Config.INF_MEN - 4, "hp = soldados en condiciones")
	assert_true(sq.alive, "sigue viva")


func test_wounded_stay_behind() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(40, 80), Unit.Kind.INFANTRY)
	var s: Soldier = sq.soldiers[4]
	world.damage_soldier(sq, s)
	s.state = Soldier.State.WOUNDED # determinista: herido
	var at: Vector2 = s.pos
	world.order_move(sq.id, Vector2i(40, 60))
	_run(world, 300)
	assert_eq(s.pos, at, "el herido no se mueve")
	assert_true(sq.pos.y < 75.0, "la escuadra sigue sin él")
