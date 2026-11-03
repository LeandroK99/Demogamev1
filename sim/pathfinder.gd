class_name Pathfinder
extends RefCounted
## A* sobre la grilla con costo por exposición y pendiente.

var astar: AStarGrid2D = AStarGrid2D.new()
var height_field: HeightField
var exposure_k: float = Config.EXPOSURE_WEIGHT_K # se puede cambiar en tests


func _init(hf: HeightField) -> void:
	height_field = hf
	astar.region = Rect2i(0, 0, hf.size, hf.size)
	astar.cell_size = Vector2(1.0, 1.0)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y: int in hf.size:
		for x: int in hf.size:
			var c: Vector2i = Vector2i(x, y)
			if hf.slope_at(c) > Config.PATH_MAX_SLOPE:
				astar.set_point_solid(c, true)
	var zero: PackedFloat32Array = PackedFloat32Array()
	zero.resize(hf.size * hf.size)
	zero.fill(0.0)
	set_exposure(zero)


## weight_scale = 1 + K * exposición + penalidad por pendiente.
func set_exposure(exposure: PackedFloat32Array) -> void:
	var hf: HeightField = height_field
	for y: int in hf.size:
		for x: int in hf.size:
			var c: Vector2i = Vector2i(x, y)
			var slope_pen: float = clampf(hf.slope_at(c) / Config.PATH_MAX_SLOPE, 0.0, 1.0) * Config.PATH_SLOPE_COST
			astar.set_point_weight_scale(c, 1.0 + exposure_k * exposure[y * hf.size + x] + slope_pen)


func is_walkable(c: Vector2i) -> bool:
	return height_field.in_bounds(c) and not astar.is_point_solid(c)


## Ruta de celdas desde from hasta to (incluye ambas). Vacía si no hay ruta.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not is_walkable(from) or not is_walkable(to):
		return []
	return astar.get_id_path(from, to)
