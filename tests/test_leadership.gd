extends TestBase
## Tests del mando: calidad del jefe, desorganización al caer y el segundo que toma el mando.

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


func test_think_interval_by_quality() -> void:
	var m: SquadMind = SquadMind.new()
	m.quality = SquadMind.Quality.VETERAN
	var vet: int = m.think_ticks()
	m.quality = SquadMind.Quality.GREEN
	assert_lt(vet, m.think_ticks(), "el veterano piensa más seguido")


func test_green_leader_scores_with_noise() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	world.order_move(sq.id, Vector2i(48, 60))
	world.begin_execute()
	sq.mind.next_think_tick = 1000000
	sq.mind.autonomy = SquadMind.Autonomy.NORMAL
	sq.last_fired_upon_tick = 1000000 # contacto constante
	sq.mind.quality = SquadMind.Quality.VETERAN
	world.minds.think(world, sq)
	assert_eq(float(sq.mind.scores[O.CONTACT_DRILL]), Config.DRILL_SCORE, "veterano: sin error")
	sq.mind.reset(0)
	sq.mind.quality = SquadMind.Quality.GREEN
	world.minds.think(world, sq)
	var a: float = float(sq.mind.scores.get(O.CONTACT_DRILL, Config.DRILL_SCORE))
	assert_true(absf(a - Config.DRILL_SCORE) <= Config.MIND_NOISE_GREEN, "novato: con error acotado")


func test_leader_loss_disorganizes_then_second_takes_over() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 85), Unit.Kind.INFANTRY)
	world.order_move(sq.id, Vector2i(48, 50))
	world.begin_execute()
	for i: int in 10:
		world.step()
	world.damage_soldier(sq, sq.soldiers[0])
	assert_true(sq.mind.is_disorganized(world.total_ticks), "desorganizada")
	assert_eq(world.radio_log.back()["text"], "¡cayó el jefe!", "lo avisa")
	var y: float = sq.pos.y
	for i: int in roundi(Config.LEADERLESS_MIN_SECONDS / Config.TICK) - 5:
		world.step()
	assert_eq(sq.pos.y, y, "no avanza sin jefe")
	for i: int in roundi((Config.LEADERLESS_MAX_SECONDS - Config.LEADERLESS_MIN_SECONDS) / Config.TICK) + 60:
		world.step()
	assert_lt(sq.pos.y, y, "con el nuevo jefe sigue")
	var leaders: int = 0
	for s: Soldier in sq.soldiers:
		if s.is_ok() and s.role == Soldier.Role.LEADER:
			leaders += 1
	assert_eq(leaders, 1, "hay un jefe nuevo")
	assert_eq(sq.mind.quality, SquadMind.Quality.GREEN, "que manda peor")
