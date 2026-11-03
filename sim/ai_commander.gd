class_name AICommander
extends RefCounted
## IA de un bando. Se ejecuta al entrar en PLAN y usa solo lo que su bando conoce.
## Por tanque vivo, en orden de prioridad:
##   1. hp == 1 -> retroceder a la celda de menor exposición dentro de AI_RETREAT_RADIUS.
##   2. Hay amenazas y la celda actual no es hull-down -> orden HULLDOWN.
##   3. Ya está en hull-down y puede disparar a una amenaza -> OVERWATCH hacia las amenazas.
##      (si está oculto pero no puede disparar: con una sola amenaza, SCOOT, asoma, tira y
##      vuelve; con más, HULLDOWN, busca desde dónde tirar).
##   4. Sin amenazas -> avanzar a la cresta por delante, a una posición hull-down
##      contra un observador hipotético del lado enemigo.
## Las escuadras de infantería tienen su propia lógica (ver _infantry_orders): defienden
## desde la cobertura, emboscan a corta distancia, suprimen y se repliegan diezmadas.

var side: int = 1


func _init(p_side: int) -> void:
	side = p_side


## Dirección "hacia el enemigo" en la grilla: los rojos miran al sur (+y).
func forward() -> Vector2i:
	return Vector2i(0, 1) if side == 1 else Vector2i(0, -1)


func issue_orders(world: SimWorld) -> void:
	var threats: Array[Vector2i] = world.threats_for(side)
	var hulldown_ids: Array[int] = []
	var reserved: Array[Vector2i] = []
	for u: Unit in world.units:
		if u.side != side or not u.alive:
			continue
		world.set_engagement(u.id, Vector2.ZERO, Config.MAX_RANGE)
		if u.is_infantry():
			_infantry_orders(world, u, threats, reserved)
			reserved.append(world.destination(u))
			continue
		if u.hp == 1 and not threats.is_empty():
			_retreat(world, u)
			reserved.append(world.destination(u))
		elif not threats.is_empty():
			var state: Dictionary = evaluate_cell(world, u.cell(), threats)
			if state["hull_hidden"] and state["can_fire"]:
				# Emboscada: no tira de lejos salvo que ya lo hayan atacado
				var ambush_m: float = Config.MAX_RANGE if world.fired_upon_recently(u) else Config.AI_AMBUSH_RANGE
				world.set_engagement(u.id, Vector2.ZERO, ambush_m)
				if not world.order_overwatch(u.id, SimWorld.facing_to_threats(u.cell(), threats)):
					u.path.clear()
					u.moving = false
					u.order = Unit.Order.HOLD
				reserved.append(u.cell())
			elif state["hull_hidden"] and threats.size() == 1 and _scoot(world, u, threats, reserved):
				reserved.append(u.cell())
			else:
				hulldown_ids.append(u.id)
		else:
			var target: Vector2i = crest_target(world, u.cell(), reserved)
			if world.order_move(u.id, target):
				u.order = Unit.Order.HULLDOWN if target != u.cell() else Unit.Order.HOLD
			reserved.append(world.destination(u))
	if not hulldown_ids.is_empty():
		world.order_hulldown(hulldown_ids, reserved)


## {hull_hidden, can_fire} de una celda contra las amenazas.
static func evaluate_cell(world: SimWorld, cell: Vector2i, threats: Array[Vector2i]) -> Dictionary:
	var hidden: bool = true
	var fire: bool = false
	for th: Vector2i in threats:
		if hidden and world.analysis.los(th, Config.EYE_H, cell, Config.HULL_H):
			hidden = false
		if not fire and TerrainAnalysis.dist_m(cell, th) <= Config.MAX_RANGE \
				and world.analysis.los(cell, Config.EYE_H, th, Config.CENTER_H):
			fire = true
	return {"hull_hidden": hidden, "can_fire": fire}


## Oculto y sin tiro contra una sola amenaza: asomar a la celda más cercana con tiro.
func _scoot(world: SimWorld, u: Unit, threats: Array[Vector2i], reserved: Array[Vector2i]) -> bool:
	var best: Vector2i = u.cell()
	var best_d: float = INF
	for c: Dictionary in world.analysis.hulldown_candidates(u.cell(), threats, Config.AI_SCOOT_RADIUS):
		var cell: Vector2i = c["cell"]
		var d: float = Vector2(cell).distance_to(Vector2(u.cell()))
		if c["can_fire"] and d < best_d and world.pathfinder.is_walkable(cell) and SimWorld.is_free(cell, reserved):
			best = cell
			best_d = d
	return best != u.cell() and world.order_scoot(u.id, best)


## Al retroceder expuesto: humo entre la unidad y la amenaza más cercana.
func _smoke_cover(world: SimWorld, u: Unit) -> void:
	if u.smoke_charges <= 0:
		return
	var origin: Vector2i = u.cell()
	if world.exposure_for(side)[origin.y * world.height_field.size + origin.x] <= Config.AI_SMOKE_EXPOSURE:
		return
	var nearest: Vector2i = origin
	var best_d: float = INF
	for th: Vector2i in world.threats_for(side):
		var d: float = Vector2(th).distance_to(Vector2(origin))
		if d < best_d:
			best_d = d
			nearest = th
	if nearest == origin:
		return
	var dir: Vector2 = (Vector2(nearest) - Vector2(origin)).normalized()
	var at: Vector2i = Vector2i((Vector2(origin) + dir * minf(Config.AI_SMOKE_DIST, best_d * 0.5)).round())
	world.order_smoke(u.id, at)


