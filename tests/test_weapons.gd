extends TestBase
## Tests de las armas cruzadas: coaxial, fusiles, antitanque y bajas por hombre.

const N: int = 96


## Llano sin IA: solo el tanque azul 0 vivo (en 48, 60) y el rojo 4 vivo pero lejos y sin recarga.
func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 0 or u.id == 4
	world.units[0].pos = Vector2(48, 60)
	world.units[4].pos = Vector2(5, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	return world


func _shots(world: SimWorld, shooter: int, weapon: int) -> int:
	var n: int = 0
	for e: Dictionary in world.shot_events:
		if int(e["shooter"]) == shooter and int(e["weapon"]) == weapon:
			n += 1
	return n


func _run(world: SimWorld, ticks: int) -> void:
	world.update_detection()
	world.begin_execute()
	for i: int in ticks:
		world.step()


func test_tank_uses_coax_on_infantry() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(1, Vector2(48, 40), Unit.Kind.INFANTRY) # 80 m, de pie
	sq.reload_left = 1000.0
	sq.reload2_left = 1000.0
	sq.moving = true
	_run(world, 200)
	assert_eq(_shots(world, 0, Unit.Weapon.CANNON), 0, "no gasta el cañón en infantería")
	assert_true(_shots(world, 0, Unit.Weapon.COAX) > 1, "tira con la coaxial")
	assert_lt(sq.hp, Config.INF_MEN, "bajas")


func test_rifles_do_not_hurt_tanks() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(1, Vector2(48, 20), Unit.Kind.INFANTRY) # 160 m: fuera del antitanque
	world.units[0].reload_left = 1000.0
	world.units[0].reload2_left = 1000.0
	world.units[0].moving = true
	_run(world, 100)
	assert_eq(_shots(world, sq.id, Unit.Weapon.RIFLES), 0, "los fusiles no tiran al tanque")
	assert_eq(_shots(world, sq.id, Unit.Weapon.AT), 0, "a 160 m el antitanque no tira")
	assert_eq(world.units[0].hp, Config.TANK_HP, "el tanque intacto")


func test_at_in_range_spends_charges() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(1, Vector2(48, 30), Unit.Kind.INFANTRY) # 120 m
	world.units[0].reload_left = 1000.0
	world.units[0].reload2_left = 1000.0
	world.units[0].moving = true
	_run(world, 300)
	assert_eq(_shots(world, sq.id, Unit.Weapon.AT), Config.INF_AT_CHARGES, "tiró todas sus cargas")
	assert_eq(sq.at_charges, 0, "sin cargas")


func test_infantry_firefight_and_prone_protects() -> void:
	var standing: int = 0
	var prone: int = 0
	for trial: int in 2:
		var world: SimWorld = _world()
		world.units[0].alive = false
		var a: Unit = world.add_unit(0, Vector2(48, 60), Unit.Kind.INFANTRY)
		var b: Unit = world.add_unit(1, Vector2(48, 50), Unit.Kind.INFANTRY) # 40 m: se la ve aun cuerpo a tierra
		b.reload_left = 1000.0
		b.reload2_left = 1000.0
		b.moving = true # que la vean
		if trial == 1:
			b.prone = true
			b.still_time = 1000.0
		world.update_detection()
		world.begin_execute()
		for i: int in 300:
			b.moving = trial == 0
			world.step()
		if trial == 0:
			standing = Config.INF_MEN - b.hp
		else:
			prone = Config.INF_MEN - b.hp
		assert_true(_shots(world, a.id, Unit.Weapon.RIFLES) > 5, "la escuadra tira a la escuadra")
	assert_lt(prone, standing, "cuerpo a tierra recibe menos bajas (%d vs %d)" % [prone, standing])


func test_squad_dies_at_zero_men() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(1, Vector2(48, 56), Unit.Kind.INFANTRY)
	sq.hp = 1
	sq.reload_left = 1000.0
	sq.reload2_left = 1000.0
	sq.moving = true
	_run(world, 300)
	assert_true(not sq.alive, "con 0 hombres la escuadra muere")
