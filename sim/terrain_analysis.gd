class_name TerrainAnalysis
extends RefCounted
## Línea de visión, mapas de exposición y búsqueda de posiciones hull-down.

var height_field: HeightField


func _init(hf: HeightField) -> void:
	height_field = hf


## ¿Hay línea de visión entre un punto a from_h metros sobre from_cell
## y otro a to_h metros sobre to_cell? Muestrea la recta cada LOS_STEP celdas.
func los(from_cell: Vector2i, from_h: float, to_cell: Vector2i, to_h: float) -> bool:
	var hf: HeightField = height_field
	var size: int = hf.size
	var hs: PackedFloat32Array = hf.heights
	var ax: float = float(from_cell.x)
	var ay: float = float(from_cell.y)
	var dx: float = float(to_cell.x) - ax
	var dy: float = float(to_cell.y) - ay
	var dist: float = sqrt(dx * dx + dy * dy)
	var ha: float = hf.height_at_cell(from_cell) + from_h
	var dh: float = hf.height_at_cell(to_cell) + to_h - ha
	var t_step: float = Config.LOS_STEP / maxf(dist, 0.0001)
	var t: float = t_step
	while t < 1.0:
		# Bilineal en línea (es el bucle caliente)
		var x: float = ax + dx * t
		var y: float = ay + dy * t
		var x0: int = mini(int(x), size - 2)
		var y0: int = mini(int(y), size - 2)
		var tx: float = x - float(x0)
		var ty: float = y - float(y0)
		var i: int = y0 * size + x0
		var h0: float = hs[i] + (hs[i + 1] - hs[i]) * tx
		var h1: float = hs[i + size] + (hs[i + size + 1] - hs[i + size]) * tx
		var ground: float = h0 + (h1 - h0) * ty
		if ground > ha + dh * t - Config.LOS_EPSILON:
			return false
		t += t_step
	return true


## Distancia en metros entre dos celdas.
static func dist_m(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a).distance_to(Vector2(b)) * Config.CELL_SIZE


## Exposición por celda: fracción de amenazas (a <= MAX_RANGE) que ven el casco.
## 0 = cubierta; 1 = vista por todas.
func exposure_map(threats: Array[Vector2i]) -> PackedFloat32Array:
	var start_ms: int = Time.get_ticks_msec()
	var size: int = height_field.size
	var result: PackedFloat32Array = PackedFloat32Array()
	result.resize(size * size)
	result.fill(0.0)
	if threats.is_empty():
		return result
	var inv: float = 1.0 / float(threats.size())
	for y: int in size:
		for x: int in size:
			var c: Vector2i = Vector2i(x, y)
			var seen: int = 0
			for th: Vector2i in threats:
				if dist_m(th, c) <= Config.MAX_RANGE and los(th, Config.EYE_H, c, Config.HULL_H):
					seen += 1
			result[y * size + x] = float(seen) * inv
	print("exposure_map: %d ms (%d amenazas)" % [Time.get_ticks_msec() - start_ms, threats.size()])
	return result


## Candidatos hull-down alrededor de origin, ordenados por puntaje descendente.
## Cada uno: {cell, score, can_fire, hull_hidden}.
func hulldown_candidates(origin: Vector2i, threats: Array[Vector2i], radius: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var hf: HeightField = height_field
	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var c: Vector2i = origin + Vector2i(dx, dy)
			if not hf.in_bounds(c) or hf.slope_at(c) >= Config.HULLDOWN_MAX_SLOPE:
				continue
			var can_fire: bool = false
			var hull_hidden: bool = true
			for th: Vector2i in threats:
				if not can_fire and dist_m(c, th) <= Config.MAX_RANGE and los(c, Config.EYE_H, th, Config.CENTER_H):
					can_fire = true
				if hull_hidden and los(th, Config.EYE_H, c, Config.HULL_H):
					hull_hidden = false
			var score: float = Config.HULLDOWN_W_HIDDEN * float(hull_hidden) \
				+ Config.HULLDOWN_W_FIRE * float(can_fire) \
				- Vector2(origin).distance_to(Vector2(c)) / Config.HULLDOWN_DIST_DIV
			out.append({"cell": c, "score": score, "can_fire": can_fire, "hull_hidden": hull_hidden})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	return out
