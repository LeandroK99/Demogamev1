class_name InfantrySim
extends RefCounted
## Los soldados de las escuadras: movimiento en formación (y, en las fases siguientes, cobertura,
## visión, fuego y supresión por soldado). Es de SimWorld y recibe el mundo en cada llamada
## (no guarda una referencia, para no hacer un ciclo).

## Soldados enemigos que ve cada bando (índice = side): clave soldier_key -> true.
var visible_soldiers: Array[Dictionary] = [{}, {}]
var _observers: Dictionary = {} # unit id -> Array[Soldier]: los que miran en esta detección
var _round: int = 0 # turno de los observadores que rotan


static func soldier_key(unit_id: int, index: int) -> int:
	return unit_id * 64 + index


## ¿Algún soldado de la escuadra quedó lejos de su lugar? Entonces el ancla lo espera.
func lagging(u: Unit) -> bool:
	for s: Soldier in u.soldiers:
		if s.is_ok() and s.pos.distance_to(u.slot_pos_m(s.index)) > Config.SOLDIER_LAG_M:
			return true
	return false


## Cada soldado en condiciones va hacia su lugar: el de la formación en marcha, o su punto
## de cobertura si la escuadra está detenida. Los heridos se quedan donde cayeron.
func move_soldiers(w: SimWorld) -> void:
	var limit: float = float(w.height_field.size - 1) * Config.CELL_SIZE
	for u: Unit in w.units:
		if not u.alive or not u.is_infantry():
			continue
		var speed: float = w.speed_at(u.cell(), Unit.Kind.INFANTRY) * SimWorld.pace_speed_factor(SimWorld.effective_pace(u))
		var step_m: float = speed * Config.SOLDIER_CATCHUP * Config.TICK
		for s: Soldier in u.soldiers:
			if not s.is_ok():
				s.moving = false
				continue
			var target: Vector2 = s.cover_pos if s.has_cover and not u.moving else u.slot_pos_m(s.index)
			target = Vector2(clampf(target.x, 0.0, limit), clampf(target.y, 0.0, limit))
			var d: Vector2 = target - s.pos
			var dist: float = d.length()
			if dist > Config.SOLDIER_TELEPORT_M:
				s.pos = target # la escuadra fue reubicada (escenarios y tests): los soldados van con ella
				continue
			if dist <= Config.SOLDIER_ARRIVE_M:
				s.moving = false
				if not u.moving:
					s.heading = u.heading
				continue
			s.moving = true
			s.heading = d / dist
			s.pos += d / dist * minf(step_m, dist)


## Un impacto en la escuadra sin soldado elegido: le toca a uno al azar de los que están en condiciones.
func hit_random(w: SimWorld, u: Unit) -> void:
	var ok: Array[Soldier] = []
	for s: Soldier in u.soldiers:
		if s.is_ok():
			ok.append(s)
	if ok.is_empty():
		return
	hit_soldier(w, u, ok[w.rng.randi_range(0, ok.size() - 1)])


## Un impacto en un soldado: herido (SOLDIER_WOUND_P) o muerto; un herido que recibe otro, muere.
## Actualiza los hombres de la escuadra (hp = soldiers en condiciones).
func hit_soldier(w: SimWorld, u: Unit, s: Soldier) -> void:
	if s.state == Soldier.State.DEAD:
		return
	if s.state == Soldier.State.OK and w.rng.randf() < Config.SOLDIER_WOUND_P:
		s.state = Soldier.State.WOUNDED
	else:
		s.state = Soldier.State.DEAD
	s.posture = Soldier.Posture.PRONE
	s.moving = false
	u.hp = u.ok_count()


## --- Cobertura ---

## Desnivel del suelo por la microcobertura (negativo dentro de un cráter).
static func ground_offset(w: SimWorld, p: Vector2) -> float:
	return minf(0.0, w.micro.height_at_m(p)) if w.micro != null else 0.0


## Punto (en metros) contra el que se cubre la escuadra: el centro de las amenazas conocidas
## o, si no hay, uno adelante en su rumbo.
func threat_point(w: SimWorld, u: Unit) -> Vector2:
	var threats: Array[Vector2i] = w.threats_for(u.side)
	if threats.is_empty():
		return u.pos_m() + u.heading * Config.SOLDIER_NO_THREAT_M
	var sum: Vector2 = Vector2.ZERO
	for th: Vector2i in threats:
		sum += Vector2(th)
	return sum / float(threats.size()) * Config.CELL_SIZE


