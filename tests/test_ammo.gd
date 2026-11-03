extends TestBase
## Tests de la munición: fuego rápido o sostenido, sin munición no tira, el proveedor pasa cintas.

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


## Escuadra quieta cuya ametralladora bate un punto a 100 m durante secs segundos.
func _mg_fires(pace: int, secs: float) -> Soldier:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 60), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.STRICT
	sq.pace = pace
	world.begin_execute()
	var mg: Soldier = sq.soldiers[1]
	for i: int in roundi(secs / Config.TICK):
		mg.suppress_m = Vector2(48, 35) * Config.CELL_SIZE
		world.step()
	return mg


func test_full_ammo_by_role() -> void:
	var sq: Unit = Unit.new(0, 0, Vector2(10, 10), Unit.Kind.INFANTRY)
	assert_eq(sq.soldiers[1].ammo, Config.AMMO_MG, "ametralladora: ráfagas")
	assert_eq(sq.soldiers[4].ammo, Config.AMMO_RIFLE, "fusilero: tiros")
	assert_eq(sq.soldiers[2].ammo_carry, Config.AMMO_ASSISTANT_CARRY, "el proveedor carga cintas")
	assert_eq(sq.ammo_fraction(), 1.0, "llena")


func test_rapid_fire_spends_faster() -> void:
	var slow: Soldier = _mg_fires(Unit.Pace.NORMAL, 20.0)
	var fast: Soldier = _mg_fires(Unit.Pace.FAST, 20.0)
	assert_lt(Config.AMMO_MG - slow.ammo, Config.AMMO_MG - fast.ammo, "a fuego rápido gasta más")
	assert_true(slow.ammo < Config.AMMO_MG, "y el sostenido también gasta")


func test_no_ammo_no_fire() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 60), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.STRICT
	var mg: Soldier = sq.soldiers[1]
	mg.ammo = 0
	sq.soldiers[2].ammo_carry = 0
	world.begin_execute()
	for i: int in 50:
		mg.suppress_m = Vector2(48, 35) * Config.CELL_SIZE
		world.step()
	assert_eq(mg.ammo, 0, "sigue vacía")
	assert_lt(mg.last_fire_tick, 0, "no tiró")


func test_low_ammo_conserves() -> void:
	var sq: Unit = Unit.new(0, 0, Vector2(10, 10), Unit.Kind.INFANTRY)
	sq.order = Unit.Order.ASSAULT
	var s: Soldier = sq.soldiers[4]
	assert_eq(InfantrySim.fire_rate_factor(sq, s), Config.FIRE_RAPID_RELOAD, "asalto: fuego rápido")
	s.ammo = 10
	assert_eq(InfantrySim.fire_rate_factor(sq, s), Config.FIRE_CONSERVE_RELOAD, "con poca munición dosifica")


func test_assistant_passes_belts() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 60), Unit.Kind.INFANTRY)
	var mg: Soldier = sq.soldiers[1]
	var ast: Soldier = sq.soldiers[2]
	mg.ammo = 0
	ast.pos = mg.pos + Vector2(2.0, 0.0)
	world.begin_execute()
	for i: int in 31:
		world.inf.update_ammo(world)
		world.total_ticks += 1
	assert_eq(mg.ammo, 4 * Config.AMMO_PASS_PER_SECOND, "4 segundos de pasar cintas")
	assert_eq(ast.ammo_carry, Config.AMMO_ASSISTANT_CARRY - mg.ammo, "salen de lo que carga")


func test_radio_when_running_dry() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 60), Unit.Kind.INFANTRY)
	var mg: Soldier = sq.soldiers[1]
	mg.ammo = 1
	world.inf.spend_ammo(world, sq, mg)
	assert_eq(str(world.radio_log.back()["text"]), "¡ametralladora sin munición!", "lo avisa")
	for s: Soldier in sq.soldiers:
		s.ammo = 0
	world.inf.spend_ammo(world, sq, sq.soldiers[4])
	assert_eq(str(world.radio_log.back()["text"]), "nos queda poca munición", "poca munición")
