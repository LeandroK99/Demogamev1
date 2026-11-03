extends TestBase
## Tests de las reglas de fuego (ROE): retener, solo si te disparan, arco y distancia máxima.

const N: int = 96


## Mundo llano sin IA: azul 0 en (48, 60) y rojo 4 a dist celdas al norte; el rojo no recarga.
func _duel(dist: int = 20) -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 0 or u.id == 4
	world.units[0].pos = Vector2(48, 60)
	world.units[4].pos = Vector2(48, 60 - dist)
	world.units[4].reload_left = 1000.0
	world.update_detection()
	return world


func _shots_by(world: SimWorld, shooter: int) -> int:
	var n: int = 0
	for e: Dictionary in world.shot_events:
		if int(e["shooter"]) == shooter:
			n += 1
	return n


func _run(world: SimWorld, ticks: int) -> void:
	world.begin_execute()
	for i: int in ticks:
		world.step()


func test_free_fire_shoots() -> void:
	var world: SimWorld = _duel()
	world.p_hit_base = 0.0
	_run(world, 20)
	assert_true(_shots_by(world, 0) > 0, "con fuego libre dispara")


func test_hold_fire_never_shoots() -> void:
	var world: SimWorld = _duel()
	world.p_hit_base = 0.0
	assert_true(world.set_roe(0, Unit.Roe.HOLD), "ROE aceptada")
	_run(world, 100)
	assert_eq(_shots_by(world, 0), 0, "retener fuego: no dispara")


func test_return_fire_waits_until_shot_at() -> void:
	var world: SimWorld = _duel()
	world.p_hit_base = 0.0 # sin bajas
	world.set_roe(0, Unit.Roe.RETURN_FIRE)
	_run(world, 50)
	assert_eq(_shots_by(world, 0), 0, "no abre fuego por su cuenta")
	world.units[4].reload_left = 0.0 # el rojo tira
	for i: int in 3:
		world.step()
	assert_true(_shots_by(world, 4) > 0, "el rojo disparó")
	for i: int in 3:
		world.step()
	assert_true(_shots_by(world, 0) > 0, "devuelve el fuego")


func test_fire_arc_filters_targets() -> void:
	var world: SimWorld = _duel()
	world.p_hit_base = 0.0
	world.set_engagement(0, Vector2(1.0, 0.0)) # arco hacia el este; el rojo está al norte
	_run(world, 50)
	assert_eq(_shots_by(world, 0), 0, "fuera del arco no tira")
	world.phase = SimWorld.Phase.PLAN
	world.set_engagement(0, Vector2(0.2, -1.0))
	_run(world, 5)
	assert_true(_shots_by(world, 0) > 0, "dentro del arco tira")


func test_max_engage_range() -> void:
	var world: SimWorld = _duel(30) # 120 m
	world.p_hit_base = 0.0
	world.set_engagement(0, Vector2.ZERO, 100.0)
	_run(world, 50)
	assert_eq(_shots_by(world, 0), 0, "a 120 m con tope de 100 m no tira")
	world.phase = SimWorld.Phase.PLAN
	world.set_engagement(0, Vector2.ZERO, 150.0)
	_run(world, 5)
	assert_true(_shots_by(world, 0) > 0, "con tope de 150 m tira")


func test_roe_survives_new_orders() -> void:
	var world: SimWorld = _duel()
	world.set_roe(0, Unit.Roe.HOLD)
	world.set_engagement(0, Vector2(1.0, 0.0), 120.0)
	world.order_move(0, Vector2i(40, 60))
	world.order_overwatch(0, Vector2(0.0, -1.0))
	var u: Unit = world.units[0]
	assert_eq(u.roe, Unit.Roe.HOLD, "la ROE sigue")
	assert_true(u.fire_arc_dir.is_equal_approx(Vector2(1.0, 0.0)), "el arco sigue")
	assert_eq(u.max_engage_m, 120.0, "la distancia sigue")


func test_roe_only_in_plan() -> void:
	var world: SimWorld = _duel()
	world.begin_execute()
	assert_true(not world.set_roe(0, Unit.Roe.HOLD), "no se cambia la ROE ejecutando")
	assert_true(not world.set_engagement(0, Vector2(1.0, 0.0)), "ni el arco")
