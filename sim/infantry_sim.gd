class_name InfantrySim
extends RefCounted
## Los soldados de las escuadras: movimiento en formación (y, en las fases siguientes, cobertura,
## visión, fuego y supresión por soldado). Es de SimWorld y recibe el mundo en cada llamada
## (no guarda una referencia, para no hacer un ciclo).


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
