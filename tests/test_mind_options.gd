extends TestBase
## Tests de reubicarse a defilade, emboscar y romper el contacto.

const N: int = 96
const O := SquadMind.Option


## Terreno plano con una loma baja (4 m) en la fila 48: tapa lo que está al sur de lo que viene del norte.
func _world(with_ridge: bool = false) -> SimWorld:
	var hf: HeightField = HeightField.new(N)
	if with_ridge:
		for x: int in range(36, 61):
			hf.set_height(Vector2i(x, 48), 4.0)
	var world: SimWorld = SimWorld.new(7, hf, false)
	for u: Unit in world.units:
		u.alive = u.id == 4 # un tanque rojo lejos, para que no termine la partida
	world.units[4].pos = Vector2(5, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	world.set_micro(MicroCover.new(N))
	return world


func _under_fire(world: SimWorld, sq: Unit, from_cell: Vector2i) -> void:
	sq.mind.learn(4, Vector2(from_cell) * Config.CELL_SIZE, world.total_ticks, true)
	sq.last_fired_upon_tick = world.total_ticks


func test_relocates_behind_the_ridge() -> void:
	var world: SimWorld = _world(true)
	var sq: Unit = world.add_unit(0, Vector2(48, 45), Unit.Kind.INFANTRY)
	world.begin_execute()
	world.step()
	_under_fire(world, sq, Vector2i(48, 5))
	world.mind_think_now(sq)
	assert_eq(sq.mind.option, O.RELOCATE, "al descubierto bajo fuego: se reubica")
	assert_true(world.destination(sq).y > 48, "detrás de la loma: %s" % str(world.destination(sq)))
	assert_true(Vector2(world.destination(sq) - Vector2i(48, 45)).length() <= Config.RELOCATE_RADIUS, "cerca")
	for i: int in 300:
		if i % 30 == 0:
			_under_fire(world, sq, Vector2i(48, 5))
		world.step()
	assert_true(sq.cell().y > 48, "llegó")
	assert_eq(sq.mind.option, O.RELOCATE, "y se queda mientras le tiran")


func test_no_relocation_without_better_spot() -> void:
	var world: SimWorld = _world(false)
	var sq: Unit = world.add_unit(0, Vector2(48, 45), Unit.Kind.INFANTRY)
	world.begin_execute()
	world.step()
	_under_fire(world, sq, Vector2i(48, 5))
	world.mind_think_now(sq)
	assert_true(sq.mind.option != O.RELOCATE, "en el llano no hay adónde ir")


func test_ambush_holds_fire_until_close() -> void:
	var world: SimWorld = _world()
	var red: Unit = world.add_unit(1, Vector2(48, 20), Unit.Kind.INFANTRY)
	var blue: Unit = world.add_unit(0, Vector2(48, 70), Unit.Kind.INFANTRY) # 200 m
	world.begin_execute()
	red.mind.learn(blue.id, blue.pos_m(), world.total_ticks, true)
	world.mind_think_now(red)
	assert_eq(red.mind.option, O.AMBUSH, "emboscada")
	assert_eq(red.roe, Unit.Roe.HOLD, "retiene el fuego")
	blue.pos = Vector2(48, 42) # 88 m
	red.mind.learn(blue.id, blue.pos_m(), world.total_ticks, true)
	world.mind_think_now(red)
	assert_eq(red.mind.option, O.FOLLOW, "a 100 m, abre fuego")
	assert_eq(red.roe, Unit.Roe.FREE, "fuego libre otra vez")
	assert_true(world.radio_log.any(func(r: Dictionary) -> bool: return r["text"] == "¡fuego!"), "lo grita")


func test_break_contact_when_decimated() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(1, Vector2(48, 30), Unit.Kind.INFANTRY)
	sq.set_men(4)
	world.begin_execute()
	_under_fire(world, sq, Vector2i(48, 60))
	world.mind_think_now(sq)
	assert_eq(sq.mind.option, O.BREAK_CONTACT, "diezmada bajo fuego: rompe el contacto")
	assert_eq(sq.smoke_charges, Config.INF_SMOKE_CHARGES - 1, "con humo")
	assert_true(not sq.path.is_empty(), "y se repliega")
	assert_eq(sq.order, Unit.Order.WITHDRAW, "en retirada")


func test_normal_autonomy_does_not_break_contact() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 60), Unit.Kind.INFANTRY)
	sq.set_men(4)
	world.begin_execute()
	_under_fire(world, sq, Vector2i(48, 20))
	world.mind_think_now(sq)
	assert_true(sq.mind.option != O.BREAK_CONTACT, "normal: lo decide el jugador")
