extends TestBase
## Tests de las granadas: contra el que está cubierto, el granadero de lejos, esquirlas que ignoran el muro.

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


## Un soldado rojo cuerpo a tierra detrás de una pirca, a dist_m al norte del soldado azul s.
func _behind_wall(world: SimWorld, s: Soldier, dist_m: float) -> Dictionary:
	var red: Unit = world.add_unit(1, (s.pos + Vector2(0.0, -dist_m)) / Config.CELL_SIZE, Unit.Kind.INFANTRY)
	red.mind.autonomy = SquadMind.Autonomy.STRICT
	var t: Soldier = red.soldiers[0]
	for o: Soldier in red.soldiers:
		o.pos = Vector2(-500.0, -500.0) # los demás, lejos
	t.pos = s.pos + Vector2(0.0, -dist_m)
	t.posture = Soldier.Posture.CROUCH
	for dx: int in range(-2, 3):
		world.micro.set_type(MicroCover.cell_of(t.pos + Vector2(float(dx), 1.0)), MicroCover.Type.WALL)
	var key: int = InfantrySim.soldier_key(red.id, 0)
	world.inf.visible_soldiers[0][key] = true
	return {"unit": red, "soldier": t}


func _blue(world: SimWorld) -> Unit:
	var sq: Unit = world.add_unit(0, Vector2(48, 60), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.STRICT
	return sq


func test_hand_grenade_against_covered_enemy() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _blue(world)
	var s: Soldier = sq.soldiers[5]
	var r: Dictionary = _behind_wall(world, s, 20.0)
	assert_true(InfantrySim.is_protected_from(world, r["soldier"], s.pos), "la pirca lo protege del fusil")
	assert_true(world.inf.try_grenade(world, sq, s), "tira la granada")
	assert_eq(s.grenades, Config.GRENADES_PER_SOLDIER - 1, "gasta una")
	assert_eq(world.grenades.size(), 1, "en el aire")


func test_no_grenade_in_the_open() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _blue(world)
	var s: Soldier = sq.soldiers[5]
	var r: Dictionary = _behind_wall(world, s, 20.0)
	world.micro = MicroCover.new(N) # sin pirca
	(r["soldier"] as Soldier).posture = Soldier.Posture.STAND
	assert_true(not world.inf.try_grenade(world, sq, s), "al descubierto, fusil")


func test_grenadier_reaches_far() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _blue(world)
	var g: Soldier = sq.soldiers[Config.GRENADIER_INDEX]
	_behind_wall(world, g, 80.0)
	assert_true(world.inf.try_grenade(world, sq, g), "lanzagranadas a 80 m")
	assert_eq(g.gl_rounds, Config.GL_ROUNDS - 1, "gasta una granada de fusil")
	assert_eq(g.grenades, Config.GRENADES_PER_SOLDIER, "no la de mano")


func test_no_grenade_near_friends() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _blue(world)
	var s: Soldier = sq.soldiers[5]
	var r: Dictionary = _behind_wall(world, s, 20.0)
	sq.soldiers[6].pos = (r["soldier"] as Soldier).pos + Vector2(3.0, 2.0)
	assert_true(not world.inf.try_grenade(world, sq, s), "hay un propio al lado del blanco")


func test_blast_ignores_wall_and_runs_out() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _blue(world)
	var r: Dictionary = _behind_wall(world, sq.soldiers[5], 20.0)
	var t: Soldier = r["soldier"]
	var hits: int = 0
	for i: int in 200:
		t.state = Soldier.State.OK
		t.posture = Soldier.Posture.CROUCH
		(r["unit"] as Unit).alive = true
		(r["unit"] as Unit).hp = 1
		world.inf.explode(world, t.pos + Vector2(1.0, 0.0), sq, sq.soldiers[5].pos)
		if t.state != Soldier.State.OK:
			hits += 1
	assert_lt(60, hits, "las esquirlas pasan la pirca")
	assert_lt(40.0, t.suppression, "y suprimen")


func test_grenades_run_out() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _blue(world)
	var s: Soldier = sq.soldiers[5]
	_behind_wall(world, s, 20.0)
	for i: int in Config.GRENADES_PER_SOLDIER:
		assert_true(world.inf.try_grenade(world, sq, s), "tira")
	assert_true(not world.inf.try_grenade(world, sq, s), "no le quedan")
