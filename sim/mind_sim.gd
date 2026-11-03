class_name MindSim
extends RefCounted
## La autonomía de las escuadras: cada una piensa cada tanto (puntúa sus opciones y elige con
## histéresis, ver SquadMind.choose) y, en cada tick, ejecuta la opción elegida. Las decisiones
## que la apartan de la orden del jugador se avisan por radio (SimWorld.radio). Al volver a FOLLOW
## retoma la orden guardada. Es de SimWorld y recibe el mundo en cada llamada.


## Avisos de radio en camino: {tick (de llegada), unit (el que lo recibe), enemy, pos, seen (tick de la noticia)}.
var _radio_queue: Array[Dictionary] = []
var _announced: Array[Dictionary] = [{}, {}] # por bando: enemigo -> tick del último anuncio por radio


## Un tick: llegan los avisos de radio, se olvidan los contactos viejos, las escuadras a las que
## les toca piensan y todas ejecutan su opción.
func update(w: SimWorld) -> void:
	_deliver_radio(w)
	for u: Unit in w.units:
		if not u.alive or u.mind == null:
			continue
		var m: SquadMind = u.mind
		if u.broken:
			if not m.is_following():
				switch_to(w, u, SquadMind.Option.FOLLOW) # la retirada por moral manda
			continue
		if m.disorganized_until >= 0:
			if m.is_disorganized(w.total_ticks):
				continue # sin jefe: cada uno se cubre donde está
			_new_leader(w, u)
		_smoke_reflex(w, u)
		if w.total_ticks >= m.next_think_tick:
			m.next_think_tick = w.total_ticks + think_interval(u)
			_forget(w, u)
			think(w, u)
		act(w, u)


## --- Conocimiento ---

## Tras cada detección: lo que el bando ve a menos de CONTACT_OWN_M de una escuadra, ella lo sabe
## al momento y exacto; lo que está más lejos le llega por radio con demora.
func on_detection(w: SimWorld) -> void:
	for u: Unit in w.units:
		if not u.alive or u.mind == null:
			continue
		var m: SquadMind = u.mind
		for id: int in w.visible_enemies[u.side]:
			var e: Unit = w.units[id]
			if e.pos_m().distance_to(u.pos_m()) <= Config.CONTACT_OWN_M:
				if m.learn(id, e.pos_m(), w.total_ticks, true):
					_announce_contact(w, u, e, e.pos_m())
			elif not m.pending.has(id):
				m.pending[id] = true
				var delay: float = w.mind_rng.randf_range(Config.RADIO_DELAY_MIN, Config.RADIO_DELAY_MAX)
				_radio_queue.append({"tick": w.total_ticks + roundi(delay / Config.TICK), "unit": u.id,
					"enemy": id, "pos": e.pos_m(), "seen": w.total_ticks})


## Le tiraron: si no ve al tirador, sabe más o menos de dónde vino (CONTACT_FLASH_ERROR de la distancia).
func flash(w: SimWorld, target: Unit, shooter: Unit, from: Vector2) -> void:
	if target.mind == null or not target.alive:
		return
	if w.visible_enemies[target.side].has(shooter.id) and from.distance_to(target.pos_m()) <= Config.CONTACT_OWN_M:
		target.mind.learn(shooter.id, shooter.pos_m(), w.total_ticks, true)
		return
	var old: Dictionary = target.mind.contacts.get(shooter.id, {})
	if not old.is_empty() and int(old["tick"]) >= w.total_ticks - Config.MIND_THINK_TICKS:
		return # ya tiene una noticia de este segundo
	var err: float = from.distance_to(target.pos_m()) * Config.CONTACT_FLASH_ERROR
	var pos: Vector2 = from + Vector2(w.mind_rng.randf_range(-err, err), w.mind_rng.randf_range(-err, err))
	if target.mind.learn(shooter.id, pos, w.total_ticks, false):
		_announce_contact(w, target, shooter, pos)


func _deliver_radio(w: SimWorld) -> void:
	while not _radio_queue.is_empty() and int(_radio_queue[0]["tick"]) <= w.total_ticks:
		var msg: Dictionary = _radio_queue.pop_front()
		var u: Unit = w.get_unit(int(msg["unit"]))
		if u == null or not u.alive or u.mind == null:
			continue
		u.mind.pending.erase(int(msg["enemy"]))
		u.mind.learn(int(msg["enemy"]), msg["pos"], int(msg["seen"]), true)


## Se olvidan los contactos sin noticias en CONTACT_FORGET_SECONDS (y los de enemigos muertos).
func _forget(w: SimWorld, u: Unit) -> void:
	var m: SquadMind = u.mind
	for id: int in m.contacts.keys():
		var e: Unit = w.units[id]
		if not e.alive or float(w.total_ticks - int(m.contacts[id]["tick"])) * Config.TICK > Config.CONTACT_FORGET_SECONDS:
			m.contacts.erase(id)


