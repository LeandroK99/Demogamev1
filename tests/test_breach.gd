extends TestBase
## Tests de los boquetes y del tanque con infantería (fase 65).

const N: int = 64


## Casa cerrada (sin puertas) de 12 x 10 m: micro 100..111 x 100..109 (metros 98 a 110, 98 a 108).
func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 4
	world.units[4].pos = Vector2(2, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	world.set_micro(MicroCover.new(N))
	var bm: BuildingMap = BuildingMap.new(N)
	bm.add_house(Rect2i(100, 100, 12, 10))
	world.set_buildings(bm)
	return world


func _inside(world: SimWorld, sq: Unit) -> int:
	var n: int = 0
	for s: Soldier in sq.soldiers:
		if world.buildings.inside_m(s.pos):
			n += 1
	return n


func test_tank_breach_lets_squad_in() -> void:
	var world: SimWorld = _world()
	var tank: Unit = world.add_unit(0, Vector2(26, 45), Unit.Kind.TANK)
	var sq: Unit = world.add_unit(0, Vector2(20, 40), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.STRICT
	sq.formation = Unit.Formation.FILE
	sq.shape = Unit.Formation.FILE
	sq.snap_soldiers()
	sq.pace = Unit.Pace.FAST
	assert_true(world.order_breach(tank.id, Vector2(104, 109)), "el tanque acepta abrir la pared sur")
	world.begin_execute()
	for i: int in 30:
		world.step()
	var breaches: int = 0
	for x: int in range(100, 112):
		if world.buildings.type_at(Vector2i(x, 109)) == BuildingMap.Type.BREACH:
			breaches += 1
	assert_eq(breaches, Config.BREACH_WIDTH, "boquete abierto en la pared sur")
	assert_eq(tank.order, Unit.Order.NONE, "orden cumplida")
	# Ahora la escuadra entra por el boquete
	world.phase = SimWorld.Phase.PLAN
	assert_true(world.order_move(sq.id, Vector2i(26, 26)), "orden de entrar")
	world.begin_execute()
	for i: int in 1500:
		world.step()
	assert_lt(4.5, float(_inside(world, sq)), "entraron por el boquete (%d adentro)" % _inside(world, sq))


func test_squad_charge_breach() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(26, 35), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.STRICT
	sq.formation = Unit.Formation.FILE
	sq.shape = Unit.Formation.FILE
	sq.snap_soldiers()
	sq.pace = Unit.Pace.FAST
	assert_true(world.order_breach(sq.id, Vector2(104, 109)), "orden aceptada")
	world.begin_execute()
	for i: int in 1200:
		world.step()
	assert_eq(sq.breach_charges, Config.BREACH_CHARGES - 1, "usó su carga")
	var breaches: int = 0
	for x: int in range(100, 112):
		if world.buildings.type_at(Vector2i(x, 109)) == BuildingMap.Type.BREACH:
			breaches += 1
	assert_eq(breaches, Config.BREACH_WIDTH, "voló la pared")


func test_no_doors_no_way_in_without_breach() -> void:
	var world: SimWorld = _world()
	var path: PackedVector2Array = world.buildings.route(Vector2(104, 120), MicroCover.center_m(Vector2i(105, 104)))
	assert_true(path.is_empty(), "sin puertas no se entra")


func test_escorted_tank_is_harder_to_hit_with_at() -> void:
	var world: SimWorld = _world()
	var tank: Unit = world.add_unit(0, Vector2(26, 30), Unit.Kind.TANK)
	var alone: float = InfantrySim.tank_escort_factor(world, tank)
	world.add_unit(0, Vector2(28, 33), Unit.Kind.INFANTRY)
	var escorted: float = InfantrySim.tank_escort_factor(world, tank)
	assert_lt(escorted, alone, "con escolta le pegan menos (%.2f contra %.2f)" % [escorted, alone])
	assert_lt(1.0, alone, "solo, pegado a las casas, le pegan más")
