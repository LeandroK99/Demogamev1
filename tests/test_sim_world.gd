extends TestBase
## Tests de SimWorld: determinismo, detección y combate.

const N: int = 96


func _flat_world(sim_seed: int = 7) -> SimWorld:
	return SimWorld.new(sim_seed, HeightField.new(N))


## Mapa llano con una pared de 10 m de alto a lo ancho, entre los dos despliegues.
func _walled_world() -> SimWorld:
	var hf: HeightField = HeightField.new(N)
	for x: int in N:
		hf.set_height(Vector2i(x, N / 2), 10.0)
	return SimWorld.new(7, hf)


func _run_scenario(world: SimWorld) -> void:
	# Azules avanzan al norte cruzando la cresta; un turno completo
	for u: Unit in world.units:
		if u.side == 0:
			world.order_move(u.id, u.cell() + Vector2i(0, -40))
	world.begin_execute()
	for i: int in world.ticks_per_turn:
		world.step()


func test_determinism() -> void:
	var a: SimWorld = SimWorld.new(Config.SEED)
	var b: SimWorld = SimWorld.new(Config.SEED)
	_run_scenario(a)
	_run_scenario(b)
	var diffs: int = 0
	for i: int in a.units.size():
		if a.units[i].pos != b.units[i].pos or a.units[i].hp != b.units[i].hp:
			diffs += 1
	assert_eq(diffs, 0, "unidades distintas tras 300 ticks")
	assert_eq(a.turn, 2, "pasó al turno 2")
	assert_eq(a.phase, SimWorld.Phase.PLAN, "volvió a PLAN")


func test_detected_on_open_ground() -> void:
	# Control: sin pared, a 83 celdas (332 m) en el llano sí se ven
	var world: SimWorld = _flat_world()
	world.update_detection()
	assert_eq(world.visible_enemies[0].size(), 4, "azules ven a los 4 rojos")


func test_wall_hides_tank() -> void:
	var world: SimWorld = _walled_world()
	world.update_detection()
	assert_eq(world.visible_enemies[0].size(), 0, "azules no ven a nadie detrás de la pared")
	assert_eq(world.visible_enemies[1].size(), 0, "rojos no ven a nadie detrás de la pared")
	assert_true(world.threats_for(0).is_empty(), "sin amenazas conocidas")


func test_visible_target_takes_damage() -> void:
	var world: SimWorld = _flat_world()
	world.p_hit_base = 1.0
	world.hulldown_hit_factor = 1.0
	world.moving_shooter_factor = 1.0
	# Duelo aislado: un azul y un rojo pegados (factor de distancia ~1)
	for u: Unit in world.units:
		u.alive = u.id == 0 or u.id == 4
	var shooter: Unit = world.units[0]
	var target: Unit = world.units[4]
	target.pos = shooter.pos + Vector2(0.0, -1.0)
	target.reload_left = 100.0 # el rojo no dispara
	world.update_detection()
	world.begin_execute()
	world.step()
	assert_eq(target.hp, Config.TANK_HP - 1, "el blanco perdió 1 hp")
	assert_eq(target.shots_received, 1, "disparo registrado")
	assert_true(shooter.reload_left > Config.RELOAD_SECONDS - 0.2, "el tirador está recargando")


func test_orders_only_in_plan() -> void:
	var world: SimWorld = _flat_world()
	world.begin_execute()
	assert_true(not world.order_move(0, Vector2i(48, 60)), "orden rechazada en EXECUTE")


func test_last_side_standing_wins() -> void:
	var world: SimWorld = _flat_world()
	for u: Unit in world.units:
		if u.side == 1:
			u.alive = false
	world.begin_execute()
	world.step()
	assert_true(world.game_over, "terminó la partida")
	assert_eq(world.winner, 0, "ganó azul")
