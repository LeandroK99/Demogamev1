extends TestBase
## Tests del tirador selecto: ve y tira más lejos, y elige al jefe o a la ametralladora.

const N: int = 160


func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 4 # un tanque rojo lejos, para que no termine la partida
	world.units[4].pos = Vector2(5, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	world.set_micro(MicroCover.new(N))
	return world


func test_one_marksman_per_squad() -> void:
	var sq: Unit = Unit.new(0, 0, Vector2(10, 10), Unit.Kind.INFANTRY)
	var n: int = 0
	for s: Soldier in sq.soldiers:
		n += 1 if s.marksman else 0
	assert_eq(n, 1, "uno por escuadra")
	assert_eq(sq.soldiers[Config.MARKSMAN_INDEX].team, 0, "en el equipo de la base de fuego")


func test_marksman_prefers_leader() -> void:
	var world: SimWorld = _world()
	var blue: Unit = world.add_unit(0, Vector2(80, 120), Unit.Kind.INFANTRY)
	var red: Unit = world.add_unit(1, Vector2(80, 60), Unit.Kind.INFANTRY) # 240 m
	var mk: Soldier = blue.soldiers[Config.MARKSMAN_INDEX]
	var rifle: Soldier = red.soldiers[5]
	var leader: Soldier = red.soldiers[0]
	leader.pos = mk.pos + Vector2(0.0, -240.0)
	rifle.pos = mk.pos + Vector2(10.0, -200.0) # más cerca, pero es un fusilero
	world.inf.visible_soldiers[0][InfantrySim.soldier_key(red.id, 0)] = true
	world.inf.visible_soldiers[0][InfantrySim.soldier_key(red.id, 5)] = true
	var t: Dictionary = world.inf.pick_soldier(world, blue, mk.pos, InfantrySim.eye_of(world, mk), Config.MARKSMAN_RANGE, mk.index, true)
	assert_eq((t["soldier"] as Soldier).role, Soldier.Role.LEADER, "elige al jefe")
	var t2: Dictionary = world.inf.pick_soldier(world, blue, mk.pos, InfantrySim.eye_of(world, mk), Config.MARKSMAN_RANGE, 0, false)
	assert_eq(t2["soldier"], rifle, "un fusilero elige al más cercano")


func test_marksman_hits_better_far_and_still() -> void:
	var world: SimWorld = _world()
	var blue: Unit = world.add_unit(0, Vector2(80, 120), Unit.Kind.INFANTRY)
	var red: Unit = world.add_unit(1, Vector2(80, 60), Unit.Kind.INFANTRY)
	var mk: Soldier = blue.soldiers[Config.MARKSMAN_INDEX]
	var rf: Soldier = blue.soldiers[5]
	var t: Soldier = red.soldiers[0]
	t.pos = mk.pos + Vector2(0.0, -250.0)
	var eye: float = InfantrySim.eye_of(world, mk)
	var p_mk: float = world.inf.soldier_hit_p(world, blue, false, mk.pos, eye, red, t, Unit.Weapon.RIFLES, true, mk)
	var p_rf: float = world.inf.soldier_hit_p(world, blue, false, mk.pos, eye, red, t, Unit.Weapon.RIFLES, true, rf)
	assert_lt(p_rf * 3.0, p_mk, "a 250 m, mucho mejor que un fusilero")
	t.moving = true
	var p_mv: float = world.inf.soldier_hit_p(world, blue, false, mk.pos, eye, red, t, Unit.Weapon.RIFLES, true, mk)
	assert_lt(p_mv, p_mk, "peor contra un blanco en marcha")


func test_marksman_spots_farther() -> void:
	var world: SimWorld = _world()
	var blue: Unit = world.add_unit(0, Vector2(80, 120), Unit.Kind.INFANTRY)
	var red: Unit = world.add_unit(1, Vector2(80, 70), Unit.Kind.INFANTRY) # 200 m, quietos de pie
	red.set_posture(Soldier.Posture.STAND)
	for s: Soldier in blue.soldiers:
		if not s.marksman:
			s.state = Soldier.State.DEAD
	blue.hp = 1
	world.update_detection()
	assert_true(world.visible_enemies[0].has(red.id), "a 200 m (más que los 120 m normales) los ve con la mira")