## Primera noticia de un enemigo para el bando (o pasado RADIO_REPORT_SECONDS): se anuncia por radio.
func _announce_contact(w: SimWorld, u: Unit, e: Unit, pos: Vector2) -> void:
	var last: int = int(_announced[u.side].get(e.id, -1000000))
	if float(w.total_ticks - last) * Config.TICK < Config.RADIO_REPORT_SECONDS:
		return
	_announced[u.side][e.id] = w.total_ticks
	var what: String = "infantería" if e.is_infantry() else "tanque"
	var d: Vector2 = pos - u.pos_m()
	w.radio(u, "contacto: %s a %d m al %s" % [what, roundi(d.length()), compass(d)])


## Rumbo en palabras (el norte es -y en la grilla).
static func compass(d: Vector2) -> String:
	const NAMES: Array[String] = ["este", "sudeste", "sur", "sudoeste", "oeste", "noroeste", "norte", "noreste"]
	var a: float = fposmod(atan2(d.y, d.x), TAU)
	return NAMES[roundi(a / (TAU / 8.0)) % 8]


## Reflejo de la escuadra: frenada por la supresión más de INF_SMOKE_SUPPRESSED_SECONDS, tira una
## granada de humo de mano entre ella y la amenaza (si le quedan). Con autonomía normal o alta.
func _smoke_reflex(w: SimWorld, u: Unit) -> void:
	var m: SquadMind = u.mind
	if not w.inf.halted(u):
		m.halted_since = -1
		m.crawling = false
		return
	if m.halted_since < 0:
		m.halted_since = w.total_ticks
		return
	_crawl_reflex(w, u)
	if m.autonomy < SquadMind.Autonomy.NORMAL or u.smoke_charges <= 0:
		return
	if float(w.total_ticks - m.halted_since) * Config.TICK < Config.INF_SMOKE_SUPPRESSED_SECONDS:
		return
	if throw_smoke_toward(w, u, w.inf.threat_point(w, u)):
		w.radio(u, "humo, ¡nos tienen clavados!")
	m.halted_since = w.total_ticks # la próxima, otros 15 s después


## Clavada en marcha más de CRAWL_AFTER_SECONDS (autonomía normal o alta): sigue reptando hacia su
## destino en vez de quedarse quieta. No en la retirada ni si decidió frenar.
func _crawl_reflex(w: SimWorld, u: Unit) -> void:
	var m: SquadMind = u.mind
	var can: bool = m.autonomy >= SquadMind.Autonomy.NORMAL and not u.path.is_empty() and not m.hold \
			and u.order != Unit.Order.WITHDRAW and m.option in [SquadMind.Option.FOLLOW, SquadMind.Option.BOUND]
	if not can:
		m.crawling = false
		return
	if not m.crawling and float(w.total_ticks - m.halted_since) * Config.TICK >= Config.CRAWL_AFTER_SECONDS:
		m.crawling = true
		w.radio(u, "nos tienen clavados, seguimos reptando")


## Granada de humo de mano hacia threat (a INF_SMOKE_DIST_M, o a mitad de camino si está más cerca).
func throw_smoke_toward(w: SimWorld, u: Unit, threat: Vector2) -> bool:
	var from: Vector2 = u.pos_m()
	var d: float = from.distance_to(threat)
	if d < 0.01:
		return false
	return w.hand_smoke(u, from + (threat - from) / d * minf(Config.INF_SMOKE_DIST_M, d * 0.5))


## Ticks entre decisiones (según el jefe).
func think_interval(u: Unit) -> int:
	return u.mind.think_ticks()


## --- Mando ---

## Cayó el jefe: deja lo que hacía (guarda la orden) y queda desorganizada un rato.
func on_leader_lost(w: SimWorld, u: Unit) -> void:
	var m: SquadMind = u.mind
	if not m.is_following():
		switch_to(w, u, SquadMind.Option.FOLLOW)
	var secs: float = w.mind_rng.randf_range(Config.LEADERLESS_MIN_SECONDS, Config.LEADERLESS_MAX_SECONDS)
	m.disorganized_until = w.total_ticks + roundi(secs / Config.TICK)
	w.radio(u, "¡cayó el jefe!")


## Pasada la desorganización, el segundo toma el mando (un fusilero o el proveedor si hay; si no,
## cualquiera). Manda peor: la calidad baja un escalón.
func _new_leader(w: SimWorld, u: Unit) -> void:
	var m: SquadMind = u.mind
	m.disorganized_until = -1
	var pick: Soldier = null
	for s: Soldier in u.soldiers:
		if s.is_ok() and (s.role == Soldier.Role.RIFLE or s.role == Soldier.Role.ASSISTANT):
			pick = s
			break
	if pick == null:
		for s: Soldier in u.soldiers:
			if s.is_ok():
				pick = s
				break
	if pick == null:
		return
	pick.role = Soldier.Role.LEADER
	m.quality = mini(m.quality + 1, SquadMind.Quality.GREEN)
	m.next_think_tick = w.total_ticks
	w.radio(u, "el soldado %d toma el mando" % (pick.index + 1))


## Puntúa las opciones permitidas y cambia si corresponde.
func think(w: SimWorld, u: Unit) -> void:
	var m: SquadMind = u.mind
	var all: Dictionary = score_options(w, u)
	var p_scores: Dictionary = {}
	var noise: float = m.score_noise()
	for opt: int in all:
		if SquadMind.allowed(m.autonomy, opt):
			var e: float = w.mind_rng.randf_range(-noise, noise) if noise > 0.0 and opt != SquadMind.Option.FOLLOW else 0.0
			p_scores[opt] = float(all[opt]) + e
	m.scores = p_scores
	var next: int = SquadMind.choose(m.option, m.since_tick, p_scores, w.total_ticks)
	if next != m.option:
		switch_to(w, u, next)


