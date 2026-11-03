extends TestBase
## Tests de la capa de edificios (fase 60): paredes, ventanas, puertas, techo y rutas por adentro.

const N: int = 64


## Casa de 10 x 8 m (micro-celdas 100..109 x 100..107): puerta al sur en (104, 107), ventana al
## norte en (104, 100). En metros: de x 98 a 108, y de 98 a 106.
func _world() -> Array:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 4
	world.units[4].pos = Vector2(2, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	world.set_micro(MicroCover.new(N))
	var bm: BuildingMap = BuildingMap.new(N)
	var doors: Array[Vector2i] = [Vector2i(104, 107)]
	var windows: Array[Vector2i] = [Vector2i(104, 100)]
	bm.add_house(Rect2i(100, 100, 10, 8), doors, windows)
	world.set_buildings(bm)
	return [world, bm]


func _m(c: Vector2i) -> Vector2:
	return MicroCover.center_m(c)


func test_wall_blocks_sight_window_does_not() -> void:
	var r: Array = _world()
	var world: SimWorld = r[0]
	var inside: Vector2 = _m(Vector2i(104, 103))
	var la: TerrainAnalysis = world.analysis
	assert_true(not la.los_m(_m(Vector2i(90, 103)), 1.6, inside, 1.6), "por la pared del oeste no se ve")
	assert_true(la.los_m(_m(Vector2i(104, 90)), 1.6, inside, 1.6), "por la ventana del norte sí")
	assert_true(not la.los_m(_m(Vector2i(104, 90)), 0.4, inside, 0.4), "por debajo del antepecho no")
	assert_true(la.los_m(_m(Vector2i(104, 115)), 1.6, inside, 1.6), "por la puerta abierta sí")
	assert_true(la.los_m(_m(Vector2i(90, 90)), 1.6, _m(Vector2i(120, 90)), 1.6), "al lado de la casa, nada")


func test_roof_blocks_from_above_but_not_over() -> void:
	var r: Array = _world()
	var world: SimWorld = r[0]
	var inside: Vector2 = _m(Vector2i(104, 103))
	assert_true(not world.analysis.los_m(_m(Vector2i(104, 60)), 40.0, inside, 1.0), "desde muy alto, el techo tapa")
	assert_true(world.analysis.los_m(_m(Vector2i(90, 103)), 6.0, _m(Vector2i(120, 103)), 6.0), "por encima del techo se ve")


func test_cell_los_for_tanks_too() -> void:
	var r: Array = _world()
	var world: SimWorld = r[0]
	# celdas de 4 m a los dos lados de la casa (x 98..108 m = celdas 24.5..27)
	assert_true(not world.analysis.los(Vector2i(20, 25), Config.HULL_H, Vector2i(32, 25), Config.HULL_H), "la casa tapa al tanque")


func test_soldier_behind_wall_is_protected() -> void:
	var r: Array = _world()
	var world: SimWorld = r[0]
	var sq: Unit = world.add_unit(0, Vector2(26, 25), Unit.Kind.INFANTRY)
	var s: Soldier = sq.soldiers[0]
	s.pos = _m(Vector2i(101, 103)) # pegado a la pared del oeste, adentro
	s.posture = Soldier.Posture.CROUCH
	assert_true(InfantrySim.is_protected_from(world, s, _m(Vector2i(80, 103))), "la pared lo protege")
	s.pos = _m(Vector2i(104, 101)) # detrás de la ventana
	assert_true(InfantrySim.is_protected_from(world, s, _m(Vector2i(104, 80))), "agachado bajo el antepecho, protegido")
	s.posture = Soldier.Posture.STAND
	assert_true(not InfantrySim.is_protected_from(world, s, _m(Vector2i(104, 80))), "parado en la ventana, no")


func test_route_goes_through_the_door() -> void:
	var r: Array = _world()
	var bm: BuildingMap = r[1]
	var from: Vector2 = _m(Vector2i(104, 90)) # afuera, al norte (la ventana no es puerta)
	var to: Vector2 = _m(Vector2i(104, 103))
	assert_true(bm.crosses(from, to), "derecho atraviesa la pared")
	var path: PackedVector2Array = bm.route(from, to)
	assert_true(not path.is_empty(), "hay ruta")
	var prev: Vector2 = from
	var by_door: bool = false
	for p: Vector2 in path:
		assert_true(not bm.crosses(prev, p), "ningún tramo atraviesa paredes")
		prev = p
	prev = from
	for p: Vector2 in path:
		for k: int in 21:
			if prev.lerp(p, k / 20.0).distance_to(_m(Vector2i(104, 107))) < 0.8:
				by_door = true
		prev = p
	assert_true(by_door, "pasa por la puerta")
	assert_eq(path[path.size() - 1], to, "termina en el destino")


func test_squad_walks_in_through_the_door() -> void:
	var r: Array = _world()
	var world: SimWorld = r[0]
	var bm: BuildingMap = r[1]
	var sq: Unit = world.add_unit(0, Vector2(26, 22), Unit.Kind.INFANTRY) # 10 m al norte
	sq.mind.autonomy = SquadMind.Autonomy.STRICT
	sq.formation = Unit.Formation.FILE
	sq.snap_soldiers()
	world.order_move(sq.id, Vector2i(26, 26)) # adentro de la casa
	world.begin_execute()
	var walls: int = 0
	for i: int in 600:
		world.step()
		for s: Soldier in sq.soldiers:
			if not bm.walkable_m(s.pos):
				walls += 1
	assert_eq(walls, 0, "nadie pisó una pared ni pasó por la ventana")
	var inside: int = 0
	for s: Soldier in sq.soldiers:
		if bm.inside_m(s.pos):
			inside += 1
	assert_lt(0.5, float(inside), "entraron (%d adentro)" % inside)


func test_tank_does_not_drive_through_houses() -> void:
	var r: Array = _world()
	var world: SimWorld = r[0]
	var bm: BuildingMap = r[1]
	var pf: Pathfinder = world.pathfinders[Unit.Kind.TANK]
	for c: Vector2i in bm.footprint_cells():
		assert_true(not pf.is_walkable(c), "celda %s bloqueada para el tanque" % c)
	assert_true(world.pathfinders[Unit.Kind.INFANTRY].is_walkable(Vector2i(26, 25)), "la infantería sí puede")
