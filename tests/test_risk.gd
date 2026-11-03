extends TestBase
## Tests de la vista previa de riesgo de la ruta.

const N: int = 96


## Llano con una pared de 10 m en y = 50, de x = 20 a 76; azul 0 al sur y rojo 4 al norte, conocido.
func _world() -> SimWorld:
	var hf: HeightField = HeightField.new(N)
	for x: int in range(20, 77):
		hf.set_height(Vector2i(x, 50), 10.0)
	var world: SimWorld = SimWorld.new(7, hf, false)
	for u: Unit in world.units:
		u.alive = u.id == 0 or u.id == 4
	world.units[4].pos = Vector2(48, 20)
	world.known_enemies[0][4] = {"cell": Vector2i(48, 20), "last_seen_turn": world.turn}
	world.invalidate_exposure()
	return world


func test_no_route_no_risk() -> void:
	var world: SimWorld = _world()
	var r: Dictionary = world.route_risk(0)
	assert_eq(r["level"], 0, "sin ruta, riesgo bajo")
	assert_eq(r["total_s"], 0.0, "sin tiempo")


func test_hidden_route_is_safe() -> void:
	var world: SimWorld = _world()
	var u: Unit = world.units[0]
	u.pos = Vector2(40, 56) # detrás de la pared
	world.order_move(0, Vector2i(56, 56), Vector2.ZERO, false)
	var r: Dictionary = world.route_risk(0)
	assert_true(float(r["total_s"]) > 5.0, "la ruta tarda (%.1f s)" % r["total_s"])
	assert_eq(r["exposed_s"], 0.0, "nunca expuesto")
	assert_eq(r["worst_aspect"], -1, "nunca lo ven")
	assert_eq(r["level"], 0, "riesgo bajo")


func test_open_route_toward_threat_is_risky() -> void:
	var world: SimWorld = _world()
	var u: Unit = world.units[0]
	u.pos = Vector2(10, 46) # delante de la pared, a la vista
	world.order_move(0, Vector2i(10, 30), Vector2.ZERO, false)
	var r: Dictionary = world.route_risk(0)
	assert_true(float(r["exposed_s"]) > 0.9 * float(r["total_s"]), "expuesto casi todo el tiempo")
	assert_true(float(r["expected_hits"]) > 0.0, "impactos esperados > 0")
	assert_eq(r["threats_seeing"], 1, "lo ve una amenaza")
	assert_true(int(r["level"]) >= 1, "riesgo medio o alto (%.2f impactos)" % r["expected_hits"])


func test_driving_away_shows_rear_but_withdraw_shows_front() -> void:
	var world: SimWorld = _world()
	var u: Unit = world.units[0]
	u.pos = Vector2(48, 30)
	u.heading = Vector2(0.0, -1.0)
	world.order_move(0, Vector2i(48, 38), Vector2.ZERO, false) # se aleja del rojo de frente al sur
	assert_eq(world.route_risk(0)["worst_aspect"], SimWorld.Aspect.REAR, "yéndose de frente muestra la cola")
	world.order_withdraw(0, Vector2i(48, 38))
	assert_true(u.reversing, "retirada en reversa")
	assert_eq(world.route_risk(0)["worst_aspect"], SimWorld.Aspect.FRONT, "en reversa muestra el frente")


func test_cautious_pace_lowers_exposure() -> void:
	var world: SimWorld = _world()
	var u: Unit = world.units[0]
	world.units[4].pos = Vector2(48, 2)
	world.known_enemies[0][4] = {"cell": Vector2i(48, 2), "last_seen_turn": world.turn}
	world.invalidate_exposure()
	u.pos = Vector2(90, 46) # a ~245 m del rojo: más lejos que la detección de un tanque quieto
	world.order_move(0, Vector2i(90, 40), Vector2.ZERO, false)
	var normal: Dictionary = world.route_risk(0)
	world.set_pace(0, Unit.Pace.CAUTIOUS)
	var cautious: Dictionary = world.route_risk(0)
	assert_true(float(normal["exposed_s"]) > 0.0, "a ritmo normal lo ven")
	assert_lt(float(cautious["expected_hits"]), float(normal["expected_hits"]), "cauto: menos riesgo")
