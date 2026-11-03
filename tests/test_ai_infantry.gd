extends TestBase
## Tests de la IA roja con infantería.

const N: int = 96


## Llano con IA; el rojo 4 vivo (tanque, lejos) para que la partida siga; el resto muerto.
func _world(cm: CoverMap) -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 0 or u.id == 4
	world.units[0].pos = Vector2(90, 94)
	world.units[4].pos = Vector2(90, 2)
	world.set_cover(cm)
	world.ai = AICommander.new(1)
	return world


func test_squad_takes_cover_facing_forward() -> void:
	var cm: CoverMap = CoverMap.new(N)
	for x: int in range(44, 53):
		cm.set_type(Vector2i(x, 33), CoverMap.Type.WALL)
	var world: SimWorld = _world(cm)
	var sq: Unit = world.add_unit(1, Vector2(48, 30), Unit.Kind.INFANTRY)
	world.known_enemies[1].clear()
	world.start_plan()
	assert_eq(cm.type_at(world.destination(sq)), CoverMap.Type.WALL, "va al muro (%s)" % world.destination(sq))
	assert_eq(sq.max_engage_m, Config.AI_INF_AMBUSH_RANGE, "emboscada: tira de cerca")


func test_squad_suppresses_hidden_infantry() -> void:
	var world: SimWorld = _world(CoverMap.new(N))
	var sq: Unit = world.add_unit(1, Vector2(48, 30), Unit.Kind.INFANTRY)
	var blue: Unit = world.add_unit(0, Vector2(48, 70), Unit.Kind.INFANTRY) # 160 m, no visible
	blue.prone = true
	blue.still_time = 100.0
	world.update_detection()
	world.known_enemies[1][blue.id] = {"cell": blue.cell(), "last_seen_turn": world.turn}
	world.start_plan()
	assert_eq(sq.order, Unit.Order.SUPPRESS, "suprime la última posición conocida")
	assert_eq(sq.suppress_cell, blue.cell(), "en la celda conocida")


func test_weak_squad_withdraws() -> void:
	var hf: HeightField = HeightField.new(N)
	for x: int in range(36, 61):
		hf.set_height(Vector2i(x, 26), 3.0) # loma baja detrás de la escuadra
	var world: SimWorld = SimWorld.new(7, hf, false)
	for u: Unit in world.units:
		u.alive = u.id == 0 or u.id == 4
	world.units[0].pos = Vector2(48, 60)
	world.units[4].pos = Vector2(90, 2)
	world.ai = AICommander.new(1)
	var sq: Unit = world.add_unit(1, Vector2(48, 30), Unit.Kind.INFANTRY)
	sq.set_men(2)
	world.known_enemies[1][0] = {"cell": Vector2i(48, 60), "last_seen_turn": world.turn}
	world.start_plan()
	assert_eq(sq.order, Unit.Order.WITHDRAW, "diezmada se repliega")


func test_loma_ai_runs_turns() -> void:
	var world: SimWorld = SimWorld.new(1337, null, true, SimWorld.Scenario.LOMA)
	for t: int in 3:
		world.begin_execute()
		while world.phase == SimWorld.Phase.EXECUTE and not world.game_over:
			world.step()
	assert_true(world.turn >= 3 or world.game_over, "corre turnos con la IA")
	for u: Unit in world.units:
		if u.side == 1 and u.alive and u.is_infantry():
			assert_true(world.pathfinders[u.kind].is_walkable(u.cell()), "escuadra roja en celda válida")
