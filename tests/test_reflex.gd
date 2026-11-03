extends TestBase
## Tests de la granada antes de entrar y del tiro reflejo (fase 68).

const N: int = 64


func _world(sim_seed: int, house: bool) -> SimWorld:
	var world: SimWorld = SimWorld.new(sim_seed, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = false
	world.set_micro(MicroCover.new(N))
	var bm: BuildingMap = BuildingMap.new(N)
	if house:
		var doors: Array[Vector2i] = [Vector2i(103, 109)]
		bm.add_house(Rect2i(100, 100, 10, 10), doors)
	world.set_buildings(bm)
	return world


## Duelo a 6 m: a quieto con el arma lista contra b que camina. Devuelve 0 si cae b primero, 1 si a.
func _duel(sim_seed: int) -> int:
	var world: SimWorld = _world(sim_seed, false)
	var a: Unit = world.add_unit(0, Vector2(20, 20), Unit.Kind.INFANTRY)
	var b: Unit = world.add_unit(1, Vector2(18.5, 19), Unit.Kind.INFANTRY)
	for u: Unit in [a, b]:
		u.mind.autonomy = SquadMind.Autonomy.STRICT
		u.set_men(1)
	a.soldiers[0].pos = Vector2(80, 80)
	a.soldiers[0].cqb_post = true
	b.soldiers[0].pos = Vector2(74, 76)
	world.order_move(b.id, Vector2i(30, 19)) # pasa a 4 m
	world.begin_execute()
	for i: int in 200:
		world.step()
		if not b.soldiers[0].is_ok():
			return 0
		if not a.soldiers[0].is_ok():
			return 1
	return -1


func test_ready_soldier_wins_the_reflex_duel() -> void:
	var wins: int = 0
	var n: int = 0
	for k: int in 30:
		var r: int = _duel(100 + k)
		if r >= 0:
			n += 1
			wins += 1 - r
	assert_lt(20.0, float(n), "hubo duelo (%d)" % n)
	assert_lt(float(n) * 0.8, float(wins), "el que tiene el arma lista gana %d de %d" % [wins, n])


## Limpia una casa de un cuarto con dos defensores; devuelve los azules caídos.
func _assault(sim_seed: int, grenade: bool) -> int:
	var world: SimWorld = _world(sim_seed, true)
	var red: Unit = world.add_unit(1, Vector2(26, 26), Unit.Kind.INFANTRY)
	red.mind.autonomy = SquadMind.Autonomy.STRICT
	red.set_men(2)
	red.snap_soldiers()
	world.cqb.defend_house(world, red)
	for s: Soldier in red.soldiers:
		if s.task_pos.x >= 0.0:
			s.pos = s.task_pos
	var blue: Unit = world.add_unit(0, Vector2(26, 29), Unit.Kind.INFANTRY)
	blue.mind.autonomy = SquadMind.Autonomy.STRICT
	if not grenade:
		for s: Soldier in blue.soldiers:
			s.grenades = 0
	world.order_clear(blue.id, Vector2(104, 104))
	world.begin_execute()
	for i: int in 900:
		world.step()
		if world.phase != SimWorld.Phase.EXECUTE:
			world.begin_execute()
		if blue.clear.is_empty() or not red.alive:
			break
	return blue.max_hp() - blue.ok_count()


func test_grenade_before_entry_saves_men() -> void:
	var with_g: int = 0
	var without: int = 0
	for k: int in 8:
		with_g += _assault(200 + k, true)
		without += _assault(200 + k, false)
	assert_lt(float(with_g), float(without), "con granada caen %d, sin granada %d" % [with_g, without])
