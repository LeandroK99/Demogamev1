extends TestBase
## Tests de los pozos de tirador y de consolidar al tomar una posición.

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


func test_still_squad_digs_in() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 60), Unit.Kind.INFANTRY)
	world.known_enemies[0][4] = {"cell": Vector2i(48, 20), "last_seen_turn": world.turn}
	world.begin_execute()
	for i: int in roundi(Config.DIG_SECONDS / Config.TICK) + 60:
		world.step()
	var dug: int = 0
	for s: Soldier in sq.soldiers:
		if world.micro.type_at_m(s.pos) == MicroCover.Type.CRATER:
			dug += 1
	assert_lt(5, dug, "casi todos en su pozo (%d)" % dug)
	var s0: Soldier = sq.soldiers[4]
	if world.micro.type_at_m(s0.pos) == MicroCover.Type.CRATER and s0.posture != Soldier.Posture.STAND:
		assert_true(InfantrySim.is_protected_from(world, s0, s0.pos + Vector2(0.0, -150.0)), "el pozo lo protege")


func test_moving_squad_does_not_dig() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	world.order_move(sq.id, Vector2i(48, 20))
	world.begin_execute()
	for i: int in 300:
		world.step()
	for s: Soldier in sq.soldiers:
		assert_lt(s.dig_time, 0.01, "en marcha no cava")


func test_consolidate_shares_ammo() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 60), Unit.Kind.INFANTRY)
	sq.soldiers[4].ammo = 0
	sq.soldiers[5].ammo = 100
	sq.soldiers[7].state = Soldier.State.DEAD
	sq.soldiers[7].ammo = 80
	world.inf.consolidate(world, sq)
	assert_lt(0, sq.soldiers[4].ammo, "el que no tenía recibe")
	assert_eq(sq.soldiers[7].ammo, 0, "se reparte la del caído")
	assert_eq(str(world.radio_log.back()["text"]), "posición tomada, consolidamos", "lo avisa")


func test_assault_arrival_consolidates() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 70), Unit.Kind.INFANTRY)
	world.order_assault(sq.id, Vector2i(48, 64))
	world.begin_execute()
	for i: int in 400:
		world.step()
	var said: bool = false
	for r: Dictionary in world.radio_log:
		said = said or str(r["text"]) == "posición tomada, consolidamos"
	assert_true(said, "al terminar el asalto, consolida")
