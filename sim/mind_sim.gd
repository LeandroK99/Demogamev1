class_name MindSim
extends RefCounted
## La autonomía de las escuadras: cada una piensa cada tanto (puntúa sus opciones y elige con
## histéresis, ver SquadMind.choose) y, en cada tick, ejecuta la opción elegida. Las decisiones
## que la apartan de la orden del jugador se avisan por radio (SimWorld.radio). Al volver a FOLLOW
## retoma la orden guardada. Es de SimWorld y recibe el mundo en cada llamada.


## Un tick: las escuadras a las que les toca piensan; todas ejecutan su opción.
func update(w: SimWorld) -> void:
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
			think(w, u)
		act(w, u)


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
func score_options(_w: SimWorld, _u: Unit) -> Dictionary:
	return {SquadMind.Option.FOLLOW: Config.MIND_FOLLOW_SCORE}


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
		w.radio(u, m.option_name())


func _enter(_w: SimWorld, u: Unit, _opt: int) -> void:
	u.mind.hold = true # por defecto, una decisión propia frena la marcha


func _exit(_w: SimWorld, u: Unit, _opt: int) -> void:
	u.mind.hold = false


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
