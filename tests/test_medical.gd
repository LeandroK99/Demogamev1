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
