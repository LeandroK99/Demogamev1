class_name CqbSim
extends RefCounted
## Combate en espacios cerrados (fases 66 a 71).
## - Apilarse: el equipo de entrada (1 a 4) se forma pegado a la pared, al costado de la puerta,
##   nunca delante (la "bolsa de la muerte" del vano).
## - Entrada dinámica: el 1 cruza a la esquina profunda del lado contrario, el 2 engancha la del
##   lado del apilado, el 3 y el 4 a los puntos intermedios; todos sobre la pared de la entrada,
##   nadie se queda en la puerta. En un pasillo, en serpentina con alguien siempre mirando atrás.
## - Granada al cuarto antes de entrar, y tiro reflejo a menos de CQB_REFLEX_M: gana el que tiene
##   el arma lista (y no está aturdido).
## - "Limpiar la casa": la escuadra recorre los cuartos en orden, los marca limpios y deja seguridad.
## - La defensa roja de una casa: repartida por cuartos, apuntando a las puertas, y se repliega de
##   cuarto en cuarto.


## --- Geometría: apilado y puntos de dominio ---

## Lugares del apilado para entrar por el portal p al cuarto into. Devuelve {points, side, t, toward}:
## toward apunta desde into hacia donde está el apilado; t corre a lo largo de la pared; side (+1 o
## -1) es el costado de la puerta en el que se forman.
static func stack_points(w: SimWorld, p: int, into: int) -> Dictionary:
	var rm: RoomMap = w.rooms()
	var bm: BuildingMap = w.buildings
	var c: Vector2 = rm.portals[p]["center"]
	var toward: Vector2 = rm.normal_from(p, into)
	var t: Vector2 = Vector2(-toward.y, toward.x)
	var from: int = rm.other(p, into)
	var half: float = float((rm.portals[p]["cells"] as Array).size()) * MicroCover.MICRO_M * 0.5
	var best: Array[Vector2] = []
	var best_side: float = 1.0
	var best_ok: int = -1
	for side: float in [1.0, -1.0]:
		var pts: Array[Vector2] = []
		var ok: int = 0
		var bent: bool = false
		for i: int in Config.CQB_TEAM:
			var along: float = Config.CQB_STACK_FIRST_M + (half - 0.5) + float(i) * Config.CQB_STACK_GAP_M
			var q: Vector2 = c + toward * Config.CQB_STACK_OFF_M + t * side * along
			if bent or not _stack_spot_ok(w, q, from):
				# Contra una esquina: la fila sigue hacia afuera, siempre corrida del vano
				bent = true
				var k: int = i - ok
				q = c + toward * (Config.CQB_STACK_OFF_M + float(k + 1) * Config.CQB_STACK_GAP_M) \
						+ t * side * (Config.CQB_STACK_FIRST_M + (half - 0.5) + float(maxi(ok - 1, 0)) * Config.CQB_STACK_GAP_M)
				q = bm.nearest_walkable_m(q)
			else:
				ok += 1
			pts.append(q)
		if ok > best_ok:
			best_ok = ok
			best = pts
			best_side = side
	return {"points": best, "side": best_side, "t": t, "toward": toward, "center": c}


static func _stack_spot_ok(w: SimWorld, q: Vector2, room: int) -> bool:
	var bm: BuildingMap = w.buildings
	var ty: int = bm.type_at_m(q)
	if not bm.walkable_m(q) or (ty != BuildingMap.Type.FLOOR and ty != BuildingMap.Type.NONE):
		return false
	if room >= 0:
		return w.rooms().room_at_m(q) == room
	return bm.house_at_m(q) < 0


