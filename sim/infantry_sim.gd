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
		if s.is_ok() and s.suppression < Config.PINNED and s.pos.distance_to(u.slot_pos_m(s.index)) > Config.SOLDIER_LAG_M:
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
			if not s.is_ok() or s.suppression >= Config.PINNED or s.dive_until > w.total_ticks:
				s.moving = false # herido, clavado o recién tirado al suelo: se queda donde está
				continue
			var target: Vector2 = u.slot_pos_m(s.index)
			if s.has_cover and not u.moving:
				target = s.fire_pos if s.peeking else s.cover_pos
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


## Soldado en condiciones al azar (para un impacto en la escuadra sin soldado elegido). null si no hay.
func random_ok(w: SimWorld, u: Unit) -> Soldier:
	var ok: Array[Soldier] = []
	for s: Soldier in u.soldiers:
		if s.is_ok():
			ok.append(s)
	return ok[w.rng.randi_range(0, ok.size() - 1)] if not ok.is_empty() else null


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
	if u.mind != null and not u.mind.contacts.is_empty():
		var acc: Vector2 = Vector2.ZERO
		for id: int in u.mind.contacts:
			acc += u.mind.contacts[id]["pos"]
		return acc / float(u.mind.contacts.size()) # lo que sabe la propia escuadra
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
	var r: float = u.mind.cover_m if u.mind != null else Config.SOLDIER_COVER_SEARCH_M
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
	_choose_fire_pos(w, s, threat, cands)


## Reflejo "asomar y tirar": si desde su cobertura no tiene tiro, busca cerca (a REFLEX_PEEK_RADIUS_M)
## un punto desde el que sí lo tenga; ahí se asoma por turnos (ver update_peeks).
func _choose_fire_pos(w: SimWorld, s: Soldier, threat: Vector2, cands: Array[Dictionary]) -> void:
	s.has_fire_pos = false
	s.peeking = false
	if s.can_fire:
		return
	var near: Array[Dictionary] = []
	for ev: Dictionary in cands:
		var p: Vector2 = ev["pos"]
		if bool(ev["fire"]) and p.distance_to(s.cover_pos) <= Config.REFLEX_PEEK_RADIUS_M:
			near.append(ev)
	near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["pos"] as Vector2).distance_to(s.cover_pos) < (b["pos"] as Vector2).distance_to(s.cover_pos))
	for k: int in mini(near.size(), Config.REFLEX_PEEK_LOS_CHECKS):
		var p: Vector2 = near[k]["pos"]
		var post: int = near[k]["posture"]
		var eye: float = Config.SOLDIER_EYE_CROUCH if post == Soldier.Posture.CROUCH else Config.SOLDIER_EYE_PRONE
		if w.analysis.los_m(p, eye + ground_offset(w, p), threat, 1.0):
			s.has_fire_pos = true
			s.fire_pos = p
			s.fire_posture = post
			s.peek_tick = w.total_ticks + roundi(Config.REFLEX_PEEK_HIDE_SECONDS / Config.TICK * 0.5) + s.index * 3
			return


## Los que tienen desde dónde asomar se turnan: un rato asomados tirando, otro a cubierto. Si la
## escuadra no conoce amenazas, o el soldado está suprimido, se queda a cubierto.
func update_peeks(w: SimWorld) -> void:
	var now: int = w.total_ticks
	for u: Unit in w.units:
		if not u.alive or not u.is_infantry():
			continue
		var threats: bool = not w.threats_for(u.side).is_empty() if not u.moving else false
		for s: Soldier in u.soldiers:
			if not s.peeking and not s.has_fire_pos:
				continue
			if not s.is_ok() or not s.has_cover or not s.has_fire_pos or u.moving or not threats \
					or s.suppression >= Config.SUPPRESSED:
				if s.peeking:
					s.peeking = false
					s.peek_tick = now + roundi(Config.REFLEX_PEEK_HIDE_SECONDS / Config.TICK)
				continue
			if now >= s.peek_tick:
				s.peeking = not s.peeking
				var secs: float = Config.REFLEX_PEEK_FIRE_SECONDS if s.peeking else Config.REFLEX_PEEK_HIDE_SECONDS
				s.peek_tick = now + roundi(secs / Config.TICK)


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
			if s.has_cover and _cover_flanked(w, s):
				s.has_cover = false # cubierta inválida: le tiran desde donde no lo protege
			if s.has_cover:
				taken.append(s.cover_pos)
			else:
				pending.append(s)
		if pending.is_empty():
			continue
		pending.sort_custom(func(a: Soldier, b: Soldier) -> bool: return _cover_priority(a) < _cover_priority(b))
		for s: Soldier in pending:
			choose_cover(w, u, s, _incoming_threat(w, s, threat), taken)


