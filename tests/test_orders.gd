extends TestBase
## Tests de las órdenes de orientación final y de ataque.

const N: int = 96


## Mundo llano sin IA con solo los tanques indicados vivos.
func _world(alive_ids: Array[int]) -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = alive_ids.has(u.id)
	return world


func test_move_with_final_facing() -> void:
	var ids: Array[int] = [0, 4] # un rojo vivo para que la partida no termine
	var world: SimWorld = _world(ids)
	world.p_hit_base = 0.0
	var u: Unit = world.units[0]
	var facing: Vector2 = Vector2(1.0, 0.0) # mirar al este
	assert_true(world.order_move(0, u.cell() + Vector2i(0, -5), facing), "orden aceptada")
	for i: int in 60:
		world.step()
	assert_true(not u.moving, "llegó")
	assert_true(u.heading.is_equal_approx(facing), "quedó mirando al este (%s)" % u.heading)


func test_facing_only_rotates_in_place() -> void:
	var ids: Array[int] = [0, 4]
	var world: SimWorld = _world(ids)
	var u: Unit = world.units[0]
	assert_true(world.order_move(0, u.cell(), Vector2(-1.0, 0.0)), "orden aceptada")
	assert_true(u.heading.is_equal_approx(Vector2(-1.0, 0.0)), "gira sin moverse")


func test_attack_unknown_enemy_rejected() -> void:
	var ids: Array[int] = [0, 4]
	var world: SimWorld = _world(ids)
	world.known_enemies[0].clear()
	assert_true(not world.order_attack(0, 4), "no se puede atacar a un enemigo desconocido")


func test_attack_advances_until_line_of_fire() -> void:
	var ids: Array[int] = [0, 4]
	var world: SimWorld = _world(ids)
	world.p_hit_base = 0.0 # sin bajas: solo interesa el movimiento
	var blue: Unit = world.units[0]
	var red: Unit = world.units[4]
	# A 90 celdas (360 m): fuera de alcance, conocido como fantasma
	blue.pos = Vector2(48, 92)
	red.pos = Vector2(48, 2)
	world.update_detection()
	assert_true(not world.visible_enemies[0].has(4), "arranca sin verlo")
	world.known_enemies[0][4] = {"cell": red.cell(), "last_seen_turn": world.turn}
	assert_true(world.order_attack(0, 4), "orden aceptada")
	world.begin_execute()
	for i: int in 60:
		world.step()
	assert_eq(blue.order, Unit.Order.ATTACK, "sigue con la orden de ataque")
	assert_true(not blue.moving and blue.path.is_empty(), "frenó al tener línea de tiro")
	var d: float = TerrainAnalysis.dist_m(blue.cell(), red.cell())
	assert_true(d <= Config.MAX_RANGE and d > Config.MAX_RANGE - 3.0 * Config.CELL_SIZE, "frenó apenas entró en alcance (%.0f m)" % d)


func test_attack_target_has_priority() -> void:
	var ids: Array[int] = [0, 4, 5]
	var world: SimWorld = _world(ids)
	var blue: Unit = world.units[0]
	world.units[4].pos = blue.pos + Vector2(0.0, -10.0) # cerca
	world.units[5].pos = blue.pos + Vector2(0.0, -30.0) # lejos
	world.units[4].reload_left = 100.0
	world.units[5].reload_left = 100.0
	world.update_detection()
	assert_true(world.order_attack(0, 5), "orden aceptada")
	world.begin_execute()
	world.step()
	assert_eq(world.shot_events.size(), 1, "un disparo")
	assert_eq(int(world.shot_events[0]["target"]), 5, "le tiró al blanco ordenado, no al más cercano")


func test_attack_ends_when_target_dies() -> void:
	var ids: Array[int] = [0, 4]
	var world: SimWorld = _world(ids)
	world.units[4].moving = true # en movimiento se lo detecta a 332 m
	world.update_detection()
	assert_true(world.order_attack(0, 4), "orden aceptada")
	world.units[4].alive = false
	world.units[5].alive = true # para que la partida no termine
	world.begin_execute()
	world.step()
	assert_eq(world.units[0].order, Unit.Order.NONE, "la orden terminó")
	assert_eq(world.units[0].attack_target, -1, "sin blanco")


