class_name TurnController
extends Node
## Ciclo WeGo en la vista: Espacio ejecuta el turno, +/- cambian la velocidad.
## También aplica la niebla a las vistas.

const PLAYER_SIDE: int = 0
const SPEEDS: Array[float] = [1.0, 2.0, 4.0]

signal plan_started

var world: SimWorld
var unit_views: Array[UnitView] = []
var fx: CombatFx
var _speed_index: int = 0
var _accum: float = 0.0


func setup(p_world: SimWorld, views: Array[UnitView], p_fx: CombatFx) -> void:
	world = p_world
	unit_views = views
	fx = p_fx
	_apply_fog(1.0)


func speed() -> float:
	return SPEEDS[_speed_index]


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_SPACE:
			if world.phase == SimWorld.Phase.PLAN:
				world.begin_execute()
				_accum = 0.0
		KEY_EQUAL, KEY_KP_ADD:
			_speed_index = mini(_speed_index + 1, SPEEDS.size() - 1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_speed_index = maxi(_speed_index - 1, 0)


func _process(delta: float) -> void:
	if world.phase == SimWorld.Phase.EXECUTE and not world.game_over:
		_accum += delta * speed()
		while _accum >= Config.TICK:
			_accum -= Config.TICK
			for v: UnitView in unit_views:
				v.prev_pos = v.unit.pos
			world.step()
			if world.phase == SimWorld.Phase.PLAN or world.game_over:
				_accum = 0.0
				for v: UnitView in unit_views:
					v.prev_pos = v.unit.pos
				plan_started.emit()
				break
	for e: Dictionary in world.shot_events:
		var shooter: Unit = world.units[int(e["shooter"])]
		if shooter.side == PLAYER_SIDE or world.visible_enemies[PLAYER_SIDE].has(shooter.id):
			fx.add_shot(shooter, world.units[int(e["target"])], bool(e["hit"]), int(e.get("aspect", SimWorld.Aspect.FRONT)))
	world.shot_events.clear()
	var alpha: float = clampf(_accum / Config.TICK, 0.0, 1.0) if world.phase == SimWorld.Phase.EXECUTE else 1.0
	_apply_fog(alpha)


## Propios: siempre visibles. Enemigos: visibles, fantasma en su última posición, u ocultos.
func _apply_fog(alpha: float) -> void:
	var vis: Dictionary = world.visible_enemies[PLAYER_SIDE]
	var known: Dictionary = world.known_enemies[PLAYER_SIDE]
	for v: UnitView in unit_views:
		var u: Unit = v.unit
		if u.side == PLAYER_SIDE:
			v.sync_from_sim(alpha)
			v.set_display(UnitView.Display.NORMAL if u.alive else UnitView.Display.WRECK)
		elif not u.alive:
			v.sync_from_sim(1.0)
			v.set_display(UnitView.Display.WRECK if known.has(u.id) else UnitView.Display.HIDDEN)
		elif vis.has(u.id):
			v.sync_from_sim(alpha)
			v.set_display(UnitView.Display.NORMAL)
		elif known.has(u.id):
			v.show_ghost_at(known[u.id]["cell"])
		else:
			v.set_display(UnitView.Display.HIDDEN)
