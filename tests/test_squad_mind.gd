extends TestBase
## Tests de la base de la autonomía: elección con histéresis, autonomía, radio y orden guardada.

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


func test_choose_needs_margin() -> void:
	var s: Dictionary = {O.FOLLOW: 1.0, O.CONTACT_DRILL: 1.3}
	assert_eq(SquadMind.choose(O.FOLLOW, 0, s, 500), O.FOLLOW, "1,3 no supera 1 + margen")
	s[O.CONTACT_DRILL] = 1.6
	assert_eq(SquadMind.choose(O.FOLLOW, 0, s, 500), O.CONTACT_DRILL, "1,6 sí")


func test_choose_min_duration() -> void:
	var s: Dictionary = {O.FOLLOW: 3.0, O.CONTACT_DRILL: 1.0}
	assert_eq(SquadMind.choose(O.CONTACT_DRILL, 100, s, 150), O.CONTACT_DRILL, "una decisión dura al menos 10 s")
	assert_eq(SquadMind.choose(O.CONTACT_DRILL, 100, s, 100 + Config.MIND_MIN_TICKS), O.FOLLOW, "pasado el mínimo, cambia")
	s.erase(O.CONTACT_DRILL)
	assert_eq(SquadMind.choose(O.CONTACT_DRILL, 100, s, 150), O.FOLLOW, "si la actual deja de valer, cambia ya")


func test_allowed_by_autonomy() -> void:
	assert_true(not SquadMind.allowed(SquadMind.Autonomy.STRICT, O.CONTACT_DRILL), "estricta: solo la orden")
	assert_true(SquadMind.allowed(SquadMind.Autonomy.NORMAL, O.CONTACT_DRILL), "normal: reacciona")
	assert_true(not SquadMind.allowed(SquadMind.Autonomy.NORMAL, O.FLANK), "normal: no maniobra")
	assert_true(SquadMind.allowed(SquadMind.Autonomy.HIGH, O.FLANK), "alta: maniobra")


func test_default_autonomy() -> void:
	var world: SimWorld = _world()
	var blue: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	var red: Unit = world.add_unit(1, Vector2(48, 20), Unit.Kind.INFANTRY)
	assert_eq(blue.mind.autonomy, SquadMind.Autonomy.NORMAL, "el jugador, normal")
	assert_eq(red.mind.autonomy, SquadMind.Autonomy.HIGH, "la IA roja, alta")
	assert_true(world.add_unit(0, Vector2(30, 80)).mind == null, "los tanques no tienen")


func test_hold_keeps_order_and_resumes() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	world.order_move(sq.id, Vector2i(48, 60))
	world.begin_execute()
	sq.mind.next_think_tick = 1000000 # que no piense: la opción la fija el test
	world.minds.switch_to(world, sq, O.CONTACT_DRILL)
	var y: float = sq.pos.y
	for i: int in 50:
		world.step()
	assert_eq(sq.pos.y, y, "frenada por decisión propia")
	assert_eq(world.radio_log.back()["text"], SquadMind.OPTION_NAMES[O.CONTACT_DRILL], "lo avisa por radio")
	world.minds.switch_to(world, sq, O.FOLLOW)
	for i: int in 50:
		world.step()
	assert_lt(sq.pos.y, y, "retoma la marcha")
	assert_eq(world.destination(sq), Vector2i(48, 60), "con el mismo destino")


func test_reroute_returns_to_player_waypoint() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	world.order_move(sq.id, Vector2i(48, 60))
	world.begin_execute()
	sq.mind.next_think_tick = 1000000
	world.minds.switch_to(world, sq, O.RELOCATE)
	assert_true(world.minds.autonomous_move(world, sq, Vector2i(55, 80)), "se mueve por su cuenta en la ejecución")
	assert_eq(world.destination(sq), Vector2i(55, 80), "va a su lugar")
	assert_eq(sq.mind.option, O.RELOCATE, "su propia orden no la resetea")
	world.minds.switch_to(world, sq, O.FOLLOW)
	assert_eq(world.destination(sq), Vector2i(48, 60), "vuelve al destino del jugador")
	assert_eq(sq.order, Unit.Order.MOVE, "con la orden del jugador")


func test_player_order_resets_mind() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	world.minds.switch_to(world, sq, O.CONTACT_DRILL)
	world.order_move(sq.id, Vector2i(48, 70))
	assert_eq(sq.mind.option, O.FOLLOW, "la orden nueva manda")
	assert_true(not sq.mind.hold, "y no queda frenada")


func test_strict_never_leaves_follow() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.STRICT
	world.begin_execute()
	for i: int in 100:
		world.step()
	assert_eq(sq.mind.option, O.FOLLOW, "estricta")
	assert_true(world.radio_log.is_empty(), "sin radio")