func test_waypoints_chain() -> void:
	var ids: Array[int] = [0, 4]
	var world: SimWorld = _world(ids)
	world.p_hit_base = 0.0
	var u: Unit = world.units[0]
	var a: Vector2i = u.cell() + Vector2i(0, -6)
	var b: Vector2i = a + Vector2i(6, 0)
	assert_true(world.order_move(0, a), "primer tramo")
	assert_true(world.order_move(0, b, Vector2.ZERO, false, true), "segundo tramo (directo, agregado)")
	assert_true(u.path.has(a), "la ruta pasa por el primer destino")
	assert_eq(u.path.back(), b, "termina en el segundo")
	assert_eq(u.waypoints.size(), 2, "dos tramos")
	assert_true(bool(u.waypoints[1]["direct"]), "el segundo tramo es directo")
	world.begin_execute()
	for i: int in 120:
		world.step()
	assert_eq(u.cell(), b, "llegó al final")
	assert_true(u.waypoints.is_empty(), "consumió los waypoints")


func test_move_without_append_replaces() -> void:
	var ids: Array[int] = [0, 4]
	var world: SimWorld = _world(ids)
	var u: Unit = world.units[0]
	var a: Vector2i = u.cell() + Vector2i(0, -6)
	assert_true(world.order_move(0, a), "primer tramo")
	assert_true(world.order_move(0, a + Vector2i(6, 0), Vector2.ZERO, true, true), "segundo tramo")
	var c: Vector2i = u.cell() + Vector2i(-5, 0)
	assert_true(world.order_move(0, c), "orden nueva sin Shift")
	assert_eq(u.path.back(), c, "la ruta nueva termina en c")
	assert_true(not u.path.has(a), "descartó los tramos anteriores")
	assert_eq(u.waypoints.size(), 1, "un solo tramo")


func test_overwatch_sector_limits_fire() -> void:
	var ids: Array[int] = [0, 4]
	var world: SimWorld = _world(ids)
	var blue: Unit = world.units[0]
	var red: Unit = world.units[4]
	red.pos = blue.pos + Vector2(20.0, 0.0) # al este, a 80 m
	red.reload_left = 100.0
	blue.reload_left = 5.0
	world.update_detection()
	assert_true(world.visible_enemies[0].has(4), "lo ve")
	assert_true(world.order_overwatch(0, Vector2(0.0, -1.0)), "vigila al norte")
	world.begin_execute()
	assert_eq(blue.reload_left, 0.0, "arranca con la recarga lista")
	world.step()
	assert_eq(world.shot_events.size(), 0, "no tira fuera del sector")
	world.phase = SimWorld.Phase.PLAN
	assert_true(world.order_overwatch(0, Vector2(1.0, 0.0)), "vigila al este")
	world.begin_execute()
	world.step()
	assert_eq(world.shot_events.size(), 1, "tira dentro del sector en el primer tick")


func test_overwatch_ambush_bonus() -> void:
	var ids: Array[int] = [0, 4]
	var world: SimWorld = _world(ids)
	world.p_hit_base = 0.3 # lejos del tope
	var blue: Unit = world.units[0]
	var red: Unit = world.units[4]
	red.pos = blue.pos + Vector2(0.0, -20.0)
	red.moving = true
	var p_normal: float = world.hit_probability(blue, red)
	assert_true(world.order_overwatch(0, Vector2(0.0, -1.0)), "vigila al norte")
	world.begin_execute()
	var p_ambush: float = world.hit_probability(blue, red)
	assert_true(is_equal_approx(p_ambush, p_normal * Config.OVERWATCH_FIRST_SHOT_FACTOR), "emboscada ×1,5 (%.3f vs %.3f)" % [p_ambush, p_normal])
	blue.overwatch_ready = false
	assert_true(is_equal_approx(world.hit_probability(blue, red), p_normal), "después del primer disparo, normal")
