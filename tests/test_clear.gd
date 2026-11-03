extends TestBase
## Tests de la orden "limpiar la casa" (fase 70).

const N: int = 64


## Casa de 12 x 10 m con cuatro cuartos (paredes en x = 106 e y = 104 con pasos) y la puerta al sur.
func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 4
	world.units[4].pos = Vector2(2, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	world.set_micro(MicroCover.new(N))
	var bm: BuildingMap = BuildingMap.new(N)
	var doors: Array[Vector2i] = [Vector2i(103, 109)]
	bm.add_house(Rect2i(100, 100, 12, 10), doors)
	for y: int in range(101, 109):
		if y != 102:
			bm.set_type(Vector2i(106, y), BuildingMap.Type.WALL)
	for x: int in range(101, 111):
		if x != 103 and x != 109 and x != 106:
			bm.set_type(Vector2i(x, 104), BuildingMap.Type.WALL)
	world.set_buildings(bm)
	return world


func test_one_order_clears_four_rooms() -> void:
	var world: SimWorld = _world()
	var rm: RoomMap = world.rooms()
	assert_eq(rm.rooms_of(0).size(), 4, "cuatro cuartos")
	var sq: Unit = world.add_unit(0, Vector2(26, 31), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.STRICT
	assert_true(world.order_clear(sq.id, Vector2(104, 104)), "orden aceptada")
	world.begin_execute()
	var security: bool = false
	for i: int in 3000:
		world.step()
		if world.phase != SimWorld.Phase.EXECUTE:
			world.begin_execute()
		if not sq.clear.is_empty() and int(sq.clear["step"]) >= 1 and str(sq.clear["phase"]) == "entry":
			for s: Soldier in sq.soldiers:
				if s.is_ok() and s.cqb_role < 0 and world.cleared_rooms.has(rm.room_at_m(s.pos)):
					security = true
		if sq.clear.is_empty():
			break
	for r: int in rm.rooms_of(0):
		assert_eq(int(world.cleared_rooms.get(r, -1)), 0, "cuarto %d limpio" % r)
	assert_eq(int(world.cleared_houses.get(0, -1)), 0, "la casa marcada como limpia")
	assert_true(security, "deja seguridad en los cuartos ya limpios")
	assert_eq(sq.order, Unit.Order.NONE, "orden cumplida")


func test_no_door_no_clear() -> void:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	var bm: BuildingMap = BuildingMap.new(N)
	bm.add_house(Rect2i(100, 100, 12, 10))
	world.set_buildings(bm)
	var sq: Unit = world.add_unit(0, Vector2(26, 31), Unit.Kind.INFANTRY)
	assert_true(not world.order_clear(sq.id, Vector2(104, 104)), "sin puerta hay que abrir un boquete primero")


func test_new_order_cancels_clearing() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(26, 31), Unit.Kind.INFANTRY)
	assert_true(world.order_clear(sq.id, Vector2(104, 104)), "orden aceptada")
	assert_true(world.order_move(sq.id, Vector2i(20, 35)), "otra orden")
	assert_true(sq.clear.is_empty(), "deja de limpiar")
