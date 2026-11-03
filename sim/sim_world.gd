class_name SimWorld
extends RefCounted
## Estado completo de la simulación. Avanza en ticks fijos de Config.TICK.
## Ciclo WeGo: PLAN (se aceptan órdenes) -> EXECUTE (ticks_per_turn ticks) -> PLAN ...

enum Phase { PLAN, EXECUTE }
## TANKS: la demo original (4 tanques por bando, sin cobertura). LOMA: infantería y un tanque
## por bando, con cobertura; el rojo defiende la cresta central.
enum Scenario { TANKS, LOMA, PUEBLO }
enum Aspect { FRONT, FLANK, REAR }
const NO_WINNER: int = -1
const DRAW: int = 2

var height_field: HeightField
var analysis: TerrainAnalysis
var pathfinder: Pathfinder # el de los tanques (pathfinders[Unit.Kind.TANK])
var pathfinders: Array[Pathfinder] = [] # uno por tipo de unidad (índice = Unit.Kind)
var units: Array[Unit] = []
var platoons: Array[Platoon] = [] # uno por bando (índice = side)
## Misión de pelotón por bando (fase 58): null si el pelotón de infantería no tiene misión.
var missions: Array[PlatoonLeader] = [null, null]
var _bound_count: int = 0 # para nombrar las señales de los avances por saltos
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Azar de la autonomía (error de los contactos, demoras de radio, ruido de las decisiones). Aparte
## del de combate para que pensar no cambie la secuencia de los dados; también con semilla.
var mind_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var turn: int = 1
var tick_in_turn: int = 0
var total_ticks: int = 0 # ticks desde el comienzo de la partida
var phase: int = Phase.PLAN
var ticks_per_turn: int = roundi(Config.TURN_SECONDS / Config.TICK)
var winner: int = NO_WINNER # 0 azul, 1 rojo, DRAW empate
var game_over: bool = false

# Niebla, por bando (índice = side)
var visible_enemies: Array[Dictionary] = [{}, {}] # id -> true, visibles ahora
var known_enemies: Array[Dictionary] = [{}, {}] # id -> {cell, last_seen_turn}

# Nubes de humo activas: {id, center: Vector2, radius, top_h, turns_left, side}.
# Es el mismo array que analysis.smoke (la LOS las usa directamente).
var smoke_clouds: Array[Dictionary] = []
var _next_smoke_id: int = 0

# Señales con nombre emitidas por bando (nombre -> tick global); duran toda la partida
var signals: Array[Dictionary] = [{}, {}]

# Disparos ocurridos desde la última vez que la vista los leyó: {shooter, target, hit, aspect}
var shot_events: Array[Dictionary] = []
## Granadas en el aire: {at (metros), tick en que explota, side, unit, from}. blast_events: explosiones de este tick (para la vista).
var grenades: Array[Dictionary] = []
var blast_events: Array[Vector2] = []
var dug_events: Array[Vector2] = [] # pozos de tirador recién cavados (para la vista)

# Factores de combate (se pueden cambiar en tests)
var p_hit_base: float = Config.P_HIT_BASE
var hulldown_hit_factor: float = Config.HULLDOWN_HIT_FACTOR
var moving_shooter_factor: float = Config.MOVING_SHOOTER_FACTOR
var armor_enabled: bool = true
var p_hit_max: float = Config.P_HIT_MAX

# Exposición por bando y tipo (índice = side * 2 + kind); vacía = sin calcular
var _exposure: Array[PackedFloat32Array] = []
var _pathfinder_side: Array[int] = [-1, -1] # por tipo: bando cuya exposición está cargada en su pathfinder
var ai: AICommander = null # IA del bando rojo (null = sin IA)
var scenario: int = Scenario.TANKS
var _forcing: bool = false # órdenes que da la propia simulación (una retirada por moral quebrada)
var cover: CoverMap = null # cobertura fina (null = sin cobertura, como en la demo de tanques)
var micro: MicroCover = null # microcobertura a 1 m (piedras, cráteres, pircas); null = sin ella
var buildings: BuildingMap = null # casas a 1 m (fase 60); null = sin
var facade: PackedByteArray = PackedByteArray() # por celda: distancia (celdas) a una casa, hasta FACADE_MAX (fase 62); 255 lejos
var inf: InfantrySim = InfantrySim.new() # los soldados de las escuadras
var minds: MindSim = MindSim.new() # la autonomía de las escuadras
## Radio: lo que las escuadras deciden por su cuenta. {tick, turn, side, unit, text}, el último al final.
var radio_log: Array[Dictionary] = []
## Decisiones propias tomadas en la partida (nombre de la opción -> cantidad), para el banco IA contra IA.
var decision_counts: Dictionary = {}
var _autonomous: int = 0 # > 0: órdenes que se da la propia escuadra (valen en la ejecución)


## Si hf es null se genera el terreno procedural con la semilla.
## with_ai: si el bando rojo lo maneja AICommander (los tests pueden apagarlo).
func _init(sim_seed: int = Config.SEED, hf: HeightField = null, with_ai: bool = true, p_scenario: int = Scenario.TANKS) -> void:
	scenario = p_scenario
	if with_ai:
		ai = AICommander.new(1)
	rng.seed = sim_seed
	mind_rng.seed = sim_seed * 7919 + 17
	if hf == null:
		hf = HeightField.new()
		hf.generate(sim_seed)
	height_field = hf
	analysis = TerrainAnalysis.new(hf)
	analysis.smoke = smoke_clouds
	pathfinders = [Pathfinder.new(hf), Pathfinder.new(hf, Config.INF_MAX_SLOPE)]
	pathfinder = pathfinders[Unit.Kind.TANK]
	invalidate_exposure()
	if scenario == Scenario.LOMA:
		ticks_per_turn = roundi(Config.LOMA_TURN_SECONDS / Config.TICK)
		var cm: CoverMap = CoverMap.new(hf.size)
		cm.generate(sim_seed)
		cm.add_ridge_forest(hf)
		set_cover(cm)
		var mc: MicroCover = MicroCover.new(hf.size)
		mc.generate(sim_seed, cm)
		set_micro(mc)
		_deploy_loma()
	elif scenario == Scenario.PUEBLO:
		_setup_pueblo(sim_seed)
	else:
		_deploy()
	update_detection()
	start_plan()


## Azules en el borde sur (y alto), rojos en el norte, separados DEPLOY_SPACING celdas.
func _deploy() -> void:
	var n: int = height_field.size
	var first_x: int = n / 2 - (Config.UNITS_PER_SIDE - 1) * Config.DEPLOY_SPACING / 2
	for side: int in 2:
		var y: int = n - 1 - Config.DEPLOY_EDGE_MARGIN if side == 0 else Config.DEPLOY_EDGE_MARGIN
		for i: int in Config.UNITS_PER_SIDE:
			var x: int = first_x + i * Config.DEPLOY_SPACING
			units.append(Unit.new(units.size(), side, Vector2(x, y)))
	# Un pelotón por bando, con los tanques repartidos en secciones consecutivas
	var per_section: int = maxi(1, ceili(float(Config.UNITS_PER_SIDE) / Config.SECTIONS_PER_PLATOON))
	for side: int in 2:
		var secs: Array[PackedInt32Array] = []
		for i: int in Config.UNITS_PER_SIDE:
			if i % per_section == 0:
				secs.append(PackedInt32Array())
			secs[secs.size() - 1].append(side * Config.UNITS_PER_SIDE + i)
		platoons.append(Platoon.new(side, side, secs))


## La loma: por bando, LOMA_SQUADS escuadras y LOMA_TANKS tanques. El azul al sur;
## el rojo detrás de la cresta central. Pelotón con dos secciones: infantería y tanques.
func _deploy_loma() -> void:
	var n: int = height_field.size
	var count: int = Config.LOMA_SQUADS + Config.LOMA_TANKS
	var first_x: int = n / 2 - (count - 1) * Config.LOMA_SQUAD_SPACING / 2
	for side: int in 2:
		var inf_ids: PackedInt32Array = PackedInt32Array()
		var tank_ids: PackedInt32Array = PackedInt32Array()
		for i: int in count:
			var kind: int = Unit.Kind.INFANTRY if i < Config.LOMA_SQUADS else Unit.Kind.TANK
			var x: int = first_x + i * Config.LOMA_SQUAD_SPACING
			var y: int = n - 1 - Config.DEPLOY_EDGE_MARGIN
			if side == 1:
				y = roundi(height_field.ridge_center_y(float(x))) - Config.LOMA_RED_BEHIND_CREST
			var c: Vector2i = _nearest_walkable(Vector2i(x, y), kind)
			var u: Unit = add_unit(side, Vector2(c), kind)
			if kind == Unit.Kind.INFANTRY:
				u.mind.quality = Config.MIND_LOMA_QUALITY[i % Config.MIND_LOMA_QUALITY.size()]
				inf_ids.append(u.id)
			else:
				tank_ids.append(u.id)
		var secs: Array[PackedInt32Array] = [inf_ids, tank_ids]
		platoons.append(Platoon.new(side, side, secs))


## El pueblo (fase 61): terreno aplanado en el centro con casas, calles y plaza; sin bosques ni
## microcobertura suelta adentro. El azul entra desde el sur como en la loma; el rojo defiende
## desde las casas (ver AICommander) y su tanque espera detrás de la plaza.
func _setup_pueblo(sim_seed: int) -> void:
	ticks_per_turn = roundi(Config.LOMA_TURN_SECONDS / Config.TICK)
	var bm: BuildingMap = TownGenerator.build(height_field, sim_seed)
	# El terreno cambió: los A* se rehacen
	pathfinders = [Pathfinder.new(height_field), Pathfinder.new(height_field, Config.INF_MAX_SLOPE)]
	pathfinder = pathfinders[Unit.Kind.TANK]
	var area: Rect2i = TownGenerator.area_cells(height_field)
	var cm: CoverMap = CoverMap.new(height_field.size)
	cm.generate(sim_seed)
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			cm.set_type(Vector2i(x, y), CoverMap.Type.NONE)
	set_cover(cm)
	var mc: MicroCover = MicroCover.new(height_field.size)
	mc.generate(sim_seed, cm)
	var per: int = Config.MICRO_PER_CELL
	for y: int in range(area.position.y * per - per / 2, area.end.y * per - per / 2):
		for x: int in range(area.position.x * per - per / 2, area.end.x * per - per / 2):
			mc.set_type(Vector2i(x, y), MicroCover.Type.NONE)
	set_micro(mc)
	set_buildings(bm)
	_deploy_loma()
	# El rojo: escuadras a las casas de sus papeles (AICommander), el tanque detrás de la plaza
	for u: Unit in units:
		if u.side == 1 and not u.is_infantry():
			var c: Vector2i = objective_cell() - Vector2i(0, Config.TOWN_RED_TANK_BACK)
			u.pos = Vector2(_nearest_walkable(c, Unit.Kind.TANK))
	if ai != null:
		ai.assign_roles(self)
		for id: int in ai.roles:
			var u: Unit = units[id]
			u.pos = Vector2(ai.anchors[id])
			u.snap_soldiers()
			inf.prepare_house(self, u, Vector2(objective_cell().x, height_field.size - 1) * Config.CELL_SIZE)