## ¿Le tiraron hace poco desde una dirección muy distinta a la de su cobertura, y ahí no lo protege?
func _cover_flanked(w: SimWorld, s: Soldier) -> bool:
	if float(w.total_ticks - s.incoming_tick) * Config.TICK > Config.REFLEX_INCOMING_SECONDS:
		return false
	var a: Vector2 = s.cover_threat - s.pos
	var b: Vector2 = s.incoming_from - s.pos
	if a.length() < 0.01 or b.length() < 0.01 or absf(a.angle_to(b)) <= deg_to_rad(Config.SOLDIER_COVER_REEVAL_DEG):
		return false
	return not is_protected_from(w, s, s.incoming_from)


## Contra qué se cubre un soldado: de donde le vienen tirando, si fue hace poco; si no, la amenaza de la escuadra.
static func _incoming_threat(w: SimWorld, s: Soldier, threat: Vector2) -> Vector2:
	if float(w.total_ticks - s.incoming_tick) * Config.TICK <= Config.REFLEX_INCOMING_SECONDS:
		return s.incoming_from
	return threat


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
			elif s.suppression >= Config.SUPPRESSED:
				s.posture = Soldier.Posture.PRONE
			elif s.moving:
				s.posture = Soldier.Posture.CROUCH if cautious else Soldier.Posture.STAND
			elif s.dive_until > w.total_ticks:
				s.posture = Soldier.Posture.PRONE # se tiró al suelo
			elif s.has_cover:
				s.posture = s.fire_posture if s.peeking else s.cover_posture
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


## Alcance para detectar a un soldado según lo que hace: en marcha o recién disparado,
## INF_SPOT_MOVING; quieto, según la postura, achicado por el bosque y si está protegido.
static func soldier_spot_range(w: SimWorld, u: Unit, s: Soldier) -> float:
	var fired: bool = float(w.total_ticks - s.last_fire_tick) * Config.TICK < Config.FIRE_REVEAL_SECONDS
	if fired:
		return Config.INF_SPOT_MOVING
	if (s.moving or u.moving) and SimWorld.effective_pace(u) != Unit.Pace.CAUTIOUS and s.posture != Soldier.Posture.PRONE:
		return Config.INF_SPOT_MOVING
	var f: float = 1.0 - w.cover_at(Vector2i((s.pos / Config.CELL_SIZE).round())) * Config.COVER_SPOT_FACTOR
	if s.protected and not s.moving and not s.peeking:
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


func round_index() -> int:
	return _round


## Detección escalonada: copia a vis_s lo que el bando veía de esa escuadra la vez anterior.
## Devuelve si veía a alguno.
func keep_previous(side: int, enemy: Unit, vis_s: Dictionary) -> bool:
	var any: bool = false
	for t: Soldier in enemy.soldiers:
		var key: int = soldier_key(enemy.id, t.index)
		if t.is_ok() and visible_soldiers[side].has(key):
			vis_s[key] = true
			any = true
	return any


## ¿El bando ve a ese soldado?
func is_soldier_visible(side: int, unit_id: int, index: int) -> bool:
	return visible_soldiers[side].has(soldier_key(unit_id, index))


## --- Fuego ---

## Los soldados de la escuadra tiran, cada uno con su arma, a soldados enemigos visibles para el
## bando a los que ellos mismos ven; el antitanque, a tanques. El soldado clavado no tira; la ROE,
## arco, distancia máxima, sector de vigilancia y blanco de ATTACK valen para todos.
## u.reload_left > 0 traba los fusiles y la ametralladora de toda la escuadra; u.reload2_left, el antitanque.
func fire_squad(w: SimWorld, u: Unit) -> void:
	u.reload_left = maxf(0.0, u.reload_left - Config.TICK)
	u.reload2_left = maxf(0.0, u.reload2_left - Config.TICK)
	for s: Soldier in u.soldiers:
		s.reload_left = maxf(0.0, s.reload_left - Config.TICK)
	if not w.roe_allows_fire(u):
		return
	var area: bool = u.order == Unit.Order.SUPPRESS
	for s: Soldier in u.soldiers:
		if not s.is_ok() or s.reload_left > 0.0 or s.suppression >= Config.PINNED:
			continue
		if s.role == Soldier.Role.AT and not area and u.at_charges > 0 and u.reload2_left <= 0.0:
			var tank: Unit = _pick_tank(w, u, s)
			if tank != null:
				_fire_at_tank(w, u, s, tank)
				continue
		if u.reload_left > 0.0:
			continue
		var wpn: int = Unit.Weapon.MG if s.role == Soldier.Role.MG else Unit.Weapon.RIFLES
		if area:
			_area_shot(w, u, s, wpn)
			continue
		var t: Dictionary = pick_soldier(w, u, s.pos, eye_of(w, s), SimWorld.weapon_range(wpn), s.index)
		if not t.is_empty():
			_shoot(w, u, s.pos, eye_of(w, s), s, t["unit"], t["soldier"], wpn)


