class_name SimWorld
extends RefCounted
## Estado completo de la simulación. Avanza en ticks fijos de Config.TICK.

var height_field: HeightField
var analysis: TerrainAnalysis
var pathfinder: Pathfinder
var units: Array[Unit] = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var turn: int = 1
var tick_in_turn: int = 0

# Exposición por bando (índice = side); vacía = sin calcular
var _exposure: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
var _pathfinder_side: int = -1 # bando cuya exposición está cargada en el pathfinder


## Si hf es null se genera el terreno procedural con la semilla.
func _init(sim_seed: int = Config.SEED, hf: HeightField = null) -> void:
	rng.seed = sim_seed
	if hf == null:
		hf = HeightField.new()
		hf.generate(sim_seed)
	height_field = hf
	analysis = TerrainAnalysis.new(hf)
	pathfinder = Pathfinder.new(hf)
	_deploy()


## Azules en el borde sur (y alto), rojos en el norte, separados DEPLOY_SPACING celdas.
func _deploy() -> void:
	var n: int = height_field.size
	var first_x: int = n / 2 - (Config.UNITS_PER_SIDE - 1) * Config.DEPLOY_SPACING / 2
	for side: int in 2:
		var y: int = n - 1 - Config.DEPLOY_EDGE_MARGIN if side == 0 else Config.DEPLOY_EDGE_MARGIN
		for i: int in Config.UNITS_PER_SIDE:
			var x: int = first_x + i * Config.DEPLOY_SPACING
			units.append(Unit.new(units.size(), side, Vector2(x, y)))


func get_unit(unit_id: int) -> Unit:
	if unit_id < 0 or unit_id >= units.size():
		return null
	return units[unit_id]


## Amenazas para un bando. Provisorio hasta la fase 4 (niebla):
## usa la posición real de los enemigos vivos.
func threats_for(side: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for u: Unit in units:
		if u.alive and u.side != side:
			out.append(u.cell())
	return out


## Exposición del bando (se calcula la primera vez que se pide).
func exposure_for(side: int) -> PackedFloat32Array:
	if _exposure[side].is_empty():
		_exposure[side] = analysis.exposure_map(threats_for(side))
	return _exposure[side]


## Fuerza a recalcular la exposición de ambos bandos.
func invalidate_exposure() -> void:
	_exposure = [PackedFloat32Array(), PackedFloat32Array()]
	_pathfinder_side = -1


## Calcula la ruta más cubierta para el bando de la unidad. Devuelve false si no hay ruta.
func order_move(unit_id: int, target_cell: Vector2i) -> bool:
	var u: Unit = get_unit(unit_id)
	if u == null or not u.alive:
		return false
	if _pathfinder_side != u.side:
		pathfinder.set_exposure(exposure_for(u.side))
		_pathfinder_side = u.side
	var path: Array[Vector2i] = pathfinder.find_path(u.cell(), target_cell)
	if path.is_empty():
		return false
	path.remove_at(0) # la celda actual
	u.path = path
	u.order = Unit.Order.MOVE
	u.moving = not path.is_empty()
	return true


## Avanza un tick.
func step() -> void:
	for u: Unit in units:
		if u.alive and not u.path.is_empty():
			_advance(u, Config.TICK)
	tick_in_turn += 1


func speed_at(c: Vector2i) -> float:
	var t: float = clampf(height_field.slope_at(c) / Config.PATH_MAX_SLOPE, 0.0, 1.0)
	return Config.TANK_SPEED * lerpf(1.0, Config.SLOPE_SPEED_PENALTY, t)


func _advance(u: Unit, dt: float) -> void:
	var budget_m: float = speed_at(u.cell()) * dt
	while budget_m > 0.0 and not u.path.is_empty():
		var target: Vector2 = Vector2(u.path[0])
		var delta: Vector2 = target - u.pos
		var d_m: float = delta.length() * Config.CELL_SIZE
		if d_m > 0.0001:
			u.heading = delta.normalized()
		if d_m <= budget_m:
			u.pos = target
			budget_m -= d_m
			u.path.remove_at(0)
		else:
			u.pos += delta.normalized() * (budget_m / Config.CELL_SIZE)
			budget_m = 0.0
	u.moving = not u.path.is_empty()
	if not u.moving and u.order == Unit.Order.MOVE:
		u.order = Unit.Order.NONE