## Puntos de dominio al entrar por p al cuarto into, en orden del 1 al 4 (side: costado del apilado).
static func entry_points(w: SimWorld, p: int, into: int, side: float) -> Array[Vector2]:
	var rm: RoomMap = w.rooms()
	if rm.is_corridor(into):
		return snake_points(w, p, into)
	var c: Vector2 = rm.portals[p]["center"]
	var inward: Vector2 = -rm.normal_from(p, into)
	var t: Vector2 = Vector2(inward.y, -inward.x) # el mismo t del apilado (toward = -inward)
	var r: Rect2 = rm.rooms[into]["rect"]
	# Hasta dónde llega el cuarto a cada lado de la puerta (a lo largo de la pared de entrada) y de fondo
	var lo: float = INF
	var hi: float = -INF
	var depth: float = 0.0
	for q: Vector2 in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		var a: float = (q - c).dot(t)
		lo = minf(lo, a)
		hi = maxf(hi, a)
		depth = maxf(depth, (q - c).dot(inward))
	var near: float = hi if side > 0.0 else -lo # extensión del lado del apilado
	var far: float = -lo if side > 0.0 else hi # extensión del lado contrario
	var d0: float = minf(Config.CQB_WALL_M + 0.5, depth * 0.5)
	var p1: Vector2 = c + inward * d0 - t * side * maxf(far - Config.CQB_CORNER_M, 0.0)
	var p2: Vector2 = c + inward * d0 + t * side * maxf(near - Config.CQB_CORNER_M, 0.0)
	var p3: Vector2 = c + inward * d0 - t * side * maxf(far - Config.CQB_CORNER_M, 0.0) * 0.5
	var p4: Vector2 = c + inward * d0 + t * side * maxf(near - Config.CQB_CORNER_M, 0.0) * 0.5
	var pts: Array[Vector2] = [p1, p2, p3, p4]
	# Con la puerta pegada a una esquina, el intermedio de ese lado se va al fondo
	for i: int in [2, 3]:
		for j: int in i:
			if pts[i].distance_to(pts[j]) < 1.0 or pts[i].distance_to(c + inward * d0) < 0.9:
				pts[i] = c + inward * minf(depth - Config.CQB_CORNER_M, d0 + 1.5) + (pts[i] - c - inward * d0) * 0.5 \
						+ t * side * (0.8 if i == 3 else -0.8)
				break
	var out: Array[Vector2] = []
	for q: Vector2 in pts:
		out.append(_in_room(w, q, into))
	return out


## En un pasillo: en serpentina desde la puerta, a CQB_SNAKE_GAP_M uno del otro.
static func snake_points(w: SimWorld, p: int, into: int) -> Array[Vector2]:
	var rm: RoomMap = w.rooms()
	var c: Vector2 = rm.portals[p]["center"]
	var inward: Vector2 = -rm.normal_from(p, into)
	var r: Rect2 = rm.rooms[into]["rect"]
	var axis: Vector2 = Vector2(1, 0) if r.size.x >= r.size.y else Vector2(0, 1)
	var start: Vector2 = c + inward * Config.CQB_WALL_M
	if absf(axis.dot(inward)) < 0.5:
		# Se entra por el costado del pasillo: hacia la punta más larga
		start = c + inward * minf(r.size.x, r.size.y) * 0.5
		var to_end: float = (r.end - start).dot(axis)
		var to_start: float = (r.position - start).dot(axis)
		axis = axis if absf(to_end) >= absf(to_start) else -axis
	else:
		axis = inward
	var side: Vector2 = Vector2(-axis.y, axis.x)
	var out: Array[Vector2] = []
	for i: int in Config.CQB_TEAM:
		var lateral: float = 0.3 * (1.0 if i % 2 == 0 else -1.0)
		out.append(_in_room(w, start + axis * float(Config.CQB_TEAM - 1 - i) * Config.CQB_SNAKE_GAP_M + side * lateral, into))
	return out


## Sectores en el pasillo: el de punta adelante, dos a los costados y el último atrás (360°).
static func snake_sectors(w: SimWorld, p: int, into: int) -> Array[Vector2]:
	var pts: Array[Vector2] = snake_points(w, p, into)
	var axis: Vector2 = (pts[0] - pts[Config.CQB_TEAM - 1]).normalized()
	if axis == Vector2.ZERO:
		axis = -w.rooms().normal_from(p, into)
	var side: Vector2 = Vector2(-axis.y, axis.x)
	var out: Array[Vector2] = [axis, side, -side, -axis]
	return out


static func _in_room(w: SimWorld, q: Vector2, room: int) -> Vector2:
	var rm: RoomMap = w.rooms()
	if rm.room_at_m(q) == room:
		return q
	var best: Vector2 = rm.rooms[room]["center"]
	var best_d: float = INF
	for c: Vector2i in rm.rooms[room]["cells"]:
		var m: Vector2 = MicroCover.center_m(c)
		var d: float = m.distance_to(q)
		if d < best_d:
			best_d = d
			best = m
	return best