## Puntaje de cada opción disponible ahora (las que no figuran no se pueden elegir).
func score_options(w: SimWorld, u: Unit) -> Dictionary:
	var s: Dictionary = {SquadMind.Option.FOLLOW: Config.MIND_FOLLOW_SCORE}
	_score_drill(w, u, s)
	_score_relocate(w, u, s)
	_score_ambush(w, u, s)
	_score_break(w, u, s)
	_score_bound(w, u, s)
	_score_flank(w, u, s)
	_score_rescue(w, u, s)
	_score_near_ambush(w, u, s)
	return s


## --- Emboscada cercana (fase 52) ---
## Le tiran desde menos de NEAR_AMBUSH_M: en la zona de muerte no se busca cubierta, se asalta al
## emboscador ya, a la carrera (y con granadas, que a esa distancia salen solas). Más lejos es una
## emboscada lejana: el drill de contacto (fuego desde cubierto) y después fuego y movimiento.

func _score_near_ambush(w: SimWorld, u: Unit, s: Dictionary) -> void:
	var m: SquadMind = u.mind
	if m.option == SquadMind.Option.NEAR_AMBUSH:
		var id: int = int(m.data.get("enemy", -1))
		var e: Unit = w.get_unit(id)
		var elapsed: float = float(w.total_ticks - m.since_tick) * Config.TICK
		if e != null and e.alive and m.contacts.has(id) and elapsed < Config.NEAR_AMBUSH_MAX_SECONDS \
				and Vector2(m.contacts[id]["pos"]).distance_to(u.pos_m()) > Config.NEAR_AMBUSH_DONE_M and not u.path.is_empty():
			s[SquadMind.Option.NEAR_AMBUSH] = Config.NEAR_AMBUSH_SCORE
		return
	if not w.fired_upon_within(u, Config.NEAR_AMBUSH_FIRED_SECONDS) or u.order == Unit.Order.WITHDRAW or u.path.is_empty():
		return # solo la que va en marcha cae en una emboscada; la que defiende se queda en su puesto
	if m.option in [SquadMind.Option.BREAK_CONTACT, SquadMind.Option.RESCUE]:
		return
	var id: int = _nearest_contact_id(u)
	if id >= 0 and Vector2(m.contacts[id]["pos"]).distance_to(u.pos_m()) <= Config.NEAR_AMBUSH_M:
		m.data["near_enemy"] = id
		s[SquadMind.Option.NEAR_AMBUSH] = Config.NEAR_AMBUSH_SCORE


func _nearest_contact_id(u: Unit) -> int:
	var best: int = -1
	var best_d: float = INF
	for id: int in u.mind.contacts:
		var d: float = Vector2(u.mind.contacts[id]["pos"]).distance_to(u.pos_m())
		if d < best_d:
			best = id
			best_d = d
	return best


func _start_near_ambush(w: SimWorld, u: Unit) -> void:
	var m: SquadMind = u.mind
	var id: int = _nearest_contact_id(u)
	m.data["enemy"] = id
	m.hold = false
	_release_teams(u)
	for s: Soldier in u.soldiers:
		s.dive_until = 0 # nadie se queda tirado en la zona de muerte
	if id < 0:
		return
	var target: Vector2i = Vector2i((Vector2(m.contacts[id]["pos"]) / Config.CELL_SIZE).round())
	if autonomous_move(w, u, target, Vector2.ZERO, false):
		u.order = Unit.Order.ASSAULT # a la carrera y tirando


## --- Rescate ---
## Quieta y bajo fuego, con un herido tirado al descubierto: humo de mano entre el herido y la
## amenaza, el equipo A bate la amenaza y el médico (o un fusilero) va y lo arrastra a cubierto a
## DRAG_SPEED; ahí lo atienden.

func _score_rescue(w: SimWorld, u: Unit, s: Dictionary) -> void:
	var m: SquadMind = u.mind
	if m.option == SquadMind.Option.RESCUE:
		var t: Soldier = u.soldiers[int(m.data.get("wounded", 0))]
		var r: int = int(m.data.get("rescuer", -1))
		if t.state == Soldier.State.WOUNDED and r >= 0 and u.soldiers[r].drag_target >= 0:
			s[SquadMind.Option.RESCUE] = Config.RESCUE_SCORE + 1.0
		return
	if u.moving or not w.fired_upon_within(u, Config.RESCUE_FIRED_SECONDS):
		return
	if m.option not in [SquadMind.Option.FOLLOW, SquadMind.Option.CONTACT_DRILL]:
		return
	var threat: Vector2 = w.inf.threat_point(w, u)
	for t: Soldier in u.soldiers:
		if t.state == Soldier.State.WOUNDED and wounded_exposed(w, t, threat) and _rescuer(u, t) != null:
			m.rescue_index = t.index
			s[SquadMind.Option.RESCUE] = Config.RESCUE_SCORE
			return


