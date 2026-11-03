extends TestBase
## Tests de la defensa roja de una casa (fase 71).

const N: int = 64


## La misma casa de cuatro cuartos que en test_clear, con la puerta al sur.
func _world() -> SimWorld:
	var world: SimWorld = SimWorld.new(7, HeightField.new(N), false)
	for u: Unit in world.units:
		u.alive = false
	world.set_micro(MicroCover.new(N))
	var bm: BuildingMap = BuildingMap.new(N)
	var doors: Array[Vector2i] = [Vector2i(103, 109)]
	bm.add_house(Rect2i(100, 100, 12, 10), doors)
	for y: int in range(101, 109):
		if y != 102:
			bm.set_type(Vector2i(106, y), BuildingMap.Type.WALL)
	for x: int in range(101, 111):
		if x != 103 and x != 109 and x != 106:
			bm.set_type(Vector2i(x, 104), BuildingMap.Type.WALL)
	world.set_buildings(bm)
	return world


func _red(world: SimWorld) -> Unit:
	var red: Unit = world.add_unit(1, Vector2(26.25, 26), Unit.Kind.INFANTRY)
	red.mind.autonomy = SquadMind.Autonomy.STRICT
	red.roe = Unit.Roe.HOLD
	world.cqb.defend_house(world, red)
	for s: Soldier in red.soldiers:
		s.pos = s.task_pos
	return red


func test_spread_over_rooms_facing_doors() -> void:
	var world: SimWorld = _world()
	var red: Unit = _red(world)
	var rm: RoomMap = world.rooms()
	var per_room: Dictionary = {}
	for s: Soldier in red.soldiers:
		assert_true(s.cqb_post, "apostado")
		assert_eq(rm.room_at_m(s.task_pos), s.defend_room, "en su cuarto")
		per_room[s.defend_room] = int(per_room.get(s.defend_room, 0)) + 1
		for p: int in rm.portals_of(s.defend_room):
			assert_lt(Config.DEFEND_POST_DOOR_M - 0.01, s.task_pos.distance_to(rm.portals[p]["center"]), "lejos de la puerta")
	assert_eq(per_room.size(), 4, "uno o más en cada cuarto")
	for r: int in per_room:
		assert_lt(int(per_room[r]), red.soldiers.size(), "nunca todos en un cuarto")


func test_falls_back_when_a_room_falls() -> void:
	var world: SimWorld = _world()
	var red: Unit = _red(world)
	var rm: RoomMap = world.rooms()
	var entry: int = int(rm.portals[rm.street_portals(0)[0]]["a"])
	var in_entry: Array[Soldier] = []
	for s: Soldier in red.soldiers:
		if s.defend_room == entry:
			in_entry.append(s)
	assert_true(not in_entry.is_empty(), "hay defensores en el cuarto de la puerta")
	var blue: Unit = world.add_unit(0, Vector2(26, 29), Unit.Kind.INFANTRY)
	blue.mind.autonomy = SquadMind.Autonomy.STRICT
	blue.roe = Unit.Roe.HOLD
	blue.set_men(1)
	blue.soldiers[0].pos = MicroCover.center_m(Vector2i(102, 107)) # un azul adentro: el cuarto cayó
	world.begin_execute()
	for i: int in 60:
		world.step()
	for s: Soldier in in_entry:
		assert_true(s.defend_room != entry and s.defend_room >= 0, "se replegó a otro cuarto")
		assert_true(rm.room_at_m(s.pos) != entry, "ya salió del cuarto que cayó")
	assert_eq(red.defend_house, 0, "sigue defendiendo la casa")