## Obstáculo que protege a un soldado en p (con el centro del cuerpo a center_h) del fuego que
## viene de threat: el primero que lo tapa a menos de SOLDIER_COVER_PROBE_M. NONE si ninguno.
static func protecting_obstacle(w: SimWorld, p: Vector2, center_h: float, threat: Vector2) -> int:
	var mc: MicroCover = w.micro
	if mc == null:
		return MicroCover.Type.NONE
	var inv_cell: float = 1.0 / Config.CELL_SIZE
	var body: float = w.height_field.height_at(p * inv_cell) + ground_offset(w, p) + center_h
	var dir: Vector2 = (threat - p).normalized()
	var s: float = Config.MICRO_SELF_M
	while s <= Config.SOLDIER_COVER_PROBE_M:
		var q: Vector2 = p + dir * s
		var t: int = mc.type_at_m(q)
		if MicroCover.protects(t) and w.height_field.height_at(q * inv_cell) + mc.height_at_m(q) >= body:
			return t
		s += Config.MICRO_LOS_STEP
	return MicroCover.Type.NONE


## ¿Hay un arbusto entre p y la amenaza, pegado a p?
static func concealed(w: SimWorld, p: Vector2, threat: Vector2) -> bool:
	if w.micro == null:
		return false
	var dir: Vector2 = (threat - p).normalized()
	var s: float = Config.MICRO_SELF_M
	while s <= Config.SOLDIER_COVER_PROBE_M:
		if w.micro.type_at_m(p + dir * s) == MicroCover.Type.BUSH:
			return true
		s += Config.MICRO_LOS_STEP
	return false


## Cómo le va a un soldado en p contra threat: {posture, protected, fire (sin mirar el terreno lejano)}.
## Agachado si así queda protegido y tira por encima; si no, cuerpo a tierra (detrás de una roca o
## un tronco asoma por el costado; detrás de un muro no tira).
static func evaluate_spot(w: SimWorld, p: Vector2, threat: Vector2) -> Dictionary:
	var in_crater: bool = w.micro != null and w.micro.type_at_m(p) == MicroCover.Type.CRATER
	if in_crater:
		return {"posture": Soldier.Posture.CROUCH, "protected": true, "fire": true}
	var crouch: int = protecting_obstacle(w, p, Config.SOLDIER_CENTER_CROUCH, threat)
	if crouch != MicroCover.Type.NONE and not _blocks_eye(w, p, Config.SOLDIER_EYE_CROUCH, threat):
		return {"posture": Soldier.Posture.CROUCH, "protected": true, "fire": true}
	var prone: int = protecting_obstacle(w, p, Config.SOLDIER_CENTER_PRONE, threat)
	if prone != MicroCover.Type.NONE:
		return {"posture": Soldier.Posture.PRONE, "protected": true, "fire": prone != MicroCover.Type.WALL}
	return {"posture": Soldier.Posture.PRONE, "protected": false, "fire": true}


## ¿Un obstáculo pegado a p le tapa el ojo (a eye_h) hacia la amenaza?
static func _blocks_eye(w: SimWorld, p: Vector2, eye_h: float, threat: Vector2) -> bool:
	return protecting_obstacle(w, p, eye_h, threat) != MicroCover.Type.NONE


## Elige el punto de cobertura de un soldado alrededor de su lugar en la formación.
## taken: puntos ya elegidos por la escuadra (se respeta SOLDIER_COVER_SPACING).
func choose_cover(w: SimWorld, u: Unit, s: Soldier, threat: Vector2, taken: Array[Vector2]) -> void:
	var center: Vector2 = u.slot_pos_m(s.index)
	var r: float = Config.SOLDIER_COVER_SEARCH_M
	var w_fire: float = Config.SOLDIER_COVER_W_FIRE_MG if s.role == Soldier.Role.MG else Config.SOLDIER_COVER_W_FIRE
	var c0: Vector2i = MicroCover.cell_of(center)
	var ri: int = ceili(r / MicroCover.MICRO_M)
	var pf: Pathfinder = w.pathfinders[Unit.Kind.INFANTRY]
	var limit: float = float(w.height_field.size - 1) * Config.CELL_SIZE
	var cands: Array[Dictionary] = []
	for dy: int in range(-ri, ri + 1):
		for dx: int in range(-ri, ri + 1):
			var p: Vector2 = MicroCover.center_m(c0 + Vector2i(dx, dy))
			var d: float = p.distance_to(center)
			if d > r or p.x < 0.0 or p.y < 0.0 or p.x > limit or p.y > limit:
				continue
			if w.micro != null and MicroCover.protects(w.micro.type_at_m(p)):
				continue # dentro de una roca, un muro o un tronco
			if not pf.is_walkable(Vector2i((p / Config.CELL_SIZE).round())) or not _spaced(p, taken):
				continue
			var ev: Dictionary = evaluate_spot(w, p, threat)
			var base: float = (Config.SOLDIER_COVER_W_PROTECT if ev["protected"] else 0.0) \
				+ (Config.SOLDIER_COVER_W_CONCEAL if concealed(w, p, threat) else 0.0) \
				- Config.SOLDIER_COVER_W_DIST * d / r
			ev["pos"] = p
			ev["base"] = base
			ev["score"] = base + (w_fire if ev["fire"] else 0.0)
			cands.append(ev)
	if cands.is_empty():
		s.has_cover = true
		s.cover_pos = center
		s.protected = false
		s.can_fire = true
		s.cover_posture = Soldier.Posture.PRONE
		s.cover_threat = threat
		return
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	var best: Dictionary = {}
	var best_score: float = -INF
	var checks: int = 0
	for ev: Dictionary in cands:
		if float(ev["score"]) <= best_score:
			break # ordenadas: ninguna de las que siguen puede superarla
		var score: float = float(ev["score"])
		if bool(ev["fire"]):
			if checks >= Config.SOLDIER_COVER_LOS_CHECKS:
				continue
			checks += 1
			var p: Vector2 = ev["pos"]
			var eye: float = Config.SOLDIER_EYE_CROUCH if int(ev["posture"]) == Soldier.Posture.CROUCH else Config.SOLDIER_EYE_PRONE
			if not w.analysis.los_m(p, eye + ground_offset(w, p), threat, 1.0):
				# El terreno tapa la amenaza: protegido, pero no tira
				score = float(ev["base"]) + (0.0 if bool(ev["protected"]) else Config.SOLDIER_COVER_W_PROTECT)
				ev["fire"] = false
				ev["protected"] = true
		if score > best_score:
			best_score = score
			best = ev
	s.has_cover = true
	s.cover_pos = best["pos"]
	s.protected = best["protected"]
	s.can_fire = best["fire"]
	s.cover_posture = best["posture"]
	s.cover_threat = threat
	taken.append(s.cover_pos)


