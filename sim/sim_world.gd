class_name SimWorld
extends RefCounted
## Estado completo de la simulación. Avanza en ticks fijos de Config.TICK.
## Ciclo WeGo: PLAN (se aceptan órdenes) -> EXECUTE (ticks_per_turn ticks) -> PLAN ...

enum Phase { PLAN, EXECUTE }
const NO_WINNER: int = -1
const DRAW: int = 2

var height_field: HeightField
var analysis: TerrainAnalysis
var pathfinder: Pathfinder
var units: Array[Unit] = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var turn: int = 1
var tick_in_turn: int = 0
var phase: int = Phase.PLAN
var ticks_per_turn: int = roundi(Config.TURN_SECONDS / Config.TICK)
var winner: int = NO_WINNER # 0 azul, 1 rojo, DRAW empate
var game_over: bool = false

# Niebla, por bando (índice = side)
var visible_enemies: Array[Dictionary] = [{}, {}] # id -> true, visibles ahora
var known_enemies: Array[Dictionary] = [{}, {}] # id -> {cell, last_seen_turn}

# Disparos ocurridos desde la última vez que la vista los leyó: {shooter, target, hit}
var shot_events: Array[Dictionary] = []

# Factores de combate (se pueden cambiar en tests)
var p_hit_base: float = Config.P_HIT_BASE
var hulldown_hit_factor: float = Config.HULLDOWN_HIT_FACTOR
var moving_shooter_factor: float = Config.MOVING_SHOOTER_FACTOR

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


## Quién ve a quién: un enemigo es visible para un bando si alguna unidad viva
## de ese bando ve su centro a <= MAX_RANGE.
func update_detection() -> void:
	for side: int in 2:
		var vis: Dictionary = {}
		for enemy: Unit in units:
			if enemy.side == side or not enemy.alive:
				continue
			for own: Unit in units:
				if own.side == side and own.alive and _can_see(own, enemy, Config.CENTER_H):
					vis[enemy.id] = true
					known_enemies[side][enemy.id] = {"cell": enemy.cell(), "last_seen_turn": turn}
					break
		visible_enemies[side] = vis


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


## Calcula la ruta más cubierta para el bando de la unidad. Devuelve false si no hay ruta.
## facing: orientación final opcional (Vector2.ZERO = la de la marcha).
## covered = false: ruta directa, la más corta sin importar la exposición.
func order_move(unit_id: int, target_cell: Vector2i, facing: Vector2 = Vector2.ZERO, covered: bool = true) -> bool:
	var u: Unit = get_unit(unit_id)
	if u == null or not u.alive or phase != Phase.PLAN:
		return false
	if _pathfinder_side != u.side:
		pathfinder.set_exposure(exposure_for(u.side))
		_pathfinder_side = u.side
	var path: Array[Vector2i] = pathfinder.find_path(u.cell(), target_cell, covered)
	if path.is_empty():
		return false
	path.remove_at(0) # la celda actual
	u.path = path
	u.direct_route = not covered
	u.order = Unit.Order.MOVE
	u.moving = not path.is_empty()
	u.attack_target = -1
	u.final_heading = facing.normalized() if facing != Vector2.ZERO else Vector2.ZERO
	if not u.moving and u.final_heading != Vector2.ZERO:
		u.heading = u.final_heading # ya está en destino: solo gira
	return true


## Orden ATTACK: avanzar por la ruta cubierta hacia la última posición conocida del enemigo,
## detenerse apenas tenga línea de tiro y priorizarlo como blanco. Solo enemigos conocidos.
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
		elif not u.path.is_empty() and _can_see(u, enemy, Config.CENTER_H):
			u.path.clear()
			u.moving = false


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
		if order_move(u.id, target):
			reserved.append(target)
			u.order = Unit.Order.HULLDOWN


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
		target.shots_received += 1
		var hit: bool = rng.randf() < hit_probability(shooter, target)
		if hit:
			target.hp -= 1
			if target.hp <= 0:
				target.alive = false
				target.moving = false
				target.path.clear()
		shot_events.append({"shooter": shooter.id, "target": target.id, "hit": hit})


## Enemigo visible para el bando del tirador, más cercano, al que el tirador ve.
func _pick_target(shooter: Unit) -> Unit:
	var vis: Dictionary = visible_enemies[shooter.side]
	# Blanco prioritario de la orden ATTACK, si se lo puede tirar
	if shooter.attack_target >= 0 and vis.has(shooter.attack_target):
		var prio: Unit = units[shooter.attack_target]
		if prio.alive and _can_see(shooter, prio, Config.CENTER_H):
			return prio
	var best: Unit = null
	var best_d: float = INF
	for id: int in vis:
		var enemy: Unit = units[id]
		if not enemy.alive:
			continue
		var d: float = TerrainAnalysis.dist_m(shooter.cell(), enemy.cell())
		if d < best_d and _can_see(shooter, enemy, Config.CENTER_H):
			best = enemy
			best_d = d
	return best


## p = P_HIT_BASE x distancia x casco x movimiento.
func hit_probability(shooter: Unit, target: Unit) -> float:
	var d: float = TerrainAnalysis.dist_m(shooter.cell(), target.cell())
	var f_dist: float = clampf(1.0 - d / Config.MAX_RANGE, 0.2, 1.0)
	var f_hull: float = 1.0
	if not analysis.los(shooter.cell(), Config.EYE_H, target.cell(), Config.HULL_H):
		f_hull = hulldown_hit_factor
	var f_move: float = moving_shooter_factor if shooter.moving else 1.0
	return p_hit_base * f_dist * f_hull * f_move


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
	while budget_m > 0.0 and not u.path.is_empty():
		var target: Vector2 = Vector2(u.path[0])
		var delta: Vector2 = target - u.pos
		var d_m: float = delta.length() * Config.CELL_SIZE
		if d_m > 0.0001:
			u.heading = delta.normalized()
		if d_m <= budget_m:
			u.pos = target
			budget_m -= d_m
			u.path.remove_at(0)
		else:
			u.pos += delta.normalized() * (budget_m / Config.CELL_SIZE)
			budget_m = 0.0
	u.moving = not u.path.is_empty()
	if not u.moving:
		if u.final_heading != Vector2.ZERO:
			u.heading = u.final_heading
		if u.order == Unit.Order.MOVE:
			u.order = Unit.Order.NONE