## Coaxial de un tanque: ráfaga al soldado enemigo visible más cercano que ve desde su óptica.
func tank_coax(w: SimWorld, tank: Unit) -> void:
	if not w.roe_allows_fire(tank):
		return
	var t: Dictionary = pick_soldier(w, tank, tank.pos_m(), Config.EYE_H, Config.COAX_RANGE)
	if not t.is_empty():
		_shoot(w, tank, tank.pos_m(), Config.EYE_H, null, t["unit"], t["soldier"], Unit.Weapon.COAX)


## Blanco para un tirador en from (ojo a eye sobre el terreno): {unit, soldier} del soldado enemigo
## visible para el bando más cercano (los del blanco de ATTACK cuentan como más cerca) dentro del
## alcance, el arco y el sector, al que el tirador ve la cabeza. Vacío si no hay. spread reparte el
## fuego: el tirador arranca por el blanco spread entre los SOLDIER_TARGET_SPREAD más cercanos.
func pick_soldier(w: SimWorld, u: Unit, from: Vector2, eye: float, reach: float, spread: int = 0) -> Dictionary:
	var max_d: float = minf(reach, u.max_engage_m)
	var cands: Array[Dictionary] = []
	for key: int in visible_soldiers[u.side]:
		var tu: Unit = w.get_unit(key / 64)
		if tu == null or not tu.alive:
			continue
		var ts: Soldier = tu.soldiers[key % 64]
		if not ts.is_ok():
			continue
		var d: float = from.distance_to(ts.pos)
		var at: Vector2 = ts.pos / Config.CELL_SIZE
		if d > max_d or not SimWorld.in_fire_arc(u, at):
			continue
		if u.order == Unit.Order.OVERWATCH and not SimWorld.in_overwatch_sector(u, at):
			continue
		var rank: float = d * (0.5 if tu.id == u.attack_target else 1.0)
		cands.append({"unit": tu, "soldier": ts, "rank": rank})
	if cands.is_empty():
		return {}
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["rank"]) < float(b["rank"]))
	# Reparto del fuego: cada tirador arranca por un blanco distinto entre los más cercanos
	var start: int = spread % mini(cands.size(), Config.SOLDIER_TARGET_SPREAD)
	for k: int in mini(cands.size(), Config.SOLDIER_TARGET_CHECKS):
		var i: int = (start + k) % cands.size()
		var ts: Soldier = cands[i]["soldier"]
		if w.analysis.los_m(from, eye, ts.pos, head_of(w, ts)):
			return cands[i]
	return {}


## Probabilidad de que un tiro desde from (ojo a eye) con el arma wpn le pegue al soldado t.
## Arma (fusil o ráfaga) x distancia x tirador en marcha x postura x protección (obstáculo o terreno)
## x bosque x escuadra diezmada o suprimida. aimed: el tiro apuntado mira además si el terreno
## le tapa el cuerpo (una ráfaga no).
func soldier_hit_p(w: SimWorld, shooter: Unit, shooter_moving: bool, from: Vector2, eye: float,
		tu: Unit, t: Soldier, wpn: int, aimed: bool = true, ss: Soldier = null) -> float:
	var p: float = Config.SOLDIER_RIFLE_P_HIT
	if wpn == Unit.Weapon.MG:
		p = Config.SOLDIER_MG_P_HIT
	elif wpn == Unit.Weapon.COAX:
		p = Config.SOLDIER_COAX_P_HIT
	var d: float = from.distance_to(t.pos)
	var f_dist: float = clampf(1.0 - d / SimWorld.weapon_range(wpn), 0.2, 1.0)
	var f_post: float = 1.0
	if t.posture == Soldier.Posture.PRONE:
		f_post = Config.INF_PRONE_HIT_FACTOR
	elif t.posture == Soldier.Posture.CROUCH:
		f_post = Config.SOLDIER_CROUCH_HIT_FACTOR
	var f_cover: float = 1.0
	if is_protected_from(w, t, from) or (aimed and not w.analysis.los_m(from, eye, t.pos, t.center_h() + ground_offset(w, t.pos))):
		f_cover = Config.SOLDIER_COVER_HIT_FACTOR
	var f_forest: float = 1.0 - w.cover_at(Vector2i((t.pos / Config.CELL_SIZE).round()))
	var f_weak: float = soldier_weak_factor(shooter, ss) if shooter.is_infantry() else 1.0
	return minf(p * f_dist * w.move_fire_factor(shooter, shooter_moving) * f_post * f_cover * f_forest * f_weak, w.p_hit_max)


