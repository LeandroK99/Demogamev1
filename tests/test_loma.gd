extends TestBase
## Tests del escenario "La loma" y del pelotón mixto.


func _loma() -> SimWorld:
	return SimWorld.new(1337, null, false, SimWorld.Scenario.LOMA)


func test_loma_deploys_mixed_platoons() -> void:
	var world: SimWorld = _loma()
	for side: int in 2:
		var inf: int = 0
		var tanks: int = 0
		for u: Unit in world.units:
			if u.side == side:
				if u.is_infantry():
					inf += 1
				else:
					tanks += 1
		assert_eq(inf, Config.LOMA_SQUADS, "escuadras del bando %d" % side)
		assert_eq(tanks, Config.LOMA_TANKS, "tanques del bando %d" % side)
		var p: Platoon = world.platoons[side]
		assert_eq(p.sections.size(), 2, "dos secciones: infantería y tanques")
	assert_eq(world.ticks_per_turn, roundi(Config.LOMA_TURN_SECONDS / Config.TICK), "turnos de 45 s")
	assert_true(world.cover != null, "hay cobertura")


func test_red_defends_the_crest() -> void:
	var world: SimWorld = _loma()
	var hf: HeightField = world.height_field
	for u: Unit in world.units:
		if u.side != 1:
			continue
		var ry: float = hf.ridge_center_y(u.pos.x)
		assert_true(u.pos.y < ry and u.pos.y > ry - 15.0, "rojo %d detrás de la cresta (y %.0f, eje %.0f)" % [u.id, u.pos.y, ry])
		assert_true(world.pathfinders[u.kind].is_walkable(u.cell()), "en celda transitable")


func test_reverse_slope_forest() -> void:
	var world: SimWorld = _loma()
	var hf: HeightField = world.height_field
	var x: int = Config.LOMA_FOREST_X_STEP / 2
	var ry: int = roundi(hf.ridge_center_y(float(x)))
	assert_true(world.cover.is_forest(Vector2i(x, ry - Config.LOMA_FOREST_FROM)), "bosque en la contrapendiente")


func test_mixed_platoon_tank_stays_behind() -> void:
	var world: SimWorld = _loma()
	var target: Vector2i = Vector2i(48, 70)
	assert_true(world.order_platoon_move(0, target), "orden aceptada")
	var tank: Unit = null
	var inf_d: float = 0.0
	for u: Unit in world.units:
		if u.side != 0:
			continue
		var d: float = Vector2(world.destination(u)).distance_to(Vector2(target))
		if u.is_infantry():
			inf_d = maxf(inf_d, d)
		else:
			tank = u
	var tank_d: float = Vector2(world.destination(tank)).distance_to(Vector2(target))
	assert_true(tank_d > inf_d + 3.0, "el tanque queda detrás (%.1f vs %.1f)" % [tank_d, inf_d])
	assert_true(world.destination(tank).y > target.y, "detrás, del lado azul")


func test_tank_scenario_unchanged() -> void:
	var world: SimWorld = SimWorld.new(1337, null, false)
	assert_eq(world.units.size(), Config.UNITS_PER_SIDE * 2, "4 tanques por bando")
	assert_true(world.cover == null, "sin cobertura")
	assert_eq(world.ticks_per_turn, roundi(Config.TURN_SECONDS / Config.TICK), "turnos de 30 s")
