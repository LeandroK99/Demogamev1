class_name Hud
extends CanvasLayer
## HUD: estado del turno, unidad seleccionada, disparos recibidos, ayuda de teclas y cartel final.

const PLAYER_SIDE: int = 0
const HELP: String = "Clic izq: seleccionar · Clic der: mover (arrastrar: orientación) · Ctrl+clic der: ruta directa · Shift+clic der: agregar tramo · Clic der sobre rojo: atacar\n" \
	+ "H: hull-down · V: vigilar hacia el cursor · F + clic der: disparar y replegarse · G + clic izq: humo · Doble clic: pelotón · J + clic der: avance por saltos · K: condición del último tramo · T + clic der: asaltar · B: retirarse · X: ritmo · Z: reglas de fuego · C: área de enganche hacia el cursor (Shift+C: quitar) · Espacio: ejecutar turno\n1/2/3: overlays · +/-: velocidad · Q/E: rotar · R: reiniciar · Shift+R: mapa nuevo"
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
}
const ASPECT_NAMES: Array[String] = ["el frente", "el flanco", "la cola"]
const RISK_NAMES: Array[String] = ["BAJO", "MEDIO", "ALTO"]
const PACE_NAMES: Dictionary = {
	Unit.Pace.NORMAL: "normal",
	Unit.Pace.FAST: "rápido",
	Unit.Pace.CAUTIOUS: "cauto",
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
		phase_text = "EJECUTANDO %d / %d s" % [world.tick_in_turn / 10, roundi(Config.TURN_SECONDS)]
	_status.text = "Turno %d / %d · %s · ×%d\nAzules vivos: %d · Rojos vivos: %d · Semilla %d" % [
		world.turn, Config.MAX_TURNS, phase_text, roundi(turn_controller.speed()),
		world.alive_count(0), world.alive_count(1), map_seed]
	_unit_info.text = _unit_text()
	if world.game_over:
		_banner.visible = true
		var result: String = "EMPATE"
		if world.winner == PLAYER_SIDE:
			result = "VICTORIA"
		elif world.winner != SimWorld.DRAW:
			result = "DERROTA"
		_banner.text = "%s\nR: jugar de nuevo · Shift+R: mapa nuevo" % result


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
		lines.append("Tanque %d · sección %s" % [sel.id + 1, Platoon.section_letter(plt.section_of(sel.id) if plt != null else -1)])
		lines.append("%s: %d / %d" % ["Hombres" if sel.is_infantry() else "Vida", sel.hp, sel.max_hp()])
		lines.append("Recarga: %s" % ("lista" if sel.reload_left <= 0.0 else "%.1f s" % sel.reload_left))
		var order_text: String = ORDER_NAMES.get(sel.order, "?")
		if sel.is_infantry() and sel.order == Unit.Order.HULLDOWN:
			order_text = "tomar posición"
		if sel.order == Unit.Order.ATTACK and sel.attack_target >= 0:
			order_text += " (rojo %d)" % (sel.attack_target - Config.UNITS_PER_SIDE + 1)
		lines.append("Orden: %s" % order_text)
		lines.append("Mira al %s" % compass(sel.heading))
		if sel.is_infantry():
			lines.append("Postura: %s" % ("cuerpo a tierra" if sel.prone else "de pie"))
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
		lines.append("Humo: %d / %d" % [sel.smoke_charges, Config.SMOKE_CHARGES])
		lines.append("")
	lines.append("Disparos recibidos")
	for u: Unit in world.units:
		if u.side == PLAYER_SIDE:
			lines.append("Tanque %d: %d%s" % [u.id + 1, u.shots_received, "" if u.alive else " (destruido)"])
	return "\n".join(lines)