## Escuadra diezmada o soldado suprimido: tira peor.
static func soldier_weak_factor(u: Unit, s: Soldier) -> float:
	var f: float = 1.0
	if u.hp <= Config.INF_WEAK_MEN:
		f *= Config.INF_WEAK_FACTOR
	if s != null and s.suppression >= Config.SUPPRESSED:
		f *= Config.SUPPRESSED_FIRE_FACTOR
	return f


## ¿Un obstáculo (o el cráter en que está, si no está de pie) protege al soldado del fuego que viene de from?
static func is_protected_from(w: SimWorld, t: Soldier, from: Vector2) -> bool:
	if w.micro == null:
		return false
	if t.posture != Soldier.Posture.STAND and w.micro.type_at_m(t.pos) == MicroCover.Type.CRATER:
		return true
	return protecting_obstacle(w, t.pos, t.center_h(), from) != MicroCover.Type.NONE


## Un tiro (o una ráfaga) desde from contra el soldado t de la escuadra tu. s: el soldado que tira
## (null si es la coaxial de un tanque).
func _shoot(w: SimWorld, su: Unit, from: Vector2, eye: float, s: Soldier, tu: Unit, t: Soldier, wpn: int) -> void:
	var moving: bool = s.moving if s != null else su.moving
	var reload: float = SimWorld.weapon_reload(wpn)
	if s != null:
		reload = (Config.SOLDIER_RIFLE_RELOAD if wpn == Unit.Weapon.RIFLES else reload) * w.rng.randf_range(0.75, 1.25)
		s.reload_left = reload
		s.last_fire_tick = w.total_ticks
		s.heading = (t.pos - s.pos).normalized()
	else:
		su.reload2_left = reload
	su.last_fire_tick = w.total_ticks
	su.overwatch_ready = false
	# Fogonazo: el bando del blanco sabe de dónde vino el tiro, aunque no lo vea
	w.known_enemies[tu.side][su.id] = {"cell": su.cell(), "last_seen_turn": w.turn}
	w.minds.flash(w, tu, su, from)
	tu.shots_received += 1
	tu.last_fired_upon_tick = w.total_ticks
	var hit: bool = false
	if wpn == Unit.Weapon.RIFLES:
		hit = w.rng.randf() < soldier_hit_p(w, su, moving, from, eye, tu, t, wpn, true, s)
		if hit:
			w.damage_soldier(tu, t)
	else:
		hit = _burst(w, su, moving, from, eye, tu.side, t.pos, wpn, 1.0, s) > 0
	suppress_at(w, tu.side, t.pos, from, wpn, hit)
	w.shot_events.append({"shooter": su.id, "target": tu.id, "hit": hit, "aspect": SimWorld.Aspect.FRONT,
		"weapon": wpn, "from_m": from, "from_h": eye, "to_m": t.pos, "to_h": t.center_h(), "soldier": t.index})


## Ráfaga sobre at: cada soldado del bando side a <= SOLDIER_BURST_M tira su dado (heridos incluidos).
## Devuelve cuántos impactos hubo.
func _burst(w: SimWorld, su: Unit, moving: bool, from: Vector2, eye: float, side: int, at: Vector2,
		wpn: int, factor: float, ss: Soldier = null) -> int:
	var hits: int = 0
	for tu: Unit in w.units:
		if not tu.alive or tu.side != side or not tu.is_infantry() or tu.pos_m().distance_to(at) > Config.SOLDIER_LAG_M * 4.0:
			continue
		for t: Soldier in tu.soldiers:
			if t.state == Soldier.State.DEAD or t.pos.distance_to(at) > Config.SOLDIER_BURST_M:
				continue
			if w.rng.randf() < soldier_hit_p(w, su, moving, from, eye, tu, t, wpn, false, ss) * factor:
				w.damage_soldier(tu, t)
				hits += 1
	return hits


