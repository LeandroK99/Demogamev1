extends TestBase
## Tests de la IA y de la orden HULLDOWN sobre un mapa sintético:
## una loma de 6 m a lo ancho (y = 48) entre los dos despliegues.

const N: int = 96
const RIDGE_Y: int = 48


func _ridge_world() -> SimWorld:
	var hf: HeightField = HeightField.new(N)
	for y: int in N:
		for x: int in N:
			hf.set_height(Vector2i(x, y), maxf(0.0, 6.0 - absf(float(y - RIDGE_Y)) * 1.0))
	var world: SimWorld = SimWorld.new(7, hf, false)
	# Solo quedan un azul (en el sur) y un rojo, que está en la ladera expuesta
	for u: Unit in world.units:
		u.alive = u.id == 0 or u.id == 4
	world.units[4].pos = Vector2(44, 56)
	world.update_detection()
	return world


func _blue_known_by_red(world: SimWorld) -> void:
	var blue: Unit = world.units[0]
	world.known_enemies[1][blue.id] = {"cell": blue.cell(), "last_seen_turn": world.turn}
	world.invalidate_exposure()


func test_ai_picks_hulldown_cell() -> void:
	var world: SimWorld = _ridge_world()
	_blue_known_by_red(world)
	var red: Unit = world.units[4]
	var threats: Array[Vector2i] = world.threats_for(1)
	assert_true(not AICommander.evaluate_cell(world, red.cell(), threats)["hull_hidden"], "arranca expuesto")
	AICommander.new(1).issue_orders(world)
	var dest: Vector2i = world.destination(red)
	assert_eq(red.order, Unit.Order.HULLDOWN, "orden HULLDOWN")
	assert_true(AICommander.evaluate_cell(world, dest, threats)["hull_hidden"], "el destino tiene el casco oculto (%s)" % dest)


func test_ai_retreats_when_damaged() -> void:
	var world: SimWorld = _ridge_world()
	_blue_known_by_red(world)
	var red: Unit = world.units[4]
	red.hp = 1
	AICommander.new(1).issue_orders(world)
	var e: PackedFloat32Array = world.exposure_for(1)
	var here: Vector2i = red.cell()
	var dest: Vector2i = world.destination(red)
	assert_true(dest != here, "se mueve")
	assert_lt(e[dest.y * N + dest.x], e[here.y * N + here.x], "el destino está menos expuesto")


func test_ai_without_threats_goes_to_crest() -> void:
	var world: SimWorld = _ridge_world()
	var red: Unit = world.units[4]
	red.pos = Vector2(44, 10) # lejos, sin contacto
	world.known_enemies[1].clear()
	AICommander.new(1).issue_orders(world)
	var dest: Vector2i = world.destination(red)
	assert_true(dest.y > 30 and dest.y <= RIDGE_Y, "va a la contrapendiente de la cresta (%s)" % dest)


func test_player_hulldown_spreads_units() -> void:
	var hf: HeightField = HeightField.new(N)
	for y: int in N:
		for x: int in N:
			hf.set_height(Vector2i(x, y), maxf(0.0, 6.0 - absf(float(y - RIDGE_Y)) * 1.0))
	var world: SimWorld = SimWorld.new(7, hf, false)
	# Dos azules juntos en la ladera norte, un rojo conocido al norte
	world.units[0].pos = Vector2(44, 40)
	world.units[1].pos = Vector2(45, 40)
	var red: Unit = world.units[4]
	world.known_enemies[0][red.id] = {"cell": red.cell(), "last_seen_turn": world.turn}
	var ids: Array[int] = [0, 1]
	world.order_hulldown(ids)
	var a: Vector2i = world.destination(world.units[0])
	var b: Vector2i = world.destination(world.units[1])
	assert_true(Vector2(a).distance_to(Vector2(b)) >= Config.HULLDOWN_MIN_SEPARATION, "destinos separados (%s, %s)" % [a, b])
	assert_eq(world.units[0].order, Unit.Order.HULLDOWN, "orden HULLDOWN")


func test_ai_hulldown_respects_holding_units() -> void:
	var world: SimWorld = _ridge_world()
	_blue_known_by_red(world)
	var red: Unit = world.units[4]
	AICommander.new(1).issue_orders(world)
	var first: Vector2i = world.destination(red)
	# Un segundo rojo en la ladera expuesta, y el primero ya parado en su posición
	red.pos = Vector2(first)
	red.path.clear()
	var other: Unit = world.units[5]
	other.alive = true
	other.pos = Vector2(first.x + 1, 56)
	AICommander.new(1).issue_orders(world)
	var d: float = Vector2(world.destination(other)).distance_to(Vector2(world.destination(red)))
	assert_true(d >= Config.HULLDOWN_MIN_SEPARATION, "no se pega al que está en posición (distancia %.1f)" % d)
