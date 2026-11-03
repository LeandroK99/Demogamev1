extends TestBase
## Tests de las armas cruzadas: coaxial, fusiles, antitanque y bajas por hombre.

const N: int = 96


## Llano sin IA: solo el tanque azul 0 vivo (en 48, 60) y el rojo 4 vivo pero lejos y sin recarga.
func _world(sim_seed: int = 7) -> SimWorld:
	var world: SimWorld = SimWorld.new(sim_seed, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 0 or u.id == 4
	world.units[0].pos = Vector2(48, 60)
	world.units[4].pos = Vector2(5, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	return world


func _shots(world: SimWorld, shooter: int, weapon: int) -> int:
	var n: int = 0
	for e: Dictionary in world.shot_events:
		if int(e["shooter"]) == shooter and int(e["weapon"]) == weapon:
			n += 1
	return n


func _run(world: SimWorld, ticks: int) -> void:
	world.update_detection()
	world.begin_execute()
	for i: int in ticks:
		world.step()


func test_tank_uses_coax_on_infantry() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(1, Vector2(48, 50), Unit.Kind.INFANTRY) # 40 m: se la ve aun cuerpo a tierra
	sq.reload_left = 1000.0
	sq.reload2_left = 1000.0
	_run(world, 300)
	assert_eq(_shots(world, 0, Unit.Weapon.CANNON), 0, "no gasta el cañón en infantería")
	assert_true(_shots(world, 0, Unit.Weapon.COAX) > 1, "tira con la coaxial")
	assert_lt(sq.hp, Config.INF_MEN, "bajas")


func test_rifles_do_not_hurt_tanks() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(1, Vector2(48, 20), Unit.Kind.INFANTRY) # 160 m: fuera del antitanque
	world.units[0].reload_left = 1000.0
	world.units[0].reload2_left = 1000.0
	world.units[0].moving = true
	_run(world, 100)
	assert_eq(_shots(world, sq.id, Unit.Weapon.RIFLES), 0, "los fusiles no tiran al tanque")
	assert_eq(_shots(world, sq.id, Unit.Weapon.AT), 0, "a 160 m el antitanque no tira")
	assert_eq(world.units[0].hp, Config.TANK_HP, "el tanque intacto")


func test_at_in_range_spends_charges() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(1, Vector2(48, 30), Unit.Kind.INFANTRY) # 120 m
	world.units[0].reload_left = 1000.0
	world.units[0].reload2_left = 1000.0
	world.units[0].moving = true
	_run(world, 300)
	assert_eq(_shots(world, sq.id, Unit.Weapon.AT), Config.INF_AT_CHARGES, "tiró todas sus cargas")
	assert_eq(sq.at_charges, 0, "sin cargas")


func test_infantry_firefight_both_sides_bleed() -> void:
	var world: SimWorld = _world()
	world.units[0].alive = false
	var a: Unit = world.add_unit(0, Vector2(48, 60), Unit.Kind.INFANTRY)
	var b: Unit = world.add_unit(1, Vector2(48, 50), Unit.Kind.INFANTRY) # 40 m
	_run(world, 300)
	assert_true(_shots(world, a.id, Unit.Weapon.RIFLES) > 10, "los fusileros tiran")
	assert_true(_shots(world, a.id, Unit.Weapon.MG) > 3, "la ametralladora tira ráfagas")
	assert_lt(a.hp + b.hp, 2 * Config.INF_MEN, "hay bajas")


func test_posture_and_cover_cut_hit_chance() -> void:
	var world: SimWorld = _world()
	world.set_micro(MicroCover.new(N))
	var a: Unit = world.add_unit(0, Vector2(48, 60), Unit.Kind.INFANTRY)
	var b: Unit = world.add_unit(1, Vector2(48, 50), Unit.Kind.INFANTRY)
	var shooter: Soldier = a.soldiers[0]
	var t: Soldier = b.soldiers[0]
	var eye: float = InfantrySim.eye_of(world, shooter)
	var p: Array[float] = []
	for posture: int in [Soldier.Posture.STAND, Soldier.Posture.CROUCH, Soldier.Posture.PRONE]:
		t.posture = posture
		p.append(world.inf.soldier_hit_p(world, a, false, shooter.pos, eye, b, t, Unit.Weapon.RIFLES))
	assert_lt(p[1], p[0], "agachado, menos que de pie")
	assert_lt(p[2], p[1], "cuerpo a tierra, menos que agachado")
	t.posture = Soldier.Posture.CROUCH
	world.micro.set_type(MicroCover.cell_of(t.pos + (shooter.pos - t.pos).normalized() * 1.0), MicroCover.Type.WALL)
	var behind: float = world.inf.soldier_hit_p(world, a, false, shooter.pos, eye, b, t, Unit.Weapon.RIFLES)
	assert_lt(behind, p[1] * 0.5, "detrás del muro, mucho menos")
	shooter.moving = true
	assert_lt(world.inf.soldier_hit_p(world, a, true, shooter.pos, eye, b, t, Unit.Weapon.RIFLES), behind, "tirando en marcha, peor")


func test_mg_burst_hits_several_in_area() -> void:
	var world: SimWorld = _world()
	var a: Unit = world.add_unit(0, Vector2(48, 60), Unit.Kind.INFANTRY)
	var b: Unit = world.add_unit(1, Vector2(48, 56), Unit.Kind.INFANTRY) # 16 m
	for s: Soldier in b.soldiers:
		s.pos = b.pos_m() + Vector2(float(s.index % 3) - 1.0, float(s.index / 3) - 1.0) # amontonados
	var hits: int = 0
	for i: int in 20:
		hits += world.inf._burst(world, a, false, a.soldiers[1].pos, 1.7, 1, b.pos_m(), Unit.Weapon.MG, 1.0)
	assert_true(hits >= 5, "las ráfagas pegan a varios amontonados (%d)" % hits)


func test_squad_dies_at_zero_men() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(1, Vector2(48, 56), Unit.Kind.INFANTRY)
	sq.set_men(1)
	sq.reload_left = 1000.0
	sq.reload2_left = 1000.0
	sq.moving = true
	_run(world, 300)
	assert_true(not sq.alive, "con 0 hombres la escuadra muere")
