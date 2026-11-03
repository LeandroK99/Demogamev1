extends TestBase
## Tests de la IA roja de pelotón en la loma: defensa en profundidad, repliegue, refuerzo y contraataque.

const A := AICommander.Role


func _loma() -> SimWorld:
	return SimWorld.new(11, null, true, SimWorld.Scenario.LOMA)


func _red_by_role(world: SimWorld, role: int) -> Unit:
	for id: int in world.ai.roles:
		if world.ai.roles[id] == role:
			return world.units[id]
	return null


func test_roles_in_depth() -> void:
	var world: SimWorld = _loma()
	var fwd: Unit = _red_by_role(world, A.FORWARD)
	var main: Unit = _red_by_role(world, A.MAIN)
	var res: Unit = _red_by_role(world, A.RESERVE)
	assert_true(fwd != null and main != null and res != null, "tres papeles")
	var obj: Vector2i = world.objective_cell()
	assert_lt(world.ai.anchors[res.id].y, world.ai.anchors[main.id].y, "la reserva más atrás que la principal")
	assert_lt(world.ai.anchors[main.id].y, world.ai.anchors[fwd.id].y + 1, "la principal detrás de la adelantada")
	assert_true(absi(world.ai.anchors[fwd.id].y - obj.y) <= 2, "la adelantada en la cresta")


func test_forward_withdraws_when_decimated() -> void:
	var world: SimWorld = _loma()
	var fwd: Unit = _red_by_role(world, A.FORWARD)
	world.begin_execute()
	fwd.set_men(3)
	world.ai.monitor(world)
	assert_eq(world.ai.roles[fwd.id], A.MAIN, "pasa a la línea principal")
	assert_eq(world.destination(fwd), world.ai.anchors[fwd.id], "y va para allá")
	assert_true(str(world.radio_log.back()["text"]).contains("repliega"), "lo avisa")


func test_reserve_reinforces_squad_in_contact() -> void:
	var world: SimWorld = _loma()
	var main: Unit = _red_by_role(world, A.MAIN)
	var res: Unit = _red_by_role(world, A.RESERVE)
	world.begin_execute()
	main.last_fired_upon_tick = world.total_ticks
	world.ai.monitor(world)
	assert_true(not res.path.is_empty(), "la reserva sale")
	assert_lt(Vector2(world.destination(res) - main.cell()).length(), 6.0, "hacia la escuadra en contacto")
	var dest: Vector2i = world.destination(res)
	world.ai.monitor(world)
	assert_eq(world.destination(res), dest, "una sola vez")


func test_counterattack_on_weak_blue_on_objective() -> void:
	var world: SimWorld = _loma()
	var obj: Vector2i = world.objective_cell()
	var blue: Unit = null
	for u: Unit in world.units:
		if u.side == 0 and u.is_infantry():
			blue = u
			break
	blue.pos = Vector2(obj)
	blue.snap_soldiers()
	blue.set_men(3)
	world.begin_execute()
	world.ai.monitor(world)
	var assaulting: int = 0
	for u: Unit in world.units:
		if u.side == 1 and u.alive and u.order == Unit.Order.ASSAULT:
			assaulting += 1
			assert_eq(world.destination(u), obj, "al objetivo")
	assert_eq(assaulting, 1, "una escuadra contraataca")
