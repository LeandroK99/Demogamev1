extends TestBase
## Tests de los sectores de tiro, la línea final de la ametralladora y su cambio de posición.

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


func _holding(world: SimWorld) -> Unit:
	var sq: Unit = world.add_unit(0, Vector2(48, 60), Unit.Kind.INFANTRY)
	world.known_enemies[0][4] = {"cell": Vector2i(48, 20), "last_seen_turn": world.turn}
	world.begin_execute()
	world.step()
	return sq


func test_sectors_cover_the_front() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _holding(world)
	var north: Vector2 = Vector2(0.0, -1.0)
	for deg: float in range(-55, 56, 5):
		var at: Vector2 = sq.pos_m() + north.rotated(deg_to_rad(deg)) * 150.0
		var covered: int = 0
		for s: Soldier in sq.soldiers:
			if s.role != Soldier.Role.MG and InfantrySim.in_sector(s, at):
				covered += 1
		assert_lt(0, covered, "sin huecos a %d°" % int(deg))
	var left: int = 0
	for s: Soldier in sq.soldiers:
		if s.role != Soldier.Role.MG and s.sector_dir.x < -0.3:
			left += 1
	assert_lt(0, left, "alguno mira a la izquierda")


func test_mg_has_final_line() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _holding(world)
	var mg: Soldier = sq.soldiers[1]
	assert_true(mg.fpl_dir != Vector2.ZERO, "línea final")
	assert_lt(InfantrySim.fpl_dist(mg, mg.pos + mg.fpl_dir * 100.0), 0.01, "sobre la línea")
	assert_eq(InfantrySim.fpl_dist(mg, mg.pos - mg.fpl_dir * 100.0), INF, "no hacia atrás")


func test_shooter_prefers_own_sector() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _holding(world)
	var red: Unit = world.add_unit(1, Vector2(48, 30), Unit.Kind.INFANTRY)
	var s: Soldier = null
	for o: Soldier in sq.soldiers:
		if o.role == Soldier.Role.RIFLE and o.sector_dir.x < -0.3:
			s = o
	var in_left: Soldier = red.soldiers[2]
	var right_close: Soldier = red.soldiers[3]
	in_left.pos = s.pos + s.sector_dir * 120.0
	right_close.pos = s.pos + Vector2(0.6, -0.8) * 80.0 # más cerca pero a la derecha
	world.inf.visible_soldiers[0][InfantrySim.soldier_key(red.id, 2)] = true
	world.inf.visible_soldiers[0][InfantrySim.soldier_key(red.id, 3)] = true
	var t: Dictionary = world.inf.pick_soldier(world, sq, s.pos, InfantrySim.eye_of(world, s), 300.0, 0, false, s)
	assert_eq(t["soldier"], in_left, "tira al de su sector")


func test_grazing_fire_along_final_line() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _holding(world)
	var mg: Soldier = sq.soldiers[1]
	var red: Unit = world.add_unit(1, Vector2(48, 30), Unit.Kind.INFANTRY)
	for k: int in red.soldiers.size():
		red.soldiers[k].pos = mg.pos + mg.fpl_dir * (60.0 + 8.0 * float(k))
	var sup_before: float = red.soldiers[8].suppression
	world.inf._graze(world, sq, mg, 1, red.soldiers[0].pos)
	assert_lt(sup_before, red.soldiers[8].suppression, "la ráfaga barre la línea")


func test_mg_displaces_when_spotted() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _holding(world)
	var mg: Soldier = sq.soldiers[1]
	for i: int in 20:
		world.step()
	assert_true(mg.has_cover, "en posición")
	var was: Vector2 = mg.cover_pos
	mg.incoming_tick = world.total_ticks
	for i: int in Config.MG_DISPLACE_BURSTS:
		world.inf._maybe_displace(world, sq, mg)
	assert_true(not mg.has_cover, "deja la posición")
	world.step()
	assert_true(mg.has_cover, "elige otra")
	assert_lt(Config.MG_DISPLACE_MIN_M - 0.01, mg.cover_pos.distance_to(was), "lejos de la anterior")


func test_mg_stays_if_not_spotted() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _holding(world)
	var mg: Soldier = sq.soldiers[1]
	for i: int in 20:
		world.step()
	for i: int in Config.MG_DISPLACE_BURSTS * 2:
		world.inf._maybe_displace(world, sq, mg)
	assert_true(mg.has_cover, "nadie le tira: se queda")
