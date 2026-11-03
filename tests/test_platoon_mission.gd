extends TestBase
## Tests de la misión del pelotón (fase 58): se acerca con una de punta, fija con la trabada y
## flanquea con las otras, asalta y la base corre el fuego.

const N: int = 128
const ST := PlatoonLeader.Stage


func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 4 # un tanque rojo lejos, para que no termine la partida
	world.units[4].pos = Vector2(5, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	world.set_micro(MicroCover.new(N))
	return world


func _platoon(world: SimWorld) -> Array[Unit]:
	var out: Array[Unit] = []
	for x: int in [56, 64, 72]:
		out.append(world.add_unit(0, Vector2(x, 110 + (x - 56) / 4), Unit.Kind.INFANTRY))
	return out


func test_mission_only_in_plan_and_with_squads() -> void:
	var world: SimWorld = _world()
	assert_true(not world.order_mission(0, Vector2i(64, 30)), "sin escuadras no hay misión")
	_platoon(world)
	world.begin_execute()
	assert_true(not world.order_mission(0, Vector2i(64, 30)), "en ejecución no")


func test_approach_lead_goes_others_follow() -> void:
	var world: SimWorld = _world()
	var sq: Array[Unit] = _platoon(world)
	assert_true(world.order_mission(0, Vector2i(64, 30)), "misión aceptada")
	var pl: PlatoonLeader = world.missions[0]
	assert_eq(pl.stage, ST.APPROACH, "se acerca")
	var lead: Unit = sq[0] # la más cercana al objetivo (y = 110)
	assert_eq(world.destination(lead), Vector2i(64, 30), "la de punta va al objetivo")
	for k: int in range(1, 3):
		var d: Vector2i = world.destination(sq[k])
		assert_lt(float(d.y), float(sq[k].pos.y) + 0.5, "la %d no se va para atrás" % k)
		assert_lt(70.0, float(d.y), "la %d queda detrás de la punta (y %d)" % [k, d.y])


func test_contact_fixes_and_flanks() -> void:
	var world: SimWorld = _world()
	var sq: Array[Unit] = _platoon(world)
	world.order_mission(0, Vector2i(64, 30))
	world.begin_execute()
	var enemy: Vector2 = Vector2(56, 70) * Config.CELL_SIZE # a 160 m de la punta
	sq[0].mind.learn(4, enemy, 1000000, true)
	var pl: PlatoonLeader = world.missions[0]
	pl.monitor(world)
	assert_eq(pl.stage, ST.FIX, "fija y flanquea")
	assert_eq(pl.base_id, sq[0].id, "la trabada es la base")
	assert_eq(sq[0].order, Unit.Order.SUPPRESS, "la base bate el contacto")
	assert_true(sq[0].path.is_empty(), "la base se queda")
	assert_eq(pl.maneuver.size(), 2, "las otras dos maniobran")
	for k: int in range(1, 3):
		var d: Vector2 = Vector2(world.destination(sq[k])) * Config.CELL_SIZE
		assert_lt(d.distance_to(enemy), Config.FLANK_OFFSET_M * 1.3, "la %d va al costado del contacto" % k)


func test_assault_then_shift_fire() -> void:
	var world: SimWorld = _world()
	var sq: Array[Unit] = _platoon(world)
	world.order_mission(0, Vector2i(64, 30))
	world.begin_execute()
	var enemy: Vector2 = Vector2(56, 70) * Config.CELL_SIZE
	sq[0].mind.learn(4, enemy, 1000000, true)
	var pl: PlatoonLeader = world.missions[0]
	pl.monitor(world)
	for k: int in range(1, 3): # llegaron al flanco
		sq[k].path.clear()
		sq[k].waypoints.clear()
	pl.monitor(world)
	assert_eq(pl.stage, ST.ASSAULT, "asalta")
	assert_eq(sq[1].order, Unit.Order.ASSAULT, "la de maniobra asalta")
	var before: Vector2i = sq[0].suppress_cell
	sq[1].pos = enemy / Config.CELL_SIZE + Vector2(5, 0) # a 20 m
	pl.monitor(world)
	assert_true(pl.shifted, "la base levantó el fuego")
	assert_lt(float(sq[0].suppress_cell.y), float(before.y), "corrió el tiro más allá del enemigo")
