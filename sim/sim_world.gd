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
var pathfinder: Pathfinder
var units: Array[Unit] = []
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

# Disparos ocurridos desde la última vez que la vista los leyó: {shooter, target, hit, aspect}
var shot_events: Array[Dictionary] = []

# Factores de combate (se pueden cambiar en tests)
var p_hit_base: float = Config.P_HIT_BASE
var hulldown_hit_factor: float = Config.HULLDOWN_HIT_FACTOR
var moving_shooter_factor: float = Config.MOVING_SHOOTER_FACTOR
var armor_enabled: bool = true
var p_hit_max: float = Config.P_HIT_MAX

# Exposición por bando (índice = side); vacía = sin calcular
var _exposure: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
var _pathfinder_side: int = -1 # bando cuya exposición está cargada en el pathfinder
var ai: AICommander = null # IA del bando rojo (null = sin IA)


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
	pathfinder = Pathfinder.new(hf)
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
	if not analysis.los(observer.cell(), Config.EYE_H, target.cell(), Config.CENTER_H):
		return false
	if target.moving or recently_fired(target):
		return true
	if d <= Config.SPOT_RANGE_HULLDOWN:
		return true
	if d > Config.SPOT_RANGE_STATIONARY:
		return false
	# Quieto entre los dos alcances: solo si se le ve el casco
	return analysis.los(observer.cell(), Config.EYE_H, target.cell(), Config.HULL_H)


func recently_fired(u: Unit) -> bool:
	return float(total_ticks - u.last_fire_tick) * Config.TICK < Config.FIRE_REVEAL_SECONDS


## Línea de tiro: LOS al centro del blanco a <= MAX_RANGE (para disparar, además
## el blanco tiene que ser visible para el bando).
func _can_see(observer: Unit, target: Unit, target_h: float) -> bool:
	return TerrainAnalysis.dist_m(observer.cell(), target.cell()) <= Config.MAX_RANGE \
		and analysis.los(observer.cell(), Config.EYE_H, target.cell(), target_h)


## Exposición del bando (se calcula la primera vez que se pide).
func exposure_for(side: int) -> PackedFloat32Array:
	if _exposure[side].is_empty():
		_exposure[side] = analysis.exposure_map(threats_for(side))
	return _exposure[side]


## Fuerza a recalcular la exposición de ambos bandos.
func invalidate_exposure() -> void:
	_exposure = [PackedFloat32Array(), PackedFloat32Array()]
	_pathfinder_side = -1


## Ruta para una unidad desde from hasta to, con la exposición de su bando (sin la celda from).
## Vacía si no hay ruta. No mira la fase: también sirve para rutas decididas en EXECUTE.
func _route(u: Unit, from: Vector2i, to: Vector2i, covered: bool) -> Array[Vector2i]:
	if covered and _pathfinder_side != u.side:
		pathfinder.set_exposure(exposure_for(u.side))
		_pathfinder_side = u.side
	var path: Array[Vector2i] = pathfinder.find_path(from, to, covered)
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
		and analysis.los(u.cell(), Config.EYE_H, cell, 1.0)


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
	if _can_see(u, enemy, Config.CENTER_H) and visible_enemies[u.side].has(enemy_id):
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
		elif not u.path.is_empty() and visible_enemies[u.side].has(enemy.id) and _can_see(u, enemy, Config.CENTER_H):
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
			var cands: Array[Dictionary] = analysis.hulldown_candidates(u.cell(), threats, Config.HULLDOWN_RADIUS)
			for c: Dictionary in cands:
				var cell: Vector2i = c["cell"]
				if pathfinder.is_walkable(cell) and is_free(cell, reserved):
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
		if u.alive and not u.path.is_empty():
			_advance(u, Config.TICK)
	tick_in_turn += 1
	total_ticks += 1
	if tick_in_turn % Config.DETECTION_INTERVAL_TICKS == 0:
		update_detection()
	_combat()
	_check_victory()
	if not game_over and tick_in_turn >= ticks_per_turn:
		_end_turn()