## ¿El herido está a la vista y sin nada que lo proteja de la amenaza?
static func wounded_exposed(w: SimWorld, t: Soldier, threat: Vector2) -> bool:
	if InfantrySim.is_protected_from(w, t, threat):
		return false
	return w.analysis.los_m(threat, Config.INF_EYE_H, t.pos, Config.SOLDIER_CENTER_PRONE + InfantrySim.ground_offset(w, t.pos))


## El médico si puede; si no, el fusilero o proveedor más cercano que no esté clavado.
static func _rescuer(u: Unit, t: Soldier) -> Soldier:
	return InfantrySim.caregiver(u, t)


## Adónde arrastrarlo: el punto protegido más cercano a RESCUE_SEARCH_M; si no hay, 8 m hacia atrás.
func drag_spot(w: SimWorld, t: Soldier, threat: Vector2) -> Vector2:
	var best: Vector2 = Vector2(-1.0, -1.0)
	var best_d: float = INF
	var c0: Vector2i = MicroCover.cell_of(t.pos)
	var ri: int = ceili(Config.RESCUE_SEARCH_M / MicroCover.MICRO_M)
	var limit: float = float(w.height_field.size - 1) * Config.CELL_SIZE
	for dy: int in range(-ri, ri + 1):
		for dx: int in range(-ri, ri + 1):
			var p: Vector2 = MicroCover.center_m(c0 + Vector2i(dx, dy))
			var d: float = p.distance_to(t.pos)
			if d > Config.RESCUE_SEARCH_M or d >= best_d or p.x < 0.0 or p.y < 0.0 or p.x > limit or p.y > limit:
				continue
			if w.micro != null and MicroCover.protects(w.micro.type_at_m(p)):
				continue
			var ev: Dictionary = InfantrySim.evaluate_spot(w, p, threat)
			if bool(ev["protected"]):
				best = p
				best_d = d
	if best.x >= 0.0:
		return best
	var away: Vector2 = (t.pos - threat).normalized()
	var p: Vector2 = t.pos + away * 8.0
	return Vector2(clampf(p.x, 0.0, limit), clampf(p.y, 0.0, limit))


func _start_rescue(w: SimWorld, u: Unit) -> void:
	var m: SquadMind = u.mind
	var t: Soldier = u.soldiers[m.rescue_index]
	var threat: Vector2 = w.inf.threat_point(w, u)
	var r: Soldier = _rescuer(u, t)
	if r == null:
		return
	m.data["wounded"] = t.index
	m.data["rescuer"] = r.index
	r.care_target = -1
	r.drag_target = t.index
	t.dragged = true # nadie más lo atiende hasta que esté a cubierto
	for s: Soldier in u.soldiers:
		if s.care_target == t.index:
			s.care_target = -1
			s.care_time = 0.0
	r.drag_dest = drag_spot(w, t, threat)
	# Humo entre el herido y la amenaza, y fuego de cobertura del equipo A
	var d: float = t.pos.distance_to(threat)
	if d > 1.0:
		w.hand_smoke(u, t.pos + (threat - t.pos) / d * minf(Config.INF_SMOKE_DIST_M, d * 0.5))
	for s: Soldier in u.soldiers:
		if s.team == 0 and s.is_ok() and s != r:
			s.suppress_m = threat


## --- Equipos de fuego: avanzar por saltos ---
## En marcha con un contacto cerca: el equipo A queda como base de fuego (quieto, tirando o batiendo
## el contacto) mientras el B avanza BOUND_M con el ancla. Bajo fuego, saltos sucesivos: el ancla
## frena, B se cubre y A sube a su lugar. Sin fuego encima, alternados (más rápidos): el que estaba
## quieto salta y pasa adelante, y el otro queda de base.

func _score_bound(w: SimWorld, u: Unit, s: Dictionary) -> void:
	var m: SquadMind = u.mind
	if u.path.is_empty() or u.order not in [Unit.Order.MOVE, Unit.Order.HULLDOWN, Unit.Order.ATTACK]:
		return
	if m.option != SquadMind.Option.BOUND and m.option != SquadMind.Option.FOLLOW:
		return
	if _nearest_contact_m(u) <= Config.BOUND_CONTACT_M:
		s[SquadMind.Option.BOUND] = Config.BOUND_SCORE


func _start_bound(w: SimWorld, u: Unit) -> void:
	var m: SquadMind = u.mind
	m.data["phase"] = "B"
	m.data["start"] = u.pos_m()
	m.hold = false
	if w.fired_upon_within(u, Config.BOUND_SMOKE_FIRED_SECONDS) and u.smoke_charges > 0 and not m.data.has("smoked"):
		m.data["smoked"] = true
		if throw_smoke_toward(w, u, w.inf.threat_point(w, u)):
			w.radio(u, "humo, cruzamos")
	var target: Vector2 = _nearest_contact_pos(u)
	var mover: int = int(m.data.get("mover", 1))
	m.data["mover"] = mover
	for s: Soldier in u.soldiers:
		s.hold_pos = s.team != mover and s.is_ok()
		s.suppress_m = target if s.hold_pos else Vector2(-1.0, -1.0)


