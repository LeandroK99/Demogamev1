class_name PlatoonLeader
extends RefCounted
## Jefe de pelotón con una misión (fase 58): el jugador (o el banco) le da un objetivo y el pelotón
## de infantería de su bando maniobra solo, como un cuerpo. Se acerca con una escuadra de punta y las
## demás detrás; al primer contacto, la escuadra trabada queda de base de fuego (bate el contacto) y
## las otras van al flanco; desde ahí asaltan, y la base levanta y corre el fuego cuando el asalto
## llega cerca. Tomada la posición, todos al objetivo. Las escuadras siguen con su propia cabeza
## (drills, saltos, emboscadas) entre una orden y otra.

enum Stage { APPROACH, FIX, ASSAULT, CONSOLIDATE }
const STAGE_NAMES: Array[String] = ["se acerca", "fija y flanquea", "asalta", "consolida"]

var side: int = 0
var target: Vector2i = Vector2i.ZERO
var stage: int = Stage.APPROACH
var base_id: int = -1 # la escuadra que fija al enemigo
var maneuver: Array[int] = [] # las que flanquean y asaltan
var contact: Vector2 = Vector2.ZERO # posición del enemigo que se fija (metros)
var shifted: bool = false # la base ya levantó el fuego
var stage_tick: int = 0 # tick global en que empezó la etapa


func _init(p_side: int, p_target: Vector2i) -> void:
	side = p_side
	target = p_target


func squads(w: SimWorld) -> Array[Unit]:
	var out: Array[Unit] = []
	for u: Unit in w.units:
		if u.alive and u.side == side and u.is_infantry() and not u.broken:
			out.append(u)
	return out


## Al empezar la misión y en cada plan: órdenes de la etapa a las escuadras que no tienen ruta.
func issue(w: SimWorld) -> void:
	match stage:
		Stage.APPROACH:
			_approach(w)
		Stage.CONSOLIDATE:
			for u: Unit in squads(w):
				if u.path.is_empty() and u.pos.distance_to(Vector2(target)) > Config.LOMA_OBJECTIVE_RADIUS:
					w.command_move(u.id, _slot_near(w, target, squads(w).find(u)))


## Durante la ejecución (cada AI_MONITOR_TICKS).
func monitor(w: SimWorld) -> void:
	match stage:
		Stage.APPROACH:
			_check_contact(w)
			if stage == Stage.APPROACH:
				_approach(w)
		Stage.FIX:
			_check_flanks(w)
		Stage.ASSAULT:
			_check_assault(w)


## La de punta va al objetivo; las demás, detrás de ella sobre el eje de avance.
func _approach(w: SimWorld) -> void:
	var sq: Array[Unit] = squads(w)
	if sq.is_empty():
		return
	sq.sort_custom(func(a: Unit, b: Unit) -> bool: return a.pos.distance_to(Vector2(target)) < b.pos.distance_to(Vector2(target)))
	var lead: Unit = sq[0]
	if lead.path.is_empty():
		w.command_move(lead.id, target)
	var axis: Vector2 = (Vector2(target) - lead.pos).normalized()
	for k: int in range(1, sq.size()):
		var u: Unit = sq[k]
		var side_off: Vector2 = Vector2(-axis.y, axis.x) * float(6 * (1 if k % 2 == 1 else -1))
		var c: Vector2 = lead.pos - axis * float(Config.PLT_FOLLOW_CELLS) + side_off
		var cell: Vector2i = w._nearest_walkable(_clamp(w, Vector2i(c.round())), Unit.Kind.INFANTRY)
		# Solo hacia adelante: si ya está detrás de su lugar, espera a que la punta avance
		var ahead: float = (Vector2(cell) - u.pos).dot(axis)
		if u.path.is_empty() and ahead > 3.0:
			w.command_move(u.id, cell)


## La primera escuadra en contacto queda de base: bate el contacto; las otras van al flanco.
func _check_contact(w: SimWorld) -> void:
	for u: Unit in squads(w):
		var c: Vector2 = _nearest_contact(u)
		if c.x < 0.0:
			continue
		var d: float = c.distance_to(u.pos_m())
		if d > Config.PLT_CONTACT_M and not (w.fired_upon_within(u, Config.PLT_FIRED_SECONDS) and d <= Config.PLT_CONTACT_M * 1.5):
			continue
		base_id = u.id
		contact = c
		stage = Stage.FIX
		stage_tick = w.total_ticks
		_fix(w, u)
		maneuver.clear()
		for o: Unit in squads(w):
			if o == u:
				continue
			var cell: Vector2i = w.minds.flank_cell(w, o, contact, u.pos_m())
			if cell.x >= 0 and w.command_move(o.id, cell):
				maneuver.append(o.id)
		w.radio(u, "pelotón: los fijamos, las demás por el flanco")
		if maneuver.is_empty():
			_start_assault(w) # sin nadie para flanquear: asalto de frente
		return


