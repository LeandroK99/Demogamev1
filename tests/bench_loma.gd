extends SceneTree
## Rendimiento de La loma con soldados (no es un test): 4 turnos con la IA roja.
## godot --headless --path . --script res://tests/bench_loma.gd
## El peor tick es el fin de turno (la IA planifica y recalcula la exposición).
func _initialize() -> void:
	var w: SimWorld = SimWorld.new(1337, null, true, SimWorld.Scenario.LOMA)
	var worst: int = 0
	var total: int = 0
	var n: int = 0
	for t: int in 4:
		w.begin_execute()
		while w.phase == SimWorld.Phase.EXECUTE and not w.game_over:
			var t0: int = Time.get_ticks_usec()
			w.step()
			var dt: int = Time.get_ticks_usec() - t0
			worst = maxi(worst, dt)
			total += dt
			n += 1
	print("ticks %d  medio %.2f ms  peor %.2f ms  turno %d" % [n, total / float(n) / 1000.0, worst / 1000.0, w.turn])
	quit()