## Retroceder: la celda transitable de menor exposición (desempate: la más cercana).
func _retreat(world: SimWorld, u: Unit) -> void:
	var best: Vector2i = world.lowest_exposure_cell(side, u.cell(), Config.AI_RETREAT_RADIUS)
	# Llega mirando a la amenaza: el frente blindado hacia el enemigo
	world.order_move(u.id, best, SimWorld.facing_to_threats(best, world.threats_for(side)))
	# Después de elegir la ruta con la exposición sin humo: la nube tapa la retirada
	_smoke_cover(world, u)


## Sin amenazas: la cresta más alta en la columna de la unidad hacia adelante y,
## cerca de ella, la mejor posición hull-down contra un observador hipotético
## AI_CREST_PROBE_DIST celdas más adelante.
func crest_target(world: SimWorld, from: Vector2i, reserved: Array[Vector2i]) -> Vector2i:
	var hf: HeightField = world.height_field
	var fwd: Vector2i = forward()
	var crest: Vector2i = from
	var crest_h: float = hf.height_at_cell(from)
	for k: int in range(1, Config.AI_CREST_SEARCH_DEPTH + 1):
		var c: Vector2i = from + fwd * k
		if not hf.in_bounds(c):
			break
		if hf.height_at_cell(c) > crest_h:
			crest = c
			crest_h = hf.height_at_cell(c)
	var probe: Vector2i = crest + fwd * Config.AI_CREST_PROBE_DIST
	probe = Vector2i(clampi(probe.x, 0, hf.size - 1), clampi(probe.y, 0, hf.size - 1))
	var probes: Array[Vector2i] = [probe]
	var cands: Array[Dictionary] = world.analysis.hulldown_candidates(crest, probes, Config.AI_CREST_CAND_RADIUS)
	for c: Dictionary in cands:
		var cell: Vector2i = c["cell"]
		if c["hull_hidden"] and world.pathfinder.is_walkable(cell) and SimWorld.is_free(cell, reserved):
			return cell
	var fallback: Vector2i = crest - fwd * 2
	return fallback if world.pathfinder.is_walkable(fallback) else from


## --- Infantería ---

## Una escuadra roja: emboscada a corta distancia desde la cobertura.
##   1. Diezmada (<= INF_WEAK_MEN) con amenazas -> retirarse a la celda menos expuesta.
##   2. Hay infantería enemiga conocida que no ve, a tiro -> suprimir esa zona.
##   3. Si no -> tomar (o mantener) la mejor posición cercana: cobertura y vista hacia
##      las amenazas (o hacia adelante si no hay).
func _infantry_orders(world: SimWorld, u: Unit, threats: Array[Vector2i], reserved: Array[Vector2i]) -> void:
	var ambush_m: float = Config.RIFLES_RANGE if world.fired_upon_recently(u) else Config.AI_INF_AMBUSH_RANGE
	world.set_engagement(u.id, Vector2.ZERO, ambush_m)
	if u.hp <= Config.INF_WEAK_MEN and not threats.is_empty():
		if world.order_withdraw(u.id):
			return
	var target: Vector2i = _hidden_infantry_target(world, u)
	if target.x >= 0 and u.suppression < Config.AI_INF_SUPPRESS_MAX and world.order_suppress(u.id, target):
		return
	var best: Vector2i = infantry_position(world, u, threats, reserved)
	if best == u.cell():
		u.path.clear()
		u.waypoints.clear()
		u.moving = false
		u.order = Unit.Order.HOLD
	elif world.order_move(u.id, best):
		u.order = Unit.Order.HULLDOWN


## Infantería enemiga conocida, no visible ahora, a tiro de fusil y con línea de visión a su celda.
func _hidden_infantry_target(world: SimWorld, u: Unit) -> Vector2i:
	var known: Dictionary = world.known_enemies[side]
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: float = INF
	for id: int in known:
		var enemy: Unit = world.units[id]
		var info: Dictionary = known[id]
		if not enemy.alive or not enemy.is_infantry() or world.visible_enemies[side].has(id):
			continue
		if int(info["last_seen_turn"]) < world.turn - 1:
			continue
		var cell: Vector2i = info["cell"]
		var d: float = TerrainAnalysis.dist_m(u.cell(), cell)
		if d < best_d and world.can_suppress_at(u, cell):
			best = cell
			best_d = d
	return best


## Mejor celda para la escuadra a <= AI_INF_POSITION_RADIUS: cobertura + vista a las amenazas
## (o a un punto AI_CREST_PROBE_DIST celdas adelante), sin repetir celdas reservadas.
func infantry_position(world: SimWorld, u: Unit, threats: Array[Vector2i], reserved: Array[Vector2i]) -> Vector2i:
	var targets: Array[Vector2i] = threats.duplicate()
	if targets.is_empty():
		var probe: Vector2i = u.cell() + forward() * Config.AI_CREST_PROBE_DIST
		var n: int = world.height_field.size - 1
		targets.append(Vector2i(clampi(probe.x, 0, n), clampi(probe.y, 0, n)))
	var pf: Pathfinder = world.pathfinders[Unit.Kind.INFANTRY]
	var best: Vector2i = u.cell()
	var best_score: float = -INF
	var r: int = Config.AI_INF_POSITION_RADIUS
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			var c: Vector2i = u.cell() + Vector2i(dx, dy)
			if dx * dx + dy * dy > r * r or not pf.is_walkable(c):
				continue
			if c != u.cell() and not SimWorld.is_free(c, reserved):
				continue
			var view: bool = false
			for t: Vector2i in targets:
				if world.analysis.los(c, Config.INF_EYE_H, t, 1.0):
					view = true
					break
			var score: float = Config.AI_INF_W_COVER * world.cover_at(c) + Config.AI_INF_W_VIEW * float(view) \
				- Vector2(dx, dy).length() / Config.HULLDOWN_DIST_DIV
			if score > best_score + 0.0001:
				best = c
				best_score = score
	return best
