class_name SimWorld
extends RefCounted
## Estado completo de la simulación. Avanza en ticks fijos de Config.TICK.
## Ciclo WeGo: PLAN (se aceptan órdenes) -> EXECUTE (ticks_per_turn ticks) -> PLAN ...

enum Phase { PLAN, EXECUTE }
enum Aspect { FRONT, FLANK, REAR }
const NO_WINNER: int = -1
const DRAW: int = 2

var height_field: HeightField
var analysis: TerrainAnalysis
var pathfinder: Pathfinder # el de los tanques (pathfinders[Unit.Kind.TANK])
var pathfinders: Array[Pathfinder] = [] # uno por tipo de unidad (índice = Unit.Kind)
var units: Array[Unit] = []
var platoons: Array[Platoon] = [] # uno por bando (índice = side)
var _bound_count: int = 0 # para nombrar las señales de los avances por saltos
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
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
var cover: CoverMap = null # cobertura fina (null = sin cobertura, como en la demo de tanques)


## Si hf es null se genera el terreno procedural con la semilla.
## with_ai: si el bando rojo lo maneja AICommander (los tests pueden apagarlo).
func _init(sim_seed: int = Config.SEED, hf: HeightField = null, with_ai: bool = true) -> void:
	if with_ai:
		ai = AICommander.new(1)
	rng.seed = sim_seed
	if hf == null:
		hf = HeightField.new()
		hf.generate(sim_seed)
	height_field = hf
	analysis = TerrainAnalysis.new(hf)
	analysis.smoke = smoke_clouds
	pathfinders = [Pathfinder.new(hf), Pathfinder.new(hf, Config.INF_MAX_SLOPE)]
	pathfinder = pathfinders[Unit.Kind.TANK]
	invalidate_exposure()
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


## Quién ve a quién: un enemigo es visible para un bando si alguna unidad viva
## de ese bando lo detecta (ver _can_spot).
func update_detection() -> void:
	for side: int in 2:
		var vis: Dictionary = {}
		for enemy: Unit in units:
			if enemy.side == side or not enemy.alive:
				continue
			for own: Unit in units:
				if own.side == side and own.alive and _can_spot(own, enemy):
					vis[enemy.id] = true
					known_enemies[side][enemy.id] = {"cell": enemy.cell(), "last_seen_turn": turn}
					break
		visible_enemies[side] = vis


## Detección: LOS al centro del blanco y distancia dentro del alcance de detección, que depende
## de lo que hace el blanco: en movimiento o recién disparado, MAX_RANGE; quieto,
## SPOT_RANGE_STATIONARY; quieto y con el casco oculto para el observador, SPOT_RANGE_HULLDOWN.
func _can_spot(observer: Unit, target: Unit) -> bool:
	var d: float = TerrainAnalysis.dist_m(observer.cell(), target.cell())
	if d > Config.MAX_RANGE:
		return false
	if not analysis.los(observer.cell(), observer.eye_h(), target.cell(), target.center_h()):
		return false
	if target.is_infantry():
		return d <= infantry_spot_range(target)
	if recently_fired(target) or (target.moving and effective_pace(target) != Unit.Pace.CAUTIOUS):
		return true
	if d <= Config.SPOT_RANGE_HULLDOWN:
		return true
	if d > Config.SPOT_RANGE_STATIONARY:
		return false
	# Quieto entre los dos alcances: solo si se le ve el casco
	return analysis.los(observer.cell(), observer.eye_h(), target.cell(), target.profile_h())


## Alcance de detección de una escuadra según lo que hace.
func infantry_spot_range(target: Unit) -> float:
	if recently_fired(target) or (target.moving and effective_pace(target) != Unit.Pace.CAUTIOUS):
		return Config.INF_SPOT_MOVING
	var f_cover: float = 1.0 - cover_at(target.cell()) * Config.COVER_SPOT_FACTOR
	if target.prone:
		return Config.INF_SPOT_PRONE * f_cover
	return Config.INF_SPOT_STILL * f_cover


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
	if u == null or not u.alive or phase != Phase.PLAN:
		return false
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
	for i: int in secs.size():
		var center: Vector2 = Vector2(target) + perp * (float(i) - float(secs.size() - 1) * 0.5) * Config.SECTION_GAP
		var ids: Array[int] = []
		ids.assign(secs[i])
		out.merge(formation_cells(ids, _clamp_cell(Vector2i(center.round())), facing))
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


