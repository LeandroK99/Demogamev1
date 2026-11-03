extends TestBase
## Tests de la visión por soldado: rocas y arbustos, observadores que rotan, ver tanques.

const N: int = 96


## Llano sin IA; el tanque rojo 4 en (40, 60), quieto y sin disparar; el azul 0 lejos.
func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 0 or u.id == 4
	world.units[0].pos = Vector2(5, 90)
	world.units[4].pos = Vector2(40, 60)
	for id: int in [0, 4]:
		world.units[id].reload_left = 1000.0
		world.units[id].reload2_left = 1000.0
	world.set_micro(MicroCover.new(N))
	return world


## Escuadra azul a 40 m al sur del tanque con un solo soldado en condiciones (el 5), cuerpo a tierra.
func _lone_soldier(world: SimWorld) -> Soldier:
	var sq: Unit = world.add_unit(0, Vector2(40, 70), Unit.Kind.INFANTRY)
	for s: Soldier in sq.soldiers:
		if s.index != 5:
			s.state = Soldier.State.DEAD
	var s5: Soldier = sq.soldiers[5]
	s5.pos = Vector2(160.5, 280.5)
	s5.posture = Soldier.Posture.PRONE
	return s5


func test_rock_hides_prone_soldier() -> void:
	var world: SimWorld = _world()
	var s: Soldier = _lone_soldier(world)
	var sq_id: int = world.units.size() - 1
	world.update_detection()
	assert_true(world.visible_enemies[1].has(sq_id), "en el llano, a 40 m, se lo ve cuerpo a tierra")
	assert_true(world.inf.is_soldier_visible(1, sq_id, 5), "y se anota el soldado")
	world.micro.set_type(MicroCover.cell_of(s.pos + Vector2(0.0, -1.0)), MicroCover.Type.ROCK)
	world.update_detection()
	assert_true(not world.visible_enemies[1].has(sq_id), "detrás de la roca, no")
	s.posture = Soldier.Posture.STAND
	world.update_detection()
	assert_true(world.visible_enemies[1].has(sq_id), "de pie asoma por encima")


func test_bush_hides_but_others_give_the_squad_away() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(40, 70), Unit.Kind.INFANTRY)
	sq.set_posture(Soldier.Posture.CROUCH)
	var s: Soldier = sq.soldiers[4]
	world.micro.set_type(MicroCover.cell_of(s.pos + Vector2(0.0, -1.0)), MicroCover.Type.BUSH)
	world.update_detection()
	assert_true(world.visible_enemies[1].has(sq.id), "la escuadra se ve")
	assert_true(not world.inf.is_soldier_visible(1, sq.id, 4), "el del arbusto, no")
	assert_true(world.inf.is_soldier_visible(1, sq.id, 0), "el jefe, sí")


func test_observers_are_leader_plus_rotating() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(40, 80), Unit.Kind.INFANTRY)
	var seen: Dictionary = {}
	for r: int in 4:
		world.inf.begin_detection(world)
		var obs: Array = world.inf._observers[sq.id]
		assert_eq(obs.size(), Config.SOLDIER_OBSERVERS, "tres observadores")
		assert_eq((obs[0] as Soldier).role, Soldier.Role.LEADER, "el jefe siempre mira")
		for o: Soldier in obs:
			seen[o.index] = true
	assert_eq(seen.size(), Config.INF_MEN, "en cuatro rondas miraron todos")


func test_soldiers_spot_moving_tank_far() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(40, 90), Unit.Kind.INFANTRY) # 120 m
	var tank: Unit = world.units[4]
	world.update_detection()
	assert_true(world.visible_enemies[0].has(tank.id), "a 120 m, quieto, se ve el tanque")
	sq.pos = Vector2(40, 95)
	tank.pos = Vector2(40, 15) # 320 m
	sq.snap_soldiers()
	world.update_detection()
	assert_true(not world.visible_enemies[0].has(tank.id), "quieto a 320 m, no")
	tank.moving = true
	world.update_detection()
	assert_true(world.visible_enemies[0].has(tank.id), "en marcha, sí")