## Abrir un boquete (fase 65) en la pared más cercana a at_m. Un tanque lo abre de un cañonazo
## desde donde está (con línea de visión a la pared); una escuadra va hasta la pared y pone una
## carga. Solo en PLAN.
func order_breach(unit_id: int, at_m: Vector2) -> bool:
	var u: Unit = get_unit(unit_id)
	if not _can_order(u) or buildings == null:
		return false
	var c: Vector2i = buildings.nearest_wall(at_m)
	if c.x < 0:
		return false
	var face: Vector2 = buildings.outside_of(c, 0.6)
	if u.is_infantry():
		if u.breach_charges <= 0:
			return false
		var stand: Vector2 = buildings.outside_of(c, 1.5)
		if not order_move(unit_id, _nearest_walkable(Vector2i((stand / Config.CELL_SIZE).round()), Unit.Kind.INFANTRY)):
			return false
		u.breach_m = MicroCover.center_m(c)
		u.breach_time = 0.0
		return true # va como MOVE; al llegar pone la carga
	else:
		if face.distance_to(u.pos_m()) > Config.BREACH_TANK_RANGE_M:
			return false
		_new_intent(u)
		u.path.clear()
		u.waypoints.clear()
		u.moving = false
		_face(u, face / Config.CELL_SIZE)
	u.order = Unit.Order.BREACH
	u.breach_m = MicroCover.center_m(c)
	u.breach_time = 0.0
	return true


## Boquetes pendientes: el tanque tira cuando está listo y ve la pared; la escuadra, al llegar,
## pone la carga y a los BREACH_CHARGE_SECONDS vuela la pared (y lo que haya detrás).
func _update_breaches() -> void:
	if buildings == null:
		return
	for u: Unit in units:
		if not u.alive or u.breach_m.x < 0.0:
			continue
		if u.order != Unit.Order.BREACH and u.order != Unit.Order.NONE and u.order != Unit.Order.MOVE:
			_finish_breach(u) # le dieron otra orden
			continue
		var c: Vector2i = MicroCover.cell_of(u.breach_m)
		if buildings.type_at(c) != BuildingMap.Type.WALL and buildings.type_at(c) != BuildingMap.Type.WINDOW:
			_finish_breach(u)
			continue
		var face: Vector2 = buildings.outside_of(c, 0.6)
		if u.is_infantry():
			if u.moving or not u.path.is_empty() or u.pos_m().distance_to(face) > Config.BREACH_REACH_M + Config.CELL_SIZE:
				continue
			u.breach_time += Config.TICK
			if u.breach_time >= Config.BREACH_CHARGE_SECONDS:
				u.breach_charges -= 1
				_blow(u, c)
		elif u.reload_left <= 0.0 and analysis.los_m(u.pos_m(), Config.EYE_H, face, 1.0):
			u.reload_left = weapon_reload(Unit.Weapon.CANNON)
			u.last_fire_tick = total_ticks
			shot_events.append({"shooter": u.id, "target": -1, "hit": true, "aspect": Aspect.FRONT, "weapon": Unit.Weapon.AT,
				"from_m": u.pos_m(), "from_h": Config.EYE_H, "to_m": face, "to_h": 1.2})
			_blow(u, c)


func _blow(u: Unit, c: Vector2i) -> void:
	buildings.breach(c)
	inf.explode(self, MicroCover.center_m(c), u, u.pos_m()) # lo que haya detrás de la pared lo siente
	radio(u, "¡boquete abierto!")
	invalidate_exposure()
	_finish_breach(u)


func _finish_breach(u: Unit) -> void:
	u.breach_m = Vector2(-1.0, -1.0)
	u.breach_time = 0.0
	if u.order == Unit.Order.BREACH:
		u.order = Unit.Order.NONE


## ¿El escenario tiene un objetivo a ocupar (la cresta, la plaza)?
func has_objective() -> bool:
	return scenario == Scenario.LOMA or scenario == Scenario.PUEBLO


## Radio (celdas) del objetivo.
func objective_radius() -> float:
	return Config.TOWN_OBJECTIVE_RADIUS if scenario == Scenario.PUEBLO else Config.LOMA_OBJECTIVE_RADIUS


## Celda transitable para el tipo más cercana a c (c si ya lo es).
func _nearest_walkable(c: Vector2i, kind: int) -> Vector2i:
	var pf: Pathfinder = pathfinders[kind]
	for r: int in 12:
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				var t: Vector2i = c + Vector2i(dx, dy)
				if maxi(absi(dx), absi(dy)) == r and pf.is_walkable(t):
					return t
	return c


## Activa la cobertura fina: la línea de visión, los pathfinders y la exposición la usan.
func set_cover(cm: CoverMap) -> void:
	cover = cm
	analysis.cover = cm
	var costs: PackedFloat32Array = PackedFloat32Array()
	costs.resize(height_field.size * height_field.size)
	for i: int in costs.size():
		costs[i] = Config.FOREST_TANK_PATH_COST if cm != null and cm.types[i] == CoverMap.Type.FOREST else 0.0
	pathfinders[Unit.Kind.TANK].set_extra_cost(costs)
	invalidate_exposure()


## Activa la microcobertura (la usa la línea de visión en metros de los soldados).
func set_micro(mc: MicroCover) -> void:
	micro = mc
	analysis.micro = mc


## Casas (fase 60): cortan la vista y las balas, los soldados entran por las puertas y el tanque
## no pasa por encima.
func set_buildings(bm: BuildingMap) -> void:
	buildings = bm
	analysis.buildings = bm
	var pf: Pathfinder = pathfinders[Unit.Kind.TANK]
	for c: Vector2i in bm.footprint_cells():
		if height_field.in_bounds(c):
			pf.astar.set_point_solid(c, true)
			pf.astar_direct.set_point_solid(c, true)
	_build_facade(bm)
	invalidate_exposure()


## Distancia de cada celda a la casa más cercana (BFS hasta FACADE_MAX) y, con eso, la ruta de
## infantería: pegada a las fachadas no cuesta nada, por el medio de la calle cuesta FACADE_OPEN_COST
## y por adentro de las casas FACADE_HOUSE_COST.
func _build_facade(bm: BuildingMap) -> void:
	var n: int = height_field.size
	facade.resize(n * n)
	facade.fill(255)
	var frontier: Array[Vector2i] = []
	for c: Vector2i in bm.footprint_cells():
		if height_field.in_bounds(c):
			facade[c.y * n + c.x] = 0
			frontier.append(c)
	for d: int in range(1, Config.FACADE_MAX + 1):
		var next: Array[Vector2i] = []
		for c: Vector2i in frontier:
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
				var t: Vector2i = c + o
				if height_field.in_bounds(t) and facade[t.y * n + t.x] == 255:
					facade[t.y * n + t.x] = d
					next.append(t)
		frontier = next
	var costs: PackedFloat32Array = PackedFloat32Array()
	costs.resize(n * n)
	for i: int in costs.size():
		var f: int = facade[i]
		costs[i] = Config.FACADE_HOUSE_COST if f == 0 else (Config.FACADE_OPEN_COST if f >= 2 and f <= Config.FACADE_MAX else 0.0)
	pathfinders[Unit.Kind.INFANTRY].set_extra_cost(costs)


## Distancia (celdas) de c a la casa más cercana; 255 lejos del pueblo o sin casas.
func facade_at(c: Vector2i) -> int:
	if facade.is_empty() or not height_field.in_bounds(c):
		return 255
	return facade[c.y * height_field.size + c.x]


## ¿c es la calle abierta (ni pegada a una fachada ni adentro de una casa)?
func is_street(c: Vector2i) -> bool:
	var f: int = facade_at(c)
	return f >= 2 and f <= Config.FACADE_MAX


## Cobertura de la celda para la infantería (0 sin cobertura).
func cover_at(c: Vector2i) -> float:
	return cover.cover_at(c) if cover != null else 0.0


## Agrega una unidad (escenarios y tests). No la mete en ningún pelotón.
func add_unit(side: int, pos: Vector2, kind: int = Unit.Kind.TANK) -> Unit:
	var u: Unit = Unit.new(units.size(), side, pos, kind)
	units.append(u)
	return u


func get_unit(unit_id: int) -> Unit:
	if unit_id < 0 or unit_id >= units.size():
		return null
	return units[unit_id]