func _act_bound(w: SimWorld, u: Unit) -> void:
	var m: SquadMind = u.mind
	var rush: bool = w.fired_upon_within(u, Config.RUSH_FIRED_SECONDS)
	if rush and not m.rushing:
		# Empiezan las carreras: las parejas se turnan (una corre mientras la otra está tirada)
		for s: Soldier in u.soldiers:
			s.rush_until = 0
			s.down_until = w.total_ticks + (roundi(Config.RUSH_DOWN_MIN_SECONDS / Config.TICK) if (s.index / 2) % 2 == 1 else 0)
	m.rushing = rush
	if not m.data.has("phase"):
		_start_bound(w, u)
		return
	if str(m.data["phase"]) == "B":
		if u.pos_m().distance_to(m.data["start"]) >= Config.BOUND_M or u.path.is_empty():
			var mover: int = int(m.data.get("mover", 1))
			m.bound_alternate = not rush and not u.path.is_empty()
			if m.bound_alternate:
				if w.inf.lagging(u):
					return # el que salta todavía no llegó a su lugar
				m.data["mover"] = 1 - mover # saltos alternados: ahora salta el otro y pasa adelante
				_start_bound(w, u)
				return
			m.data["phase"] = "A" # saltos sucesivos: el que saltó frena, se cubre y el otro lo alcanza
			m.data["mover"] = 1
			m.hold = true
			for s: Soldier in u.soldiers:
				s.hold_pos = false
				s.suppress_m = _nearest_contact_pos(u) if s.team == mover else Vector2(-1.0, -1.0)
	elif not w.inf.lagging(u):
		_start_bound(w, u) # ya lo alcanzó: otro salto


func _release_teams(u: Unit) -> void:
	u.mind.rushing = false
	for s: Soldier in u.soldiers:
		s.hold_pos = false
		s.suppress_m = Vector2(-1.0, -1.0)


func _nearest_contact_pos(u: Unit) -> Vector2:
	var best: Vector2 = Vector2(-1.0, -1.0)
	var best_d: float = INF
	for id: int in u.mind.contacts:
		var p: Vector2 = u.mind.contacts[id]["pos"]
		var d: float = p.distance_to(u.pos_m())
		if d < best_d:
			best = p
			best_d = d
	return best


## --- Flanquear ---
## Un contacto al que otra escuadra propia ya le está tirando (base de fuego) y a esta no le tiran:
## va por la ruta cubierta a un punto FLANK_OFFSET_M al costado del contacto y se queda ahí.

func _score_flank(w: SimWorld, u: Unit, s: Dictionary) -> void:
	var m: SquadMind = u.mind
	if m.option == SquadMind.Option.FLANK:
		if not u.path.is_empty():
			s[SquadMind.Option.FLANK] = Config.FLANK_SCORE + 1.0
		return
	if m.option != SquadMind.Option.FOLLOW or u.path.is_empty():
		return # solo flanquea la que avanza; la que defiende se queda en su puesto
	if w.fired_upon_within(u, Config.FLANK_QUIET_SECONDS) or u.order in [Unit.Order.ASSAULT, Unit.Order.WITHDRAW]:
		return
	for id: int in m.contacts:
		if m.reacted.has(-1 - id) or _someone_flanking(w, u, id):
			continue
		var c: Vector2 = m.contacts[id]["pos"]
		if c.distance_to(u.pos_m()) > Config.FLANK_MAX_M:
			continue
		var base: Unit = _base_of_fire(w, u, c)
		if base == null:
			continue
		var cell: Vector2i = flank_cell(w, u, c, base.pos_m())
		if cell.x < 0:
			continue
		m.target_cell = cell
		m.flank_enemy = id
		s[SquadMind.Option.FLANK] = Config.FLANK_SCORE
		return


## Otra escuadra propia tirando hace poco a menos de FLANK_BASE_M del contacto.
func _base_of_fire(w: SimWorld, u: Unit, c: Vector2) -> Unit:
	for o: Unit in w.units:
		if o == u or not o.alive or o.side != u.side or not o.is_infantry():
			continue
		if o.pos_m().distance_to(c) <= Config.FLANK_BASE_M \
				and float(w.total_ticks - o.last_fire_tick) * Config.TICK < Config.FLANK_BASE_FIRED_SECONDS:
			return o
	return null


func _someone_flanking(w: SimWorld, u: Unit, enemy_id: int) -> bool:
	for o: Unit in w.units:
		if o != u and o.alive and o.side == u.side and o.mind != null \
				and o.mind.option == SquadMind.Option.FLANK and o.mind.flank_enemy == enemy_id:
			return true
	return false


## Celda transitable al costado del contacto c (perpendicular a la línea base de fuego -> contacto),
## del lado más cercano a la escuadra. (-1, -1) si no hay.
func flank_cell(w: SimWorld, u: Unit, c: Vector2, base: Vector2) -> Vector2i:
	var axis: Vector2 = (c - base).normalized()
	if axis.length() < 0.5:
		return Vector2i(-1, -1)
	var perp: Vector2 = Vector2(-axis.y, axis.x)
	var a: Vector2 = c + perp * Config.FLANK_OFFSET_M - axis * Config.FLANK_OFFSET_M * 0.3
	var b: Vector2 = c - perp * Config.FLANK_OFFSET_M - axis * Config.FLANK_OFFSET_M * 0.3
	var p: Vector2 = a if a.distance_to(u.pos_m()) <= b.distance_to(u.pos_m()) else b
	var n: int = w.height_field.size - 1
	var cell: Vector2i = Vector2i((p / Config.CELL_SIZE).round())
	cell = Vector2i(clampi(cell.x, 0, n), clampi(cell.y, 0, n))
	if not w.pathfinders[Unit.Kind.INFANTRY].is_walkable(cell):
		return Vector2i(-1, -1)
	return cell


