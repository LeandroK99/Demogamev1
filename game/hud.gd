class_name Hud
extends CanvasLayer
## HUD: estado del turno, unidad seleccionada, disparos recibidos, ayuda de teclas y cartel final.

const PLAYER_SIDE: int = 0
const HELP: String = "Clic izq: seleccionar · Clic der: mover (arrastrar: orientación) · Ctrl+clic der: ruta directa · Shift+clic der: agregar tramo · Clic der sobre rojo: atacar\n" \
	+ "H: hull-down · V: vigilar hacia el cursor · M: misión del pelotón al cursor (Shift+M: cancelar) · F + clic der: disparar y replegarse · G + clic izq: humo · Doble clic: pelotón · J + clic der: avance por saltos · U + clic der: suprimir zona · K: condición del último tramo · T + clic der: asaltar · B: retirarse · X: ritmo · N: formación · Y: autonomía · P: evacuar heridos · Z: reglas de fuego · C: área de enganche hacia el cursor (Shift+C: quitar) · Espacio: ejecutar turno\n1/2/3: overlays · +/-: velocidad · Q/E: rotar · R: reiniciar · Shift+R: mapa nuevo · L: cambiar escenario (tanques / la loma)"
const ORDER_NAMES: Dictionary = {
	Unit.Order.NONE: "ninguna",
	Unit.Order.MOVE: "mover",
	Unit.Order.HULLDOWN: "hull-down",
	Unit.Order.HOLD: "mantener",
	Unit.Order.ATTACK: "atacar",
	Unit.Order.OVERWATCH: "vigilancia",
	Unit.Order.SCOOT: "disparar y replegarse",
	Unit.Order.ASSAULT: "asaltar",
	Unit.Order.WITHDRAW: "retirarse",
	Unit.Order.SUPPRESS: "suprimir",
}
const ASPECT_NAMES: Array[String] = ["el frente", "el flanco", "la cola"]
const RISK_NAMES: Array[String] = ["BAJO", "MEDIO", "ALTO"]
const PACE_NAMES: Dictionary = {
	Unit.Pace.NORMAL: "normal",
	Unit.Pace.FAST: "rápido",
	Unit.Pace.CAUTIOUS: "cauto",
	Unit.Pace.CRAWL: "reptando",
}

const FORMATION_NAMES: Dictionary = {
	Unit.Formation.WEDGE: "cuña",
	Unit.Formation.FILE: "fila india",
	Unit.Formation.LINE: "línea",
	Unit.Formation.ECHELON: "escalón",
}
const ROE_NAMES: Dictionary = {
	Unit.Roe.FREE: "fuego libre",
	Unit.Roe.RETURN_FIRE: "solo si le disparan",
	Unit.Roe.HOLD: "retener fuego",
}

var world: SimWorld
var turn_controller: TurnController
var input_controller: InputController
var map_seed: int = 0

var _status: Label = Label.new()
var _unit_info: Label = Label.new()
var _help: Label = Label.new()
var _banner: Label = Label.new()
var _radio: Label = Label.new()
const RADIO_LINES: int = 6


func setup(p_world: SimWorld, tc: TurnController, ic: InputController, p_seed: int) -> void:
	world = p_world
	turn_controller = tc
	input_controller = ic
	map_seed = p_seed
	_style(_status, 20)
	_status.position = Vector2(12.0, 8.0)
	add_child(_status)

	_style(_unit_info, 16)
	_unit_info.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_unit_info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_unit_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_unit_info.position = Vector2(-12.0, 8.0)
	add_child(_unit_info)

	_style(_help, 15)
	_help.text = HELP
	_help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.offset_bottom = -8.0
	add_child(_help)

	_style(_radio, 15)
	_radio.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_radio.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_radio.position = Vector2(12.0, -150.0)
	_radio.modulate = Color(0.75, 1.0, 0.75)
	add_child(_radio)

	_style(_banner, 52)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false
	add_child(_banner)


func _style(label: Label, size: int) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	var phase_text: String = "PLANIFICAR (Espacio: ejecutar)"
	if world.phase == SimWorld.Phase.EXECUTE:
		phase_text = "EJECUTANDO %d / %d s" % [world.tick_in_turn / 10, roundi(world.ticks_per_turn * Config.TICK)]
	var scen: String = "Tanques"
	if world.scenario == SimWorld.Scenario.LOMA:
		var holders: Dictionary = {0: "azul", 1: "rojo", SimWorld.DRAW: "en disputa", SimWorld.NO_WINNER: "nadie"}
		scen = "La loma (cresta: %s)" % holders.get(world.objective_holder(), "?")
	_status.text = "%s · Turno %d / %d · %s · ×%d\nAzules vivos: %d · Rojos vivos: %d · Semilla %d" % [
		scen, world.turn, Config.MAX_TURNS, phase_text, roundi(turn_controller.speed()),
		world.alive_count(0), world.alive_count(1), map_seed]
	_unit_info.text = _unit_text()
	_radio.text = radio_text(world, PLAYER_SIDE, RADIO_LINES)
	if world.game_over:
		_banner.visible = true
		var result: String = "EMPATE"
		if world.winner == PLAYER_SIDE:
			result = "VICTORIA"
		elif world.winner != SimWorld.DRAW:
			result = "DERROTA"
		_banner.text = "%s\nR: jugar de nuevo · Shift+R: mapa nuevo" % result


