extends SceneTree
## Banco IA contra IA en La loma (no es un test): el azul avanza hacia la cresta con autonomía alta
## y el rojo defiende con su comandante. Imprime ganador, bajas y decisiones por semilla y el total.
## godot --headless --path . --script res://tests/harness_loma.gd -- [semillas] [turnos] [mixta|peloton|pueblo]
## pueblo: lo mismo en El pueblo (la plaza es el objetivo).
## peloton: el azul recibe una sola misión (tomar la cresta) y su jefe de pelotón maniobra solo.
## mixta: las tres escuadras azules con autonomía estricta, normal y alta (para compararlas); imprime
## en qué turno llegó cada una a la cresta.
func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var seeds: int = int(args[0]) if args.size() > 0 else 20
	var max_turns: int = int(args[1]) if args.size() > 1 else Config.MAX_TURNS
	var mixed: bool = args.size() > 2 and args[2] == "mixta"
	var platoon: bool = args.size() > 2 and args[2] == "peloton"
	var scen: int = SimWorld.Scenario.PUEBLO if args.size() > 2 and args[2] == "pueblo" else SimWorld.Scenario.LOMA
	var reached_sum: Array[int] = [0, 0, 0]
	var wins: Array[int] = [0, 0, 0] # azul, rojo, empate
	var decisions: Dictionary = {}
	var men_left: Array[int] = [0, 0]
	for k: int in seeds:
		var w: SimWorld = SimWorld.new(1000 + k, null, true, scen)
		var blues: Array[Unit] = []
		for u: Unit in w.units:
			if u.side == 0 and u.mind != null:
				u.mind.autonomy = blues.size() % 3 if mixed else SquadMind.Autonomy.HIGH
				blues.append(u)
		var reached: Array[int] = [0, 0, 0]
		var obj: Vector2 = Vector2(w.objective_cell())
		if platoon:
			w.order_mission(0, w.objective_cell())
		while not w.game_over and w.turn <= max_turns:
			if not platoon:
				_blue_orders(w)
			w.begin_execute()
			while w.phase == SimWorld.Phase.EXECUTE and not w.game_over:
				w.step()
			if platoon and w.missions[0] != null:
				var pl: PlatoonLeader = w.missions[0]
				var at: Array[String] = []
				for u: Unit in pl.squads(w):
					at.append("%d:%.0f%s" % [u.id, u.pos.distance_to(obj), "" if u.path.is_empty() else "→"])
				print("  turno %d: %s  %s" % [w.turn, PlatoonLeader.STAGE_NAMES[pl.stage], " ".join(at)])
			for b: int in blues.size():
				if reached[b] == 0 and blues[b].alive and blues[b].pos.distance_to(obj) <= w.objective_radius():
					reached[b] = w.turn
		if mixed:
			print("  llegó a la cresta (turno, 0 = no): estricta %d · normal %d · alta %d" % [reached[0], reached[1], reached[2]])
			for b: int in 3:
				reached_sum[b] += 1 if reached[b] > 0 else 0
			if w.turn > max_turns:
				break
		var win: int = w.winner if w.game_over else w.objective_holder()
		var slot: int = 2
		if win == 0:
			slot = 0
		elif win == 1:
			slot = 1
		wins[slot] += 1
		var men: Array[int] = [0, 0]
		for u: Unit in w.units:
			if u.alive and u.is_infantry():
				men[u.side] += u.ok_count()
		men_left[0] += men[0]
		men_left[1] += men[1]
		for key: String in w.decision_counts:
			decisions[key] = int(decisions.get(key, 0)) + int(w.decision_counts[key])
		print("semilla %d: %s  turno %d  hombres azul %d rojo %d" % [1000 + k, ["azul", "rojo", "empate"][slot], w.turn, men[0], men[1]])
	print("TOTAL azul %d · rojo %d · empate %d · hombres promedio azul %.1f rojo %.1f" % [wins[0], wins[1], wins[2],
		men_left[0] / float(seeds), men_left[1] / float(seeds)])
	print("decisiones: %s" % str(decisions))
	if mixed:
		print("llegaron a la cresta: estricta %d · normal %d · alta %d (de %d)" % [reached_sum[0], reached_sum[1], reached_sum[2], seeds])
	quit()


## En el pueblo: una casa con rojos conocidos a CLEAR_NEAR_M o menos, sin limpiar -> limpiarla.
const CLEAR_NEAR_M: float = 70.0


func _clear_known_house(w: SimWorld, u: Unit) -> bool:
	if u.ok_count() < 4:
		return false # diezmada: no se mete en una casa
	var best: int = -1
	var best_d: float = CLEAR_NEAR_M
	for id: int in w.known_enemies[0]:
		var e: Unit = w.units[id]
		if not e.alive or not e.is_infantry() or e.surrendered or e.ok_count() == 0:
			continue
		var at: Vector2 = Vector2(w.known_enemies[0][id]["cell"]) * Config.CELL_SIZE
		var h: int = CqbSim.house_near(w.buildings, at)
		if h < 0 or int(w.cleared_houses.get(h, -1)) == 0:
			continue
		var d: float = w.buildings.rect_m(h).get_center().distance_to(u.pos_m())
		if d < best_d:
			best_d = d
			best = h
	return best >= 0 and w.order_clear(u.id, w.buildings.rect_m(best).get_center())


## El azul: cada escuadra sin ruta va hacia la cresta (al costado del objetivo según su número); el tanque cubre.
func _blue_orders(w: SimWorld) -> void:
	var obj: Vector2i = w.objective_cell()
	var i: int = 0
	for u: Unit in w.units:
		if u.side != 0 or not u.alive:
			continue
		if u.is_infantry():
			# Los últimos turnos: nada de casas, todos a la plaza (el que la ocupa al final gana)
			var late: bool = w.turn >= Config.MAX_TURNS - 2
			if late and w.buildings != null:
				if not u.clear.is_empty():
					w.cqb.abort_clear(w, u, "")
				# A la plaza corriendo y sin improvisar (el jugador haría lo mismo con Y y X)
				w.set_autonomy(u.id, SquadMind.Autonomy.STRICT)
				w.set_pace(u.id, Unit.Pace.FAST)
			if w.buildings != null and not late and u.clear.is_empty() and _clear_known_house(w, u):
				i += 1
				continue
			# En el pueblo la plaza es chica: las escuadras van más juntas, y si quedaron lejos de la plaza
			# haciendo otra cosa (cortar contacto, cubrirse) se las vuelve a mandar.
			var town: bool = w.buildings != null
			var spread: int = 2 if town else 6
			var far: bool = town and u.pos.distance_to(Vector2(obj)) > w.objective_radius() - 1.0 \
					and (u.order != Unit.Order.MOVE or late) and not u.broken
			if (u.path.is_empty() or far) and u.clear.is_empty():
				w.order_move(u.id, w._nearest_walkable(obj + Vector2i((i - 1) * spread, 0), Unit.Kind.INFANTRY))
			i += 1
