extends TestBase
## Tests de la rendición de una escuadra quebrada y acorralada (fase 59) y del contraataque rojo
## antes de que el atacante se afirme.

const N: int = 96


func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 4
	world.units[4].pos = Vector2(5, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	world.set_micro(MicroCover.new(N))
	return world


func _broken(world: SimWorld, enemy_m: float) -> Unit:
	var sq: Unit = world.add_unit(1, Vector2(48, 48), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.STRICT
	world.begin_execute()
	world._lose_morale(sq, 100.0)
	sq.broken_tick = -1000
	sq.mind.learn(4, sq.pos_m() + Vector2(0.0, enemy_m), 1000000, true)
	return sq


func test_broken_cornered_squad_surrenders() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _broken(world, 30.0)
	assert_true(sq.broken, "quebrada")
	for i: int in 10:
		world.step()
	assert_true(sq.surrendered, "sin ruta y con el enemigo encima: se rinde")
	assert_true(not sq.alive, "fuera de combate")


func test_broken_with_route_or_far_enemy_does_not() -> void:
	var world: SimWorld = _world()
	var far: Unit = _broken(world, 200.0)
	for i: int in 10:
		world.step()
	assert_true(not far.surrendered, "con el enemigo lejos no se rinde")
	var world2: SimWorld = _world()
	var running: Unit = _broken(world2, 30.0)
	world2._forcing = true
	world2._autonomous += 1
	world2.order_move(running.id, Vector2i(48, 80))
	world2._autonomous -= 1
	world2._forcing = false
	for i: int in 10:
		world2.step()
	assert_true(not running.surrendered, "si todavía se puede ir, se va")


func test_fresh_red_counterattacks_before_blue_digs_in() -> void:
	var world: SimWorld = SimWorld.new(1337, null, true, SimWorld.Scenario.LOMA)
	var obj: Vector2i = world.objective_cell()
	var blue: Unit = null
	for u: Unit in world.units:
		if u.side == 0 and u.is_infantry():
			blue = u
			break
	blue.pos = Vector2(obj)
	blue.snap_soldiers()
	world.begin_execute()
	assert_true(not world.ai.roles.is_empty(), "el rojo tiene roles")
	world.ai._monitor_counterattack(world)
	var assaulting: int = 0
	for u: Unit in world.units:
		if u.side == 1 and u.alive and u.order == Unit.Order.ASSAULT:
			assaulting += 1
	assert_lt(1.5, float(assaulting), "con un azul recién llegado, sin pozos: contraatacan varias (%d)" % assaulting)