## Ritmo de una unidad (solo en PLAN). Dura hasta que se cambie.
func set_pace(unit_id: int, pace: int) -> bool:
	var u: Unit = get_unit(unit_id)
	if u == null or not u.alive or phase != Phase.PLAN:
		return false
	u.pace = pace
	return true


## El asalto siempre va a ritmo rápido.
static func effective_pace(u: Unit) -> int:
	return Unit.Pace.FAST if u.order == Unit.Order.ASSAULT else u.pace


static func pace_speed_factor(pace: int) -> float:
	match pace:
		Unit.Pace.FAST:
			return Config.PACE_FAST_SPEED
		Unit.Pace.CAUTIOUS:
			return Config.PACE_CAUTIOUS_SPEED
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
	if u == null or not u.alive or phase != Phase.PLAN:
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
	if u == null or not u.alive or phase != Phase.PLAN or dir.length() < 0.001:
		return false
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
	if u == null or not u.alive or phase != Phase.PLAN or u.smoke_charges <= 0:
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
	if u == null or enemy == null or not u.alive or not enemy.alive or enemy.side == u.side:
		return false
	if phase != Phase.PLAN or not known_enemies[u.side].has(enemy_id):
		return false
	if _can_see(u, enemy, enemy.center_h()) and visible_enemies[u.side].has(enemy_id):
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
	for u: Unit in units:
		if not u.alive or u.path.is_empty():
			u.waiting = false
			continue
		if _leg_gate_closed(u):
			u.waiting = true
			u.moving = false
			continue
		u.waiting = false
		_advance(u, Config.TICK)
	_update_posture()
	tick_in_turn += 1
	total_ticks += 1
	if tick_in_turn % Config.DETECTION_INTERVAL_TICKS == 0:
		update_detection()
	_combat()
	_check_victory()
	if not game_over and tick_in_turn >= ticks_per_turn:
		_end_turn()


## Infantería: en movimiento va de pie; quieta INF_PRONE_SECONDS, cuerpo a tierra.
func _update_posture() -> void:
	for u: Unit in units:
		if not u.alive or not u.is_infantry():
			continue
		if u.moving:
			u.still_time = 0.0
			u.prone = false
		else:
			u.still_time += Config.TICK
			u.prone = u.still_time >= Config.INF_PRONE_SECONDS - 0.0001


func _combat() -> void:
	for shooter: Unit in units:
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
	target.shots_received += 1
	target.last_fired_upon_tick = total_ticks
	var hit: bool = rng.randf() < hit_probability(shooter, target, w)
	if hit:
		target.hp -= 1
		if target.hp <= 0:
			target.alive = false
			target.moving = false
			target.path.clear()
	shooter.overwatch_ready = false
	if shooter.order == Unit.Order.SCOOT and not shooter.scoot_fired:
		_start_scoot_return(shooter, target)
	shot_events.append({"shooter": shooter.id, "target": target.id, "hit": hit,
		"aspect": aspect_of(target, shooter.pos), "weapon": w})


## ¿Contra qué tipo de unidad sirve el arma?
static func weapon_target_kind(w: int) -> int:
	return Unit.Kind.INFANTRY if w == Unit.Weapon.COAX or w == Unit.Weapon.RIFLES else Unit.Kind.TANK


static func weapon_range(w: int) -> float:
	match w:
		Unit.Weapon.COAX:
			return Config.COAX_RANGE
		Unit.Weapon.RIFLES:
			return Config.RIFLES_RANGE
		Unit.Weapon.AT:
			return Config.AT_RANGE
	return Config.MAX_RANGE


static func weapon_reload(w: int) -> float:
	match w:
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


## Escuadra diezmada: tira peor.
static func _weak_factor(shooter: Unit) -> float:
	return Config.INF_WEAK_FACTOR if shooter.is_infantry() and shooter.hp <= Config.INF_WEAK_MEN else 1.0


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
	var spot_m: float = Config.SPOT_RANGE_STATIONARY if pace == Unit.Pace.CAUTIOUS else Config.MAX_RANGE
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
	update_detection()
	if turn >= Config.MAX_TURNS:
		var blue: int = alive_count(0)
		var red: int = alive_count(1)
		game_over = true
		winner = DRAW if blue == red else (0 if blue > red else 1)
		phase = Phase.PLAN
		return
	turn += 1
	tick_in_turn = 0
	start_plan()


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
