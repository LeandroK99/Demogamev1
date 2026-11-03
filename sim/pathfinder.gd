class_name Pathfinder
extends RefCounted
## A* sobre la grilla: ruta cubierta (costo por exposición y pendiente) y ruta directa (solo pendiente).

var astar: AStarGrid2D = AStarGrid2D.new() # ruta cubierta: pesa la exposición
var astar_direct: AStarGrid2D = AStarGrid2D.new() # ruta directa: solo pendiente
var height_field: HeightField
var exposure_k: float = Config.EXPOSURE_WEIGHT_K # se puede cambiar en tests
var max_slope: float = Config.PATH_MAX_SLOPE # metros; más empinado es intransitable
var extra_cost: PackedFloat32Array = PackedFloat32Array() # costo extra por celda (vacío = ninguno)
var _exposure: PackedFloat32Array = PackedFloat32Array()


func _init(hf: HeightField, p_max_slope: float = Config.PATH_MAX_SLOPE) -> void:
	height_field = hf
	max_slope = p_max_slope
	for a: AStarGrid2D in [astar, astar_direct]:
		a.region = Rect2i(0, 0, hf.size, hf.size)
		a.cell_size = Vector2(1.0, 1.0)
		a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		a.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		a.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		a.update()
	for y: int in hf.size:
		for x: int in hf.size:
			var c: Vector2i = Vector2i(x, y)
			if hf.slope_at(c) > max_slope:
				astar.set_point_solid(c, true)
				astar_direct.set_point_solid(c, true)
			astar_direct.set_point_weight_scale(c, 1.0 + _slope_penalty(c))
	var zero: PackedFloat32Array = PackedFloat32Array()
	zero.resize(hf.size * hf.size)
	zero.fill(0.0)
	set_exposure(zero)


## weight_scale = 1 + K * exposición + penalidad por pendiente.
func set_exposure(exposure: PackedFloat32Array) -> void:
	_exposure = exposure
	var hf: HeightField = height_field
	var has_extra: bool = not extra_cost.is_empty()
	for y: int in hf.size:
		for x: int in hf.size:
			var c: Vector2i = Vector2i(x, y)
			var extra: float = extra_cost[y * hf.size + x] if has_extra else 0.0
			astar.set_point_weight_scale(c, 1.0 + exposure_k * exposure[y * hf.size + x] + _slope_penalty(c) + extra)


## Costo extra por celda (por ejemplo, bosque para el tanque). Rehace los pesos de las dos rutas.
func set_extra_cost(costs: PackedFloat32Array) -> void:
	extra_cost = costs
	var hf: HeightField = height_field
	for y: int in hf.size:
		for x: int in hf.size:
			var c: Vector2i = Vector2i(x, y)
			astar_direct.set_point_weight_scale(c, 1.0 + _slope_penalty(c) + costs[y * hf.size + x])
	set_exposure(_exposure)


func _slope_penalty(c: Vector2i) -> float:
	return clampf(height_field.slope_at(c) / max_slope, 0.0, 1.0) * Config.PATH_SLOPE_COST


func is_walkable(c: Vector2i) -> bool:
	return height_field.in_bounds(c) and not astar.is_point_solid(c)


## Ruta de celdas desde from hasta to (incluye ambas). Vacía si no hay ruta.
## covered = false: ruta directa (la más corta, ignora la exposición; sigue esquivando
## las pendientes intransitables).
func find_path(from: Vector2i, to: Vector2i, covered: bool = true) -> Array[Vector2i]:
	if not is_walkable(from) or not is_walkable(to):
		return []
	return (astar if covered else astar_direct).get_id_path(from, to)