## --- Reubicarse ---
## Quieta, bajo fuego y con la mitad o más al descubierto: busca a <= RELOCATE_RADIUS una celda
## tapada por el terreno o con cobertura y va por la ruta cubierta. Ya ubicada, se queda hasta que
## se calma.

func _score_relocate(w: SimWorld, u: Unit, s: Dictionary) -> void:
	var m: SquadMind = u.mind
	if m.option == SquadMind.Option.RELOCATE:
		if not u.path.is_empty() or w.fired_upon_within(u, Config.DRILL_CALM_SECONDS):
			s[SquadMind.Option.RELOCATE] = Config.RELOCATE_SCORE + 1.0
		return
	if u.moving or u.order == Unit.Order.ASSAULT or not w.fired_upon_within(u, Config.RELOCATE_FIRED_SECONDS):
		return
	if not (m.option == SquadMind.Option.FOLLOW and u.path.is_empty()) and m.option != SquadMind.Option.CONTACT_DRILL:
		return
	var exposed: float = exposed_fraction(u)
	if exposed < Config.RELOCATE_EXPOSED:
		return
	var best: Vector2i = relocate_cell(w, u)
	if best == u.cell():
		return
	m.target_cell = best
	s[SquadMind.Option.RELOCATE] = Config.RELOCATE_SCORE + exposed


## Fracción de soldados en condiciones que no están protegidos.
static func exposed_fraction(u: Unit) -> float:
	var n: int = 0
	var bad: int = 0
	for s: Soldier in u.soldiers:
		if s.is_ok():
			n += 1
			if not (s.has_cover and s.protected):
				bad += 1
	return float(bad) / float(n) if n > 0 else 0.0


## Mejor celda cercana contra la amenaza de la escuadra (la propia si ninguna es bastante mejor).
func relocate_cell(w: SimWorld, u: Unit) -> Vector2i:
	var threat_m: Vector2 = w.inf.threat_point(w, u)
	var threat: Vector2i = Vector2i((threat_m / Config.CELL_SIZE).round())
	threat = Vector2i(clampi(threat.x, 0, w.height_field.size - 1), clampi(threat.y, 0, w.height_field.size - 1))
	var pf: Pathfinder = w.pathfinders[Unit.Kind.INFANTRY]
	var origin: Vector2i = u.cell()
	var base: float = _position_value(w, origin, threat)
	var best: Vector2i = origin
	var best_score: float = base + Config.RELOCATE_MIN_GAIN
	var r: int = Config.RELOCATE_RADIUS
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			var c: Vector2i = origin + Vector2i(dx, dy)
			if dx * dx + dy * dy > r * r or c == origin or not pf.is_walkable(c):
				continue
			var score: float = _position_value(w, c, threat) - Vector2(dx, dy).length() / Config.HULLDOWN_DIST_DIV
			if score > best_score:
				best = c
				best_score = score
	return best


func _position_value(w: SimWorld, c: Vector2i, threat: Vector2i) -> float:
	var v: float = Config.RELOCATE_W_COVER * w.cover_at(c)
	if not w.analysis.los(threat, Config.INF_EYE_H, c, Config.INF_STAND_H):
		v += Config.RELOCATE_W_DEFILADE
	if w.micro != null and w.micro.any_near_m(Vector2(c) * Config.CELL_SIZE):
		v += Config.RELOCATE_W_MICRO
	return v


## --- Emboscada ---
## Quieta, sin ruta, sin haber tirado ni recibido fuego, con enemigos acercándose a menos de
## AMBUSH_WATCH_M: retiene el fuego hasta que el más cercano esté a AMBUSH_FIRE_M (o le tiren).

func _score_ambush(w: SimWorld, u: Unit, s: Dictionary) -> void:
	var m: SquadMind = u.mind
	if not u.path.is_empty() or u.order == Unit.Order.SUPPRESS:
		return
	if m.option != SquadMind.Option.AMBUSH and (m.option != SquadMind.Option.FOLLOW or u.roe == Unit.Roe.HOLD):
		return
	if w.fired_upon_within(u, Config.AMBUSH_QUIET_SECONDS if m.option != SquadMind.Option.AMBUSH else 1.0):
		return
	if m.option != SquadMind.Option.AMBUSH and float(w.total_ticks - u.last_fire_tick) * Config.TICK < Config.AMBUSH_QUIET_SECONDS:
		return
	var nearest: float = _nearest_contact_m(u)
	if nearest <= Config.AMBUSH_FIRE_M or nearest > Config.AMBUSH_WATCH_M:
		return
	s[SquadMind.Option.AMBUSH] = Config.AMBUSH_SCORE


