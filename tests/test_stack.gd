extends TestBase
## Tests de los cuartos y del apilado en la puerta (fase 66).

const N: int = 64


## Casa de 12 x 10 m (micro 100..111 x 100..109) partida en dos por una pared en x = 106 con un
## paso en y = 103; la puerta en la pared sur, en x = 103.
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
	bm.add_wall(Vector2i(106, 101), Vector2i(106, 102))
	bm.add_wall(Vector2i(106, 104), Vector2i(106, 108))
	world.set_buildings(bm)
	return world


func test_rooms_and_portals() -> void:
	var world: SimWorld = _world()
	var rm: RoomMap = world.rooms()
	assert_eq(rm.rooms.size(), 2, "dos cuartos")
	assert_eq(rm.portals.size(), 2, "un paso interior y la puerta")
	var street: Array[int] = rm.street_portals(0)
	assert_eq(street.size(), 1, "una puerta a la calle")
	var west: int = rm.room_at_m(MicroCover.center_m(Vector2i(102, 105)))
	assert_eq(int(rm.portals[street[0]]["a"]), west, "la puerta da al cuarto oeste")
	assert_true(rm.normal_from(street[0], west).is_equal_approx(Vector2(0, 1)), "la normal apunta a la calle")
	assert_eq(CqbSim.plan_rooms(rm, street[0]).size(), 2, "el plan recorre los dos cuartos")


func test_breach_adds_portal() -> void:
	var world: SimWorld = _world()
	var before: int = world.rooms().portals.size()
	world.buildings.breach(Vector2i(109, 109))
	assert_eq(world.rooms().portals.size(), before + 1, "el boquete es una entrada nueva")


func test_stack_beside_the_door_never_in_front() -> void:
	var world: SimWorld = _world()
	var rm: RoomMap = world.rooms()
	var p: int = rm.street_portals(0)[0]
	var into: int = int(rm.portals[p]["a"])
	var st: Dictionary = CqbSim.stack_points(world, p, into)
	var c: Vector2 = st["center"]
	var t: Vector2 = st["t"]
	var toward: Vector2 = st["toward"]
	var pts: Array = st["points"]
	assert_eq(pts.size(), 4, "cuatro lugares")
	for q: Vector2 in pts:
		assert_lt(0.9, absf((q - c).dot(t)), "al costado de la puerta, no delante (%.2f)" % (q - c).dot(t))
		assert_lt((q - c).dot(toward), 1.5, "pegado a la pared")
		assert_lt(0.0, (q - c).dot(toward), "del lado de afuera")
		assert_true(world.buildings.house_at_m(q) < 0, "afuera de la casa")


func test_interior_stack_stays_in_the_cleared_room() -> void:
	var world: SimWorld = _world()
	var rm: RoomMap = world.rooms()
	var west: int = rm.room_at_m(MicroCover.center_m(Vector2i(102, 105)))
	var east: int = rm.room_at_m(MicroCover.center_m(Vector2i(109, 105)))
	var p: int = -1
	for i: int in rm.portals_of(west):
		if rm.other(i, west) == east:
			p = i
	var st: Dictionary = CqbSim.stack_points(world, p, east)
	for q: Vector2 in st["points"]:
		assert_eq(rm.room_at_m(q), west, "se apila adentro del cuarto ya limpio")


func test_squad_stacks_at_the_door() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(26, 33), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.STRICT
	for s: Soldier in sq.soldiers:
		s.grenades = 0 # sin granada: se apila y entra
	assert_true(world.order_clear(sq.id, Vector2(104, 104)), "orden aceptada")
	world.begin_execute()
	var stacked: bool = false
	for i: int in 900:
		world.step()
		if not sq.clear.is_empty() and str(sq.clear["phase"]) == "stack" and CqbSim._team_arrived(sq):
			stacked = true
			break
	assert_true(stacked, "el equipo se apiló")
	var roles: Array[int] = []
	for s: Soldier in sq.soldiers:
		if s.cqb_role >= 0:
			roles.append(s.cqb_role)
			assert_true(s.role != Soldier.Role.MG, "la ametralladora no entra")
	roles.sort()
	assert_eq(roles, [0, 1, 2, 3], "roles 1 a 4")
