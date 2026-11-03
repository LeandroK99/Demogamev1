extends TestBase
## Tests de los pasillos (fase 69).

const N: int = 64


## Casa de 14 x 10 m con un pasillo de 2 m a lo largo (filas 104 y 105) y la puerta al oeste, en el
## pasillo; cuatro cuartos dan a él.
func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 4
	world.units[4].pos = Vector2(2, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	world.set_micro(MicroCover.new(N))
	var bm: BuildingMap = BuildingMap.new(N)
	var doors: Array[Vector2i] = [Vector2i(100, 104)]
	bm.add_house(Rect2i(100, 100, 14, 10), doors)
	for wy: int in [103, 106]:
		for x: int in range(101, 113):
			if x != 102 and x != 110:
				bm.set_type(Vector2i(x, wy), BuildingMap.Type.WALL)
	for y: int in [101, 102, 107, 108]:
		bm.set_type(Vector2i(107, y), BuildingMap.Type.WALL)
	world.set_buildings(bm)
	return world


func test_generator_makes_corridors() -> void:
	var found: bool = false
	for sd: int in 6:
		var bm: BuildingMap = TownGenerator.build(HeightField.new(96), 1337 + sd)
		var rm: RoomMap = RoomMap.build(bm)
		for r: int in rm.rooms.size():
			if rm.is_corridor(r) and (rm.rooms[r]["rect"] as Rect2).size.length() >= 8.0:
				found = true
	assert_true(found, "las casas grandes tienen pasillo")


func test_snake_in_the_corridor() -> void:
	var world: SimWorld = _world()
	var rm: RoomMap = world.rooms()
	assert_eq(rm.rooms_of(0).size(), 5, "cuatro cuartos y el pasillo")
	var p: int = rm.street_portals(0)[0]
	var cor: int = int(rm.portals[p]["a"])
	assert_true(rm.is_corridor(cor), "la puerta da al pasillo")
	var pts: Array[Vector2] = CqbSim.snake_points(world, p, cor)
	for i: int in pts.size():
		assert_eq(rm.room_at_m(pts[i]), cor, "el %d en el pasillo" % (i + 1))
		if i > 0:
			var d: float = pts[i].distance_to(pts[i - 1])
			assert_true(d >= 1.0 and d <= 2.0, "en serpentina, a %.1f m del de adelante" % d)


func test_corridor_keeps_360_security() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(22, 26), Unit.Kind.INFANTRY)
	sq.mind.autonomy = SquadMind.Autonomy.STRICT
	assert_true(world.order_clear(sq.id, Vector2(104, 104)), "orden aceptada")
	world.begin_execute()
	var checked: bool = false
	for i: int in 900:
		world.step()
		if world.phase != SimWorld.Phase.EXECUTE:
			world.begin_execute()
		if str(sq.clear.get("phase", "")) == "dominate" and int(sq.clear["step"]) == 0:
			checked = true
			for deg: int in range(0, 360, 30):
				var dir: Vector2 = Vector2.RIGHT.rotated(deg_to_rad(float(deg)))
				var covered: bool = false
				for s: Soldier in sq.soldiers:
					if s.cqb_role >= 0 and s.is_ok() and rad_to_deg(absf(s.sector_dir.angle_to(dir))) <= s.sector_half_deg:
						covered = true
				assert_true(covered, "alguien cubre los %d°" % deg)
			break
	assert_true(checked, "entraron al pasillo")
	for i: int in 2000:
		world.step()
		if world.phase != SimWorld.Phase.EXECUTE:
			world.begin_execute()
		if sq.clear.is_empty():
			break
	assert_eq(int(world.cleared_houses.get(0, -1)), 0, "limpió el pasillo y los cuatro cuartos")
