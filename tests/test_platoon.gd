extends TestBase
## Tests del pelotón: secciones, orden repartida y avance por saltos.

const N: int = 96


func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		if u.side == 1:
			u.alive = u.id == 4
	world.units[4].pos = Vector2(48, 2)
	world.units[4].reload_left = 1000.0
	world.update_detection()
	return world


func test_platoons_have_two_sections() -> void:
	var world: SimWorld = _world()
	assert_eq(world.platoons.size(), 2, "un pelotón por bando")
	var p: Platoon = world.platoons[0]
	assert_eq(p.sections.size(), 2, "dos secciones")
	assert_eq(p.sections[0], PackedInt32Array([0, 1]), "sección A")
	assert_eq(p.sections[1], PackedInt32Array([2, 3]), "sección B")
	assert_eq(world.platoon_of(6).side, 1, "el tanque 6 es del pelotón rojo")


func test_platoon_move_spreads_sections() -> void:
	var world: SimWorld = _world()
	assert_true(world.order_platoon_move(0, Vector2i(48, 70)), "orden aceptada")
	var dest: Array[Vector2i] = []
	for uid: int in 4:
		dest.append(world.destination(world.units[uid]))
	var within: float = Vector2(dest[0]).distance_to(Vector2(dest[1]))
	var between: float = Vector2(dest[1]).distance_to(Vector2(dest[2]))
	assert_true(within <= Config.FORMATION_GAP + 0.5, "dentro de la sección: %.1f" % within)
	assert_true(between > within + 2.0, "entre secciones hay más espacio: %.1f" % between)
	for i: int in 4:
		for j: int in range(i + 1, 4):
			assert_true(dest[i] != dest[j], "destinos distintos")


func test_platoon_move_skips_dead() -> void:
	var world: SimWorld = _world()
	world.units[2].alive = false
	assert_true(world.order_platoon_move(0, Vector2i(48, 70)), "orden aceptada")
	assert_true(world.units[2].path.is_empty(), "el muerto no recibe orden")
	assert_true(not world.units[3].path.is_empty(), "el resto sí")


func test_bounding_overwatch() -> void:
	var world: SimWorld = _world()
	# La sección B (2, 3) más cerca del objetivo, al este
	assert_true(world.order_platoon_bound(0, Vector2i(70, 75)), "avance por saltos aceptado")
	var b_first: Array[int] = [2, 3]
	var a_second: Array[int] = [0, 1]
	world.begin_execute()
	var first_done_tick: int = -1
	var second_start_tick: int = -1
	var start_pos: Vector2 = world.units[0].pos
	for i: int in 600:
		world.step()
		if first_done_tick < 0 and world.units[2].path.is_empty() and world.units[3].path.is_empty():
			first_done_tick = world.total_ticks
		if second_start_tick < 0 and world.units[0].pos != start_pos:
			second_start_tick = world.total_ticks
	assert_true(first_done_tick > 0, "la primera sección llegó")
	assert_true(second_start_tick >= first_done_tick, "la segunda arrancó cuando llegó la primera (%d >= %d)" % [second_start_tick, first_done_tick])
	for uid: int in a_second + b_first:
		assert_true(world.units[uid].path.is_empty(), "el tanque %d llegó" % uid)