## --- Limpiar la casa (fase 70) ---

## Plan de la limpieza: los cuartos en el orden en que se entra (cada uno desde uno ya limpio).
## [{portal, room, from}]; el primero entra desde la calle por entry.
static func plan_rooms(rm: RoomMap, entry: int) -> Array[Dictionary]:
	var first: int = int(rm.portals[entry]["a"])
	var plan: Array[Dictionary] = [{"portal": entry, "room": first, "from": -1}]
	var seen: Dictionary = {first: true}
	var k: int = 0
	while k < plan.size():
		var r: int = int(plan[k]["room"])
		for p: int in rm.portals_of(r):
			var o: int = rm.other(p, r)
			if o >= 0 and not seen.has(o):
				seen[o] = true
				plan.append({"portal": p, "room": o, "from": r})
		k += 1
	return plan


## Casa a limpiar cerca de at (la que lo contiene, o la más cercana a CQB_CLEAR_RANGE_M).
static func house_near(bm: BuildingMap, at: Vector2) -> int:
	var h: int = bm.house_at_m(at)
	if h >= 0:
		return h
	var best: float = Config.CQB_CLEAR_RANGE_M
	for i: int in bm.houses.size():
		var r: Rect2 = bm.rect_m(i)
		var q: Vector2 = Vector2(clampf(at.x, r.position.x, r.end.x), clampf(at.y, r.position.y, r.end.y))
		if q.distance_to(at) < best:
			best = q.distance_to(at)
			h = i
	return h


## Arranca la limpieza (la escuadra ya fue mandada a la puerta). entry: portal a la calle.
static func start_clear(w: SimWorld, u: Unit, h: int, entry: int) -> void:
	var rm: RoomMap = w.rooms()
	u.clear = {"house": h, "plan": plan_rooms(rm, entry), "step": 0, "phase": "approach", "t0": w.total_ticks}


func update(w: SimWorld) -> void:
	if w.buildings == null:
		return
	for u: Unit in w.units:
		if not u.alive or not u.is_infantry():
			continue
		if not u.clear.is_empty():
			_update_clear(w, u)
	if w.total_ticks % roundi(Config.DEFEND_CHECK_SECONDS / Config.TICK) == 0:
		for u: Unit in w.units:
			if u.alive and u.is_infantry() and u.defend_house >= 0:
				_update_defense(w, u)


func _update_clear(w: SimWorld, u: Unit) -> void:
	var c: Dictionary = u.clear
	var phase: String = str(c["phase"])
	if u.broken or u.surrendered:
		abort_clear(w, u, "")
		return
	if phase == "approach":
		if u.moving or not u.path.is_empty():
			return
		u.order = Unit.Order.CLEAR
		_begin_step(w, u)
		return
	if _team_ok(u) < Config.CQB_MIN_TEAM:
		abort_clear(w, u, "no podemos limpiar la casa, nos quedamos")
		return
	var elapsed: float = float(w.total_ticks - int(c["t0"])) * Config.TICK
	var step: Dictionary = c["plan"][int(c["step"])]
	match phase:
		"stack":
			if _team_arrived(u) or elapsed >= Config.CQB_STACK_SECONDS:
				_throw_or_enter(w, u, step)
		"grenade":
			if w.total_ticks >= int(c["enter_tick"]):
				_enter(w, u, step)
		"entry":
			if _team_arrived(u) or elapsed >= Config.CQB_ENTRY_MAX_SECONDS:
				c["phase"] = "dominate"
				c["t0"] = w.total_ticks
		"dominate":
			if elapsed < Config.CQB_DOMINATE_SECONDS:
				return
			if enemies_in_room(w, u.side, int(step["room"])) > 0:
				return # pelean adentro (tiro reflejo); se sigue cuando no quede nadie
			w.cleared_rooms[int(step["room"])] = u.side
			c["step"] = int(c["step"]) + 1
			if int(c["step"]) >= (c["plan"] as Array).size():
				_house_clear(w, u)
			else:
				w.radio(u, "cuarto limpio")
				_begin_step(w, u)