## Orden SUPPRESS: cada tiro (o ráfaga) cae en un punto al azar de la zona; suprime a las escuadras
## enemigas de la zona y casi no mata.
func _area_shot(w: SimWorld, u: Unit, s: Soldier, wpn: int) -> void:
	if not w.can_suppress_at(u, u.suppress_cell):
		return
	s.reload_left = (Config.SOLDIER_RIFLE_RELOAD if wpn == Unit.Weapon.RIFLES else SimWorld.weapon_reload(wpn)) * w.rng.randf_range(0.75, 1.25)
	s.last_fire_tick = w.total_ticks
	u.last_fire_tick = w.total_ticks
	var r: float = Config.SUPPRESS_AREA_RADIUS * Config.CELL_SIZE
	var center: Vector2 = Vector2(u.suppress_cell) * Config.CELL_SIZE
	var at: Vector2 = center + Vector2(w.rng.randf_range(-r, r), w.rng.randf_range(-r, r))
	var eye: float = eye_of(w, s)
	for tu: Unit in w.units:
		if not tu.alive or tu.side == u.side or tu.pos_m().distance_to(center) > r + Config.SOLDIER_LAG_M:
			continue
		w.known_enemies[tu.side][u.id] = {"cell": u.cell(), "last_seen_turn": w.turn}
		w.minds.flash(w, tu, u, s.pos)
		w._add_suppression(tu, SimWorld.weapon_suppression(wpn) * Config.SUPPRESS_AREA_SUPP * Config.SOLDIER_SHOT_SUPP_SCALE)
	_burst(w, u, s.moving, s.pos, eye, 1 - u.side, at, wpn, Config.SUPPRESS_AREA_HIT_FACTOR, s)
	w.shot_events.append({"shooter": u.id, "target": -1, "cell": u.suppress_cell, "hit": false,
		"aspect": SimWorld.Aspect.FRONT, "weapon": wpn, "from_m": s.pos, "from_h": eye, "to_m": at, "to_h": 0.5})


## Tanque enemigo visible para el bando, el más cercano al alcance del antitanque al que el tirador ve.
func _pick_tank(w: SimWorld, u: Unit, s: Soldier) -> Unit:
	var best: Unit = null
	var best_d: float = INF
	var eye: float = eye_of(w, s)
	for id: int in w.visible_enemies[u.side]:
		var tank: Unit = w.units[id]
		if not tank.alive or tank.is_infantry():
			continue
		var d: float = s.pos.distance_to(tank.pos_m())
		if d > minf(Config.AT_RANGE, u.max_engage_m) or d >= best_d or not SimWorld.in_fire_arc(u, tank.pos):
			continue
		if w.analysis.los_m(s.pos, eye, tank.pos_m(), tank.center_h()):
			best = tank
			best_d = d
	return best


## Disparo del antitanque: AT_P_HIT x distancia x en marcha x casco x blindaje x escuadra diezmada.
func _fire_at_tank(w: SimWorld, u: Unit, s: Soldier, tank: Unit) -> void:
	var eye: float = eye_of(w, s)
	var d: float = s.pos.distance_to(tank.pos_m())
	var f_dist: float = clampf(1.0 - d / Config.AT_RANGE, 0.2, 1.0)
	var f_hull: float = 1.0 if w.analysis.los_m(s.pos, eye, tank.pos_m(), tank.profile_h()) else w.hulldown_hit_factor
	var aspect: int = SimWorld.aspect_of(tank, s.pos / Config.CELL_SIZE)
	var f_armor: float = SimWorld.aspect_factor(aspect) if w.armor_enabled else 1.0
	var p: float = minf(Config.AT_P_HIT * f_dist * w.move_fire_factor(u, s.moving) * f_hull * f_armor * SimWorld._weak_factor(u), w.p_hit_max)
	u.at_charges -= 1
	u.reload2_left = Config.AT_RELOAD
	s.reload_left = Config.AT_RELOAD
	s.last_fire_tick = w.total_ticks
	u.last_fire_tick = w.total_ticks
	w.known_enemies[tank.side][u.id] = {"cell": u.cell(), "last_seen_turn": w.turn}
	tank.shots_received += 1
	tank.last_fired_upon_tick = w.total_ticks
	var hit: bool = w.rng.randf() < p
	if hit:
		w._damage(tank)
	w._suppress(tank, Unit.Weapon.AT, hit)
	w.shot_events.append({"shooter": u.id, "target": tank.id, "hit": hit, "aspect": aspect, "weapon": Unit.Weapon.AT,
		"from_m": s.pos, "from_h": eye, "to_m": tank.pos_m(), "to_h": tank.center_h()})


