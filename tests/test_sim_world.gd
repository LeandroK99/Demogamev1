extends TestBase
## Tests de SimWorld: determinismo, detección y combate.

const N: int = 96


func _flat_world(sim_seed: int = 7) -> SimWorld:
	return SimWorld.new(sim_seed, HeightField.new(N), false)


## Mapa llano con una pared de 10 m de alto a lo ancho, entre los dos despliegues.
func _walled_world() -> SimWorld:
	var hf: HeightField = HeightField.new(N)
	for x: int in N:
		hf.set_height(Vector2i(x, N / 2), 10.0)
	return SimWorld.new(7, hf, false)


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
	# Control: sin pared, a 83 celdas (332 m) en el llano se ven si se mueven
	var world: SimWorld = _flat_world()
	for u: Unit in world.units:
		u.moving = true
	world.update_detection()
	assert_eq(world.visible_enemies[0].size(), 4, "azules ven a los 4 rojos en movimiento")


func test_stationary_not_spotted_far() -> void:
	# Quietos a 332 m: fuera de SPOT_RANGE_STATIONARY, nadie ve a nadie
	var world: SimWorld = _flat_world()
	world.update_detection()
	assert_eq(world.visible_enemies[0].size(), 0, "rojos quietos a 332 m no se detectan")
	# A 200 m, quieto y con el casco a la vista: sí
	world.units[4].pos = world.units[0].pos + Vector2(0.0, -50.0)
	world.update_detection()
	assert_true(world.visible_enemies[0].has(4), "rojo quieto a 200 m detectado")


func test_firing_reveals_shooter() -> void:
	# Un rojo detrás de la pared le dispara a un azul visible (por ejemplo, gracias a otro rojo):
	# el azul no lo ve, pero queda como fantasma en known_enemies.
	var world: SimWorld = _flat_world()
	for u: Unit in world.units:
		u.alive = u.id == 0 or u.id == 4
	var blue: Unit = world.units[0]
	var red: Unit = world.units[4]
	red.pos = blue.pos + Vector2(0.0, -70.0) # 280 m, quieto: el azul no lo detecta
	blue.moving = true # el rojo sí detecta al azul en movimiento
	world.update_detection()
	assert_true(world.visible_enemies[1].has(0), "el rojo ve al azul que se mueve")
	assert_true(not world.visible_enemies[0].has(4), "el azul no ve al rojo quieto")
	world.known_enemies[0].clear()
	world.begin_execute()
	world._combat()
	assert_true(world.known_enemies[0].has(4), "el fogonazo delata al rojo")
	assert_true(world.recently_fired(red), "recién disparó")
	world.update_detection()
	assert_true(world.visible_enemies[0].has(4), "recién disparado se lo detecta a 280 m")


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
	world.armor_enabled = false
	world.p_hit_max = 1.0
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


## Mundo llano sin IA, con el azul 0 y el rojo 4 vivos frente a frente a 20 celdas.
func _duel_world() -> SimWorld:
	var world: SimWorld = SimWorld.new(3, HeightField.new(96), false)
	for u: Unit in world.units:
		u.alive = u.id == 0 or u.id == 4
	world.units[0].pos = Vector2(48, 60)
	world.units[4].pos = Vector2(48, 40)
	return world


func test_armor_front_flank_rear() -> void:
	var world: SimWorld = _duel_world()
	var shooter: Unit = world.units[0]
	var target: Unit = world.units[4]
	target.heading = Vector2(0.0, 1.0) # mira al tirador (sur)
	var p_front: float = world.hit_probability(shooter, target)
	target.heading = Vector2(1.0, 0.0)
	var p_flank: float = world.hit_probability(shooter, target)
	target.heading = Vector2(0.0, -1.0) # le da la espalda
	var p_rear: float = world.hit_probability(shooter, target)
	assert_lt(p_front, p_flank, "frente < flanco")
	assert_lt(p_flank, p_rear, "flanco < retaguardia")
	assert_eq(SimWorld.aspect_of(target, shooter.pos), SimWorld.Aspect.REAR, "cara trasera")


func test_hulldown_faces_threat() -> void:
	var world: SimWorld = _duel_world()
	var blue: Unit = world.units[0]
	world.known_enemies[0][4] = {"cell": Vector2i(48, 20), "last_seen_turn": world.turn}
	world.invalidate_exposure()
	world.order_hulldown([0])
	assert_true(blue.final_heading.dot(Vector2(0.0, -1.0)) > 0.9, "va a mirar al norte, hacia la amenaza (%s)" % blue.final_heading)