func _nearest_contact_m(u: Unit) -> float:
	var best: float = INF
	for id: int in u.mind.contacts:
		best = minf(best, (u.mind.contacts[id]["pos"] as Vector2).distance_to(u.pos_m()))
	return best


## --- Romper el contacto ---
## Diezmada, con la moral baja o frenada mucho tiempo, y bajo fuego: humo hacia la amenaza y
## repliegue a la celda menos expuesta. Ya replegada y sin fuego un rato, lo deja (y no retoma
## la orden: se queda donde se replegó).

func _score_break(w: SimWorld, u: Unit, s: Dictionary) -> void:
	var m: SquadMind = u.mind
	if m.option == SquadMind.Option.BREAK_CONTACT:
		if not u.path.is_empty() or w.fired_upon_within(u, Config.BREAK_CALM_SECONDS):
			s[SquadMind.Option.BREAK_CONTACT] = Config.BREAK_SCORE
		return
	if u.order == Unit.Order.WITHDRAW or not w.fired_upon_within(u, Config.RELOCATE_FIRED_SECONDS):
		return
	if u.ok_count() <= Config.BREAK_MEN:
		s[SquadMind.Option.BREAK_CONTACT] = Config.BREAK_SCORE


## --- Drill de contacto ---
## En marcha (con ruta), si le tiran o ve a un enemigo nuevo cerca: alto, cobertura a
## DRILL_COVER_M, devolver el fuego; retoma cuando la supresión media queda por debajo de
## DRILL_CALM_SUPP durante DRILL_CALM_SECONDS. En asalto o retirada no frena.

func _score_drill(w: SimWorld, u: Unit, s: Dictionary) -> void:
	var m: SquadMind = u.mind
	if m.option == SquadMind.Option.CONTACT_DRILL:
		# Con orden de avanzar: reacción corta y sigue por fuego y movimiento, salvo que la hayan
		# diezmado (más de la mitad caída): ahí se queda a cubierto.
		var advancing: bool = not u.path.is_empty() and float(u.ok_count()) > float(u.max_hp()) * Config.DRILL_STAY_FRACTION
		if advancing and float(w.total_ticks - m.since_tick) * Config.TICK >= Config.DRILL_REACT_SECONDS:
			return
		if u.suppression >= Config.DRILL_CALM_SUPP or w.fired_upon_within(u, Config.DRILL_CALM_SECONDS):
			m.data["calm_since"] = w.total_ticks
		if advancing or float(w.total_ticks - int(m.data.get("calm_since", m.since_tick))) * Config.TICK < Config.DRILL_CALM_SECONDS:
			s[SquadMind.Option.CONTACT_DRILL] = Config.DRILL_SCORE
		return
	if u.path.is_empty() or u.order in [Unit.Order.ASSAULT, Unit.Order.WITHDRAW] or m.option == SquadMind.Option.BOUND:
		return # el asalto, la retirada y el avance por saltos ya son la respuesta al contacto
	if float(w.total_ticks - m.drill_end_tick) * Config.TICK < Config.DRILL_COOLDOWN_SECONDS:
		return # ya reaccionó hace poco: sigue avanzando
	if w.fired_upon_within(u, Config.DRILL_FIRED_SECONDS) or not _new_contacts(w, u).is_empty():
		s[SquadMind.Option.CONTACT_DRILL] = Config.DRILL_SCORE


## Contactos de la escuadra a menos de DRILL_SPOT_M que todavía no provocaron un drill.
func _new_contacts(_w: SimWorld, u: Unit) -> Array[int]:
	var out: Array[int] = []
	for id: int in u.mind.contacts:
		if not u.mind.reacted.has(id) and (u.mind.contacts[id]["pos"] as Vector2).distance_to(u.pos_m()) <= Config.DRILL_SPOT_M:
			out.append(id)
	return out


## Cambia de opción: guarda la orden al salir de FOLLOW, la retoma al volver y avisa por radio.
func switch_to(w: SimWorld, u: Unit, opt: int) -> void:
	var m: SquadMind = u.mind
	if opt == m.option:
		return
	if m.is_following():
		_save_intent(u)
	_exit(w, u, m.option)
	var was: int = m.option
	m.option = opt
	m.since_tick = w.total_ticks
	m.data = {"was": was}
	if opt == SquadMind.Option.FOLLOW:
		_restore_intent(w, u)
		if was not in [SquadMind.Option.CONTACT_DRILL, SquadMind.Option.AMBUSH]:
			w.radio(u, "retoma la orden") # tras un drill o una emboscada sigue sin avisar
	else:
		_enter(w, u, opt)
		w.radio(u, _announce(opt))
		var key: String = SquadMind.OPTION_NAMES[opt]
		w.decision_counts[key] = int(w.decision_counts.get(key, 0)) + 1