## Las últimas n líneas de radio del bando: "[m:ss] Escuadra 2: ¡contacto! ...".
static func radio_text(w: SimWorld, side: int, n: int) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for i: int in range(w.radio_log.size() - 1, -1, -1):
		var r: Dictionary = w.radio_log[i]
		if int(r["side"]) != side:
			continue
		var secs: int = roundi(float(r["tick"]) * Config.TICK)
		var u: Unit = w.get_unit(int(r["unit"]))
		lines.insert(0, "[%d:%02d] %s %d: %s" % [secs / 60, secs % 60, unit_name(u), u.id + 1, r["text"]])
		if lines.size() >= n:
			break
	if lines.is_empty():
		return ""
	return "Radio\n" + "\n".join(lines)


static func unit_name(u: Unit) -> String:
	return "Escuadra" if u.is_infantry() else "Tanque"


static func gate_text(gate: Dictionary) -> String:
	match str(gate.get("type", "")):
		"time":
			return "a los %d s" % roundi(float(gate["seconds"]))
		"contact":
			return "contacto"
		"signal":
			return "la señal %s" % gate["name"]
		"unit":
			return "al tanque %d" % (int(gate["unit"]) + 1)
		"all_signals":
			return "a que llegue la otra sección"
	return "?"



## Escuadra: cuántos soldados en condiciones hay de pie, agachados y cuerpo a tierra, y cuántos cubiertos.
static func soldiers_text(u: Unit) -> String:
	var counts: Array[int] = [0, 0, 0]
	var covered: int = 0
	var pinned: int = 0
	for s: Soldier in u.soldiers:
		if not s.is_ok():
			continue
		counts[s.posture] += 1
		if s.has_cover and s.protected and not s.moving:
			covered += 1
		if s.suppression >= Config.PINNED:
			pinned += 1
	var out: String = "De pie %d · agachados %d · cuerpo a tierra %d · cubiertos %d" % [counts[0], counts[1], counts[2], covered]
	if pinned > 0:
		out += " · clavados %d" % pinned
	return out


## " (2 heridos, 1 se desangra: 45 s)" si la escuadra tiene heridos.
static func wounded_text(u: Unit) -> String:
	var n: int = 0
	var bleeding: int = 0
	var worst: float = INF
	for s: Soldier in u.soldiers:
		if s.state == Soldier.State.WOUNDED:
			n += 1
			if s.is_bleeding():
				bleeding += 1
				worst = minf(worst, s.bleed_left)
	if n == 0:
		return ""
	var out: String = " (%d herido%s" % [n, "" if n == 1 else "s"]
	if bleeding > 0:
		out += ", %d se desangra%s: %d s" % [bleeding, "" if bleeding == 1 else "n", roundi(worst)]
	return out + ")"


## Rumbo de la grilla como punto cardinal (y crece hacia el sur).
static func compass(dir: Vector2) -> String:
	const NAMES: Array[String] = ["este", "sureste", "sur", "suroeste", "oeste", "noroeste", "norte", "noreste"]
	var idx: int = posmod(roundi(dir.angle() / (PI / 4.0)), 8)
	return NAMES[idx]


