extends TestBase
## Tests de cortar la torta en una esquina (fase 64).

const N: int = 64
const O := SquadMind.Option


## Casa de 12 x 12 m (metros 98 a 110); la escuadra sube por el lado este y dobla al oeste por el
## norte, donde espera un enemigo que desde el sur no se ve.
func _world() -> Array:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = u.id == 4
	world.units[4].pos = Vector2(2, 2)
	world.units[4].reload_left = 1000.0
	world.units[4].reload2_left = 1000.0
	world.set_micro(MicroCover.new(N))
	var bm: BuildingMap = BuildingMap.new(N)
	bm.add_house(Rect2i(100, 100, 12, 12))
	world.set_buildings(bm)
	var red: Unit = world.add_unit(1, Vector2(24, 23), Unit.Kind.INFANTRY)
	red.mind.autonomy = SquadMind.Autonomy.STRICT
	red.roe = Unit.Roe.HOLD
	for s: Soldier in red.soldiers: # pegados a la pared norte: desde el sur no se ven
		s.pos = Vector2(100.0 + float(s.index), 95.0)
		s.hold_pos = true
	var blue: Unit = world.add_unit(0, Vector2(29, 33), Unit.Kind.INFANTRY)
	blue.mind.autonomy = SquadMind.Autonomy.NORMAL
	blue.roe = Unit.Roe.HOLD
	world.order_move(blue.id, Vector2i(22, 23), Vector2.ZERO, false)
	_east_route(blue)
	world.begin_execute()
	blue.mind.learn(4, Vector2(2, 2) * Config.CELL_SIZE, 1000000, false) # contacto viejo: hay enemigos
	blue.mind.reacted[4] = true
	return [world, blue, red]


## Ruta fija: sube por el lado este (x 29) y dobla al oeste por el norte (y 23).
func _east_route(u: Unit) -> void:
	var path: Array[Vector2i] = []
	var y: int = roundi(u.pos.y) - 1
	while y > 23:
		path.append(Vector2i(29, y))
		y -= 1
	for x: int in range(29, 21, -1):
		path.append(Vector2i(x, 23))
	u.path = path


func test_blind_corner_found() -> void:
	var r: Array = _world()
	var world: SimWorld = r[0]
	var blue: Unit = r[1]
	blue.pos = Vector2(29, 26)
	_east_route(blue)
	var c: Dictionary = MindSim.blind_corner(world, blue)
	assert_true(not c.is_empty(), "hay una esquina ciega adelante")
	assert_lt((c["k"] as Vector2).distance_to(Vector2(110, 98)), 2.0, "la esquina noreste")


func test_slice_sees_before_exposing() -> void:
	var r: Array = _world()
	var world: SimWorld = r[0]
	var blue: Unit = r[1]
	var red: Unit = r[2]
	var sliced: bool = false
	var exposed_at_contact: int = -1
	for i: int in 900:
		world.step()
		if blue.mind.option == O.CORNER:
			sliced = true
		if exposed_at_contact < 0 and blue.mind.contacts.has(red.id):
			exposed_at_contact = 0
			for s: Soldier in blue.soldiers:
				var seen: bool = false
				for t: Soldier in red.soldiers:
					if world.analysis.los_m(t.pos, InfantrySim.eye_of(world, t), s.pos, InfantrySim.head_of(world, s)):
						seen = true
				if seen:
					exposed_at_contact += 1
			break
	assert_true(sliced, "cortó la torta")
	assert_true(exposed_at_contact >= 0, "vio al enemigo")
	assert_lt(float(exposed_at_contact), 2.5, "al verlo, a lo sumo los dos de punta a la vista (%d)" % exposed_at_contact)


func test_clear_corner_squad_goes_on() -> void:
	var r: Array = _world()
	var world: SimWorld = r[0]
	var blue: Unit = r[1]
	var red: Unit = r[2]
	red.alive = false
	for i: int in 1500:
		world.step()
	assert_lt(float(blue.cell().x), 26.5, "dobló la esquina y siguió al oeste (x %d)" % blue.cell().x)
	for s: Soldier in blue.soldiers:
		assert_true(s.task_pos.x < 0.0, "sin tareas pendientes")