## Se apilan en el portal del paso actual (los demás, a cubierto: afuera o en el último cuarto limpio).
func _begin_step(w: SimWorld, u: Unit) -> void:
	var c: Dictionary = u.clear
	var step: Dictionary = c["plan"][int(c["step"])]
	var team: Array[Soldier] = _pick_team(u)
	var st: Dictionary = stack_points(w, int(step["portal"]), int(step["room"]))
	c["side"] = st["side"]
	c["phase"] = "stack"
	c["t0"] = w.total_ticks
	for s: Soldier in u.soldiers:
		s.cqb_role = -1
		s.cqb_fast = false
		s.cqb_start_tick = 0
	var pts: Array = st["points"]
	for k: int in team.size():
		var s: Soldier = team[k]
		s.cqb_role = k
		s.cqb_fast = true
		s.task_pos = pts[k]
		s.task_posture = Soldier.Posture.CROUCH
		s.hold_pos = false
		s.sector_dir = Vector2.ZERO
	# Seguridad: los que no entran quedan en el último cuarto limpio (o afuera, junto a la puerta)
	var from: int = int(step["from"])
	var k2: int = 0
	for s: Soldier in u.soldiers:
		if not s.is_ok() or s.cqb_role >= 0:
			continue
		if from >= 0:
			s.task_pos = _security_spot(w, from, k2)
			s.task_posture = Soldier.Posture.CROUCH
		k2 += 1
	if int(c["step"]) == 0:
		w.radio(u, "nos apilamos en la puerta")


static func _security_spot(w: SimWorld, room: int, k: int) -> Vector2:
	var cells: Array = w.rooms().rooms[room]["cells"]
	if cells.is_empty():
		return w.rooms().rooms[room]["center"]
	# Repartidos por el cuarto (determinista)
	return MicroCover.center_m(cells[(k * 7 + 3) % cells.size()])


## Con granada y el cuarto sin propios: la tira el 2 (o el que tenga) y entran al explotar.
func _throw_or_enter(w: SimWorld, u: Unit, step: Dictionary) -> void:
	var c: Dictionary = u.clear
	var room: int = int(step["room"])
	var thrower: Soldier = null
	for k: int in [1, 0, 2, 3]:
		for s: Soldier in u.soldiers:
			if s.cqb_role == k and s.is_ok() and s.grenades > 0 and thrower == null:
				thrower = s
	if thrower != null and not _friends_in_room(w, u.side, room):
		thrower.grenades -= 1
		var at: Vector2 = _deep_point(w, int(step["portal"]), room)
		w.grenades.append({"tick": w.total_ticks + roundi(Config.CQB_GRENADE_FUSE_SECONDS / Config.TICK), "at": at,
			"unit": u.id, "from": thrower.pos})
		c["phase"] = "grenade"
		c["enter_tick"] = w.total_ticks + roundi((Config.CQB_GRENADE_FUSE_SECONDS + Config.CQB_AFTER_BLAST_SECONDS) / Config.TICK)
		w.radio(u, "¡granada!")
		return
	_enter(w, u, step)


## El punto del cuarto más lejos de la puerta (ahí cae la granada).
static func _deep_point(w: SimWorld, p: int, room: int) -> Vector2:
	var rm: RoomMap = w.rooms()
	var c: Vector2 = rm.portals[p]["center"]
	var r: Rect2 = rm.rooms[room]["rect"]
	var q: Vector2 = r.get_center() + (r.get_center() - c).normalized() * minf(r.size.x, r.size.y) * 0.25
	return _in_room(w, q, room)


