extends TestBase
## Tests del sistema médico: sangrado, médico, estabilizar, rescate y evacuación.

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


## Hiere a un soldado (sin el dado: herido seguro).
func _wound(world: SimWorld, sq: Unit, i: int) -> Soldier:
	var s: Soldier = sq.soldiers[i]
	s.state = Soldier.State.WOUNDED
	s.stabilized = false
	s.bleed_left = world.mind_rng.randf_range(Config.BLEED_MIN_SECONDS, Config.BLEED_MAX_SECONDS)
	sq.hp = sq.ok_count()
	return s


func test_wound_bleeds_in_range() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	var wounded: int = 0
	for i: int in 40:
		var s: Soldier = sq.soldiers[i % Config.INF_MEN]
		s.state = Soldier.State.OK
		world.inf.hit_soldier(world, sq, s)
		if s.state == Soldier.State.WOUNDED:
			wounded += 1
			assert_true(s.bleed_left >= Config.BLEED_MIN_SECONDS and s.bleed_left <= Config.BLEED_MAX_SECONDS, "entre 90 y 240 s")
			assert_true(s.is_bleeding(), "se desangra")
	assert_true(wounded > 5, "algunos heridos")


func test_bleeds_out_and_drains_morale() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.STRICT # sin rescates: solo el reloj
	var s: Soldier = _wound(world, sq, 5)
	s.bleed_left = 3.0
	world.begin_execute()
	for i: int in 20:
		world.step()
	assert_lt(sq.morale, 100.0, "la escuadra pierde moral")
	for i: int in 20:
		world.step()
	assert_eq(s.state, Soldier.State.DEAD, "se desangró")
	assert_true(str(world.radio_log.back()["text"]).contains("desangró"), "lo avisa")


func test_stabilized_does_not_bleed() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	var s: Soldier = _wound(world, sq, 5)
	s.stabilized = true
	s.bleed_left = 1.0
	world.begin_execute()
	for i: int in 30:
		world.step()
	assert_eq(s.state, Soldier.State.WOUNDED, "estabilizado, vive")
	assert_eq(sq.morale, 100.0, "sin drenaje")


func test_medic_stabilizes() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	assert_eq(sq.soldiers[Config.MEDIC_INDEX].role, Soldier.Role.MEDIC, "el 9 es el médico")
	var s: Soldier = _wound(world, sq, 5)
	world.begin_execute()
	for i: int in roundi(Config.MEDIC_STABILIZE_SECONDS / Config.TICK) + 200:
		world.step()
	assert_true(s.stabilized, "el médico llega y lo estabiliza en unos 15 s")


func test_buddy_aid_is_slower() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	sq.soldiers[Config.MEDIC_INDEX].state = Soldier.State.DEAD
	var s: Soldier = _wound(world, sq, 5)
	world.begin_execute()
	for i: int in roundi(Config.MEDIC_STABILIZE_SECONDS / Config.TICK) + 60:
		world.step()
	assert_true(not s.stabilized, "sin médico, a los 20 s todavía no")
	for i: int in roundi((Config.BUDDY_STABILIZE_SECONDS - Config.MEDIC_STABILIZE_SECONDS) / Config.TICK) + 20:
		world.step()
	assert_true(s.stabilized, "un compañero lo estabiliza en unos 40 s")


func test_no_care_on_the_move() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	var s: Soldier = _wound(world, sq, 5)
	world.order_move(sq.id, Vector2i(48, 20))
	world.begin_execute()
	for i: int in 250:
		world.step()
	assert_true(not s.stabilized, "en marcha no se atiende")


func test_rescue_drags_exposed_wounded_to_cover() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 50), Unit.Kind.INFANTRY)
	var t: Soldier = _wound(world, sq, 5)
	t.bleed_left = 1000.0
	# Una roca 6 m detrás del herido: ahí lo pueden arrastrar
	var rock: Vector2 = t.pos + Vector2(0.0, 5.0)
	world.micro.set_type(MicroCover.cell_of(rock), MicroCover.Type.ROCK)
	world.micro.set_type(MicroCover.cell_of(rock + Vector2(1.0, 0.0)), MicroCover.Type.ROCK)
	world.begin_execute()
	world.step()
	var threat: Vector2 = Vector2(48, 50) * Config.CELL_SIZE + Vector2(0.0, 150.0) # del sur: la roca queda entre medio
	sq.mind.learn(4, threat, 1000000, true)
	sq.last_fired_upon_tick = world.total_ticks
	assert_true(MindSim.wounded_exposed(world, t, threat), "al descubierto")
	world.mind_think_now(sq)
	assert_eq(sq.mind.option, O.RESCUE, "lo van a buscar")
	assert_eq(world.smoke_clouds.size(), 1, "con humo")
	assert_true(sq.soldiers[1].suppress_m.x >= 0.0, "la ametralladora cubre")
	for i: int in 400:
		if i % 50 == 0:
			sq.last_fired_upon_tick = world.total_ticks
		world.step()
	assert_true(InfantrySim.is_protected_from(world, t, threat), "lo arrastraron detrás de la roca")
	assert_true(sq.mind.option != O.RESCUE, "terminó el rescate")


func test_evacuate_wounded_with_bearer() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 50), Unit.Kind.INFANTRY)
	var t: Soldier = _wound(world, sq, 5)
	assert_eq(world.order_evacuate(sq.id), 1, "evacúa al herido")
	assert_eq(t.state, Soldier.State.EVACUATING, "sale")
	assert_eq(sq.ok_count(), 7, "con un camillero")
	var y: float = t.pos.y
	world.begin_execute()
	for i: int in roundi(Config.EVAC_SECONDS / Config.TICK) + 2:
		world.step()
	assert_lt(y, t.pos.y, "hacia el borde propio (sur)")
	assert_eq(t.state, Soldier.State.EVACUATED, "fuera del campo")
	assert_true(not t.is_bleeding(), "no se desangró")
