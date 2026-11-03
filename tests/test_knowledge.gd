extends TestBase
## Tests del conocimiento de cada escuadra: lo propio exacto, el fogonazo aproximado, la radio con demora.

const N: int = 96


func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 4 # un tanque rojo lejos, para que no termine la partida
	world.units[4].pos = Vector2(5, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	world.set_micro(MicroCover.new(N))
	return world


func test_own_sighting_is_exact_and_immediate() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	var red: Unit = world.add_unit(1, Vector2(48, 55), Unit.Kind.INFANTRY) # 100 m
	world.visible_enemies[0][red.id] = true
	world.minds.on_detection(world)
	assert_true(sq.mind.contacts.has(red.id), "lo sabe")
	assert_true(bool(sq.mind.contacts[red.id]["exact"]), "exacto")
	assert_eq(sq.mind.contacts[red.id]["pos"], red.pos_m(), "donde está")
	assert_true(str(world.radio_log.back()["text"]).begins_with("contacto: infantería a 100 m al norte"), "lo anuncia")


func test_far_contact_arrives_by_radio_with_delay() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 90), Unit.Kind.INFANTRY)
	var red: Unit = world.add_unit(1, Vector2(48, 30), Unit.Kind.INFANTRY) # 240 m
	red.reload_left = 1000.0
	sq.mind.next_think_tick = 1000000
	world.visible_enemies[0][red.id] = true
	world.minds.on_detection(world)
	world.begin_execute()
	assert_true(not sq.mind.contacts.has(red.id), "todavía no")
	for i: int in roundi(Config.RADIO_DELAY_MIN / Config.TICK) - 2:
		world.minds.update(world)
		world.total_ticks += 1
	assert_true(not sq.mind.contacts.has(red.id), "a los 3 s todavía no")
	for i: int in roundi((Config.RADIO_DELAY_MAX - Config.RADIO_DELAY_MIN) / Config.TICK) + 4:
		world.minds.update(world)
		world.total_ticks += 1
	assert_true(sq.mind.contacts.has(red.id), "a los 5 s ya llegó")


func test_flash_is_approximate() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	var red: Unit = world.add_unit(1, Vector2(48, 30), Unit.Kind.INFANTRY) # 200 m, no lo ve
	world.minds.flash(world, sq, red, red.pos_m())
	var c: Dictionary = sq.mind.contacts[red.id]
	assert_true(not bool(c["exact"]), "aproximado")
	var err: float = (c["pos"] as Vector2).distance_to(red.pos_m())
	assert_true(err <= 200.0 * Config.CONTACT_FLASH_ERROR * 1.5, "error acotado: %f" % err)


func test_cover_faces_own_contacts() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 50), Unit.Kind.INFANTRY)
	sq.mind.learn(99, sq.pos_m() + Vector2(100.0, 0.0), 0, true)
	assert_eq(world.inf.threat_point(world, sq), sq.pos_m() + Vector2(100.0, 0.0), "se cubre contra lo que sabe")


func test_contacts_are_forgotten() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(48, 80), Unit.Kind.INFANTRY)
	var red: Unit = world.add_unit(1, Vector2(48, 30), Unit.Kind.INFANTRY)
	red.reload_left = 1000.0
	world.minds.flash(world, sq, red, red.pos_m())
	world.begin_execute()
	for i: int in roundi(Config.CONTACT_FORGET_SECONDS / Config.TICK) + 20:
		world.minds.update(world)
		world.total_ticks += 1
	assert_true(not sq.mind.contacts.has(red.id), "sin noticias, lo olvida")
