extends TestBase
## Tests de las técnicas de movimiento: simple, con vigilancia, saltos alternados y sucesivos.

const N: int = 96
const O := SquadMind.Option
const T := SquadMind.Technique


func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 4 # un tanque rojo lejos, para que no termine la partida
	world.units[4].pos = Vector2(5, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	world.set_micro(MicroCover.new(N))
	return world


func _moving(world: SimWorld) -> Unit:
	var sq: Unit = world.add_unit(0, Vector2(48, 88), Unit.Kind.INFANTRY)
	world.order_move(sq.id, Vector2i(48, 50))
	world.begin_execute()
	return sq


func test_travel_without_contacts() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _moving(world)
	for i: int in 30:
		world.step()
	assert_eq(sq.mind.technique, T.TRAVEL, "sin contactos: simple")
	assert_eq(sq.trail_m, 0.0, "todos juntos")


func test_overwatch_when_contact_possible() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _moving(world)
	sq.mind.learn(4, Vector2(48, -20) * Config.CELL_SIZE, 1000000, true) # a ~430 m
	for i: int in 150:
		world.step()
	assert_eq(sq.mind.technique, T.OVERWATCH, "contacto posible: con vigilancia")
	assert_eq(sq.trail_m, Config.OVERWATCH_TRAIL_M, "el equipo A va detrás")
	var gap: float = (sq.slot_pos_m(0) - sq.slot_pos_m(1)).dot(sq.heading)
	assert_lt(Config.OVERWATCH_TRAIL_M, gap, "la ametralladora va bien atrás del jefe")


func test_alternate_bounds_without_fire() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _moving(world)
	sq.mind.learn(4, Vector2(48, 30) * Config.CELL_SIZE, 1000000, true) # a ~230 m
	sq.mind.reacted[4] = true
	sq.mind.drill_end_tick = world.total_ticks
	world.mind_think_now(sq)
	assert_eq(sq.mind.option, O.BOUND, "contacto esperado: saltos")
	assert_true(sq.soldiers[1].hold_pos, "primero salta B, A cubre")
	var switched: bool = false
	for i: int in 600:
		world.step()
		if sq.soldiers[0].hold_pos and not sq.soldiers[1].hold_pos:
			switched = true
			break
	assert_true(switched, "después salta A y B queda de base")
	assert_true(sq.mind.bound_alternate, "alternados")
	assert_eq(sq.mind.technique, T.BOUNDING, "técnica: por saltos")


func test_successive_bounds_under_fire() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _moving(world)
	sq.mind.learn(4, Vector2(48, 30) * Config.CELL_SIZE, 1000000, true)
	sq.mind.reacted[4] = true
	sq.mind.drill_end_tick = world.total_ticks
	world.mind_think_now(sq)
	var caught_up: bool = false
	for i: int in 600:
		sq.last_fired_upon_tick = world.total_ticks
		world.step()
		if str(sq.mind.data.get("phase", "")) == "A":
			caught_up = true
			break
	assert_true(caught_up, "bajo fuego: el que saltó espera que el otro lo alcance")
	assert_true(not sq.mind.bound_alternate, "sucesivos")
