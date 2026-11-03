extends TestBase
## Tests del Pathfinder sobre un llano sintético con una franja expuesta.

const N: int = 40
const FROM: Vector2i = Vector2i(5, 20)
const TO: Vector2i = Vector2i(35, 20)


## Franja expuesta (1.0) en x 10..30, y 12..28; el resto cubierto (0.0).
## El desvío por y <= 11 es ~1,5 veces más largo que el cruce recto expuesto.
func _band_exposure() -> PackedFloat32Array:
	var e: PackedFloat32Array = PackedFloat32Array()
	e.resize(N * N)
	for y: int in N:
		for x: int in N:
			e[y * N + x] = 1.0 if (x >= 10 and x <= 30 and y >= 12 and y <= 28) else 0.0
	return e


func test_prefers_covered_detour() -> void:
	var pf: Pathfinder = Pathfinder.new(HeightField.new(N))
	var e: PackedFloat32Array = _band_exposure()
	pf.set_exposure(e)
	var path: Array[Vector2i] = pf.find_path(FROM, TO)
	assert_true(not path.is_empty(), "hay ruta")
	var exposed: int = 0
	for c: Vector2i in path:
		if e[c.y * N + c.x] > 0.0:
			exposed += 1
	assert_eq(exposed, 0, "celdas expuestas en la ruta")


func test_straight_without_exposure_weight() -> void:
	var pf: Pathfinder = Pathfinder.new(HeightField.new(N))
	pf.exposure_k = 0.0
	pf.set_exposure(_band_exposure())
	var path: Array[Vector2i] = pf.find_path(FROM, TO)
	assert_eq(path.size(), 31, "largo de la ruta recta")
	var off_line: int = 0
	for c: Vector2i in path:
		if c.y != 20:
			off_line += 1
	assert_eq(off_line, 0, "celdas fuera de la recta")


func test_unit_reaches_target() -> void:
	var world: SimWorld = SimWorld.new(1, HeightField.new(N))
	var u: Unit = world.units[0]
	var target: Vector2i = u.cell() + Vector2i(0, -10)
	assert_true(world.order_move(u.id, target), "orden aceptada")
	# 10 celdas * 4 m = 40 m a 6 m/s: ~6,7 s = 67 ticks
	for i: int in 80:
		world.step()
	assert_eq(u.cell(), target, "llegó al destino")
	assert_true(not u.moving, "quedó detenido")