static func _spaced(p: Vector2, taken: Array[Vector2]) -> bool:
	for t: Vector2 in taken:
		if p.distance_to(t) < Config.SOLDIER_COVER_SPACING:
			return false
	return true


## Escuadras detenidas: los soldados sin punto de cobertura lo eligen (primero la ametralladora y el
## jefe). En marcha se olvidan del punto. Si la amenaza se corrió, vuelven a elegir.
func update_cover(w: SimWorld) -> void:
	for u: Unit in w.units:
		if not u.alive or not u.is_infantry():
			continue
		if u.moving:
			for s: Soldier in u.soldiers:
				s.has_cover = false
			continue
		var threat: Vector2 = threat_point(w, u)
		var taken: Array[Vector2] = []
		var pending: Array[Soldier] = []
		for s: Soldier in u.soldiers:
			if not s.is_ok():
				continue
			if s.has_cover and _threat_moved(u, s, threat):
				s.has_cover = false
			if s.has_cover:
				taken.append(s.cover_pos)
			else:
				pending.append(s)
		if pending.is_empty():
			continue
		pending.sort_custom(func(a: Soldier, b: Soldier) -> bool: return _cover_priority(a) < _cover_priority(b))
		for s: Soldier in pending:
			choose_cover(w, u, s, threat, taken)


static func _cover_priority(s: Soldier) -> int:
	match s.role:
		Soldier.Role.MG:
			return 0
		Soldier.Role.LEADER:
			return 1
	return 2 + s.index


func _threat_moved(u: Unit, s: Soldier, threat: Vector2) -> bool:
	var a: Vector2 = s.cover_threat - u.pos_m()
	var b: Vector2 = threat - u.pos_m()
	if a.length() < 0.01 or b.length() < 0.01:
		return false
	return absf(a.angle_to(b)) > deg_to_rad(Config.SOLDIER_COVER_REEVAL_DEG)


## Postura de cada soldado: de pie en marcha (agachado a ritmo cauto); detenido, la de su punto
## de cobertura al llegar, o cuerpo a tierra si la escuadra está suprimida o lleva un rato quieta.
func update_postures(w: SimWorld) -> void:
	for u: Unit in w.units:
		if not u.alive or not u.is_infantry():
			continue
		var cautious: bool = SimWorld.effective_pace(u) == Unit.Pace.CAUTIOUS
		for s: Soldier in u.soldiers:
			if not s.is_ok():
				s.posture = Soldier.Posture.PRONE
			elif w.is_suppressed(u):
				s.posture = Soldier.Posture.PRONE
			elif s.moving:
				s.posture = Soldier.Posture.CROUCH if cautious else Soldier.Posture.STAND
			elif s.has_cover:
				s.posture = s.cover_posture
			else:
				s.posture = Soldier.Posture.PRONE if u.prone else Soldier.Posture.CROUCH


## --- Visión ---

