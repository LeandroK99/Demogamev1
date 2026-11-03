extends TestBase
## Tests del cruce de una zona de peligro: seguridad del lado cercano, cruza un equipo, después el otro.

const N: int = 96
const O := SquadMind.Option


## Bosque de y = 70 a 85 y de y = 45 a 59; entre medio, un claro de 10 celdas (40 m).
func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 4 # un tanque rojo lejos, para que no termine la partida
	world.units[4].pos = Vector2(5, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	var cm: CoverMap = CoverMap.new(N)
	for y: int in range(40, 86):
		if y >= 60 and y < 70:
			continue
		for x: int in range(30, 66):
			cm.set_type(Vector2i(x, y), CoverMap.Type.FOREST)
	world.set_cover(cm)
	world.set_micro(MicroCover.new(N))
	return world


func _squad(world: SimWorld, contact: bool) -> Unit:
	var sq: Unit = world.add_unit(0, Vector2(48, 72), Unit.Kind.INFANTRY)
	world.order_move(sq.id, Vector2i(48, 50))
	world.begin_execute()
	if contact:
		sq.mind.learn(4, Vector2(48, -40) * Config.CELL_SIZE, 1000000, true) # a ~450 m: contacto posible
	return sq


func test_far_edge_found() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _squad(world, false)
	assert_eq(MindSim.danger_far_edge(world, sq), Vector2i(48, 59), "el borde del bosque de enfrente")


func test_crosses_by_teams() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _squad(world, true)
	var crossed: bool = false
	var a_waited: bool = false
	for i: int in 900:
		world.step()
		if sq.mind.option == O.CROSS and str(sq.mind.data.get("phase", "")) == "B":
			crossed = true
			if sq.soldiers[1].hold_pos and sq.soldiers[1].pos.y > 69.0 * Config.CELL_SIZE:
				a_waited = true # la ametralladora quedó del lado cercano
		if crossed and sq.mind.option == O.FOLLOW:
			break
	assert_true(crossed, "cruza por equipos")
	assert_true(a_waited, "el equipo A se queda de seguridad mientras cruza B")
	assert_eq(sq.mind.option, O.FOLLOW, "después sigue la orden")
	assert_lt(sq.soldiers[1].pos.y, 64.0 * Config.CELL_SIZE, "y A también cruzó (a su lugar en la formación)")


func test_no_contact_crosses_straight() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _squad(world, false)
	for i: int in 300:
		world.step()
		assert_true(sq.mind.option != O.CROSS, "sin contactos posibles, cruza sin más")
