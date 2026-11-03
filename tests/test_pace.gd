extends TestBase
## Tests del ritmo de marcha, el asalto y la retirada.

const N: int = 96


## Mundo llano sin IA con solo los tanques indicados vivos.
func _world(alive_ids: Array[int]) -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = alive_ids.has(u.id)
	return world


## Celdas recorridas por el azul 0 hacia el norte en ticks ticks, al ritmo dado.
func _distance_at_pace(pace: int, ticks: int) -> float:
	var ids: Array[int] = [0, 4]
	var world: SimWorld = _world(ids)
	var u: Unit = world.units[0]
	u.pos = Vector2(48, 80)
	world.units[4].pos = Vector2(5, 5)
	world.set_pace(0, pace)
	world.order_move(0, Vector2i(48, 20))
	world.begin_execute()
	for i: int in ticks:
		world.step()
	return 80.0 - u.pos.y


func test_fast_is_faster_and_cautious_slower() -> void:
	var normal: float = _distance_at_pace(Unit.Pace.NORMAL, 50)
	var fast: float = _distance_at_pace(Unit.Pace.FAST, 50)
	var cautious: float = _distance_at_pace(Unit.Pace.CAUTIOUS, 50)
	assert_true(fast > normal * 1.3, "rápido: %.1f vs %.1f celdas" % [fast, normal])
	assert_true(cautious < normal * 0.6, "cauto: %.1f vs %.1f celdas" % [cautious, normal])


func test_cautious_not_spotted_far() -> void:
	# A 280 m: en movimiento normal se lo detecta; cauto, como si estuviera quieto (220 m)
	for pace: int in [Unit.Pace.NORMAL, Unit.Pace.CAUTIOUS]:
		var ids: Array[int] = [0, 4]
		var world: SimWorld = _world(ids)
		world.units[0].pos = Vector2(48, 90)
		world.units[4].pos = Vector2(48, 20) # 70 celdas = 280 m
		world.units[4].reload_left = 1000.0
		world.units[0].reload_left = 1000.0
		world.set_pace(0, pace)
		world.order_move(0, Vector2i(10, 90)) # de costado, sin acercarse
		world.begin_execute()
		for i: int in 10:
			world.step()
		var seen: bool = world.visible_enemies[1].has(0)
		if pace == Unit.Pace.NORMAL:
			assert_true(seen, "normal en movimiento: detectado a 280 m")
		else:
			assert_true(not seen, "cauto: no detectado a 280 m")


func test_fast_shooter_fires_worse() -> void:
	var ids: Array[int] = [0, 4]
	var world: SimWorld = _world(ids)
	var u: Unit = world.units[0]
	u.pos = Vector2(48, 60)
	world.units[4].pos = Vector2(48, 40)
	u.moving = true
	var normal: float = world.hit_probability(u, world.units[4])
	u.pace = Unit.Pace.FAST
	var fast: float = world.hit_probability(u, world.units[4])
	u.pace = Unit.Pace.CAUTIOUS
	var cautious: float = world.hit_probability(u, world.units[4])
	assert_lt(fast, normal, "rápido tira peor")
	assert_lt(normal, cautious, "cauto tira mejor que normal en marcha")


func test_assault_does_not_stop_on_line_of_fire() -> void:
	var ids: Array[int] = [0, 4]
	var world: SimWorld = _world(ids)
	world.p_hit_base = 0.0
	var u: Unit = world.units[0]
	u.pos = Vector2(48, 80)
	world.units[4].pos = Vector2(48, 40)
	world.units[4].reload_left = 1000.0
	world.update_detection()
	assert_true(world.order_assault(0, Vector2i(48, 50)), "asalto aceptado")
	assert_eq(SimWorld.effective_pace(u), Unit.Pace.FAST, "el asalto va rápido")
	world.begin_execute()
	for i: int in 200:
		world.step()
	assert_eq(u.cell(), Vector2i(48, 50), "llegó al objetivo del asalto")
	var shots: int = 0
	for e: Dictionary in world.shot_events:
		if int(e["shooter"]) == 0:
			shots += 1
	assert_true(shots > 0, "disparó en marcha")
	assert_eq(u.order, Unit.Order.NONE, "la orden terminó al llegar")


func test_withdraw_reverses_to_cover_facing_threat() -> void:
	var hf: HeightField = HeightField.new(N)
	# Pared de 10 m en y = 70, de x = 36 a 60: detrás (y > 70) no lo ven desde el norte
	for x: int in range(36, 61):
		hf.set_height(Vector2i(x, 70), 10.0)
	var world: SimWorld = SimWorld.new(7, hf, false)
	for u: Unit in world.units:
		u.alive = u.id == 0 or u.id == 4
	var u: Unit = world.units[0]
	u.pos = Vector2(48, 66)
	u.heading = Vector2(0.0, -1.0) # mirando al norte, hacia el rojo
	world.units[4].pos = Vector2(48, 30)
	world.units[4].reload_left = 1000.0
	world.update_detection()
	world.invalidate_exposure()
	assert_true(world.order_withdraw(0), "retirada aceptada")
	var dest: Vector2i = world.destination(u)
	assert_true(dest.y > 70, "va detrás de la pared (%s)" % dest)
	world.begin_execute()
	var max_turn: float = 0.0
	for i: int in 900:
		world.step()
		if u.moving:
			max_turn = maxf(max_turn, u.heading.angle_to(Vector2(0.0, -1.0)))
	assert_true(not u.moving, "llegó")
	assert_true(absf(max_turn) < 0.01, "en reversa no giró el casco")
	assert_true(u.heading.dot(Vector2(0.0, -1.0)) > 0.9, "termina mirando al rojo")