func _enter(w: SimWorld, u: Unit, step: Dictionary) -> void:
	var c: Dictionary = u.clear
	var p: int = int(step["portal"])
	var room: int = int(step["room"])
	var pts: Array[Vector2] = entry_points(w, p, room, float(c["side"]))
	var corridor: bool = w.rooms().is_corridor(room)
	var sectors: Array[Vector2] = []
	if corridor:
		sectors = snake_sectors(w, p, room)
	var inward: Vector2 = -w.rooms().normal_from(p, room)
	for s: Soldier in u.soldiers:
		if s.cqb_role < 0 or not s.is_ok():
			continue
		s.task_pos = pts[s.cqb_role]
		s.task_posture = Soldier.Posture.STAND
		s.cqb_start_tick = w.total_ticks + roundi(float(s.cqb_role) * Config.CQB_FLOW_SECONDS / Config.TICK)
		if corridor:
			s.sector_dir = sectors[s.cqb_role]
			s.sector_half_deg = 60.0
		else:
			s.sector_dir = (w.rooms().rooms[room]["center"] as Vector2 - pts[s.cqb_role]).normalized()
			if s.sector_dir == Vector2.ZERO:
				s.sector_dir = inward
			s.sector_half_deg = 70.0
	c["phase"] = "entry"
	c["t0"] = w.total_ticks


func _house_clear(w: SimWorld, u: Unit) -> void:
	var h: int = int(u.clear["house"])
	w.cleared_houses[h] = u.side
	w.radio(u, "¡casa limpia!")
	_release(u)
	u.clear = {}
	if u.order == Unit.Order.CLEAR or u.order == Unit.Order.MOVE:
		u.order = Unit.Order.NONE
	# La escuadra ocupa la casa: el ancla adentro, cada uno busca lugar en ella
	u.pos = w.buildings.rect_m(h).get_center() / Config.CELL_SIZE
	for s: Soldier in u.soldiers:
		s.has_cover = false


func abort_clear(w: SimWorld, u: Unit, msg: String) -> void:
	if u.clear.is_empty():
		return
	if msg != "":
		w.radio(u, msg)
	_release(u)
	u.clear = {}
	if u.order == Unit.Order.CLEAR:
		u.order = Unit.Order.NONE


static func _release(u: Unit) -> void:
	for s: Soldier in u.soldiers:
		s.cqb_role = -1
		s.cqb_fast = false
		s.cqb_start_tick = 0
		s.task_pos = Vector2(-1.0, -1.0)
		s.task_posture = -1
		s.sector_dir = Vector2.ZERO
		s.has_cover = false
	u.sector_threat = Vector2.ZERO


## Los cuatro que entran: fusileros y antitanque primero; ni la ametralladora ni el médico salvo que falten.
static func _pick_team(u: Unit) -> Array[Soldier]:
	var order: Array[int] = [Soldier.Role.RIFLE, Soldier.Role.AT, Soldier.Role.LEADER, Soldier.Role.ASSISTANT, Soldier.Role.MEDIC, Soldier.Role.MG]
	var team: Array[Soldier] = []
	for role: int in order:
		for s: Soldier in u.soldiers:
			if s.is_ok() and s.role == role and not s.marksman and team.size() < Config.CQB_TEAM:
				team.append(s)
	for s: Soldier in u.soldiers: # el tirador selecto, si no queda otro
		if s.is_ok() and not team.has(s) and team.size() < Config.CQB_TEAM:
			team.append(s)
	return team


static func _team_ok(u: Unit) -> int:
	var n: int = 0
	for s: Soldier in u.soldiers:
		if s.is_ok():
			n += 1
	return n


static func _team_arrived(u: Unit) -> bool:
	for s: Soldier in u.soldiers:
		if s.cqb_role >= 0 and s.is_ok() and s.suppression < Config.PINNED and s.pos.distance_to(s.task_pos) > Config.SOLDIER_ARRIVE_M * 2.0:
			return false
	return true


## Enemigos (de side) en condiciones adentro del cuarto.
static func enemies_in_room(w: SimWorld, side: int, room: int) -> int:
	var rm: RoomMap = w.rooms()
	var n: int = 0
	for e: Unit in w.units:
		if not e.alive or e.side == side or not e.is_infantry() or e.surrendered:
			continue
		for t: Soldier in e.soldiers:
			if t.is_ok() and rm.room_at_m(t.pos) == room:
				n += 1
	return n


static func _friends_in_room(w: SimWorld, side: int, room: int) -> bool:
	return enemies_in_room(w, 1 - side, room) > 0


## --- Tiro reflejo (fase 68) ---