func _combat() -> void:
	for shooter: Unit in units:
		if not shooter.alive:
			continue
		shooter.reload_left = maxf(0.0, shooter.reload_left - Config.TICK)
		if shooter.reload_left > 0.0:
			continue
		var target: Unit = _pick_target(shooter)
		if target == null:
			continue
		shooter.reload_left = Config.RELOAD_SECONDS
		shooter.last_fire_tick = total_ticks
		# Fogonazo: el bando del blanco sabe de dónde vino el tiro, aunque no lo vea
		known_enemies[target.side][shooter.id] = {"cell": shooter.cell(), "last_seen_turn": turn}
		target.shots_received += 1
		target.last_fired_upon_tick = total_ticks
		var hit: bool = rng.randf() < hit_probability(shooter, target)
		if hit:
			target.hp -= 1
			if target.hp <= 0:
				target.alive = false
				target.moving = false
				target.path.clear()
		shooter.overwatch_ready = false
		if shooter.order == Unit.Order.SCOOT and not shooter.scoot_fired:
			_start_scoot_return(shooter, target)
		shot_events.append({"shooter": shooter.id, "target": target.id, "hit": hit, "aspect": aspect_of(target, shooter.pos)})


## Enemigo visible para el bando del tirador, más cercano, al que el tirador ve
## y que su ROE permite (arco y distancia máxima de enganche incluidos).
func _pick_target(shooter: Unit) -> Unit:
	if not roe_allows_fire(shooter):
		return null
	var vis: Dictionary = visible_enemies[shooter.side]
	# Blanco prioritario de la orden ATTACK, si se lo puede tirar
	if shooter.attack_target >= 0 and vis.has(shooter.attack_target):
		var prio: Unit = units[shooter.attack_target]
		if prio.alive and _can_engage(shooter, prio):
			return prio
	var best: Unit = null
	var best_d: float = INF
	for id: int in vis:
		var enemy: Unit = units[id]
		if not enemy.alive:
			continue
		var d: float = TerrainAnalysis.dist_m(shooter.cell(), enemy.cell())
		if shooter.order == Unit.Order.OVERWATCH and not in_overwatch_sector(shooter, enemy.pos):
			continue
		if d < best_d and _can_engage(shooter, enemy):
			best = enemy
			best_d = d
	return best


## Línea de tiro y dentro del arco y la distancia máxima de enganche del tirador.
func _can_engage(shooter: Unit, enemy: Unit) -> bool:
	return TerrainAnalysis.dist_m(shooter.cell(), enemy.cell()) <= shooter.max_engage_m \
		and in_fire_arc(shooter, enemy.pos) and _can_see(shooter, enemy, Config.CENTER_H)


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
	var to_shooter: Vector2 = from - target.pos
	if to_shooter.length_squared() < 0.0001:
		return Aspect.FRONT
	var c: float = target.heading.normalized().dot(to_shooter.normalized())
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


## p = P_HIT_BASE x distancia x casco x movimiento (x emboscada) x blindaje (tope P_HIT_MAX).
func hit_probability(shooter: Unit, target: Unit) -> float:
	var d: float = TerrainAnalysis.dist_m(shooter.cell(), target.cell())
	var f_dist: float = clampf(1.0 - d / Config.MAX_RANGE, 0.2, 1.0)
	var f_hull: float = 1.0
	if not analysis.los(shooter.cell(), Config.EYE_H, target.cell(), Config.HULL_H):
		f_hull = hulldown_hit_factor
	var f_move: float = moving_shooter_factor if shooter.moving else 1.0
	if shooter.order == Unit.Order.OVERWATCH and shooter.overwatch_ready and target.moving:
		f_move *= Config.OVERWATCH_FIRST_SHOT_FACTOR # emboscada
	var f_armor: float = aspect_factor(aspect_of(target, shooter.pos)) if armor_enabled else 1.0
	return minf(p_hit_base * f_dist * f_hull * f_move * f_armor, p_hit_max)


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


func speed_at(c: Vector2i) -> float:
	var t: float = clampf(height_field.slope_at(c) / Config.PATH_MAX_SLOPE, 0.0, 1.0)
	return Config.TANK_SPEED * lerpf(1.0, Config.SLOPE_SPEED_PENALTY, t)


func _advance(u: Unit, dt: float) -> void:
	var budget_m: float = speed_at(u.cell()) * dt
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
				u.waypoints.remove_at(0)
		else:
			u.pos += delta.normalized() * (budget_m / Config.CELL_SIZE)
			budget_m = 0.0
	u.moving = not u.path.is_empty()
	if not u.moving:
		if u.final_heading != Vector2.ZERO:
			u.heading = u.final_heading
		if u.order == Unit.Order.MOVE or (u.order == Unit.Order.SCOOT and u.scoot_fired):
			u.order = Unit.Order.NONE
		u.reversing = false
