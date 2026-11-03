extends TestBase
## Tests de la escuadra de infantería: movimiento, postura, detección y tomar posición.

const N: int = 96


## Llano sin IA: solo el tanque azul 0 y el rojo 4 vivos (lejos), más una escuadra azul.
func _world(hf: HeightField = null) -> SimWorld:
	var world: SimWorld = SimWorld.new(7, hf if hf != null else HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 0 or u.id == 4
	world.units[4].pos = Vector2(48, 2)
	world.units[4].reload_left = 1000.0
	world.units[0].reload_left = 1000.0
	return world


func test_infantry_heights_and_men() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(40, 80), Unit.Kind.INFANTRY)
	assert_eq(sq.hp, Config.INF_MEN, "9 hombres")
	assert_eq(sq.eye_h(), Config.INF_EYE_H, "ojo a 1,7 m")
	assert_lt(sq.profile_h(), Config.HULL_H + 0.01, "perfil bajo")


func test_infantry_walks_slowly() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(40, 80), Unit.Kind.INFANTRY)
	world.order_move(sq.id, Vector2i(40, 60))
	world.begin_execute()
	for i: int in 100: # 10 s
		world.step()
	var moved_m: float = (80.0 - sq.pos.y) * Config.CELL_SIZE
	assert_true(absf(moved_m - Config.INF_SPEED * 10.0) < 1.0, "1,5 m/s en llano (%.1f m en 10 s)" % moved_m)


func test_infantry_climbs_what_tanks_cannot() -> void:
	var hf: HeightField = HeightField.new(N)
	# Escalón de 6 m a lo ancho en y = 50: muy empinado para el tanque, no para la infantería
	for y: int in range(0, 50):
		for x: int in N:
			hf.set_height(Vector2i(x, y), 6.0)
	var world: SimWorld = _world(hf)
	var sq: Unit = world.add_unit(0, Vector2(30, 60), Unit.Kind.INFANTRY)
	world.units[0].pos = Vector2(60, 60)
	assert_true(not world.order_move(0, Vector2i(60, 40)), "el tanque no sube")
	assert_true(world.order_move(sq.id, Vector2i(30, 40)), "la escuadra sí")


func test_goes_prone_when_still() -> void:
	var world: SimWorld = _world()
	var sq: Unit = world.add_unit(0, Vector2(40, 80), Unit.Kind.INFANTRY)
	world.begin_execute()
	for i: int in 20:
		world.step()
	assert_true(not sq.prone, "a los 2 s sigue de pie")
	for i: int in 15:
		world.step()
	assert_true(sq.prone, "a los 3,5 s cuerpo a tierra")
	assert_lt(sq.profile_h(), Config.INF_STAND_H, "perfil más bajo")


func test_infantry_detection_ranges() -> void:
	var world: SimWorld = _world()
	var red: Unit = world.units[4]
	var sq: Unit = world.add_unit(0, Vector2(48, 2 + 50), Unit.Kind.INFANTRY) # 200 m
	sq.moving = true
	world.update_detection()
	assert_true(world.visible_enemies[1].has(sq.id), "en movimiento: detectada a 200 m")
	sq.moving = false
	world.update_detection()
	assert_true(not world.visible_enemies[1].has(sq.id), "quieta: no detectada a 200 m")
	sq.pos = Vector2(48, 2 + 25) # 100 m
	sq.snap_soldiers()
	world.update_detection()
	assert_true(world.visible_enemies[1].has(sq.id), "quieta de pie: detectada a 100 m")
	sq.set_posture(Soldier.Posture.PRONE)
	world.update_detection()
	assert_true(not world.visible_enemies[1].has(sq.id), "cuerpo a tierra: no detectada a 100 m")
	assert_true(red.alive, "el rojo sigue")


func test_take_position_order() -> void:
	var hf: HeightField = HeightField.new(N)
	for x: int in range(30, 50):
		hf.set_height(Vector2i(x, 70), 1.5) # pircita: tapa a la escuadra, no al tanque
	var world: SimWorld = _world(hf)
	var sq: Unit = world.add_unit(0, Vector2(40, 66), Unit.Kind.INFANTRY)
	world.known_enemies[0][4] = {"cell": Vector2i(40, 90), "last_seen_turn": world.turn}
	world.units[4].pos = Vector2(40, 90)
	world.invalidate_exposure()
	var ids: Array[int] = [sq.id]
	world.order_hulldown(ids)
	assert_eq(sq.order, Unit.Order.HULLDOWN, "tomar posición aceptada")
	var dest: Vector2i = world.destination(sq)
	assert_true(dest.y < 70, "queda detrás de la pirca (%s)" % dest)
