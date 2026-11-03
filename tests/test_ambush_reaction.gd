extends TestBase
## Tests de la reacción a una emboscada: cercana (asalto inmediato) y lejana (fuego y después maniobra).

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


## Escuadra azul en marcha hacia el norte y una roja a dist_cells al norte que le acaba de tirar.
func _ambushed(world: SimWorld, dist_cells: int) -> Array[Unit]:
	var blue: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	var red: Unit = world.add_unit(1, Vector2(48, 80 - dist_cells), Unit.Kind.INFANTRY)
	red.mind.autonomy = SquadMind.Autonomy.STRICT
	red.roe = Unit.Roe.HOLD # que no tire en el test: solo cuenta el primer fuego
	world.order_move(blue.id, Vector2i(48, 40))
	world.begin_execute()
	world.step()
	blue.mind.learn(red.id, red.pos_m(), world.total_ticks, true)
	blue.last_fired_upon_tick = world.total_ticks
	world.mind_think_now(blue)
	return [blue, red]


func test_near_ambush_assaults() -> void:
	var world: SimWorld = _world()
	var pair: Array[Unit] = _ambushed(world, 5) # 20 m
	var blue: Unit = pair[0]
	assert_eq(blue.mind.option, O.NEAR_AMBUSH, "a 20 m: asalta")
	assert_eq(blue.order, Unit.Order.ASSAULT, "a la carrera")
	assert_eq(world.destination(blue), pair[1].cell(), "hacia el emboscador")
	assert_true(not blue.mind.hold, "sin frenar")
	assert_true(str(world.radio_log.back()["text"]).contains("al asalto"), "lo grita")


func test_far_ambush_returns_fire_then_maneuvers() -> void:
	var world: SimWorld = _world()
	var pair: Array[Unit] = _ambushed(world, 38) # 150 m
	var blue: Unit = pair[0]
	assert_eq(blue.mind.option, O.CONTACT_DRILL, "a 150 m: a cubierto y fuego")
	var bound: bool = false
	for i: int in 200:
		world.step()
		if blue.mind.option == O.BOUND:
			bound = true
			break
	assert_true(bound, "después avanza por fuego y movimiento")


func test_defender_does_not_assault() -> void:
	var world: SimWorld = _world()
	var blue: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	var red: Unit = world.add_unit(1, Vector2(48, 75), Unit.Kind.INFANTRY)
	red.roe = Unit.Roe.HOLD
	world.begin_execute()
	world.step()
	blue.mind.learn(red.id, red.pos_m(), world.total_ticks, true)
	blue.last_fired_upon_tick = world.total_ticks
	world.mind_think_now(blue)
	assert_true(blue.mind.option != O.NEAR_AMBUSH, "quieta en su puesto: no sale a asaltar")


func test_assault_ends_on_the_position_and_resumes() -> void:
	var world: SimWorld = _world()
	var pair: Array[Unit] = _ambushed(world, 5)
	var blue: Unit = pair[0]
	pair[1].alive = false # el emboscador cae
	for i: int in 30:
		world.step()
	assert_eq(blue.mind.option, O.FOLLOW, "retoma la orden")
	assert_eq(world.destination(blue), Vector2i(48, 40), "con su destino")
