extends TestBase
## Tests de los reflejos del soldado: al suelo bajo fuego, cubierta inválida, asomar y tirar, humo propio.

const N: int = 96


func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 4 # un tanque rojo lejos, para que no termine la partida
	world.units[4].pos = Vector2(5, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	world.set_micro(MicroCover.new(N))
	return world


func test_dive_under_fire_while_moving() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	world.order_move(sq.id, Vector2i(48, 60))
	world.begin_execute()
	for i: int in 10:
		world.step()
	var s: Soldier = sq.soldiers[0]
	world.inf.suppress_at(world, 0, s.pos, s.pos + Vector2(0.0, -150.0), Unit.Weapon.MG, false)
	var at: Vector2 = s.pos
	for i: int in 5:
		world.step()
	assert_eq(s.pos, at, "se tiró al suelo y no se mueve")
	assert_eq(s.posture, Soldier.Posture.PRONE, "cuerpo a tierra")
	for i: int in 30:
		world.step()
	assert_true(s.pos != at, "pasado el reflejo, sigue")


func test_flanked_cover_is_rechosen() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 50), Unit.Kind.INFANTRY)
	world.known_enemies[0][4] = {"cell": Vector2i(48, 20), "last_seen_turn": world.turn}
	world.begin_execute()
	world.step()
	var s: Soldier = sq.soldiers[3]
	assert_true(s.has_cover, "eligió cobertura")
	var from: Vector2 = s.pos + Vector2(80.0, 0.0)
	world.inf.suppress_at(world, 0, s.pos, from, Unit.Weapon.RIFLES, false)
	world.step()
	assert_eq(s.cover_threat, from, "le tiran de costado: se cubre contra ese tirador")


func test_peek_cycle() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 50), Unit.Kind.INFANTRY)
	world.known_enemies[0][4] = {"cell": Vector2i(48, 20), "last_seen_turn": world.turn}
	world.begin_execute()
	world.step()
	var s: Soldier = sq.soldiers[0]
	s.can_fire = false
	s.has_fire_pos = true
	s.fire_pos = s.cover_pos + Vector2(2.0, 0.0)
	s.fire_posture = Soldier.Posture.CROUCH
	s.peek_tick = world.total_ticks
	for i: int in 20:
		world.step()
	assert_true(s.peeking, "se asoma")
	assert_lt(s.pos.distance_to(s.fire_pos), 0.5, "en el punto de tiro")
	assert_eq(s.posture, Soldier.Posture.CROUCH, "con la postura de ese punto")
	for i: int in roundi(Config.REFLEX_PEEK_FIRE_SECONDS / Config.TICK) + 20:
		world.step()
	assert_true(not s.peeking, "vuelve a cubierto")
	assert_lt(s.pos.distance_to(s.cover_pos), 0.5, "a su cobertura")


func test_suppressed_soldier_does_not_peek() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 50), Unit.Kind.INFANTRY)
	world.known_enemies[0][4] = {"cell": Vector2i(48, 20), "last_seen_turn": world.turn}
	world.begin_execute()
	world.step()
	var s: Soldier = sq.soldiers[0]
	s.has_fire_pos = true
	s.fire_pos = s.cover_pos + Vector2(2.0, 0.0)
	s.peek_tick = world.total_ticks
	s.suppression = 70.0
	s.last_suppressed_tick = 1000000
	for i: int in 10:
		world.step()
	assert_true(not s.peeking, "suprimido, no asoma")


func _pin(world: SimWorld, sq: Unit) -> void:
	world.known_enemies[0][4] = {"cell": Vector2i(48, 20), "last_seen_turn": world.turn}
	sq.set_suppression(90.0, 1000000) # clavada; no baja durante el test
	world.begin_execute()


func test_smoke_after_15s_pinned() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 50), Unit.Kind.INFANTRY)
	_pin(world, sq)
	for i: int in roundi(Config.INF_SMOKE_SUPPRESSED_SECONDS / Config.TICK) - 5:
		world.step()
	assert_true(world.smoke_clouds.is_empty(), "todavía no")
	for i: int in 10:
		world.step()
	assert_eq(world.smoke_clouds.size(), 1, "tira humo")
	assert_eq(sq.smoke_charges, Config.INF_SMOKE_CHARGES - 1, "gasta una granada")
	var c: Vector2 = world.smoke_clouds[0]["center"]
	assert_lt(c.y, sq.pos.y, "hacia la amenaza")
	assert_true(str(world.radio_log.back()["text"]).begins_with("humo"), "lo avisa")


func test_hand_smoke_expires() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 50), Unit.Kind.INFANTRY)
	assert_true(world.hand_smoke(sq, sq.pos_m() + Vector2(0.0, -15.0)), "tira")
	world.begin_execute()
	for i: int in roundi(Config.INF_SMOKE_SECONDS / Config.TICK) + 1:
		world.step()
	assert_true(world.smoke_clouds.is_empty(), "se va sola")


func test_strict_squad_does_not_smoke() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 50), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.STRICT
	_pin(world, sq)
	for i: int in 200:
		world.step()
	assert_true(world.smoke_clouds.is_empty(), "estricta: no")
