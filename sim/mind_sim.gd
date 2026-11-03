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
		return
	if m.halted_since < 0:
		m.halted_since = w.total_ticks
		return
	if m.autonomy < SquadMind.Autonomy.NORMAL or u.smoke_charges <= 0:
		return
	if float(w.total_ticks - m.halted_since) * Config.TICK < Config.INF_SMOKE_SUPPRESSED_SECONDS:
		return
	if throw_smoke_toward(w, u, w.inf.threat_point(w, u)):
		w.radio(u, "humo, ¡nos tienen clavados!")
	m.halted_since = w.total_ticks # la próxima, otros 15 s después


## Granada de humo de mano hacia threat (a INF_SMOKE_DIST_M, o a mitad de camino si está más cerca).
func throw_smoke_toward(w: SimWorld, u: Unit, threat: Vector2) -> bool:
	var from: Vector2 = u.pos_m()
	var d: float = from.distance_to(threat)
	if d < 0.01:
		return false
	return w.hand_smoke(u, from + (threat - from) / d * minf(Config.INF_SMOKE_DIST_M, d * 0.5))


## Ticks entre decisiones.
func think_interval(_u: Unit) -> int:
	return Config.MIND_THINK_TICKS


## Puntúa las opciones permitidas y cambia si corresponde.
func think(w: SimWorld, u: Unit) -> void:
	var m: SquadMind = u.mind
	var all: Dictionary = score_options(w, u)
	var p_scores: Dictionary = {}
	for opt: int in all:
		if SquadMind.allowed(m.autonomy, opt):
			p_scores[opt] = all[opt]
	m.scores = p_scores
	var next: int = SquadMind.choose(m.option, m.since_tick, p_scores, w.total_ticks)
	if next != m.option:
		switch_to(w, u, next)


## Puntaje de cada opción disponible ahora (las que no figuran no se pueden elegir).
func score_options(w: SimWorld, u: Unit) -> Dictionary:
	var s: Dictionary = {SquadMind.Option.FOLLOW: Config.MIND_FOLLOW_SCORE}
	_score_drill(w, u, s)
	return s


## --- Drill de contacto ---
## En marcha (con ruta), si le tiran o ve a un enemigo nuevo cerca: alto, cobertura a
## DRILL_COVER_M, devolver el fuego; retoma cuando la supresión media queda por debajo de
## DRILL_CALM_SUPP durante DRILL_CALM_SECONDS. En asalto o retirada no frena.

func _score_drill(w: SimWorld, u: Unit, s: Dictionary) -> void:
	var m: SquadMind = u.mind
	if m.option == SquadMind.Option.CONTACT_DRILL:
		if u.suppression >= Config.DRILL_CALM_SUPP or w.fired_upon_within(u, Config.DRILL_CALM_SECONDS):
			m.data["calm_since"] = w.total_ticks
		if float(w.total_ticks - int(m.data.get("calm_since", m.since_tick))) * Config.TICK < Config.DRILL_CALM_SECONDS:
			s[SquadMind.Option.CONTACT_DRILL] = Config.DRILL_SCORE
		return
	if u.path.is_empty() or u.order in [Unit.Order.ASSAULT, Unit.Order.WITHDRAW]:
		return
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
	m.option = opt
	m.since_tick = w.total_ticks
	m.data = {}
	if opt == SquadMind.Option.FOLLOW:
		_restore_intent(w, u)
		w.radio(u, "retoma la orden")
	else:
		_enter(w, u, opt)
		w.radio(u, _announce(opt))


func _enter(w: SimWorld, u: Unit, opt: int) -> void:
	var m: SquadMind = u.mind
	m.hold = true # por defecto, una decisión propia frena la marcha
	match opt:
		SquadMind.Option.CONTACT_DRILL:
			m.cover_m = Config.DRILL_COVER_M
			m.data["calm_since"] = w.total_ticks
			for id: int in m.contacts:
				m.reacted[id] = true


func _exit(_w: SimWorld, u: Unit, _opt: int) -> void:
	u.mind.hold = false
	u.mind.cover_m = Config.SOLDIER_COVER_SEARCH_M


## Lo que dice por radio al tomar una decisión.
func _announce(opt: int) -> String:
	match opt:
		SquadMind.Option.CONTACT_DRILL:
			return "¡contacto! a cubierto y fuego"
	return SquadMind.OPTION_NAMES[opt]


## Lo que hace la opción actual en este tick.
func act(_w: SimWorld, _u: Unit) -> void:
	pass


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