## A menos de CQB_REFLEX_M y con línea de visión, cada soldado le tira al enemigo más cercano sin
## apuntar, después de su tiempo de reacción: corto con el arma lista (entrando o apostado), más
## largo caminando y mucho más largo aturdido (suprimido). El que ve primero y reacciona antes gana.
func update_reflex(w: SimWorld) -> void:
	var r: float = Config.CQB_REFLEX_M
	for u: Unit in w.units:
		if not u.alive or not u.is_infantry() or u.surrendered or not w.roe_allows_fire(u):
			continue
		var foes: Array[Unit] = []
		for e: Unit in w.units:
			if e.alive and e.side != u.side and e.is_infantry() and not e.surrendered \
					and e.pos_m().distance_to(u.pos_m()) <= r + Config.CQB_REACH_SQUADS_M:
				foes.append(e)
		if foes.is_empty():
			for s: Soldier in u.soldiers:
				s.reflex_key = -1
			continue
		for s: Soldier in u.soldiers:
			if not s.is_ok() or s.suppression >= Config.PINNED or s.ammo <= 0 or s.care_target >= 0:
				s.reflex_key = -1
				continue
			var best: Soldier = null
			var best_u: Unit = null
			var best_d: float = r
			for e: Unit in foes:
				for t: Soldier in e.soldiers:
					if not t.is_ok():
						continue
					var d: float = s.pos.distance_to(t.pos)
					if d < best_d and w.analysis.los_m(s.pos, InfantrySim.eye_of(w, s), t.pos, t.center_h() + InfantrySim.ground_offset(w, t.pos)):
						best_d = d
						best = t
						best_u = e
			if best == null:
				s.reflex_key = -1
				continue
			var key: int = InfantrySim.soldier_key(best_u.id, best.index)
			if s.reflex_key != key:
				s.reflex_key = key
				s.reflex_tick = w.total_ticks + roundi(reaction(w, s) / Config.TICK)
				continue
			if w.total_ticks < s.reflex_tick or s.reload_left > 0.0:
				continue
			_reflex_shot(w, u, s, best_u, best)
			s.reflex_tick = w.total_ticks + roundi(Config.CQB_REFLEX_RELOAD / Config.TICK)


## Segundos que tarda el soldado en tirar a uno que aparece a menos de CQB_REFLEX_M.
static func reaction(w: SimWorld, s: Soldier) -> float:
	var t: float = Config.CQB_REACT_READY
	if s.cqb_role < 0 and not s.cqb_post:
		t = Config.CQB_REACT_MOVING if s.moving else Config.CQB_REACT_READY * 2.0
	t += s.suppression / 100.0 * Config.CQB_REACT_SUPP
	return t + w.rng.randf_range(0.0, Config.CQB_REACT_JITTER)


func _reflex_shot(w: SimWorld, u: Unit, s: Soldier, tu: Unit, t: Soldier) -> void:
	s.reload_left = Config.CQB_REFLEX_RELOAD
	s.last_fire_tick = w.total_ticks
	s.heading = (t.pos - s.pos).normalized()
	w.inf.spend_ammo(w, u, s)
	u.last_fire_tick = w.total_ticks
	tu.shots_received += 1
	tu.last_fired_upon_tick = w.total_ticks
	w.known_enemies[tu.side][u.id] = {"cell": u.cell(), "last_seen_turn": w.turn}
	var hit: bool = w.rng.randf() < Config.CQB_REFLEX_P_HIT * InfantrySim.soldier_weak_factor(u, null)
	if hit:
		w.damage_soldier(tu, t)
	var wpn: int = Unit.Weapon.MG if s.role == Soldier.Role.MG else Unit.Weapon.RIFLES
	w.inf.suppress_at(w, tu.side, t.pos, s.pos, wpn, hit)
	w.shot_events.append({"shooter": u.id, "target": tu.id, "hit": hit, "aspect": SimWorld.Aspect.FRONT,
		"weapon": wpn, "from_m": s.pos, "from_h": InfantrySim.eye_of(w, s), "to_m": t.pos, "to_h": t.center_h(), "soldier": t.index})


## --- Defensa de una casa (fase 71) ---