## Antes de cada detección: elige los observadores de cada escuadra (el jefe y los que rotan).
func begin_detection(w: SimWorld) -> void:
	_round += 1
	_observers.clear()
	for u: Unit in w.units:
		if not u.alive or not u.is_infantry():
			continue
		var ok: Array[Soldier] = []
		var leader: Soldier = null
		for s: Soldier in u.soldiers:
			if s.is_ok():
				if s.role == Soldier.Role.LEADER:
					leader = s
				else:
					ok.append(s)
		var obs: Array[Soldier] = []
		if leader != null:
			obs.append(leader)
		var want: int = mini(ok.size(), Config.SOLDIER_OBSERVERS - obs.size())
		for k: int in want:
			obs.append(ok[(_round * want + k) % ok.size()])
		_observers[u.id] = obs


## Altura del ojo de un soldado sobre el terreno (con el desnivel del cráter).
static func eye_of(w: SimWorld, s: Soldier) -> float:
	return s.eye_h() + ground_offset(w, s.pos)


## Altura que hay que ver de un soldado para detectarlo (la cabeza).
static func head_of(w: SimWorld, s: Soldier) -> float:
	return s.top_h() - Config.SOLDIER_HEAD_M + ground_offset(w, s.pos)


## Alcance para detectar a un soldado según lo que hace: en marcha o recién disparado (él o su
## escuadra), INF_SPOT_MOVING; quieto, según la postura, achicado por el bosque y si está protegido.
static func soldier_spot_range(w: SimWorld, u: Unit, s: Soldier) -> float:
	var fired: bool = float(w.total_ticks - s.last_fire_tick) * Config.TICK < Config.FIRE_REVEAL_SECONDS
	if fired or w.recently_fired(u):
		return Config.INF_SPOT_MOVING
	if (s.moving or u.moving) and SimWorld.effective_pace(u) != Unit.Pace.CAUTIOUS and s.posture != Soldier.Posture.PRONE:
		return Config.INF_SPOT_MOVING
	var f: float = 1.0 - w.cover_at(Vector2i((s.pos / Config.CELL_SIZE).round())) * Config.COVER_SPOT_FACTOR
	if s.protected and not s.moving:
		f *= Config.SOLDIER_PROTECTED_SPOT_FACTOR
	var base: float = Config.INF_SPOT_PRONE if s.posture == Soldier.Posture.PRONE else Config.INF_SPOT_STILL
	return base * f


## ¿El bando side ve a algún soldado de la escuadra enemiga? Anota en vis_s a los que ve.
## Cada soldado se mira desde los observadores de cada escuadra propia y desde cada tanque,
## hasta que uno lo vea.
func spot_squad(w: SimWorld, side: int, enemy: Unit, vis_s: Dictionary) -> bool:
	var seen_any: bool = false
	var anchor: Vector2 = enemy.pos_m()
	var viewers: Array[Unit] = []
	for own: Unit in w.units:
		if own.side == side and own.alive \
				and own.pos_m().distance_to(anchor) <= Config.INF_SPOT_MOVING + Config.SOLDIER_PAIR_MARGIN_M:
			viewers.append(own)
	if viewers.is_empty():
		return false
	for t: Soldier in enemy.soldiers:
		if not t.is_ok():
			continue
		var reach: float = soldier_spot_range(w, enemy, t)
		var head: float = head_of(w, t)
		var seen: bool = false
		for own: Unit in viewers:
			if own.is_infantry():
				for o: Soldier in _observers.get(own.id, []):
					if o.pos.distance_to(t.pos) <= reach and w.analysis.los_m(o.pos, eye_of(w, o), t.pos, head):
						seen = true
						break
			else:
				var d: float = own.pos_m().distance_to(t.pos)
				if w.is_suppressed(own):
					d /= Config.TANK_BUTTONED_SPOT_FACTOR
				seen = d <= reach and w.analysis.los_m(own.pos_m(), Config.EYE_H, t.pos, head)
			if seen:
				break
		if seen:
			vis_s[soldier_key(enemy.id, t.index)] = true
			seen_any = true
	return seen_any


## ¿Algún observador de la escuadra ve al tanque? (mismas reglas de alcance que entre tanques)
func soldiers_spot_tank(w: SimWorld, own: Unit, target: Unit) -> bool:
	var tpos: Vector2 = target.pos_m()
	if own.pos_m().distance_to(tpos) > Config.MAX_RANGE + Config.SOLDIER_PAIR_MARGIN_M:
		return false
	for o: Soldier in _observers.get(own.id, []):
		var d: float = o.pos.distance_to(tpos)
		var eye: float = eye_of(w, o)
		if d > Config.MAX_RANGE or not w.analysis.los_m(o.pos, eye, tpos, target.center_h()):
			continue
		if w.tank_spot_rule(target, d, func() -> bool: return w.analysis.los_m(o.pos, eye, tpos, target.profile_h())):
			return true
	return false


## ¿El bando ve a ese soldado?
func is_soldier_visible(side: int, unit_id: int, index: int) -> bool:
	return visible_soldiers[side].has(soldier_key(unit_id, index))
