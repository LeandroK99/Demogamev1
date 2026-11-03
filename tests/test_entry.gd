extends TestBase
## Tests de la entrada dinámica (fase 67).

const N: int = 64


func _world(door_x: int = 103) -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 4
	world.units[4].pos = Vector2(2, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	world.set_micro(MicroCover.new(N))
	var bm: BuildingMap = BuildingMap.new(N)
	var doors: Array[Vector2i] = [Vector2i(door_x, 109)]
	bm.add_house(Rect2i(100, 100, 10, 10), doors)
	world.set_buildings(bm)
	return world


func _check_points(world: SimWorld, pts: Array[Vector2], c: Vector2, room: int) -> void:
	for i: int in pts.size():
		assert_eq(world.rooms().room_at_m(pts[i]), room, "el %d adentro del cuarto" % (i + 1))
		assert_lt(1.0, pts[i].distance_to(c), "el %d no se queda en la puerta" % (i + 1))
		for j: int in i:
			assert_lt(1.0, pts[i].distance_to(pts[j]), "el %d y el %d no se tapan" % [j + 1, i + 1])


func test_points_of_domination() -> void:
	for door_x: int in [103, 101, 108]: # al medio y pegada a cada esquina
		var world: SimWorld = _world(door_x)
		var rm: RoomMap = world.rooms()
		var p: int = rm.street_portals(0)[0]
		var room: int = int(rm.portals[p]["a"])
		var st: Dictionary = CqbSim.stack_points(world, p, room)
		var pts: Array[Vector2] = CqbSim.entry_points(world, p, room, float(st["side"]))
		_check_points(world, pts, rm.portals[p]["center"], room)
		# El 1 cruza al lado contrario del apilado; el 2 engancha del lado del apilado
		var t: Vector2 = st["t"]
		var c: Vector2 = rm.portals[p]["center"]
		var side: float = float(st["side"])
		if absf((pts[0] - c).dot(t)) > 0.5 and absf((pts[1] - c).dot(t)) > 0.5:
			assert_lt((pts[0] - c).dot(t) * side, 0.0, "el 1 cruza (puerta en %d)" % door_x)
			assert_lt(0.0, (pts[1] - c).dot(t) * side, "el 2 engancha (puerta en %d)" % door_x)


func test_entry_under_four_seconds() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(26, 29), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.STRICT
	for s: Soldier in sq.soldiers:
		s.grenades = 0
	assert_true(world.order_clear(sq.id, Vector2(104, 104)), "orden aceptada")
	world.begin_execute()
	var start: int = -1
	var arrived: int = -1
	for i: int in 900:
		world.step()
		if world.phase != SimWorld.Phase.EXECUTE:
			world.begin_execute()
		var ph: String = str(sq.clear.get("phase", ""))
		if start < 0 and ph == "entry":
			start = world.total_ticks
		if start >= 0 and arrived < 0 and (ph != "entry" or CqbSim._team_arrived(sq)):
			arrived = world.total_ticks
			break
	assert_true(start >= 0, "entraron")
	var secs: float = float(arrived - start) * Config.TICK
	assert_lt(secs, 4.0, "los cuatro en sus puntos en %.1f s" % secs)
	var pts: Array[Vector2] = []
	for k: int in 4:
		for s: Soldier in sq.soldiers:
			if s.cqb_role == k:
				pts.append(s.pos)
	var rm: RoomMap = world.rooms()
	var p: int = rm.street_portals(0)[0]
	_check_points(world, pts, rm.portals[p]["center"], int(rm.portals[p]["a"]))


func test_empty_house_cleared_and_marked() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(26, 29), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.STRICT
	assert_true(world.order_clear(sq.id, Vector2(104, 104)), "orden aceptada")
	world.begin_execute()
	for i: int in 1200:
		world.step()
		if world.phase != SimWorld.Phase.EXECUTE:
			world.begin_execute()
		if sq.clear.is_empty():
			break
	assert_eq(int(world.cleared_houses.get(0, -1)), 0, "casa limpia para el azul")
	assert_true(world.buildings.house_at_m(sq.pos_m()) == 0, "la escuadra ocupa la casa")