## La escuadra (adentro de la casa h) se reparte por los cuartos: nunca todos en uno; cada uno
## apostado lejos de la puerta de su cuarto, apuntándole. La ametralladora sigue en su aspillera.
func defend_house(w: SimWorld, u: Unit) -> void:
	if w.buildings == null:
		return
	var h: int = w.buildings.house_at_m(u.pos_m())
	if h < 0:
		return
	var rm: RoomMap = w.rooms()
	var rooms: Array[int] = rm.rooms_of(h)
	if rooms.is_empty():
		return
	# Primero los cuartos más grandes (los pasillos al final)
	rooms.sort_custom(func(a: int, b: int) -> bool:
		return (rm.rooms[a]["cells"] as Array).size() > (rm.rooms[b]["cells"] as Array).size())
	u.defend_house = h
	var k: int = 0
	var taken: Array[Vector2] = []
	for s: Soldier in u.soldiers:
		if not s.is_ok():
			continue
		if s.post_pos.x >= 0.0:
			s.defend_room = rm.room_at_m(s.post_pos)
			s.cqb_post = true
			taken.append(s.post_pos)
			continue
		var r: int = rooms[k % rooms.size()]
		k += 1
		_post_in(w, s, r, taken)


## Lugar del defensor s en el cuarto r: a DEFEND_POST_DOOR_M o más de las puertas, viendo la mayor
## cantidad de ellas, al fondo y separado de los demás.
func _post_in(w: SimWorld, s: Soldier, r: int, taken: Array[Vector2]) -> void:
	var rm: RoomMap = w.rooms()
	var doors: Array[Vector2] = []
	for p: int in rm.portals_of(r):
		doors.append(rm.portals[p]["center"])
	var best: Vector2 = rm.rooms[r]["center"]
	var best_score: float = -INF
	for c: Vector2i in rm.rooms[r]["cells"]:
		var q: Vector2 = MicroCover.center_m(c)
		var score: float = 0.0
		var close: bool = false
		for d: Vector2 in doors:
			var dist: float = q.distance_to(d)
			if dist < Config.DEFEND_POST_DOOR_M:
				close = true
			score += 1.0 if not w.buildings.crosses(q, d) else 0.0
			score += minf(dist, 5.0) * 0.1
		if close:
			continue
		for o: Vector2 in taken:
			if q.distance_to(o) < 1.5:
				score -= 3.0
		if score > best_score:
			best_score = score
			best = q
	taken.append(best)
	s.task_pos = best
	s.task_posture = Soldier.Posture.CROUCH
	s.cqb_post = true
	s.defend_room = r


## Cada DEFEND_CHECK_SECONDS: si en el cuarto de un defensor hay un enemigo (cayó el cuarto), los
## que quedan se repliegan a un cuarto vecino que todavía no cayó.
func _update_defense(w: SimWorld, u: Unit) -> void:
	var rm: RoomMap = w.rooms()
	var fallen: Dictionary = {}
	for r: int in rm.rooms_of(u.defend_house):
		if enemies_in_room(w, u.side, r) > 0:
			fallen[r] = true
	if fallen.is_empty():
		return
	var moved: bool = false
	var taken: Array[Vector2] = []
	for s: Soldier in u.soldiers:
		if s.is_ok() and s.cqb_post and not fallen.has(s.defend_room):
			taken.append(s.task_pos if s.task_pos.x >= 0.0 else s.pos)
	for s: Soldier in u.soldiers:
		if not s.is_ok() or not s.cqb_post or not fallen.has(s.defend_room):
			continue
		var to: int = -1
		for p: int in rm.portals_of(s.defend_room):
			var o: int = rm.other(p, s.defend_room)
			if o >= 0 and not fallen.has(o):
				to = o
				break
		if to < 0:
			continue # sin adónde ir: pelea donde está
		s.post_pos = Vector2(-1.0, -1.0)
		_post_in(w, s, to, taken)
		moved = true
	if moved:
		w.radio(u, "¡cayó un cuarto! nos replegamos al de al lado")


## Deja de defender la casa (la escuadra recibió otra orden).
static func stop_defense(u: Unit) -> void:
	if u.defend_house < 0:
		return
	u.defend_house = -1
	for s: Soldier in u.soldiers:
		if s.cqb_post:
			s.cqb_post = false
			s.defend_room = -1
			s.task_pos = Vector2(-1.0, -1.0)
			s.task_posture = -1