## Amenazas conocidas por un bando: enemigos vivos visibles o vistos
## en este turno o el anterior, en su última posición conocida.
func threats_for(side: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var known: Dictionary = known_enemies[side]
	for id: int in known:
		var info: Dictionary = known[id]
		if units[id].alive and int(info["last_seen_turn"]) >= turn - 1:
			out.append(info["cell"])
	return out


## Al entrar en PLAN: se descarta la exposición vieja (se recalcula al pedirla)
## y la IA roja da sus órdenes.
func start_plan() -> void:
	phase = Phase.PLAN
	invalidate_exposure()
	if ai != null and not game_over:
		ai.issue_orders(self)
	for pl: PlatoonLeader in missions:
		if pl != null and not game_over:
			pl.issue(self)
	_rout_broken()


## Escuadras con la moral quebrada: se retiran solas (reemplaza la orden que tuvieran).
func _rout_broken() -> void:
	for u: Unit in units:
		if u.alive and u.broken:
			_forcing = true
			order_withdraw(u.id)
			_forcing = false


## ¿La unidad acepta órdenes ahora? (viva, en PLAN y sin la moral quebrada; las que se da la
## propia escuadra valen también en la ejecución)
func _can_order(u: Unit) -> bool:
	return u != null and u.alive and (phase == Phase.PLAN or _autonomous > 0) and (not u.broken or _forcing)


## Orden nueva del jugador (o del comandante): la escuadra deja lo que hacía por su cuenta.
func _new_intent(u: Unit) -> void:
	if _autonomous == 0 and u.mind != null:
		u.mind.reset(total_ticks)
		for s: Soldier in u.soldiers:
			s.hold_pos = false # ningún equipo queda clavado como base de fuego
			s.suppress_m = Vector2(-1.0, -1.0)
			s.drag_target = -1
			s.dragged = false


func begin_autonomous() -> void:
	_autonomous += 1


func end_autonomous() -> void:
	_autonomous -= 1


## Orden del comandante (la IA del bando) en plena ejecución: manda sobre lo que la escuadra
## hacía por su cuenta. assault: asalto directo en vez de marcha cubierta.
func command_move(unit_id: int, target: Vector2i, assault: bool = false) -> bool:
	var u: Unit = get_unit(unit_id)
	if u == null or not u.alive:
		return false
	_new_intent(u)
	begin_autonomous()
	var ok: bool = order_assault(unit_id, target) if assault else order_move(unit_id, target)
	end_autonomous()
	return ok


## La escuadra piensa ya (tests y eventos).
func mind_think_now(u: Unit) -> void:
	minds.think(self, u)


## Mensaje de radio de una escuadra.
func radio(u: Unit, text: String) -> void:
	radio_log.append({"tick": total_ticks, "turn": turn, "side": u.side, "unit": u.id, "text": text})
	if radio_log.size() > Config.RADIO_LOG_MAX:
		radio_log.pop_front()


## Rehace la ruta de u desde donde está pasando por esos tramos (con sus condiciones y señales).
func reroute_through(u: Unit, wps: Array[Dictionary]) -> bool:
	var path: Array[Vector2i] = []
	var kept: Array[Dictionary] = []
	var from: Vector2i = u.cell()
	for wp: Dictionary in wps:
		var to: Vector2i = wp["cell"]
		if to == from:
			continue
		var leg: Array[Vector2i] = _route(u, from, to, not bool(wp.get("direct", false)))
		if leg.is_empty():
			continue
		path.append_array(leg)
		kept.append(wp)
		from = to
	u.path = path
	u.waypoints = kept
	u.moving = not path.is_empty()
	return u.moving


## Espacio: arranca la ejecución del turno.
func begin_execute() -> void:
	if phase == Phase.PLAN and not game_over:
		phase = Phase.EXECUTE
		tick_in_turn = 0
		# Vigilancia: arranca el turno con la recarga lista y el disparo de emboscada
		for u: Unit in units:
			if u.alive and u.order == Unit.Order.OVERWATCH:
				u.reload_left = 0.0
				u.overwatch_ready = true


## Quién ve a quién: un enemigo es visible para un bando si alguna unidad viva de ese bando
## lo detecta. Tanque contra tanque, ver _can_spot. Si hay soldados de por medio, la detección es
## por soldado (ver InfantrySim.spot_squad y soldiers_spot_tank); una escuadra es visible si se ve
## a alguno de sus soldados.
## full = false (durante la ejecución): cada vez se mira solo la mitad de las escuadras enemigas,
## alternando; las otras conservan lo de la vez anterior (cada escuadra se actualiza cada
## 2 * DETECTION_INTERVAL_TICKS). Así la detección por soldado cuesta la mitad.
func update_detection(full: bool = true) -> void:
	inf.begin_detection(self)
	for side: int in 2:
		var vis: Dictionary = {}
		var vis_s: Dictionary = {}
		for enemy: Unit in units:
			if enemy.side == side or not enemy.alive:
				continue
			var seen: bool = false
			if enemy.is_infantry() and not full and (enemy.id + inf.round_index()) % 2 == 1:
				seen = inf.keep_previous(side, enemy, vis_s) and visible_enemies[side].has(enemy.id)
			elif enemy.is_infantry():
				seen = inf.spot_squad(self, side, enemy, vis_s)
			else:
				for own: Unit in units:
					if own.side != side or not own.alive:
						continue
					if inf.soldiers_spot_tank(self, own, enemy) if own.is_infantry() else _can_spot(own, enemy):
						seen = true
						break
			if seen:
				vis[enemy.id] = true
				known_enemies[side][enemy.id] = {"cell": enemy.cell(), "last_seen_turn": turn}
		visible_enemies[side] = vis
		inf.visible_soldiers[side] = vis_s
	minds.on_detection(self)


## Detección de un tanque por otro: LOS al centro del blanco y distancia dentro del alcance de
## detección, que depende de lo que hace el blanco: en movimiento o recién disparado, MAX_RANGE;
## quieto, SPOT_RANGE_STATIONARY; quieto y con el casco oculto para el observador, SPOT_RANGE_HULLDOWN.
func _can_spot(observer: Unit, target: Unit) -> bool:
	var d: float = TerrainAnalysis.dist_m(observer.cell(), target.cell())
	if is_suppressed(observer):
		d /= Config.TANK_BUTTONED_SPOT_FACTOR # abotonado: ve a menos distancia
	if d > Config.MAX_RANGE:
		return false
	if not analysis.los(observer.cell(), observer.eye_h(), target.cell(), target.center_h()):
		return false
	return tank_spot_rule(target, d, func() -> bool:
		return analysis.los(observer.cell(), observer.eye_h(), target.cell(), target.profile_h()))


## Regla de alcance para detectar un tanque a d metros (con LOS a su centro ya comprobada).
## hull_visible: se llama solo si hace falta saber si se le ve el casco.
func tank_spot_rule(target: Unit, d: float, hull_visible: Callable) -> bool:
	if recently_fired(target) or (target.moving and effective_pace(target) != Unit.Pace.CAUTIOUS):
		return true
	if d <= Config.SPOT_RANGE_HULLDOWN:
		return true
	if d > Config.SPOT_RANGE_STATIONARY:
		return false
	# Quieto entre los dos alcances: solo si se le ve el casco
	return bool(hull_visible.call())


func recently_fired(u: Unit) -> bool:
	return float(total_ticks - u.last_fire_tick) * Config.TICK < Config.FIRE_REVEAL_SECONDS


## Línea de tiro: LOS al centro del blanco a <= MAX_RANGE (para disparar, además
## el blanco tiene que ser visible para el bando).
func _can_see(observer: Unit, target: Unit, target_h: float) -> bool:
	return TerrainAnalysis.dist_m(observer.cell(), target.cell()) <= Config.MAX_RANGE \
		and analysis.los(observer.cell(), observer.eye_h(), target.cell(), target_h)


## Exposición del bando para un tipo de unidad (se calcula la primera vez que se pide).
func exposure_for(side: int, kind: int = Unit.Kind.TANK) -> PackedFloat32Array:
	var i: int = side * 2 + kind
	if _exposure[i].is_empty():
		var h: float = Config.INF_STAND_H if kind == Unit.Kind.INFANTRY else Config.HULL_H
		_exposure[i] = analysis.exposure_map(threats_for(side), h)
	return _exposure[i]


## Fuerza a recalcular la exposición de ambos bandos.
func invalidate_exposure() -> void:
	_exposure = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	_pathfinder_side = [-1, -1]


## Ruta para una unidad desde from hasta to, con la exposición de su bando (sin la celda from).
## Vacía si no hay ruta. No mira la fase: también sirve para rutas decididas en EXECUTE.
func _route(u: Unit, from: Vector2i, to: Vector2i, covered: bool) -> Array[Vector2i]:
	var pf: Pathfinder = pathfinders[u.kind]
	if covered and _pathfinder_side[u.kind] != u.side:
		pf.set_exposure(exposure_for(u.side, u.kind))
		_pathfinder_side[u.kind] = u.side
	var path: Array[Vector2i] = pf.find_path(from, to, covered)
	if not path.is_empty():
		path.remove_at(0)
	return path


## Calcula la ruta más cubierta para el bando de la unidad. Devuelve false si no hay ruta.
## facing: orientación final opcional (Vector2.ZERO = la de la marcha).
## covered = false: ruta directa, la más corta sin importar la exposición.
## append = true: agrega un tramo desde el destino actual (waypoint) en vez de reemplazar la ruta.
func order_move(unit_id: int, target_cell: Vector2i, facing: Vector2 = Vector2.ZERO, covered: bool = true, append: bool = false) -> bool:
	var u: Unit = get_unit(unit_id)
	if not _can_order(u):
		return false
	_new_intent(u)
	append = append and not u.path.is_empty()
	var from: Vector2i = destination(u) if append else u.cell()
	if from == target_cell and append:
		return false
	var path: Array[Vector2i] = []
	if from != target_cell:
		path = _route(u, from, target_cell, covered)
		if path.is_empty():
			return false
	if append:
		u.path.append_array(path)
	else:
		u.path = path
		u.waypoints.clear()
		u.direct_route = not covered
	if not path.is_empty():
		u.waypoints.append({"cell": target_cell, "direct": not covered})
	u.order = Unit.Order.MOVE
	u.moving = not u.path.is_empty()
	u.reversing = false
	u.attack_target = -1
	u.final_heading = facing.normalized() if facing != Vector2.ZERO else Vector2.ZERO
	if not u.moving and u.final_heading != Vector2.ZERO:
		u.heading = u.final_heading # ya está en destino: solo gira
	return true


## --- Condiciones de la cadena de órdenes ---
## Cada tramo de la ruta puede esperar una condición antes de arrancar. Una vez cumplida,
## queda abierta aunque después deje de cumplirse.

## A los seconds segundos del turno.
static func gate_time(seconds: float) -> Dictionary:
	return {"type": "time", "seconds": seconds}


## Cuando el bando ve algún enemigo.
static func gate_contact() -> Dictionary:
	return {"type": "contact"}


## Cuando alguna unidad del bando emitió la señal (go-code) con ese nombre.
static func gate_signal(name: String) -> Dictionary:
	return {"type": "signal", "name": name}


## Cuando la otra unidad terminó su ruta (o murió).
static func gate_unit(unit_id: int) -> Dictionary:
	return {"type": "unit", "unit": unit_id}


## Cuando esa unidad (propia o enemiga) está suprimida (o murió).
static func gate_suppressed(unit_id: int) -> Dictionary:
	return {"type": "suppressed", "unit": unit_id}


## Pone (o quita, con gate vacío) la condición del tramo leg (-1 = el último). Solo en PLAN.
func gate_leg(unit_id: int, leg: int, gate: Dictionary) -> bool:
	var wp: Variant = _leg(unit_id, leg)
	if wp == null:
		return false
	var d: Dictionary = wp
	if gate.is_empty():
		d.erase("gate")
	else:
		d["gate"] = gate.duplicate()
	d["gate_open"] = false
	return true


## El tramo leg (-1 = el último) emite la señal name al llegar a su fin. Vacío la quita. Solo en PLAN.
func signal_leg(unit_id: int, leg: int, name: String) -> bool:
	var wp: Variant = _leg(unit_id, leg)
	if wp == null:
		return false
	(wp as Dictionary)["signal"] = name
	return true


func _leg(unit_id: int, leg: int) -> Variant:
	var u: Unit = get_unit(unit_id)
	if u == null or not u.alive or phase != Phase.PLAN or u.waypoints.is_empty():
		return null
	var i: int = leg if leg >= 0 else u.waypoints.size() + leg
	if i < 0 or i >= u.waypoints.size():
		return null
	return u.waypoints[i]


## ¿El tramo actual de u espera una condición que todavía no se cumplió? Si se cumple, la abre.
func _leg_gate_closed(u: Unit) -> bool:
	if u.waypoints.is_empty():
		return false
	var wp: Dictionary = u.waypoints[0]
	if not wp.has("gate") or bool(wp.get("gate_open", false)):
		return false
	if gate_met(u, wp["gate"]):
		wp["gate_open"] = true
		return false
	return true


func gate_met(u: Unit, gate: Dictionary) -> bool:
	match str(gate.get("type", "")):
		"time":
			return float(tick_in_turn) * Config.TICK >= float(gate["seconds"]) - 0.0001
		"contact":
			return not visible_enemies[u.side].is_empty()
		"signal":
			return signals[u.side].has(gate["name"])
		"suppressed":
			var target: Unit = get_unit(int(gate["unit"]))
			return target == null or not target.alive or is_suppressed(target)
		"all_signals":
			for n: String in gate["names"]:
				if not signals[u.side].has(n):
					return false
			return true
		"unit":
			var other: Unit = get_unit(int(gate["unit"]))
			return other == null or not other.alive or (other.path.is_empty() and not other.waiting)
	return true


## --- Pelotón ---

## Pelotón de la unidad (o null).
func platoon_of(unit_id: int) -> Platoon:
	for p: Platoon in platoons:
		if p.section_of(unit_id) >= 0:
			return p
	return null


## Ids vivos de una sección.
func _alive_ids(ids: PackedInt32Array) -> Array[int]:
	var out: Array[int] = []
	for uid: int in ids:
		if units[uid].alive:
			out.append(uid)
	return out


## Celdas en línea alrededor de target (id -> Vector2i), perpendiculares a facing
## (o a lo ancho si no hay orientación), gap celdas entre unidades, ordenadas por su posición actual.
func formation_cells(ids: Array[int], target: Vector2i, facing: Vector2, gap: float = Config.FORMATION_GAP) -> Dictionary:
	var perp: Vector2 = Vector2(-facing.y, facing.x) if facing != Vector2.ZERO else Vector2(1.0, 0.0)
	var sorted: Array[int] = ids.duplicate()
	sorted.sort_custom(func(a: int, b: int) -> bool:
		return units[a].pos.dot(perp) < units[b].pos.dot(perp))
	var n: int = sorted.size()
	var out: Dictionary = {}
	for i: int in n:
		var off: Vector2 = perp * (float(i) - float(n - 1) * 0.5) * gap
		out[sorted[i]] = _clamp_cell(Vector2i((Vector2(target) + off).round()))
	return out


func _clamp_cell(c: Vector2i) -> Vector2i:
	var limit: int = height_field.size - 1
	return Vector2i(clampi(c.x, 0, limit), clampi(c.y, 0, limit))


## Destinos de un pelotón (id -> Vector2i): las secciones lado a lado a SECTION_GAP,
## cada una en línea a FORMATION_GAP. Las secciones se ordenan por su posición actual.
func platoon_cells(p: Platoon, target: Vector2i, facing: Vector2) -> Dictionary:
	var perp: Vector2 = Vector2(-facing.y, facing.x) if facing != Vector2.ZERO else Vector2(1.0, 0.0)
	var secs: Array[Array] = []
	for sec: PackedInt32Array in p.sections:
		var ids: Array[int] = _alive_ids(sec)
		if not ids.is_empty():
			secs.append(ids)
	secs.sort_custom(func(a: Array, b: Array) -> bool:
		return _centroid(a).dot(perp) < _centroid(b).dot(perp))
	var out: Dictionary = {}
	# Pelotón mixto: la infantería va al objetivo y los tanques se quedan atrás, cubriéndola
	var foot: Array[Array] = []
	var support: Array[int] = []
	for sec: Array in secs:
		if units[int(sec[0])].is_infantry():
			foot.append(sec)
		else:
			for uid: int in sec:
				support.append(uid)
	if foot.is_empty() or support.is_empty():
		foot = secs
		support.clear()
	for i: int in foot.size():
		var center: Vector2 = Vector2(target) + perp * (float(i) - float(foot.size() - 1) * 0.5) * Config.SECTION_GAP
		var ids: Array[int] = []
		ids.assign(foot[i])
		out.merge(formation_cells(ids, _clamp_cell(Vector2i(center.round())), facing))
	if not support.is_empty():
		var back: Vector2 = _centroid(support) - Vector2(target)
		var dist: float = minf(Config.TANK_SUPPORT_BACK, back.length())
		var at: Vector2 = Vector2(target) + (back.normalized() if back.length() > 0.001 else Vector2(0.0, 1.0)) * dist
		out.merge(formation_cells(support, _nearest_walkable(_clamp_cell(Vector2i(at.round())), Unit.Kind.TANK), facing))
	return out


func _centroid(ids: Array) -> Vector2:
	var sum: Vector2 = Vector2.ZERO
	for uid: int in ids:
		sum += units[uid].pos
	return sum / float(maxi(1, ids.size()))


## Mueve a cada unidad a su celda; si la celda no sirve, al punto exacto. Devuelve cuántas aceptaron.
func _move_to_cells(cells: Dictionary, target: Vector2i, facing: Vector2, covered: bool, append: bool) -> int:
	var ok: int = 0
	for uid: int in cells:
		if order_move(uid, cells[uid], facing, covered, append) or order_move(uid, target, facing, covered, append):
			ok += 1
	return ok


## Misión al pelotón de infantería del bando (fase 58): tomar target. El pelotón maniobra solo
## (ver PlatoonLeader). Solo en PLAN.
func order_mission(side: int, target: Vector2i) -> bool:
	if phase != Phase.PLAN or not height_field.in_bounds(target):
		return false
	var pl: PlatoonLeader = PlatoonLeader.new(side, target)
	if pl.squads(self).is_empty():
		return false
	missions[side] = pl
	pl.issue(self)
	return true


func cancel_mission(side: int) -> void:
	missions[side] = null


## Orden al pelotón: se reparte entre las secciones (ver platoon_cells).
func order_platoon_move(platoon_id: int, target: Vector2i, facing: Vector2 = Vector2.ZERO, covered: bool = true, append: bool = false) -> bool:
	if platoon_id < 0 or platoon_id >= platoons.size() or phase != Phase.PLAN:
		return false
	var p: Platoon = platoons[platoon_id]
	return _move_to_cells(platoon_cells(p, target, facing), target, facing, covered, append) > 0


## Avance por saltos: la sección más cercana al objetivo va primero y, cuando llega toda,
## arranca la otra (las demás esperan quietas, cubriendo). Usa señales de la fase 16.
func order_platoon_bound(platoon_id: int, target: Vector2i, facing: Vector2 = Vector2.ZERO) -> bool:
	if platoon_id < 0 or platoon_id >= platoons.size() or phase != Phase.PLAN:
		return false
	var p: Platoon = platoons[platoon_id]
	var cells: Dictionary = platoon_cells(p, target, facing)
	var secs: Array[Array] = []
	for sec: PackedInt32Array in p.sections:
		var ids: Array[int] = _alive_ids(sec)
		if not ids.is_empty():
			secs.append(ids)
	if secs.is_empty():
		return false
	secs.sort_custom(func(a: Array, b: Array) -> bool:
		return _centroid(a).distance_to(Vector2(target)) < _centroid(b).distance_to(Vector2(target)))
	var ok: int = 0
	var prev_signals: Array[String] = []
	for i: int in secs.size():
		var my_signals: Array[String] = []
		for uid: int in secs[i]:
			if not cells.has(uid):
				continue
			var one: Dictionary = {uid: cells[uid]}
			if _move_to_cells(one, target, facing, true, false) == 0:
				continue
			ok += 1
			if units[uid].waypoints.is_empty():
				continue # ya estaba en su celda: no espera ni avisa
			_bound_count += 1
			var sig: String = "salto %d" % _bound_count
			signal_leg(uid, -1, sig)
			my_signals.append(sig)
			# Espera a que llegue toda la sección anterior (una condición por tanque de esa sección)
			if not prev_signals.is_empty():
				gate_leg(uid, 0, _all_signals_gate(prev_signals))
		prev_signals = my_signals
	return ok > 0


## Condición compuesta: todas las señales.
static func _all_signals_gate(names: Array[String]) -> Dictionary:
	return {"type": "all_signals", "names": names.duplicate()}


## Formación de una escuadra (solo en PLAN). Dura hasta que se cambie.
func set_formation(unit_id: int, f: int) -> bool:
	var u: Unit = get_unit(unit_id)
	if u == null or not u.alive or not u.is_infantry() or phase != Phase.PLAN:
		return false
	u.formation = f
	u.shape = f
	return true


## Ritmo de una unidad (solo en PLAN). Dura hasta que se cambie.
## Orden de evacuar (en PLAN): cada herido sale hacia el borde propio con un camillero (un fusilero
## o el proveedor, el más cercano); a los EVAC_SECONDS los dos dejan el campo. Siempre queda al
## menos uno en condiciones. Devuelve cuántos heridos evacúa.
func order_evacuate(unit_id: int) -> int:
	var u: Unit = get_unit(unit_id)
	if not _can_order(u) or not u.is_infantry():
		return 0
	var n: int = 0
	for t: Soldier in u.soldiers:
		if t.state != Soldier.State.WOUNDED or u.ok_count() <= 1:
			continue
		var bearer: Soldier = null
		var best_d: float = INF
		for s: Soldier in u.soldiers:
			if s.is_ok() and s.role in [Soldier.Role.RIFLE, Soldier.Role.ASSISTANT] and s.pos.distance_to(t.pos) < best_d:
				bearer = s
				best_d = s.pos.distance_to(t.pos)
		if bearer == null:
			break
		for s: Soldier in [t, bearer]:
			s.state = Soldier.State.EVACUATING
			s.evac_left = Config.EVAC_SECONDS
			s.evac_wounded = s == t
			s.care_target = -1
			s.drag_target = -1
			s.has_cover = false
		bearer.pos = t.pos + Vector2(0.6, 0.0)
		n += 1
	u.hp = u.ok_count()
	if n > 0:
		radio(u, "evacuamos %d herido%s" % [n, "" if n == 1 else "s"])
	return n


## Autonomía de una escuadra (en cualquier fase). Bajarla a estricta la hace volver a la orden.
func set_autonomy(unit_id: int, autonomy: int) -> bool:
	var u: Unit = get_unit(unit_id)
	if u == null or not u.alive or u.mind == null:
		return false
	u.mind.autonomy = autonomy
	if not SquadMind.allowed(autonomy, u.mind.option):
		minds.switch_to(self, u, SquadMind.Option.FOLLOW)
	return true


func set_pace(unit_id: int, pace: int) -> bool:
	var u: Unit = get_unit(unit_id)
	if u == null or not u.alive or phase != Phase.PLAN:
		return false
	if pace == Unit.Pace.CRAWL and not u.is_infantry():
		pace = Unit.Pace.NORMAL # los tanques no reptan
	u.pace = pace
	return true


## El asalto siempre va a ritmo rápido.
static func effective_pace(u: Unit) -> int:
	if u.order == Unit.Order.ASSAULT:
		return Unit.Pace.FAST
	if u.mind != null and u.mind.crawling:
		return Unit.Pace.CRAWL # clavada en marcha: sigue reptando (fase 53)
	return u.pace


static func pace_speed_factor(pace: int) -> float:
	match pace:
		Unit.Pace.FAST:
			return Config.PACE_FAST_SPEED
		Unit.Pace.CAUTIOUS:
			return Config.PACE_CAUTIOUS_SPEED
		Unit.Pace.CRAWL:
			return Config.PACE_CRAWL_SPEED
	return 1.0


## Orden ASSAULT: ruta directa a ritmo rápido hasta target_cell, disparando en marcha.
## A diferencia de ATTACK, no frena al tener línea de tiro.
func order_assault(unit_id: int, target_cell: Vector2i, facing: Vector2 = Vector2.ZERO) -> bool:
	if not order_move(unit_id, target_cell, facing, false):
		return false
	units[unit_id].order = Unit.Order.ASSAULT
	return true


## Orden WITHDRAW: en reversa por la ruta cubierta, con el frente hacia las amenazas.
## Sin destino (celda fuera del mapa): la celda menos expuesta a <= WITHDRAW_RADIUS o,
## si no hay amenazas, WITHDRAW_RADIUS celdas hacia atrás.
func order_withdraw(unit_id: int, target_cell: Vector2i = Vector2i(-1, -1)) -> bool:
	var u: Unit = get_unit(unit_id)
	if not _can_order(u):
		return false
	var threats: Array[Vector2i] = threats_for(u.side)
	if not height_field.in_bounds(target_cell):
		target_cell = lowest_exposure_cell(u.side, u.cell(), Config.WITHDRAW_RADIUS, u.kind)
		if target_cell == u.cell():
			target_cell = _back_target(u)
	if target_cell == u.cell():
		return false
	var facing: Vector2 = facing_to_threats(target_cell, threats)
	if facing == Vector2.ZERO:
		facing = u.heading
	if not order_move(unit_id, target_cell, facing):
		return false
	u.order = Unit.Order.WITHDRAW
	u.reversing = u.moving
	return true


## Celda transitable de menor exposición del bando dentro de radius (desempate: la más cercana).
func lowest_exposure_cell(side: int, origin: Vector2i, radius: int, kind: int = Unit.Kind.TANK) -> Vector2i:
	var exposure: PackedFloat32Array = exposure_for(side, kind)
	var pf: Pathfinder = pathfinders[kind]
	var n: int = height_field.size
	var best: Vector2i = origin
	var best_e: float = exposure[origin.y * n + origin.x]
	var best_d: float = 0.0
	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			var c: Vector2i = origin + Vector2i(dx, dy)
			if dx * dx + dy * dy > radius * radius or not pf.is_walkable(c):
				continue
			var e: float = exposure[c.y * n + c.x]
			var d: float = Vector2(dx, dy).length()
			if e < best_e or (is_equal_approx(e, best_e) and d < best_d):
				best = c
				best_e = e
				best_d = d
	return best


## Celda transitable hasta WITHDRAW_RADIUS celdas detrás de u (contra su heading).
func _back_target(u: Unit) -> Vector2i:
	var dir: Vector2 = -u.heading.normalized()
	for back: int in Config.WITHDRAW_RADIUS:
		var c: Vector2i = Vector2i((u.pos + dir * float(Config.WITHDRAW_RADIUS - back)).round())
		if height_field.in_bounds(c) and pathfinders[u.kind].is_walkable(c):
			return c
	return u.cell()


## Orden OVERWATCH: quieto, con el casco hacia dir, y solo dispara dentro del sector
## de ±OVERWATCH_HALF_ANGLE_DEG. Cualquier otra orden la cancela.
func order_overwatch(unit_id: int, dir: Vector2) -> bool:
	var u: Unit = get_unit(unit_id)
	if not _can_order(u) or dir.length() < 0.001:
		return false
	_new_intent(u)
	u.path.clear()
	u.waypoints.clear()
	u.moving = false
	u.attack_target = -1
	u.final_heading = Vector2.ZERO
	u.reversing = false
	u.overwatch_dir = dir.normalized()
	u.heading = u.overwatch_dir
	u.order = Unit.Order.OVERWATCH
	return true


## Orden SCOOT: ir a fire_cell por la ruta cubierta, hacer un disparo y volver en reversa
## (mirando al blanco) a la celda de partida. Si no tiene a quién tirar, espera en fire_cell.
func order_scoot(unit_id: int, fire_cell: Vector2i) -> bool:
	var u: Unit = get_unit(unit_id)
	if u == null or not u.alive or fire_cell == u.cell():
		return false
	var origin: Vector2i = u.cell()
	if not order_move(unit_id, fire_cell):
		return false
	u.order = Unit.Order.SCOOT
	u.return_cell = origin
	u.scoot_fired = false
	return true


## Tras el disparo de una orden SCOOT: ruta cubierta de vuelta, en reversa, mirando al blanco.
func _start_scoot_return(u: Unit, target: Unit) -> void:
	u.scoot_fired = true
	_face(u, target.pos)
	u.final_heading = u.heading
	u.path = _route(u, u.cell(), u.return_cell, true)
	u.waypoints.clear()
	if not u.path.is_empty():
		u.waypoints.append({"cell": u.return_cell, "direct": false})
	u.direct_route = false
	u.moving = not u.path.is_empty()
	u.reversing = u.moving


## Humo: una nube en cell, a <= SMOKE_RANGE y con LOS desde la unidad, si le quedan cargas.
## Aparece en el acto (en PLAN) y dura SMOKE_TURNS turnos; la exposición se recalcula.
func order_smoke(unit_id: int, cell: Vector2i) -> bool:
	var u: Unit = get_unit(unit_id)
	if u == null or not u.alive or (phase != Phase.PLAN and _autonomous == 0) or u.smoke_charges <= 0:
		return false
	if not height_field.in_bounds(cell) or not can_smoke_at(u, cell):
		return false
	u.smoke_charges -= 1
	smoke_clouds.append({
		"id": _next_smoke_id,
		"center": Vector2(cell),
		"radius": Config.SMOKE_RADIUS,
		"top_h": height_field.height_at_cell(cell) + Config.SMOKE_HEIGHT,
		"turns_left": Config.SMOKE_TURNS,
		"side": u.side,
	})
	_next_smoke_id += 1
	invalidate_exposure()
	return true


## Granada de humo de mano de una escuadra: una nube chica en at_m que dura INF_SMOKE_SECONDS
## (vale también en la ejecución).
func hand_smoke(u: Unit, at_m: Vector2) -> bool:
	if u == null or not u.alive or u.smoke_charges <= 0:
		return false
	var limit: float = float(height_field.size - 1)
	var c: Vector2 = at_m / Config.CELL_SIZE
	c = Vector2(clampf(c.x, 0.0, limit), clampf(c.y, 0.0, limit))
	u.smoke_charges -= 1
	smoke_clouds.append({
		"id": _next_smoke_id,
		"center": c,
		"radius": Config.INF_SMOKE_RADIUS,
		"top_h": height_field.height_at(c) + Config.INF_SMOKE_HEIGHT,
		"turns_left": 1000000,
		"ticks_left": roundi(Config.INF_SMOKE_SECONDS / Config.TICK),
		"side": u.side,
	})
	_next_smoke_id += 1
	invalidate_exposure()
	return true


## Las nubes de mano se van por tiempo.
func _tick_smoke() -> void:
	for i: int in range(smoke_clouds.size() - 1, -1, -1):
		var cloud: Dictionary = smoke_clouds[i]
		if cloud.has("ticks_left"):
			cloud["ticks_left"] = int(cloud["ticks_left"]) - 1
			if int(cloud["ticks_left"]) <= 0:
				smoke_clouds.remove_at(i)
				invalidate_exposure()


func can_smoke_at(u: Unit, cell: Vector2i) -> bool:
	return TerrainAnalysis.dist_m(u.cell(), cell) <= Config.SMOKE_RANGE \
		and analysis.los(u.cell(), u.eye_h(), cell, 1.0)


## Fin de turno: cada nube pierde un turno y se van las que llegaron a cero.
func _age_smoke() -> void:
	for i: int in range(smoke_clouds.size() - 1, -1, -1):
		smoke_clouds[i]["turns_left"] = int(smoke_clouds[i]["turns_left"]) - 1
		if int(smoke_clouds[i]["turns_left"]) <= 0:
			smoke_clouds.remove_at(i)


## ¿Está el punto at (en celdas) dentro del sector de vigilancia de u?
static func in_overwatch_sector(u: Unit, at: Vector2) -> bool:
	var d: Vector2 = at - u.pos
	if d.length_squared() < 0.0001:
		return true
	return u.overwatch_dir.dot(d.normalized()) >= cos(deg_to_rad(Config.OVERWATCH_HALF_ANGLE_DEG))


## Orden ATTACK: avanzar por la ruta cubierta hacia la última posición conocida del enemigo,
## detenerse apenas tenga línea de tiro y el bando lo vea y priorizarlo como blanco. Solo enemigos conocidos.
func order_attack(unit_id: int, enemy_id: int) -> bool:
	var u: Unit = get_unit(unit_id)
	var enemy: Unit = get_unit(enemy_id)
	if not _can_order(u) or enemy == null or not enemy.alive or enemy.side == u.side:
		return false
	if phase != Phase.PLAN or not known_enemies[u.side].has(enemy_id):
		return false
	if _can_see(u, enemy, enemy.center_h()) and visible_enemies[u.side].has(enemy_id):
		_new_intent(u)
		u.path.clear()
		u.moving = false
		u.final_heading = Vector2.ZERO
		_face(u, enemy.pos)
	elif not order_move(unit_id, known_enemies[u.side][enemy_id]["cell"]):
		return false
	u.order = Unit.Order.ATTACK
	u.attack_target = enemy_id
	return true


## Atacantes: frenan al tener línea de tiro; si el blanco murió, la orden termina.
func _update_attackers() -> void:
	for u: Unit in units:
		if not u.alive or u.attack_target < 0:
			continue
		var enemy: Unit = units[u.attack_target]
		if not enemy.alive:
			u.attack_target = -1
			u.order = Unit.Order.NONE
			u.path.clear()
			u.moving = false
		elif not u.path.is_empty() and visible_enemies[u.side].has(enemy.id) and _can_see(u, enemy, enemy.center_h()):
			u.path.clear()
			u.moving = false
			u.final_heading = Vector2.ZERO
			_face(u, enemy.pos)


## Gira el casco de u hacia un punto (en celdas).
static func _face(u: Unit, at: Vector2) -> void:
	var d: Vector2 = at - u.pos
	if d.length() > 0.001:
		u.heading = d.normalized()


## Orden HULLDOWN para un grupo: cada unidad va al mejor candidato contra las amenazas
## conocidas, sin repetir celdas ni quedar a menos de HULLDOWN_MIN_SEPARATION de otra.
## Sin amenazas: avanza NO_THREAT_ADVANCE celdas hacia el centro por la ruta más cubierta.
## already_reserved: celdas ya ocupadas por otras unidades (por ejemplo, las que quedan en HOLD).
func order_hulldown(unit_ids: Array[int], already_reserved: Array[Vector2i] = []) -> void:
	var reserved: Array[Vector2i] = already_reserved.duplicate()
	for id: int in unit_ids:
		var u: Unit = get_unit(id)
		if u == null or not u.alive or phase != Phase.PLAN:
			continue
		var threats: Array[Vector2i] = threats_for(u.side)
		var target: Vector2i = u.cell()
		if threats.is_empty():
			target = _advance_target(u.cell())
		else:
			var cands: Array[Dictionary] = analysis.hulldown_candidates(u.cell(), threats, Config.HULLDOWN_RADIUS,
				u.eye_h(), u.profile_h(), u.center_h(), Config.COVER_W_TAKE_POSITION if u.is_infantry() else 0.0)
			for c: Dictionary in cands:
				var cell: Vector2i = c["cell"]
				if pathfinders[u.kind].is_walkable(cell) and is_free(cell, reserved):
					target = cell
					break
		if order_move(u.id, target, facing_to_threats(target, threats)):
			reserved.append(target)
			u.order = Unit.Order.HULLDOWN


## Dirección desde cell hacia el centroide de las amenazas (cero si no hay).
static func facing_to_threats(cell: Vector2i, threats: Array[Vector2i]) -> Vector2:
	if threats.is_empty():
		return Vector2.ZERO
	var sum: Vector2 = Vector2.ZERO
	for th: Vector2i in threats:
		sum += Vector2(th)
	var d: Vector2 = sum / float(threats.size()) - Vector2(cell)
	return d.normalized() if d.length() > 0.001 else Vector2.ZERO


## ¿Está la celda a >= HULLDOWN_MIN_SEPARATION de todas las reservadas?
static func is_free(cell: Vector2i, reserved: Array[Vector2i]) -> bool:
	for r: Vector2i in reserved:
		if Vector2(cell).distance_to(Vector2(r)) < Config.HULLDOWN_MIN_SEPARATION:
			return false
	return true


## Celda transitable a NO_THREAT_ADVANCE celdas de from en dirección al centro del mapa.
func _advance_target(from: Vector2i) -> Vector2i:
	var center: Vector2 = Vector2(height_field.size, height_field.size) * 0.5
	var to_center: Vector2 = center - Vector2(from)
	var dist: float = minf(float(Config.NO_THREAT_ADVANCE), to_center.length())
	var dir: Vector2 = to_center.normalized()
	for back: int in roundi(dist) + 1:
		var c: Vector2i = Vector2i((Vector2(from) + dir * (dist - back)).round())
		if pathfinder.is_walkable(c):
			return c
	return from


## Destino actual de una unidad (su celda si no tiene ruta).
func destination(u: Unit) -> Vector2i:
	return u.path.back() if not u.path.is_empty() else u.cell()


## Avanza un tick: movimiento, detección (cada DETECTION_INTERVAL_TICKS), combate, fin de turno.
func step() -> void:
	if game_over:
		return
	_update_attackers()
	if ai != null and phase == Phase.EXECUTE and total_ticks % Config.AI_MONITOR_TICKS == 0:
		ai.monitor(self)
	if phase == Phase.EXECUTE and total_ticks % Config.AI_MONITOR_TICKS == 0:
		for pl: PlatoonLeader in missions:
			if pl != null:
				pl.monitor(self)
	minds.update(self)
	for u: Unit in units:
		if not u.alive or u.path.is_empty():
			u.waiting = false
			continue
		if _leg_gate_closed(u):
			u.waiting = true
			u.moving = false
			continue
		u.waiting = false
		if u.is_infantry() and inf.halted(u) and not (u.mind != null and u.mind.crawling):
			u.moving = false # la mayoría suprimida: cuerpo a tierra, no avanza (salvo que repte)
			continue
		if u.mind != null and (u.mind.hold or u.mind.is_disorganized(total_ticks)):
			u.moving = false # la escuadra decidió frenar o cayó el jefe (ver MindSim)
			continue
		if u.is_infantry() and inf.lagging(u):
			u.moving = true # el ancla espera a los rezagados
			continue
		_advance(u, Config.TICK)
	inf.update_cover(self)
	inf.move_soldiers(self)
	_update_suppression()
	_update_posture()
	inf.update_postures(self)
	inf.update_peeks(self)
	inf.update_wounded(self)
	inf.update_care(self)
	inf.update_evac(self)
	inf.update_ammo(self)
	inf.update_grenades(self)
	inf.update_formations(self)
	inf.update_digging(self)
	inf.update_surrender(self)
	_update_breaches()
	_tick_smoke()
	tick_in_turn += 1
	total_ticks += 1
	if tick_in_turn % Config.DETECTION_INTERVAL_TICKS == 0:
		update_detection(false)
	_combat()
	_check_victory()
	if not game_over and tick_in_turn >= ticks_per_turn:
		_end_turn()


func is_suppressed(u: Unit) -> bool:
	return u.suppression >= Config.SUPPRESSED


## Escuadra clavada: la mayoría de sus soldados en condiciones lo están (no avanza).
func is_pinned(u: Unit) -> bool:
	return u.is_infantry() and inf.pinned_fraction(u) > 0.5


## La supresión baja sola pasado un rato sin fuego; la infantería suprimida pierde moral.
func _update_suppression() -> void:
	for u: Unit in units:
		if not u.alive:
			continue
		if u.is_infantry():
			# Por soldado; la escuadra pierde moral según la parte de sus soldados suprimidos
			var frac: float = inf.decay_suppression(self, u)
			_lose_morale(u, Config.MORALE_SUPP_DRAIN * frac * Config.TICK)
			continue
		if float(total_ticks - u.last_suppressed_tick) * Config.TICK > Config.SUPP_DECAY_DELAY:
			u.suppression = maxf(0.0, u.suppression - Config.SUPP_DECAY * Config.TICK)


func _lose_morale(u: Unit, amount: float) -> void:
	if not u.is_infantry():
		return
	u.morale = maxf(0.0, u.morale - amount)
	if u.morale < Config.MORALE_BREAK:
		if not u.broken:
			u.broken_tick = total_ticks
		u.broken = true


## Supresión de un disparo con el arma w contra target (y la mitad a las unidades cercanas del mismo bando).
func _suppress(target: Unit, w: int, hit: bool, factor: float = 1.0) -> void:
	var amount: float = weapon_suppression(w) * factor * (Config.SUPP_HIT_MULT if hit else 1.0)
	for u: Unit in units:
		if not u.alive or u.side != target.side:
			continue
		var d: float = u.pos.distance_to(target.pos)
		if u == target:
			_add_suppression(u, amount)
		elif d <= Config.SUPP_NEAR_RADIUS:
			_add_suppression(u, amount * 0.5)


## Supresión a toda la unidad (a una escuadra, a cada uno de sus soldados: fuego de área y cañón).
func _add_suppression(u: Unit, amount: float) -> void:
	if u.is_infantry():
		for s: Soldier in u.soldiers:
			if s.is_ok():
				inf.add_soldier_suppression(self, s, amount)
		inf.aggregate_suppression(u)
	else:
		u.suppression = minf(100.0, u.suppression + amount)
	u.last_suppressed_tick = total_ticks
	if u.is_infantry() and is_suppressed(u):
		u.prone = true
		u.still_time = maxf(u.still_time, Config.INF_PRONE_SECONDS)


static func weapon_suppression(w: int) -> float:
	match w:
		Unit.Weapon.MG:
			return Config.SUPP_MG
		Unit.Weapon.COAX:
			return Config.SUPP_COAX
		Unit.Weapon.RIFLES:
			return Config.SUPP_RIFLES
		Unit.Weapon.AT:
			return Config.SUPP_AT
	return Config.SUPP_CANNON


## Infantería: en movimiento va de pie; quieta INF_PRONE_SECONDS, cuerpo a tierra.
func _update_posture() -> void:
	for u: Unit in units:
		if not u.alive or not u.is_infantry():
			continue
		if u.moving:
			u.still_time = 0.0
			u.prone = false
		elif is_suppressed(u):
			u.prone = true
		else:
			u.still_time += Config.TICK
			u.prone = u.still_time >= Config.INF_PRONE_SECONDS - 0.0001


func _combat() -> void:
	for shooter: Unit in units:
		if shooter.alive and shooter.is_infantry():
			inf.fire_squad(self, shooter) # cada soldado con su arma
			continue
		for slot: int in 2:
			if shooter.alive:
				_fire_slot(shooter, slot)


## Un arma de un tirador: recarga y, si está lista y hay blanco, dispara.
func _fire_slot(shooter: Unit, slot: int) -> void:
	var w: int = shooter.weapon(slot)
	if slot == 0:
		shooter.reload_left = maxf(0.0, shooter.reload_left - Config.TICK)
		if shooter.reload_left > 0.0:
			return
	else:
		shooter.reload2_left = maxf(0.0, shooter.reload2_left - Config.TICK)
		if shooter.reload2_left > 0.0 or (w == Unit.Weapon.AT and shooter.at_charges <= 0):
			return
	if is_pinned(shooter):
		return
	var anti_inf: bool = weapon_target_kind(w) == Unit.Kind.INFANTRY
	if anti_inf and shooter.order == Unit.Order.SUPPRESS:
		if roe_allows_fire(shooter):
			_area_fire(shooter, slot, w)
		return
	if w == Unit.Weapon.COAX:
		inf.tank_coax(self, shooter) # ráfaga a un soldado visible
		return
	var target: Unit = _pick_target(shooter, w)
	if target == null:
		return
	if slot == 0:
		shooter.reload_left = weapon_reload(w)
	else:
		shooter.reload2_left = weapon_reload(w)
	if w == Unit.Weapon.AT:
		shooter.at_charges -= 1
	shooter.last_fire_tick = total_ticks
	# Fogonazo: el bando del blanco sabe de dónde vino el tiro, aunque no lo vea
	known_enemies[target.side][shooter.id] = {"cell": shooter.cell(), "last_seen_turn": turn}
	minds.flash(self, target, shooter, shooter.pos_m())
	target.shots_received += 1
	target.last_fired_upon_tick = total_ticks
	var hit: bool = rng.randf() < hit_probability(shooter, target, w)
	if hit:
		_damage(target)
	_suppress(target, w, hit)
	shooter.overwatch_ready = false
	if shooter.order == Unit.Order.SCOOT and not shooter.scoot_fired:
		_start_scoot_return(shooter, target)
	shot_events.append({"shooter": shooter.id, "target": target.id, "hit": hit,
		"aspect": aspect_of(target, shooter.pos), "weapon": w})


## Un impacto: un hombre menos (con su golpe a la moral) o un impacto de cañón.
func _damage(target: Unit) -> void:
	if target.is_infantry():
		var s: Soldier = inf.random_ok(self, target)
		if s != null:
			damage_soldier(target, s)
		return
	target.hp -= 1
	_check_dead(target)


## Un impacto en un soldado (herido o muerto, ver InfantrySim.hit_soldier); si estaba en
## condiciones, la escuadra pierde moral.
func damage_soldier(u: Unit, s: Soldier) -> void:
	var was_ok: bool = s.is_ok()
	inf.hit_soldier(self, u, s)
	if was_ok:
		_lose_morale(u, Config.MORALE_PER_CASUALTY + (Config.MORALE_LEADER_LOSS if s.role == Soldier.Role.LEADER else 0.0))
		if s.role == Soldier.Role.LEADER and u.mind != null:
			minds.on_leader_lost(self, u)
	_check_dead(u)


## La escuadra se rinde: fuera de combate (los soldados quedan, sin pelear).
func surrender(u: Unit) -> void:
	u.surrendered = true
	u.alive = false
	u.moving = false
	u.path.clear()
	u.waypoints.clear()
	radio(u, "¡nos rendimos!")
	decision_counts["se rinde"] = int(decision_counts.get("se rinde", 0)) + 1


func _check_dead(u: Unit) -> void:
	if u.hp <= 0 and u.alive:
		u.alive = false
		u.moving = false
		u.path.clear()


## Fuego de área de la orden SUPPRESS: bate la zona aunque no haya blanco visible.
## Suprime a todo enemigo en SUPPRESS_AREA_RADIUS y casi no causa bajas.
func _area_fire(shooter: Unit, slot: int, w: int) -> void:
	if not can_suppress_at(shooter, shooter.suppress_cell):
		return
	if slot == 0:
		shooter.reload_left = weapon_reload(w)
	else:
		shooter.reload2_left = weapon_reload(w)
	shooter.last_fire_tick = total_ticks
	var center: Vector2 = Vector2(shooter.suppress_cell)
	for u: Unit in units:
		if not u.alive or u.side == shooter.side or u.pos.distance_to(center) > Config.SUPPRESS_AREA_RADIUS:
			continue
		known_enemies[u.side][shooter.id] = {"cell": shooter.cell(), "last_seen_turn": turn}
		minds.flash(self, u, shooter, shooter.pos_m())
		if u.is_infantry() and rng.randf() < hit_probability(shooter, u, w) * Config.SUPPRESS_AREA_HIT_FACTOR:
			_damage(u)
		_add_suppression(u, weapon_suppression(w) * Config.SUPPRESS_AREA_SUPP)
	shot_events.append({"shooter": shooter.id, "target": -1, "cell": shooter.suppress_cell, "hit": false,
		"aspect": Aspect.FRONT, "weapon": w})


## ¿Puede batir la zona? Alcance del arma antipersonal y línea de visión al suelo de la zona.
func can_suppress_at(u: Unit, cell: Vector2i) -> bool:
	var w: int = u.weapon(0) if u.is_infantry() else u.weapon(1)
	return height_field.in_bounds(cell) and TerrainAnalysis.dist_m(u.cell(), cell) <= weapon_range(w) \
		and analysis.los(u.cell(), u.eye_h(), cell, 1.0)


## Orden SUPPRESS: quieta, batiendo la zona alrededor de cell con su arma antipersonal
## (fusiles o coaxial). El cañón del tanque sigue tirando a tanques. Solo en PLAN.
func order_suppress(unit_id: int, cell: Vector2i) -> bool:
	var u: Unit = get_unit(unit_id)
	if not _can_order(u) or not can_suppress_at(u, cell):
		return false
	_new_intent(u)
	u.path.clear()
	u.waypoints.clear()
	u.moving = false
	u.attack_target = -1
	u.reversing = false
	u.final_heading = Vector2.ZERO
	_face(u, Vector2(cell))
	u.suppress_cell = cell
	u.order = Unit.Order.SUPPRESS
	return true


## ¿Contra qué tipo de unidad sirve el arma?
static func weapon_target_kind(w: int) -> int:
	return Unit.Kind.INFANTRY if w == Unit.Weapon.COAX or w == Unit.Weapon.RIFLES or w == Unit.Weapon.MG else Unit.Kind.TANK


static func weapon_range(w: int) -> float:
	match w:
		Unit.Weapon.MG:
			return Config.SOLDIER_MG_RANGE
		Unit.Weapon.COAX:
			return Config.COAX_RANGE
		Unit.Weapon.RIFLES:
			return Config.RIFLES_RANGE
		Unit.Weapon.AT:
			return Config.AT_RANGE
	return Config.MAX_RANGE


static func weapon_reload(w: int) -> float:
	match w:
		Unit.Weapon.MG:
			return Config.SOLDIER_MG_RELOAD
		Unit.Weapon.COAX:
			return Config.COAX_RELOAD
		Unit.Weapon.RIFLES:
			return Config.RIFLES_RELOAD
		Unit.Weapon.AT:
			return Config.AT_RELOAD
	return Config.RELOAD_SECONDS


## Enemigo visible para el bando del tirador, más cercano, al que el tirador ve
## y que su ROE permite (arco y distancia máxima de enganche incluidos).
## weapon: solo blancos del tipo que el arma puede dañar y dentro de su alcance.
func _pick_target(shooter: Unit, weapon: int = Unit.Weapon.CANNON) -> Unit:
	if not roe_allows_fire(shooter):
		return null
	var kind: int = weapon_target_kind(weapon)
	var reach: float = weapon_range(weapon)
	var vis: Dictionary = visible_enemies[shooter.side]
	# Blanco prioritario de la orden ATTACK, si se lo puede tirar
	if shooter.attack_target >= 0 and vis.has(shooter.attack_target):
		var prio: Unit = units[shooter.attack_target]
		if prio.alive and prio.kind == kind and _can_engage(shooter, prio, reach):
			return prio
	var best: Unit = null
	var best_d: float = INF
	for id: int in vis:
		var enemy: Unit = units[id]
		if not enemy.alive or enemy.kind != kind:
			continue
		var d: float = TerrainAnalysis.dist_m(shooter.cell(), enemy.cell())
		if shooter.order == Unit.Order.OVERWATCH and not in_overwatch_sector(shooter, enemy.pos):
			continue
		if d < best_d and _can_engage(shooter, enemy, reach):
			best = enemy
			best_d = d
	return best


## Línea de tiro y dentro del arco y la distancia máxima de enganche del tirador.
func _can_engage(shooter: Unit, enemy: Unit, reach: float = Config.MAX_RANGE) -> bool:
	return TerrainAnalysis.dist_m(shooter.cell(), enemy.cell()) <= minf(shooter.max_engage_m, reach) \
		and in_fire_arc(shooter, enemy.pos) and _can_see(shooter, enemy, enemy.center_h())


## ¿La ROE de u le deja abrir fuego ahora?
func roe_allows_fire(u: Unit) -> bool:
	match u.roe:
		Unit.Roe.HOLD:
			return false
		Unit.Roe.RETURN_FIRE:
			return fired_upon_recently(u)
	return true


## ¿Recibió un disparo en los últimos ROE_RETURN_FIRE_SECONDS?
## ¿Le tiraron en los últimos seconds segundos?
func fired_upon_within(u: Unit, seconds: float) -> bool:
	return float(total_ticks - u.last_fired_upon_tick) * Config.TICK < seconds


func fired_upon_recently(u: Unit) -> bool:
	return float(total_ticks - u.last_fired_upon_tick) * Config.TICK < Config.ROE_RETURN_FIRE_SECONDS


## ¿Está at (en celdas) dentro del arco de tiro de u? Sin arco, siempre.
static func in_fire_arc(u: Unit, at: Vector2) -> bool:
	if u.fire_arc_dir == Vector2.ZERO:
		return true
	var d: Vector2 = at - u.pos
	if d.length_squared() < 0.0001:
		return true
	return u.fire_arc_dir.dot(d.normalized()) >= cos(deg_to_rad(Config.FIRE_ARC_HALF_ANGLE_DEG))


## Reglas de fuego de una unidad (solo en PLAN). Duran hasta que se cambien.
func set_roe(unit_id: int, roe: int) -> bool:
	var u: Unit = get_unit(unit_id)
	if u == null or not u.alive or phase != Phase.PLAN:
		return false
	u.roe = roe
	return true


## Arco de tiro (dir cero = sin arco) y distancia máxima de enganche, en metros (tope MAX_RANGE). Solo en PLAN.
func set_engagement(unit_id: int, arc_dir: Vector2, max_m: float = Config.MAX_RANGE) -> bool:
	var u: Unit = get_unit(unit_id)
	if u == null or not u.alive or phase != Phase.PLAN:
		return false
	u.fire_arc_dir = arc_dir.normalized() if arc_dir.length() > 0.001 else Vector2.ZERO
	u.max_engage_m = clampf(max_m, 0.0, Config.MAX_RANGE)
	return true


## Qué cara le muestra target a un tirador en from: frente, flanco o retaguardia,
## según el ángulo entre el heading del blanco y la dirección al tirador.
static func aspect_of(target: Unit, from: Vector2) -> int:
	return aspect_from(target.heading, target.pos, from)


## Igual que aspect_of, para un blanco hipotético con ese heading en target_pos.
static func aspect_from(heading: Vector2, target_pos: Vector2, from: Vector2) -> int:
	var to_shooter: Vector2 = from - target_pos
	if to_shooter.length_squared() < 0.0001 or heading.length_squared() < 0.0001:
		return Aspect.FRONT
	var c: float = heading.normalized().dot(to_shooter.normalized())
	if c >= Config.ARMOR_FRONT_COS:
		return Aspect.FRONT
	if c <= -Config.ARMOR_FRONT_COS:
		return Aspect.REAR
	return Aspect.FLANK


static func aspect_factor(aspect: int) -> float:
	match aspect:
		Aspect.FRONT:
			return Config.ARMOR_FRONT_FACTOR
		Aspect.REAR:
			return Config.ARMOR_REAR_FACTOR
	return Config.ARMOR_FLANK_FACTOR


## Cañón: p = P_HIT_BASE x distancia x casco x movimiento (x emboscada) x blindaje (tope P_HIT_MAX).
## Otras armas: p del arma x distancia (sobre su alcance) x movimiento x postura del blanco
## x escuadra diezmada; el antitanque además x casco x blindaje.
func hit_probability(shooter: Unit, target: Unit, weapon: int = Unit.Weapon.CANNON) -> float:
	var d: float = TerrainAnalysis.dist_m(shooter.cell(), target.cell())
	var reach: float = weapon_range(weapon)
	var f_dist: float = clampf(1.0 - d / reach, 0.2, 1.0)
	var f_move: float = 1.0
	if shooter.moving:
		match effective_pace(shooter):
			Unit.Pace.FAST:
				f_move = moving_shooter_factor * Config.PACE_FAST_FIRE_FACTOR
			Unit.Pace.CAUTIOUS:
				f_move = Config.PACE_CAUTIOUS_FIRE_FACTOR
			_:
				f_move = moving_shooter_factor
	if weapon == Unit.Weapon.COAX or weapon == Unit.Weapon.RIFLES:
		var p: float = Config.COAX_P_HIT if weapon == Unit.Weapon.COAX else Config.RIFLES_P_HIT
		var f_posture: float = Config.INF_PRONE_HIT_FACTOR if target.prone else 1.0
		var f_cover: float = 1.0 - cover_at(target.cell())
		return minf(p * f_dist * f_move * f_posture * f_cover * _weak_factor(shooter), p_hit_max)
	var f_hull: float = 1.0
	if not analysis.los(shooter.cell(), shooter.eye_h(), target.cell(), target.profile_h()):
		f_hull = hulldown_hit_factor
	var f_armor: float = aspect_factor(aspect_of(target, shooter.pos)) if armor_enabled and not target.is_infantry() else 1.0
	if weapon == Unit.Weapon.AT:
		return minf(Config.AT_P_HIT * f_dist * f_move * f_hull * f_armor * _weak_factor(shooter), p_hit_max)
	if shooter.order == Unit.Order.OVERWATCH and shooter.overwatch_ready and target.moving:
		f_move *= Config.OVERWATCH_FIRST_SHOT_FACTOR # emboscada
	return minf(p_hit_base * f_dist * f_hull * f_move * f_armor, p_hit_max)


## Tirador en movimiento: factor de impacto según el ritmo (1 si está quieto).
func move_fire_factor(u: Unit, moving: bool) -> float:
	if not moving:
		return 1.0
	match effective_pace(u):
		Unit.Pace.FAST:
			return moving_shooter_factor * Config.PACE_FAST_FIRE_FACTOR
		Unit.Pace.CAUTIOUS, Unit.Pace.CRAWL:
			return Config.PACE_CAUTIOUS_FIRE_FACTOR
	return moving_shooter_factor


## Escuadra diezmada o suprimida: tira peor.
static func _weak_factor(shooter: Unit) -> float:
	var f: float = 1.0
	if shooter.is_infantry() and shooter.hp <= Config.INF_WEAK_MEN:
		f *= Config.INF_WEAK_FACTOR
	if shooter.is_infantry() and shooter.suppression >= Config.SUPPRESSED:
		f *= Config.SUPPRESSED_FIRE_FACTOR
	return f


## Probabilidad de que un tirador quieto en shooter_cell impacte a un blanco en target_cell
## con ese heading (para la vista previa de riesgo: sin emboscada ni movimiento del tirador).
func hit_probability_at(shooter_cell: Vector2i, target_cell: Vector2i, target_heading: Vector2,
		target_profile_h: float = Config.HULL_H) -> float:
	var d: float = TerrainAnalysis.dist_m(shooter_cell, target_cell)
	var f_dist: float = clampf(1.0 - d / Config.MAX_RANGE, 0.2, 1.0)
	var f_hull: float = 1.0
	if not analysis.los(shooter_cell, Config.EYE_H, target_cell, target_profile_h):
		f_hull = hulldown_hit_factor
	var f_armor: float = 1.0
	if armor_enabled:
		f_armor = aspect_factor(aspect_from(target_heading, Vector2(target_cell), Vector2(shooter_cell)))
	return minf(p_hit_base * f_dist * f_hull * f_armor, p_hit_max)


## Vista previa de riesgo de la ruta planificada de una unidad contra las amenazas conocidas
## de su bando (en su última posición conocida, quietas y con la recarga lista).
## Devuelve {total_s, exposed_s, expected_hits, threats_seeing, worst_aspect (-1 = nunca lo ven),
## level (0 bajo, 1 medio, 2 alto), exposed (PackedByteArray: 1 si la celda i de la ruta está expuesta)}.
## No cuenta las esperas de las condiciones de los tramos.
func route_risk(unit_id: int) -> Dictionary:
	var u: Unit = get_unit(unit_id)
	var out: Dictionary = {"total_s": 0.0, "exposed_s": 0.0, "expected_hits": 0.0, "threats_seeing": 0,
		"worst_aspect": -1, "level": 0, "exposed": PackedByteArray()}
	if u == null or not u.alive or u.path.is_empty():
		return out
	var threats: Array[Vector2i] = threats_for(u.side)
	var pace: int = effective_pace(u)
	var spot_m: float = Config.SPOT_RANGE_STATIONARY if pace in [Unit.Pace.CAUTIOUS, Unit.Pace.CRAWL] else Config.MAX_RANGE
	var seeing: Dictionary = {}
	var exposed: PackedByteArray = PackedByteArray()
	var pos: Vector2 = u.pos
	var heading: Vector2 = u.heading
	var total: float = 0.0
	var exposed_s: float = 0.0
	var hits: float = 0.0
	var worst: int = -1
	for c: Vector2i in u.path:
		var delta: Vector2 = Vector2(c) - pos
		var speed: float = speed_at(c, u.kind) * pace_speed_factor(pace) * (Config.REVERSE_SPEED_FACTOR if u.reversing else 1.0)
		var dt: float = delta.length() * Config.CELL_SIZE / maxf(speed, 0.01)
		if not u.reversing and delta.length() > 0.0001:
			heading = delta.normalized()
		total += dt
		var seen_here: bool = false
		for i: int in threats.size():
			var th: Vector2i = threats[i]
			if TerrainAnalysis.dist_m(th, c) > minf(spot_m, Config.MAX_RANGE) \
					or not analysis.los(th, Config.EYE_H, c, u.center_h()):
				continue
			seen_here = true
			seeing[i] = true
			hits += dt / Config.RELOAD_SECONDS * hit_probability_at(th, c, heading, u.profile_h())
			worst = maxi(worst, aspect_from(heading, Vector2(c), Vector2(th)))
		if seen_here:
			exposed_s += dt
		exposed.append(1 if seen_here else 0)
		pos = Vector2(c)
	out["total_s"] = total
	out["exposed_s"] = exposed_s
	out["expected_hits"] = hits
	out["threats_seeing"] = seeing.size()
	out["worst_aspect"] = worst
	out["exposed"] = exposed
	var level: int = 0
	if hits >= Config.RISK_HIGH_HITS:
		level = 2
	elif hits >= Config.RISK_MEDIUM_HITS or worst == Aspect.REAR:
		level = 1
	out["level"] = level
	return out


func alive_count(side: int) -> int:
	var n: int = 0
	for u: Unit in units:
		if u.side == side and u.alive:
			n += 1
	return n


func _check_victory() -> void:
	var blue: int = alive_count(0)
	var red: int = alive_count(1)
	if blue > 0 and red > 0:
		return
	game_over = true
	winner = DRAW if blue == red else (0 if blue > 0 else 1)


func _end_turn() -> void:
	_age_smoke()
	for u: Unit in units:
		if u.alive and u.is_infantry() and not is_suppressed(u):
			u.morale = minf(100.0, u.morale + Config.MORALE_RECOVER_PER_TURN)
			if u.broken and u.morale >= Config.MORALE_RALLY:
				u.broken = false
	update_detection()
	if turn >= Config.MAX_TURNS:
		var blue: int = alive_count(0)
		var red: int = alive_count(1)
		game_over = true
		winner = DRAW if blue == red else (0 if blue > red else 1)
		if has_objective():
			# La loma (y el pueblo): el azul gana solo si ocupa la cresta sin rojos; en disputa, empate; si no, gana el rojo
			var holder: int = objective_holder()
			winner = 0 if holder == 0 else (DRAW if holder == DRAW else 1)
		phase = Phase.PLAN
		return
	turn += 1
	tick_in_turn = 0
	start_plan()


## Centro del objetivo de la loma: el eje de la cresta en el medio del mapa.
func objective_cell() -> Vector2i:
	if scenario == Scenario.PUEBLO:
		return TownGenerator.center_cell(height_field)
	var x: int = height_field.size / 2
	return Vector2i(x, roundi(height_field.ridge_center_y(float(x))))


## Quién ocupa el objetivo: el bando con infantería viva y sin quebrar a <= LOMA_OBJECTIVE_RADIUS
## (y el otro sin ninguna), DRAW si los dos, NO_WINNER si nadie.
func objective_holder() -> int:
	var present: Array[bool] = [false, false]
	var center: Vector2 = Vector2(objective_cell())
	for u: Unit in units:
		if u.alive and u.is_infantry() and not u.broken and u.pos.distance_to(center) <= objective_radius():
			present[u.side] = true
	if present[0] and present[1]:
		return DRAW
	if present[0]:
		return 0
	if present[1]:
		return 1
	return NO_WINNER


func speed_at(c: Vector2i, kind: int = Unit.Kind.TANK) -> float:
	var max_slope: float = Config.INF_MAX_SLOPE if kind == Unit.Kind.INFANTRY else Config.PATH_MAX_SLOPE
	var base: float = Config.INF_SPEED if kind == Unit.Kind.INFANTRY else Config.TANK_SPEED
	if kind == Unit.Kind.TANK and cover != null and cover.is_forest(c):
		base *= Config.FOREST_TANK_SPEED
	var t: float = clampf(height_field.slope_at(c) / max_slope, 0.0, 1.0)
	return base * lerpf(1.0, Config.SLOPE_SPEED_PENALTY, t)


func _advance(u: Unit, dt: float) -> void:
	var budget_m: float = speed_at(u.cell(), u.kind) * pace_speed_factor(effective_pace(u)) * dt
	if u.reversing:
		budget_m *= Config.REVERSE_SPEED_FACTOR
	while budget_m > 0.0 and not u.path.is_empty():
		var target: Vector2 = Vector2(u.path[0])
		var delta: Vector2 = target - u.pos
		var d_m: float = delta.length() * Config.CELL_SIZE
		if d_m > 0.0001 and not u.reversing:
			u.heading = delta.normalized()
		if d_m <= budget_m:
			u.pos = target
			budget_m -= d_m
			var reached: Vector2i = u.path[0]
			u.path.remove_at(0)
			if not u.waypoints.is_empty() and u.waypoints[0]["cell"] == reached:
				var done: Dictionary = u.waypoints.pop_front()
				if str(done.get("signal", "")) != "":
					signals[u.side][done["signal"]] = total_ticks
				if _leg_gate_closed(u):
					break # espera la condición del tramo siguiente
		else:
			u.pos += delta.normalized() * (budget_m / Config.CELL_SIZE)
			budget_m = 0.0
	u.moving = not u.path.is_empty()
	if not u.moving:
		if u.final_heading != Vector2.ZERO:
			u.heading = u.final_heading
		if u.order in [Unit.Order.MOVE, Unit.Order.ASSAULT, Unit.Order.WITHDRAW] or (u.order == Unit.Order.SCOOT and u.scoot_fired):
			u.order = Unit.Order.NONE
		u.reversing = false
