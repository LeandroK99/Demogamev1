extends TestBase
## Tests de los equipos de fuego: avanzar por saltos y flanquear.

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


func test_teams() -> void:
	var a: Array[int] = []
	for i: int in Config.INF_MEN:
		if Soldier.team_of(i) == 0:
			a.append(i)
	assert_eq(a, [1, 2, 4, 6] as Array[int], "A: ametralladora, 2, 4 y 6")


func test_bounding_advance() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 85), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.HIGH
	world.order_move(sq.id, Vector2i(48, 60))
	world.begin_execute()
	sq.mind.learn(4, Vector2(48, 30) * Config.CELL_SIZE, 0, true) # contacto a 220 m
	sq.mind.contacts[4]["tick"] = 1000000 # que no lo olvide
	world.mind_think_now(sq)
	assert_eq(sq.mind.option, O.BOUND, "avanza por saltos")
	var mg: Soldier = sq.soldiers[1]
	var mg_at: Vector2 = mg.pos
	var start: Vector2 = sq.pos_m()
	var moved: bool = false
	for i: int in 250:
		world.step()
		if not moved and sq.pos_m().distance_to(start) >= Config.BOUND_M - 0.5:
			moved = true
			assert_lt(mg.pos.distance_to(mg_at), 1.0, "la base de fuego se quedó mientras B saltó")
	assert_true(moved, "B saltó 25 m")
	for i: int in 1200:
		world.step()
		if sq.path.is_empty():
			break
	assert_eq(sq.cell(), Vector2i(48, 60), "llegó por saltos")
	world.step()
	world.mind_think_now(sq)
	assert_eq(sq.mind.option, O.FOLLOW, "y vuelve a la orden")
	assert_true(not mg.hold_pos, "nadie queda clavado")


func test_flank_when_another_squad_fixes() -> void:
	var world: SimWorld = _world()
	var base: Unit = world.add_unit(0, Vector2(48, 70), Unit.Kind.INFANTRY)
	var sq: Unit = world.add_unit(0, Vector2(30, 75), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.HIGH
	world.order_move(sq.id, Vector2i(30, 55)) # flanquea la que avanza
	world.begin_execute()
	var contact: Vector2 = Vector2(48, 40) * Config.CELL_SIZE
	sq.mind.learn(4, contact, world.total_ticks, true)
	sq.mind.reacted[4] = true # ya hizo el drill por este contacto
	base.last_fire_tick = world.total_ticks
	world.mind_think_now(sq)
	assert_eq(sq.mind.option, O.FLANK, "flanquea")
	var dest: Vector2 = Vector2(world.destination(sq)) * Config.CELL_SIZE
	assert_true(absf(dest.x - contact.x) > Config.FLANK_OFFSET_M * 0.8, "al costado del contacto: %s" % str(dest))
	assert_true(dest.x < contact.x, "del lado de la escuadra")


func test_no_flank_without_base_of_fire() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(30, 75), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.HIGH
	world.begin_execute()
	sq.mind.learn(4, Vector2(48, 40) * Config.CELL_SIZE, world.total_ticks, true)
	world.mind_think_now(sq)
	assert_true(sq.mind.option != O.FLANK, "sola no flanquea")


func test_player_order_releases_teams() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 85), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.HIGH
	world.order_move(sq.id, Vector2i(48, 60))
	world.begin_execute()
	sq.mind.learn(4, Vector2(48, 30) * Config.CELL_SIZE, 1000000, true)
	world.mind_think_now(sq)
	world.step()
	assert_true(sq.soldiers[1].hold_pos, "A de base de fuego")
	world.phase = SimWorld.Phase.PLAN
	world.order_move(sq.id, Vector2i(40, 85))
	assert_true(not sq.soldiers[1].hold_pos, "la orden nueva los suelta")
