class_name AICommander
extends RefCounted
## IA de un bando. Se ejecuta al entrar en PLAN y usa solo lo que su bando conoce.
## Por tanque vivo, en orden de prioridad:
##   1. hp == 1 -> retroceder a la celda de menor exposición dentro de AI_RETREAT_RADIUS.
##   2. Hay amenazas y la celda actual no es hull-down -> orden HULLDOWN.
##   3. Ya está en hull-down y puede disparar a una amenaza -> OVERWATCH hacia las amenazas.
##      (si está oculto pero no puede disparar, también HULLDOWN: busca desde dónde tirar).
##   4. Sin amenazas -> avanzar a la cresta por delante, a una posición hull-down
##      contra un observador hipotético del lado enemigo.

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
		if u.hp == 1 and not threats.is_empty():
			_retreat(world, u)
			reserved.append(world.destination(u))
		elif not threats.is_empty():
			var state: Dictionary = evaluate_cell(world, u.cell(), threats)
			if state["hull_hidden"] and state["can_fire"]:
				if not world.order_overwatch(u.id, SimWorld.facing_to_threats(u.cell(), threats)):
					u.path.clear()
					u.moving = false
					u.order = Unit.Order.HOLD
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


## Retroceder: la celda transitable de menor exposición (desempate: la más cercana).
func _retreat(world: SimWorld, u: Unit) -> void:
	var exposure: PackedFloat32Array = world.exposure_for(side)
	var hf: HeightField = world.height_field
	var origin: Vector2i = u.cell()
	var best: Vector2i = origin
	var best_e: float = exposure[origin.y * hf.size + origin.x]
	var best_d: float = 0.0
	var r: int = Config.AI_RETREAT_RADIUS
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			var c: Vector2i = origin + Vector2i(dx, dy)
			if dx * dx + dy * dy > r * r or not world.pathfinder.is_walkable(c):
				continue
			var e: float = exposure[c.y * hf.size + c.x]
			var d: float = Vector2(dx, dy).length()
			if e < best_e or (is_equal_approx(e, best_e) and d < best_d):
				best = c
				best_e = e
				best_d = d
	# Llega mirando a la amenaza: el frente blindado hacia el enemigo
	world.order_move(u.id, best, SimWorld.facing_to_threats(best, world.threats_for(side)))


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