func _enter(w: SimWorld, u: Unit, opt: int) -> void:
	var m: SquadMind = u.mind
	m.hold = true # por defecto, una decisión propia frena la marcha
	match opt:
		SquadMind.Option.CONTACT_DRILL:
			m.cover_m = Config.DRILL_COVER_M
			m.data["calm_since"] = w.total_ticks
			for id: int in m.contacts:
				m.reacted[id] = true
		SquadMind.Option.RELOCATE:
			if not autonomous_move(w, u, m.target_cell, SimWorld.facing_to_threats(m.target_cell, w.threats_for(u.side))):
				m.hold = true
		SquadMind.Option.AMBUSH:
			m.hold = false
			m.data["roe"] = u.roe
			u.roe = Unit.Roe.HOLD
		SquadMind.Option.BOUND:
			m.hold = false
			for id: int in m.contacts:
				m.reacted[id] = true
			_start_bound(w, u)
		SquadMind.Option.FLANK:
			m.reacted[-1 - m.flank_enemy] = true # no vuelve a flanquear al mismo
			if not autonomous_move(w, u, m.target_cell):
				m.hold = true
		SquadMind.Option.RESCUE:
			_start_rescue(w, u)
		SquadMind.Option.NEAR_AMBUSH:
			_start_near_ambush(w, u)
		SquadMind.Option.BREAK_CONTACT:
			throw_smoke_toward(w, u, w.inf.threat_point(w, u))
			w.begin_autonomous()
			var ok: bool = w.order_withdraw(u.id)
			w.end_autonomous()
			m.rerouted = true
			m.hold = not ok


func _exit(w: SimWorld, u: Unit, opt: int) -> void:
	var m: SquadMind = u.mind
	m.hold = false
	m.cover_m = Config.SOLDIER_COVER_SEARCH_M
	if opt == SquadMind.Option.CONTACT_DRILL or opt == SquadMind.Option.NEAR_AMBUSH:
		m.drill_end_tick = w.total_ticks # tras reaccionar al contacto, un rato sin otro drill
	match opt:
		SquadMind.Option.AMBUSH:
			u.roe = int(m.data.get("roe", Unit.Roe.FREE))
			if _nearest_contact_m(u) <= Config.AMBUSH_FIRE_M or w.fired_upon_within(u, 1.0):
				w.radio(u, "¡fuego!")
		SquadMind.Option.BOUND:
			_release_teams(u)
		SquadMind.Option.RESCUE:
			_release_teams(u)
			for s: Soldier in u.soldiers:
				if s.drag_target >= 0:
					u.soldiers[s.drag_target].dragged = false
				s.drag_target = -1
		SquadMind.Option.FLANK:
			pass # desde el flanco retoma la orden: sigue hacia el objetivo
		SquadMind.Option.BREAK_CONTACT:
			m.saved = {} # replegada: no vuelve a meterse donde la estaban castigando
			u.path.clear()
			u.waypoints.clear()
			u.moving = false


## Lo que dice por radio al tomar una decisión.
func _announce(opt: int) -> String:
	match opt:
		SquadMind.Option.CONTACT_DRILL:
			return "¡contacto! a cubierto y fuego"
		SquadMind.Option.RELOCATE:
			return "nos movemos a mejor posición"
		SquadMind.Option.AMBUSH:
			return "emboscada, retengan el fuego"
		SquadMind.Option.BREAK_CONTACT:
			return "rompemos el contacto, humo y atrás"
		SquadMind.Option.BOUND:
			return "avanzamos por saltos"
		SquadMind.Option.FLANK:
			return "los fijan ustedes, nosotros flanqueamos"
		SquadMind.Option.RESCUE:
			return "¡herido al descubierto! humo, cobertura y lo sacamos"
		SquadMind.Option.NEAR_AMBUSH:
			return "¡emboscada! ¡al asalto!"
	return SquadMind.OPTION_NAMES[opt]


## Lo que hace la opción actual en este tick.
func act(w: SimWorld, u: Unit) -> void:
	match u.mind.option:
		SquadMind.Option.BOUND:
			_act_bound(w, u)


## --- Orden del jugador ---

func _save_intent(u: Unit) -> void:
	u.mind.saved = {
		"path": u.path.duplicate(),
		"waypoints": u.waypoints.duplicate(true),
		"order": u.order,
		"final_heading": u.final_heading,
		"reversing": u.reversing,
	}
	u.mind.rerouted = false


## Vuelve a la orden guardada. Si la opción no le tocó la ruta, sigue como estaba; si se la
## cambió, la rehace desde donde está pasando por los tramos que le faltaban.
func _restore_intent(w: SimWorld, u: Unit) -> void:
	var m: SquadMind = u.mind
	m.hold = false
	if m.saved.is_empty():
		return
	if m.rerouted:
		var wps: Array[Dictionary] = []
		for wp: Dictionary in m.saved["waypoints"]:
			wps.append(wp)
		w.reroute_through(u, wps)
		u.order = int(m.saved["order"])
		u.final_heading = m.saved["final_heading"]
		u.reversing = bool(m.saved["reversing"]) and u.moving
	m.saved = {}
	m.rerouted = false


## Una opción cambia la ruta de la escuadra (orden dada por la propia escuadra).
func autonomous_move(w: SimWorld, u: Unit, target: Vector2i, facing: Vector2 = Vector2.ZERO, covered: bool = true) -> bool:
	w.begin_autonomous()
	var ok: bool = w.order_move(u.id, target, facing, covered)
	w.end_autonomous()
	if ok:
		u.mind.rerouted = true
		u.mind.hold = false
	return ok