## --- Supresión ---

## Un tiro que cae en at (desde from): el soldado de ahí recibe SOLDIER_SUPP_RIFLE o _BURST (x SUPP_HIT_MULT
## si pegó) y los que están a <= SOLDIER_SUPP_NEAR_M, la mitad. Protegido del tiro, recibe menos.
func suppress_at(w: SimWorld, side: int, at: Vector2, from: Vector2, wpn: int, hit: bool) -> void:
	var base: float = Config.SOLDIER_SUPP_RIFLE if wpn == Unit.Weapon.RIFLES else Config.SOLDIER_SUPP_BURST
	var amount: float = base * (Config.SUPP_HIT_MULT if hit else 1.0)
	for tu: Unit in w.units:
		if not tu.alive or tu.side != side or not tu.is_infantry() \
				or tu.pos_m().distance_to(at) > Config.SOLDIER_SUPP_NEAR_M + Config.SOLDIER_LAG_M * 4.0:
			continue
		var touched: bool = false
		for t: Soldier in tu.soldiers:
			if not t.is_ok():
				continue
			var d: float = t.pos.distance_to(at)
			if d > Config.SOLDIER_SUPP_NEAR_M:
				continue
			var a: float = amount if d < 0.5 else amount * 0.5
			var prot: bool = is_protected_from(w, t, from)
			if prot:
				a *= Config.SOLDIER_SUPP_COVER_FACTOR
			add_soldier_suppression(w, t, a)
			t.incoming_from = from
			t.incoming_tick = w.total_ticks
			if tu.moving and not prot and a >= Config.REFLEX_DIVE_SUPP:
				t.dive_until = w.total_ticks + roundi(Config.REFLEX_DIVE_SECONDS / Config.TICK) # ¡al suelo!
			touched = true
		if touched:
			tu.last_suppressed_tick = w.total_ticks
			aggregate_suppression(tu)
			if w.is_suppressed(tu):
				tu.prone = true
				tu.still_time = maxf(tu.still_time, Config.INF_PRONE_SECONDS)


func add_soldier_suppression(w: SimWorld, s: Soldier, amount: float) -> void:
	s.suppression = minf(100.0, s.suppression + amount)
	s.last_suppressed_tick = w.total_ticks


## Supresión de la escuadra = promedio de la de sus soldados en condiciones.
func aggregate_suppression(u: Unit) -> void:
	var sum: float = 0.0
	var n: int = 0
	for s: Soldier in u.soldiers:
		if s.is_ok():
			sum += s.suppression
			n += 1
	u.suppression = sum / float(n) if n > 0 else 0.0


## La supresión de cada soldado baja sola pasado un rato sin fuego. Devuelve la fracción de
## soldados en condiciones que quedan suprimidos.
func decay_suppression(w: SimWorld, u: Unit) -> float:
	var n: int = 0
	var supp: int = 0
	for s: Soldier in u.soldiers:
		if not s.is_ok():
			continue
		if float(w.total_ticks - s.last_suppressed_tick) * Config.TICK > Config.SUPP_DECAY_DELAY:
			s.suppression = maxf(0.0, s.suppression - Config.SUPP_DECAY * Config.TICK)
		n += 1
		if s.suppression >= Config.SUPPRESSED:
			supp += 1
	aggregate_suppression(u)
	return float(supp) / float(n) if n > 0 else 0.0


## Fracción de soldados en condiciones clavados.
func pinned_fraction(u: Unit) -> float:
	var n: int = 0
	var pinned: int = 0
	for s: Soldier in u.soldiers:
		if s.is_ok():
			n += 1
			if s.suppression >= Config.PINNED:
				pinned += 1
	return float(pinned) / float(n) if n > 0 else 0.0


## ¿La escuadra no avanza? Cuando más de SOLDIER_SUPP_HALT de sus soldados están suprimidos.
func halted(u: Unit) -> bool:
	var n: int = 0
	var supp: int = 0
	for s: Soldier in u.soldiers:
		if s.is_ok():
			n += 1
			if s.suppression >= Config.SUPPRESSED:
				supp += 1
	return n > 0 and float(supp) / float(n) > Config.SOLDIER_SUPP_HALT
