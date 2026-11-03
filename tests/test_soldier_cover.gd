extends TestBase
## Tests de la cobertura de cada soldado: muro, roca, separación, olvido al marchar.

const N: int = 96


## Llano sin IA; el tanque rojo 4 conocido al norte (amenaza), sin disparar.
func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 0 or u.id == 4
	world.units[0].pos = Vector2(5, 90)
	world.units[4].pos = Vector2(40, 10)
	world.units[0].reload_left = 1000.0
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	world.known_enemies[0][4] = {"cell": Vector2i(40, 10), "last_seen_turn": world.turn}
	world.set_micro(MicroCover.new(N))
	return world


func _run(world: SimWorld, ticks: int) -> void:
	world.begin_execute()
	for i: int in ticks:
		world.step()


## Muro de 1 m a lo ancho, en y (metros), de x0 a x1.
func _wall(world: SimWorld, y_m: float, x0: float, x1: float) -> void:
	var x: float = x0
	while x <= x1:
		world.micro.set_type(MicroCover.cell_of(Vector2(x, y_m)), MicroCover.Type.WALL)
		x += 1.0


func test_soldiers_take_wall_cover_crouched() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(40, 80), Unit.Kind.INFANTRY)
	var wall_y: float = 80.0 * Config.CELL_SIZE + 4.0 # muro cruzando la cuña, a 4 m detrás del jefe
	_wall(world, wall_y, 130.0, 190.0)
	_run(world, 100)
	var behind: int = 0
	for s: Soldier in sq.soldiers:
		if s.protected and s.posture == Soldier.Posture.CROUCH and s.pos.y > wall_y:
			behind += 1
	assert_true(behind >= 6, "la mayoría agachados detrás del muro (%d)" % behind)
	var mg: Soldier = sq.soldiers[1]
	assert_true(mg.protected and mg.can_fire, "la ametralladora cubierta y con tiro")


func test_soldier_goes_prone_behind_rock() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(40, 80), Unit.Kind.INFANTRY)
	var slot: Vector2 = sq.slot_pos_m(5)
	world.micro.set_type(MicroCover.cell_of(slot + Vector2(0.0, -1.5)), MicroCover.Type.ROCK)
	_run(world, 100)
	var prone_behind: int = 0
	for s: Soldier in sq.soldiers:
		if s.protected:
			assert_eq(s.posture, Soldier.Posture.PRONE, "detrás de una roca, cuerpo a tierra")
			prone_behind += 1
	assert_eq(prone_behind, 1, "uno solo aprovecha la roca")


func test_cover_points_are_spaced() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(40, 80), Unit.Kind.INFANTRY)
	_wall(world, 80.0 * Config.CELL_SIZE + 1.0, 150.0, 170.0) # muro corto: compiten por él
	_run(world, 50)
	for a: Soldier in sq.soldiers:
		for b: Soldier in sq.soldiers:
			if a.index < b.index:
				assert_true(a.cover_pos.distance_to(b.cover_pos) >= Config.SOLDIER_COVER_SPACING - 0.01, "separados")


func test_no_micro_no_protection_and_marching_forgets() -> void:
	var world: SimWorld = _world()
	world.set_micro(null)
	var sq: Unit = world.add_unit(0, Vector2(40, 80), Unit.Kind.INFANTRY)
	_run(world, 50)
	for s: Soldier in sq.soldiers:
		assert_true(s.has_cover and not s.protected, "sin microcobertura no hay protección")
	world.start_plan()
	world.order_move(sq.id, Vector2i(40, 70))
	_run(world, 5)
	for s: Soldier in sq.soldiers:
		assert_true(not s.has_cover, "en marcha se olvida del punto")
		assert_eq(s.posture, Soldier.Posture.STAND, "de pie en marcha")


func test_reverse_slope_counts_as_protected() -> void:
	var hf: HeightField = HeightField.new(N)
	for x: int in N:
		for y: int in range(70, 78):
			hf.set_height(Vector2i(x, y), 4.0) # loma entre la escuadra y la amenaza
	var world: SimWorld = SimWorld.new(7, hf, false)
	for u: Unit in world.units:
		u.alive = u.id == 4
	world.units[4].pos = Vector2(40, 10)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	world.known_enemies[0][4] = {"cell": Vector2i(40, 10), "last_seen_turn": world.turn}
	world.set_micro(MicroCover.new(N))
	var sq: Unit = world.add_unit(0, Vector2(40, 84), Unit.Kind.INFANTRY)
	_run(world, 50)
	for s: Soldier in sq.soldiers:
		assert_true(s.protected and not s.can_fire, "la loma lo tapa: protegido, sin tiro")