func _fix(w: SimWorld, base: Unit) -> void:
	var cell: Vector2i = _clamp(w, Vector2i((contact / Config.CELL_SIZE).round()))
	w.begin_autonomous()
	base.path.clear()
	base.waypoints.clear()
	base.moving = false
	if not w.order_suppress(base.id, cell):
		base.order = Unit.Order.HOLD
	w.end_autonomous()


## Las de maniobra llegaron a su flanco (o ya no se mueven): asalto.
func _check_flanks(w: SimWorld) -> void:
	if _stage_seconds(w) > Config.PLT_FIX_MAX_SECONDS:
		_start_assault(w)
		return
	for id: int in maneuver:
		var u: Unit = w.units[id]
		if u.alive and not u.path.is_empty() and w.destination(u).distance_to(u.cell()) > Config.PLT_FLANK_ARRIVE_CELLS:
			return
	_start_assault(w)


func _start_assault(w: SimWorld) -> void:
	stage = Stage.ASSAULT
	stage_tick = w.total_ticks
	var cell: Vector2i = _clamp(w, Vector2i((contact / Config.CELL_SIZE).round()))
	var who: Array[int] = maneuver.duplicate()
	if who.is_empty():
		who = [base_id]
	for id: int in who:
		if w.units[id].alive:
			w.command_move(id, w._nearest_walkable(cell, Unit.Kind.INFANTRY), true)
	if not maneuver.is_empty():
		w.radio(w.units[maneuver[0]], "pelotón: ¡al asalto!")


## Asalto cerca del enemigo: la base levanta el fuego y lo corre más allá. Con el enemigo fuera
## (sin noticias) o el asalto en su lugar: todos al objetivo.
func _check_assault(w: SimWorld) -> void:
	var near: bool = false
	var arrived: bool = true
	for id: int in maneuver:
		var u: Unit = w.units[id]
		if not u.alive:
			continue
		if u.pos_m().distance_to(contact) <= Config.PLT_SHIFT_M:
			near = true
		if not u.path.is_empty():
			arrived = false
	var base: Unit = w.get_unit(base_id)
	if near and not shifted and base != null and base.alive:
		shifted = true
		_shift_fire(w, base)
	if arrived or _stage_seconds(w) > Config.PLT_ASSAULT_MAX_SECONDS:
		stage = Stage.CONSOLIDATE
		stage_tick = w.total_ticks
		var sq: Array[Unit] = squads(w)
		for k: int in sq.size():
			w.command_move(sq[k].id, _slot_near(w, target, k))
		if not sq.is_empty():
			w.radio(sq[0], "pelotón: posición tomada, al objetivo")


## La base corre el fuego PLT_SHIFT_BEYOND_M más allá del enemigo (en la dirección del asalto); si no
## puede, deja de tirar ahí.
func _shift_fire(w: SimWorld, base: Unit) -> void:
	var axis: Vector2 = (contact - base.pos_m()).normalized()
	var beyond: Vector2i = _clamp(w, Vector2i(((contact + axis * Config.PLT_SHIFT_BEYOND_M) / Config.CELL_SIZE).round()))
	w.begin_autonomous()
	if not w.order_suppress(base.id, beyond):
		base.order = Unit.Order.HOLD
	w.end_autonomous()
	w.radio(base, "levantamos el fuego, ¡corremos el tiro!")


func _stage_seconds(w: SimWorld) -> float:
	return float(w.total_ticks - stage_tick) * Config.TICK


func _nearest_contact(u: Unit) -> Vector2:
	var best: Vector2 = Vector2(-1.0, -1.0)
	var best_d: float = INF
	for id: int in u.mind.contacts:
		var p: Vector2 = u.mind.contacts[id]["pos"]
		var d: float = p.distance_to(u.pos_m())
		if d < best_d:
			best = p
			best_d = d
	return best


static func _clamp(w: SimWorld, c: Vector2i) -> Vector2i:
	var n: int = w.height_field.size - 1
	return Vector2i(clampi(c.x, 0, n), clampi(c.y, 0, n))


## Lugar k alrededor del objetivo (para no amontonarse).
func _slot_near(w: SimWorld, c: Vector2i, k: int) -> Vector2i:
	return w._nearest_walkable(_clamp(w, c + Vector2i((k - 1) * 5, 0)), Unit.Kind.INFANTRY)
