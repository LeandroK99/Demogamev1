extends TestBase
## Tests del drill de contacto: alto, cobertura cerca, fuego y retomar la marcha.

const N: int = 96
const O := SquadMind.Option


func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 4 # un tanque rojo lejos, para que no termine la partida
	world.units[4].pos = Vector2(5, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	world.set_micro(MicroCover.new(N))
	return world


func _moving_squad(world: SimWorld) -> Unit:
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	world.order_move(sq.id, Vector2i(48, 50))
	world.begin_execute()
	for i: int in 20:
		world.step()
	return sq


## Le tiran: supresión moderada (no la frena por sí sola) y el aviso de que le dispararon.
func _fire_on(world: SimWorld, sq: Unit) -> void:
	for s: Soldier in sq.soldiers:
		s.suppression = 35.0
		s.last_suppressed_tick = world.total_ticks
	world.inf.aggregate_suppression(sq)
	sq.last_fired_upon_tick = world.total_ticks


func test_drill_halts_and_takes_close_cover() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _moving_squad(world)
	_fire_on(world, sq)
	for i: int in 12:
		world.step()
	assert_eq(sq.mind.option, O.CONTACT_DRILL, "entra en drill")
	assert_true(not sq.moving, "alto")
	for i: int in 30:
		world.step()
	for s: Soldier in sq.soldiers:
		assert_true(s.has_cover, "cada uno a cubierto")
		assert_true(s.cover_pos.distance_to(sq.slot_pos_m(s.index)) <= Config.DRILL_COVER_M + 0.01, "cerca de su lugar")


func test_drill_resumes_when_calm() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _moving_squad(world)
	_fire_on(world, sq)
	for i: int in 12:
		world.step()
	var y: float = sq.pos.y
	for i: int in 300:
		world.step()
	assert_eq(sq.mind.option, O.FOLLOW, "retoma la orden")
	assert_lt(sq.pos.y, y, "y la marcha")
	assert_eq(world.destination(sq), Vector2i(48, 50), "al mismo destino")


func test_drill_waits_while_under_fire() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _moving_squad(world)
	for i: int in 200:
		if i % 20 == 0:
			_fire_on(world, sq)
		world.step()
	assert_eq(sq.mind.option, O.CONTACT_DRILL, "mientras le tiran, sigue en el drill")


func test_assault_does_not_halt() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	world.order_assault(sq.id, Vector2i(48, 50))
	world.begin_execute()
	world.step()
	_fire_on(world, sq)
	for i: int in 20:
		world.step()
	assert_eq(sq.mind.option, O.FOLLOW, "el asalto no frena")


func test_new_visible_enemy_triggers_once() -> void:
	var world: SimWorld = _world()
	var sq: Unit = _moving_squad(world)
	var red: Unit = world.add_unit(1, Vector2(48, 50), Unit.Kind.INFANTRY)
	red.reload_left = 1000.0
	world.visible_enemies[0][red.id] = true
	world.mind_think_now(sq)
	assert_eq(sq.mind.option, O.CONTACT_DRILL, "lo ve: drill")
	assert_true(sq.mind.reacted.has(red.id), "anotado")