func _unit_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	var sel: Unit = input_controller.primary_unit()
	if input_controller.pending_mode == "scoot":
		lines.append("Clic derecho: posición de tiro (Esc cancela)")
		lines.append("")
	elif input_controller.pending_mode == "suppress":
		lines.append("Clic derecho: zona a suprimir (Esc cancela)")
		lines.append("")
	elif input_controller.pending_mode == "bound":
		lines.append("Clic derecho: objetivo del avance por saltos (Esc cancela)")
		lines.append("")
	elif input_controller.pending_mode == "assault":
		lines.append("Clic derecho: objetivo del asalto (Esc cancela)")
		lines.append("")
	elif input_controller.pending_mode == "smoke":
		lines.append("Clic izquierdo: dónde tirar el humo (Esc cancela)")
		lines.append("")
	if sel != null:
		var plt: Platoon = world.platoon_of(sel.id)
		if input_controller.selected_platoon() != null:
			lines.append("Pelotón completo (%d tanques)" % input_controller.selected_ids.size())
		lines.append("%s %d · sección %s" % [unit_name(sel), sel.id + 1, Platoon.section_letter(plt.section_of(sel.id) if plt != null else -1)])
		lines.append("%s: %d / %d%s" % ["Hombres" if sel.is_infantry() else "Vida", sel.hp, sel.max_hp(), wounded_text(sel)])
		lines.append("Recarga: %s" % ("lista" if sel.reload_left <= 0.0 else "%.1f s" % sel.reload_left))
		var order_text: String = ORDER_NAMES.get(sel.order, "?")
		if sel.is_infantry() and sel.order == Unit.Order.HULLDOWN:
			order_text = "tomar posición"
		if sel.order == Unit.Order.ATTACK and sel.attack_target >= 0:
			order_text += " (rojo %d)" % (sel.attack_target - Config.UNITS_PER_SIDE + 1)
		lines.append("Orden: %s" % order_text)
		lines.append("Mira al %s" % compass(sel.heading))
		if sel.is_infantry():
			lines.append(soldiers_text(sel))
			var adapted: String = ""
			if sel.shape != sel.formation:
				adapted = " (ahora %s)" % FORMATION_NAMES.get(sel.shape, "?")
			lines.append("Formación: %s%s%s" % [FORMATION_NAMES.get(sel.formation, "?"), adapted, ", abierta" if sel.spread > 1.0 else ""])
			if sel.mind != null:
				var tech: String = SquadMind.TECHNIQUE_NAMES[sel.mind.technique]
				if sel.mind.technique == SquadMind.Technique.BOUNDING:
					tech += " alternados" if sel.mind.bound_alternate else " sucesivos"
				lines.append("Avance: %s" % tech)
			var pl: PlatoonLeader = world.missions[sel.side]
			if pl != null:
				var role: String = ""
				if sel.id == pl.base_id:
					role = ", base de fuego"
				elif pl.maneuver.has(sel.id):
					role = ", maniobra"
				lines.append("Misión del pelotón: %s%s" % [PlatoonLeader.STAGE_NAMES[pl.stage], role])
			var state: String = ""
			if sel.broken:
				state = " · QUEBRADA"
			lines.append("Moral: %d%s" % [roundi(sel.morale), state])
			var m: SquadMind = sel.mind
			lines.append("Autonomía: %s · jefe %s" % [SquadMind.AUTONOMY_NAMES[m.autonomy], SquadMind.QUALITY_NAMES[m.quality]])
			if m.is_disorganized(world.total_ticks):
				lines.append("Decide: SIN JEFE, desorganizada")
			elif not m.is_following():
				lines.append("Decide: %s" % m.option_name())
		var supp_state: String = ""
		if world.is_pinned(sel):
			supp_state = " · inmovilizada"
		elif world.is_suppressed(sel):
			supp_state = " · abotonado" if not sel.is_infantry() else " · suprimida"
		lines.append("Supresión: %d%s" % [roundi(sel.suppression), supp_state])
		var roe_text: String = ROE_NAMES.get(sel.roe, "?")
		if sel.fire_arc_dir != Vector2.ZERO:
			roe_text += ", arco al %s" % compass(sel.fire_arc_dir)
		if sel.max_engage_m < Config.MAX_RANGE:
			roe_text += ", hasta %d m" % roundi(sel.max_engage_m)
		lines.append("ROE: %s" % roe_text)
		lines.append("Ritmo: %s" % PACE_NAMES.get(SimWorld.effective_pace(sel), "?"))
		for i: int in sel.waypoints.size():
			var wp: Dictionary = sel.waypoints[i]
			var parts: PackedStringArray = PackedStringArray()
			if wp.has("gate") and not bool(wp.get("gate_open", false)):
				parts.append("espera %s" % gate_text(wp["gate"]))
			if str(wp.get("signal", "")) != "":
				parts.append("al llegar emite la señal %s" % wp["signal"])
			if not parts.is_empty():
				lines.append("Tramo %d: %s" % [i + 1, ", ".join(parts)])
		if sel.waiting:
			lines.append("ESPERANDO")
		var risk: Dictionary = input_controller.risk_for(sel)
		if not risk.is_empty():
			lines.append("")
			lines.append("Ruta: %d s, %d s a la vista de %d amenaza(s)" % [
				roundi(risk["total_s"]), roundi(risk["exposed_s"]), int(risk["threats_seeing"])])
			var aspect: String = ""
			if int(risk["worst_aspect"]) >= 0:
				aspect = ", muestra %s" % ASPECT_NAMES[int(risk["worst_aspect"])]
			lines.append("Impactos esperados: %.1f%s" % [float(risk["expected_hits"]), aspect])
			lines.append("RIESGO %s" % RISK_NAMES[int(risk["level"])])
		if sel.is_infantry():
			lines.append("Antitanque: %d / %d" % [sel.at_charges, Config.INF_AT_CHARGES])
			lines.append("Munición: %d %%%s" % [roundi(sel.ammo_fraction() * 100.0), " (fuego rápido)" if InfantrySim.rapid_fire(sel) else ""])
		else:
			lines.append("Humo: %d / %d" % [sel.smoke_charges, Config.SMOKE_CHARGES])
		lines.append("")
	lines.append("Disparos recibidos")
	for u: Unit in world.units:
		if u.side == PLAYER_SIDE:
			lines.append("%s %d: %d%s" % [unit_name(u), u.id + 1, u.shots_received, "" if u.alive else " (destruido)"])
	return "\n".join(lines)
