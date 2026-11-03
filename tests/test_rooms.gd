extends TestBase
## Tests de tirar desde adentro (fase 63): el fondo del cuarto delata menos y la ametralladora roja
## se pone en una aspillera.

const N: int = 64


## Casa de 12 x 10 m (micro 100..111 x 100..109) con puerta al norte y ventana al sur en (105, 109).
func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 4
	world.units[4].pos = Vector2(2, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	world.set_micro(MicroCover.new(N))
	var bm: BuildingMap = BuildingMap.new(N)
	var doors: Array[Vector2i] = [Vector2i(105, 100)]
	var windows: Array[Vector2i] = [Vector2i(105, 109), Vector2i(102, 109)]
	bm.add_house(Rect2i(100, 100, 12, 10), doors, windows)
	world.set_buildings(bm)
	return world


func test_firing_from_the_back_reveals_less() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(1, Vector2(26, 26), Unit.Kind.INFANTRY)
	var s: Soldier = sq.soldiers[1]
	s.last_fire_tick = world.total_ticks
	s.pos = MicroCover.center_m(Vector2i(105, 108)) # pegado a la ventana
	var at_window: float = InfantrySim.soldier_spot_range(world, sq, s)
	s.pos = MicroCover.center_m(Vector2i(105, 105)) # 3 m adentro
	var deep: float = InfantrySim.soldier_spot_range(world, sq, s)
	assert_lt(deep, at_window, "al fondo del cuarto se lo ve de más cerca (%.0f contra %.0f m)" % [deep, at_window])


func test_squad_inside_keeps_cover_inside() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(1, Vector2(26.5, 26), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.STRICT
	sq.heading = Vector2(0, 1)
	sq.snap_soldiers()
	for s: Soldier in sq.soldiers:
		s.pos = world.buildings.nearest_walkable_m(MicroCover.center_m(Vector2i(105, 104)))
	world.begin_execute()
	sq.mind.learn(4, Vector2(26.5, 50) * Config.CELL_SIZE, 1000000, true) # amenaza al sur
	for i: int in 100:
		world.step()
	var inside: int = 0
	var deep: int = 0
	for s: Soldier in sq.soldiers:
		if world.buildings.house_at_m(s.cover_pos) >= 0 and world.buildings.walkable_m(s.cover_pos):
			inside += 1
		if world.buildings.deep_m(s.cover_pos):
			deep += 1
	assert_eq(inside, 9, "todos se cubren adentro")
	assert_lt(0.5, float(deep), "alguno al fondo del cuarto (%d)" % deep)


func test_mg_loophole_faces_the_threat() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(1, Vector2(26.5, 26), Unit.Kind.INFANTRY)
	var threat: Vector2 = Vector2(26.5, 60) * Config.CELL_SIZE
	world.inf.prepare_house(world, sq, threat)
	var mg: Soldier = null
	for s: Soldier in sq.soldiers:
		if s.role == Soldier.Role.MG:
			mg = s
	assert_true(mg.post_pos.x >= 0.0, "la ametralladora tiene puesto")
	assert_true(world.buildings.deep_m(mg.post_pos), "al fondo, detrás de la aspillera")
	var hole: int = 0
	for x: int in range(100, 112):
		if world.buildings.type_at(Vector2i(x, 109)) == BuildingMap.Type.LOOPHOLE:
			hole += 1
	assert_eq(hole, 1, "una aspillera en la pared sur")
	assert_true(world.analysis.los_m(mg.post_pos, Config.SOLDIER_EYE_PRONE, threat, 1.0), "por la aspillera ve hacia la amenaza")


func test_pueblo_red_mgs_have_loopholes() -> void:
	var world: SimWorld = SimWorld.new(1337, null, true, SimWorld.Scenario.PUEBLO)
	var posts: int = 0
	for u: Unit in world.units:
		if u.side == 1 and u.is_infantry():
			for s: Soldier in u.soldiers:
				if s.post_pos.x >= 0.0:
					posts += 1
	assert_eq(posts, Config.LOMA_SQUADS, "cada ametralladora roja en su aspillera")
