extends TestBase
## Tests del escenario "El pueblo" (fase 61).


func _pueblo(sim_seed: int = 1337) -> SimWorld:
	return SimWorld.new(sim_seed, null, true, SimWorld.Scenario.PUEBLO)


func test_town_has_8_to_12_houses_without_overlap() -> void:
	var world: SimWorld = _pueblo()
	var bm: BuildingMap = world.buildings
	assert_true(bm != null, "hay casas")
	assert_lt(7.5, float(bm.houses.size()), "al menos 8 casas")
	assert_lt(float(bm.houses.size()), 12.5, "a lo sumo 12")
	for i: int in bm.houses.size():
		for j: int in range(i + 1, bm.houses.size()):
			assert_true(not bm.houses[i].grow(1).intersects(bm.houses[j]), "las casas %d y %d no se tocan" % [i, j])


func test_every_room_reachable_from_the_plaza() -> void:
	for sim_seed: int in [1337, 1001, 42]:
		var world: SimWorld = _pueblo(sim_seed)
		var bm: BuildingMap = world.buildings
		var plaza: Vector2 = Vector2(world.objective_cell()) * Config.CELL_SIZE
		for r: Rect2i in bm.houses:
			# un punto de piso en cada cuarto de la casa: las cuatro esquinas interiores
			for corner: Vector2i in [r.position + Vector2i(1, 1), Vector2i(r.end.x - 2, r.position.y + 1),
					Vector2i(r.position.x + 1, r.end.y - 2), r.end - Vector2i(2, 2)]:
				var p: Vector2 = MicroCover.center_m(corner)
				assert_eq(bm.type_at(corner), BuildingMap.Type.FLOOR, "esquina de piso")
				var path: PackedVector2Array = bm.route(plaza, p)
				assert_true(not path.is_empty() and path[path.size() - 1].distance_to(p) < 1.0,
					"semilla %d: se llega a %s" % [sim_seed, corner])


func test_red_squads_start_inside_houses_tank_outside() -> void:
	var world: SimWorld = _pueblo()
	var bm: BuildingMap = world.buildings
	for u: Unit in world.units:
		if u.side != 1:
			continue
		if u.is_infantry():
			assert_true(bm.house_at_m(u.pos_m()) >= 0, "escuadra roja %d en una casa" % u.id)
		else:
			assert_true(world.pathfinders[Unit.Kind.TANK].is_walkable(u.cell()), "el tanque rojo en la calle")


func test_town_is_flat_and_objective_is_plaza() -> void:
	var world: SimWorld = _pueblo()
	var hf: HeightField = world.height_field
	var c: Vector2i = world.objective_cell()
	assert_eq(c, Vector2i(hf.size / 2, hf.size / 2), "la plaza en el centro")
	var h: float = hf.height_at_cell(c)
	for d: Vector2i in [Vector2i(10, 0), Vector2i(-10, 5), Vector2i(0, -12)]:
		assert_lt(absf(hf.height_at_cell(c + d) - h), 0.01, "plano en %s" % d)
	assert_eq(world.ticks_per_turn, roundi(Config.LOMA_TURN_SECONDS / Config.TICK), "turnos de 45 s")
