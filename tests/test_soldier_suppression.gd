extends TestBase
## Tests de la supresión por soldado y la moral de la escuadra.

const N: int = 96


func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 4
	world.units[4].pos = Vector2(5, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	world.set_micro(MicroCover.new(N))
	return world


func test_fire_suppresses_target_and_neighbors_only() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(1, Vector2(48, 50), Unit.Kind.INFANTRY)
	sq.formation = Unit.Formation.FILE
	sq.snap_soldiers()
	var from: Vector2 = sq.pos_m() + Vector2(0.0, 100.0)
	var t: Soldier = sq.soldiers[0]
	for i: int in 3:
		world.inf.suppress_at(world, 1, t.pos, from, Unit.Weapon.MG, false)
	assert_eq(t.suppression, 3.0 * Config.SOLDIER_SUPP_BURST, "el apuntado recibe toda")
	assert_eq(sq.soldiers[1].suppression, 1.5 * Config.SOLDIER_SUPP_BURST, "el de al lado, la mitad")
	assert_eq(sq.soldiers[4].suppression, 0.0, "el del fondo de la fila, nada")
	assert_lt(sq.suppression, Config.SUPPRESSED, "la escuadra en promedio no está suprimida")


func test_protected_soldier_gets_less() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(1, Vector2(48, 50), Unit.Kind.INFANTRY)
	var from: Vector2 = sq.pos_m() + Vector2(0.0, 100.0)
	var a: Soldier = sq.soldiers[1]
	var b: Soldier = sq.soldiers[2]
	a.posture = Soldier.Posture.CROUCH
	b.posture = Soldier.Posture.CROUCH
	world.micro.set_type(MicroCover.cell_of(a.pos + Vector2(0.0, 1.0)), MicroCover.Type.WALL)
	world.inf.suppress_at(world, 1, a.pos, from, Unit.Weapon.RIFLES, false)
	world.inf.suppress_at(world, 1, b.pos, from, Unit.Weapon.RIFLES, false)
	assert_lt(a.suppression, b.suppression, "detrás del muro recibe menos")


func test_pinned_soldier_stays_and_squad_moves_on() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	var pinned: Soldier = sq.soldiers[6]
	pinned.suppression = 100.0
	pinned.last_suppressed_tick = 1000000 # no baja durante el test
	var at: Vector2 = pinned.pos
	world.order_move(sq.id, Vector2i(48, 70))
	world.begin_execute()
	for i: int in 200:
		world.step()
	assert_eq(pinned.pos, at, "el clavado no se mueve")
	assert_eq(pinned.posture, Soldier.Posture.PRONE, "cuerpo a tierra")
	assert_true(sq.pos.y < 75.0, "la escuadra sigue (uno solo clavado)")


func test_majority_pinned_halts_squad() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.STRICT # con autonomía, a los 3 s repta (test_crawl)
	for s: Soldier in sq.soldiers:
		if s.index < 6:
			s.suppression = 90.0
			s.last_suppressed_tick = 1000000
	world.order_move(sq.id, Vector2i(48, 70))
	world.begin_execute()
	for i: int in 50:
		world.step()
	assert_eq(sq.pos, Vector2(48, 80), "con la mayoría clavada no avanza")


func test_suppressed_but_not_pinned_keeps_advancing() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.STRICT
	for s: Soldier in sq.soldiers:
		s.suppression = 70.0
		s.last_suppressed_tick = 1000000
	world.order_move(sq.id, Vector2i(48, 70))
	world.begin_execute()
	for i: int in 50:
		world.step()
	assert_lt(sq.pos.y, 80.0, "suprimida pero no clavada: la orden manda")


func test_pinned_soldiers_do_not_fire_others_do() -> void:
	var world: SimWorld = _world()
	var a: Unit = world.add_unit(0, Vector2(48, 60), Unit.Kind.INFANTRY)
	var b: Unit = world.add_unit(1, Vector2(48, 50), Unit.Kind.INFANTRY)
	b.reload_left = 1000.0
	b.reload2_left = 1000.0
	for s: Soldier in a.soldiers:
		if s.index != 4:
			s.suppression = 100.0
			s.last_suppressed_tick = 1000000
	world.update_detection()
	world.begin_execute()
	world.step()
	var shooters: Dictionary = {}
	for e: Dictionary in world.shot_events:
		shooters[(e["from_m"] as Vector2)] = true
	assert_eq(shooters.size(), 1, "tira solo el que no está clavado")


func test_leader_loss_hurts_morale_more() -> void:
	var world: SimWorld = _world()
	var a: Unit = world.add_unit(0, Vector2(30, 60), Unit.Kind.INFANTRY)
	var b: Unit = world.add_unit(0, Vector2(60, 60), Unit.Kind.INFANTRY)
	world.damage_soldier(a, a.soldiers[0]) # el jefe
	world.damage_soldier(b, b.soldiers[5])
	assert_lt(a.morale, b.morale, "perder al jefe pega más")


func test_suppression_drains_morale_by_fraction() -> void:
	var world: SimWorld = _world()
	var a: Unit = world.add_unit(0, Vector2(30, 60), Unit.Kind.INFANTRY)
	var b: Unit = world.add_unit(0, Vector2(60, 60), Unit.Kind.INFANTRY)
	for s: Soldier in a.soldiers:
		s.suppression = 60.0
		s.last_suppressed_tick = 1000000
	for s: Soldier in b.soldiers:
		if s.index < 2:
			s.suppression = 60.0
			s.last_suppressed_tick = 1000000
	world.begin_execute()
	for i: int in 50:
		world.step()
	assert_lt(a.morale, b.morale, "más soldados suprimidos, más moral perdida")
	assert_lt(b.morale, 100.0, "aun con dos suprimidos baja algo")
