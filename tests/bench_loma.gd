extends SceneTree
## Rendimiento de La loma con soldados (no es un test): 4 turnos con la IA roja.
## godot --headless --path . --script res://tests/bench_loma.gd [-- pueblo]
## pueblo: en El pueblo, con el azul yendo a la plaza (casas, cuartos y reflejos en juego).
## El peor tick es el fin de turno (la IA planifica y recalcula la exposición).
func _initialize() -> void:
	var town: bool = OS.get_cmdline_user_args().has("pueblo")
	var w: SimWorld = SimWorld.new(1337, null, true, SimWorld.Scenario.PUEBLO if town else SimWorld.Scenario.LOMA)
	var worst: int = 0
	var total: int = 0
	var n: int = 0
	var exec_total: int = 0
	for t: int in 4:
		if town:
			for u: Unit in w.units:
				if u.side == 0 and u.alive and u.is_infantry() and u.path.is_empty():
					w.order_move(u.id, w._nearest_walkable(w.objective_cell(), Unit.Kind.INFANTRY))
		w.begin_execute()
		while w.phase == SimWorld.Phase.EXECUTE and not w.game_over:
			var t0: int = Time.get_ticks_usec()
			w.step()
			var dt: int = Time.get_ticks_usec() - t0
			worst = maxi(worst, dt)
			total += dt
			n += 1
			if w.phase == SimWorld.Phase.EXECUTE:
				exec_total += dt # sin el tick de fin de turno (la IA planifica una vez por turno)
	print("ticks %d  medio %.2f ms  (sin fin de turno %.2f ms)  peor %.2f ms  turno %d" % [n, total / float(n) / 1000.0,
		exec_total / float(maxi(1, n - 4)) / 1000.0, worst / 1000.0, w.turn])
	quit()
