extends TestBase
## Tests de las condiciones de la cadena de órdenes: tiempo, contacto, señales y esperar a otra unidad.

const N: int = 96


## Mundo llano sin IA; azules 0 y 1 al sur, rojo 4 lejos y sin recarga.
func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 0 or u.id == 1 or u.id == 4
	world.units[0].pos = Vector2(40, 90)
	world.units[1].pos = Vector2(56, 90)
	world.units[4].pos = Vector2(48, 2) # a 88 celdas: fuera de alcance
	world.units[4].reload_left = 1000.0
	world.update_detection()
	return world


func _steps(world: SimWorld, n: int) -> void:
	for i: int in n:
		world.step()


func test_time_gate_waits() -> void:
	var world: SimWorld = _world()
	var u: Unit = world.units[0]
	world.order_move(0, Vector2i(40, 80))
	assert_true(world.gate_leg(0, 0, SimWorld.gate_time(10.0)), "condición aceptada")
	world.begin_execute()
	_steps(world, 99)
	assert_eq(u.pos, Vector2(40, 90), "no se movió antes de los 10 s")
	assert_true(u.waiting and not u.moving, "espera quieto")
	_steps(world, 20)
	assert_true(u.pos.y < 90.0, "arrancó a los 10 s")
	assert_true(not u.waiting, "ya no espera")


func test_gate_on_second_leg_waits_at_waypoint() -> void:
	var world: SimWorld = _world()
	var u: Unit = world.units[0]
	world.order_move(0, Vector2i(40, 86))
	world.order_move(0, Vector2i(40, 80), Vector2.ZERO, true, true)
	assert_true(world.gate_leg(0, -1, SimWorld.gate_time(20.0)), "condición en el segundo tramo")
	world.begin_execute()
	_steps(world, 150)
	assert_eq(u.cell(), Vector2i(40, 86), "espera en el punto de paso")
	assert_true(u.waiting, "esperando")
	_steps(world, 100)
	assert_eq(u.cell(), Vector2i(40, 80), "siguió después de los 20 s")


func test_signal_go_code() -> void:
	var world: SimWorld = _world()
	var a: Unit = world.units[0]
	var b: Unit = world.units[1]
	world.order_move(0, Vector2i(40, 84))
	assert_true(world.signal_leg(0, -1, "ALFA"), "el tramo emite ALFA")
	world.order_move(1, Vector2i(56, 84))
	world.gate_leg(1, 0, SimWorld.gate_signal("ALFA"))
	world.begin_execute()
	var b_started_tick: int = -1
	var a_arrived_tick: int = -1
	for i: int in 200:
		world.step()
		if a_arrived_tick < 0 and a.path.is_empty():
			a_arrived_tick = world.tick_in_turn
		if b_started_tick < 0 and b.pos.y < 90.0:
			b_started_tick = world.tick_in_turn
	assert_true(a_arrived_tick > 0 and b_started_tick > 0, "los dos se movieron")
	assert_true(b_started_tick >= a_arrived_tick, "B arrancó cuando A llegó (%d >= %d)" % [b_started_tick, a_arrived_tick])
	assert_true(world.signals[0].has("ALFA"), "la señal quedó emitida")


func test_wait_for_other_unit() -> void:
	var world: SimWorld = _world()
	var a: Unit = world.units[0]
	var b: Unit = world.units[1]
	world.order_move(0, Vector2i(40, 84))
	world.order_move(1, Vector2i(56, 84))
	world.gate_leg(1, 0, SimWorld.gate_unit(0))
	world.begin_execute()
	_steps(world, 10)
	assert_eq(b.pos, Vector2(56, 90), "B espera mientras A se mueve")
	_steps(world, 150)
	assert_true(a.path.is_empty() and b.path.is_empty(), "los dos llegaron")


func test_contact_gate() -> void:
	var world: SimWorld = _world()
	var u: Unit = world.units[0]
	world.order_move(0, Vector2i(40, 80))
	world.gate_leg(0, 0, SimWorld.gate_contact())
	world.begin_execute()
	_steps(world, 20)
	assert_eq(u.pos, Vector2(40, 90), "sin contacto no arranca")
	var red: Unit = world.units[4]
	red.pos = Vector2(48, 70) # entra en alcance y se mueve: lo ven
	red.path = [Vector2i(48, 71), Vector2i(48, 72)]
	red.moving = true
	_steps(world, 15)
	assert_true(u.pos.y < 90.0, "con contacto arranca")


func test_new_order_clears_gates() -> void:
	var world: SimWorld = _world()
	world.order_move(0, Vector2i(40, 80))
	world.gate_leg(0, 0, SimWorld.gate_time(25.0))
	world.order_move(0, Vector2i(44, 80))
	assert_true(not world.units[0].waypoints[0].has("gate"), "la orden nueva no hereda la condición")


func test_gate_needs_a_leg() -> void:
	var world: SimWorld = _world()
	assert_true(not world.gate_leg(0, 0, SimWorld.gate_time(5.0)), "sin ruta no hay tramo")
