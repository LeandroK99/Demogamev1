class_name TerrainAnalysis
extends RefCounted
## Línea de visión, mapas de exposición y búsqueda de posiciones hull-down.

var height_field: HeightField
## Nubes de humo activas: {center: Vector2 (celdas), radius: float (celdas), top_h: float (m, absoluto)}.
## Las mantiene SimWorld; acá solo se usan para cortar la línea de visión.
var smoke: Array[Dictionary] = []
var cover: CoverMap = null # bosques que cortan la línea de visión (null = sin cobertura)
var micro: MicroCover = null # microcobertura a 1 m para los soldados (null = sin)


func _init(hf: HeightField) -> void:
	height_field = hf


## ¿Hay línea de visión entre un punto a from_h metros sobre from_cell
## y otro a to_h metros sobre to_cell? Muestrea la recta cada LOS_STEP celdas
## contra el terreno y después la corta con las nubes de humo.
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
	var forest_types: PackedByteArray = cover.types if cover != null else PackedByteArray()
	var forest_left: float = Config.FOREST_LOS_CELLS
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
		var ray_h: float = ha + dh * t
		if ground > ray_h - Config.LOS_EPSILON:
			return false
		if not forest_types.is_empty() and ray_h < ground + Config.FOREST_TREE_H \
				and forest_types[int(y + 0.5) * size + int(x + 0.5)] == CoverMap.Type.FOREST:
			forest_left -= Config.LOS_STEP
			if forest_left < 0.0:
				return false
		t += t_step
	if smoke.is_empty():
		return true
	return not _smoke_blocks(Vector2(ax, ay), Vector2(dx, dy), ha, dh)


## Línea de visión en metros (soldados): de a_h metros sobre el terreno en a hasta b_h sobre b.
## Terreno y bosque cada LOS_STEP celdas, como los(); además la microcobertura cada MICRO_LOS_STEP
## metros, solo a MICRO_NEAR_M de cada extremo (donde importa: la roca del blanco o del tirador),
## sin contar la micro-celda propia de cada uno. Después el humo.
func los_m(a: Vector2, a_h: float, b: Vector2, b_h: float) -> bool:
	var hf: HeightField = height_field
	var inv_cell: float = 1.0 / Config.CELL_SIZE
	var ha: float = hf.height_at(a * inv_cell) + a_h
	var hb: float = hf.height_at(b * inv_cell) + b_h
	var d: Vector2 = b - a
	var dist: float = d.length()
	if dist < 0.01:
		return true
	var step_m: float = Config.LOS_STEP * Config.CELL_SIZE
	var t_step: float = step_m / dist
	var t: float = t_step
	var forest_left: float = Config.FOREST_LOS_CELLS * Config.CELL_SIZE
	while t < 1.0:
		var p: Vector2 = a + d * t
		var ground: float = hf.height_at(p * inv_cell)
		var ray_h: float = ha + (hb - ha) * t
		if ground > ray_h - Config.LOS_EPSILON:
			return false
		if cover != null and ray_h < ground + Config.FOREST_TREE_H \
				and cover.is_forest(Vector2i(roundi(p.x * inv_cell), roundi(p.y * inv_cell))):
			forest_left -= step_m
			if forest_left < 0.0:
				return false
		t += t_step
	if micro != null:
		var near: float = minf(Config.MICRO_NEAR_M, dist * 0.5)
		for from_end: int in 2:
			var s: float = Config.MICRO_SELF_M
			while s <= near:
				var tt: float = s / dist if from_end == 0 else 1.0 - s / dist
				var p: Vector2 = a + d * tt
				var o: float = micro.height_at_m(p)
				if o > 0.0 and ha + (hb - ha) * tt < hf.height_at(p * inv_cell) + o:
					return false
				s += Config.MICRO_LOS_STEP
	if smoke.is_empty():
		return true
	return not _smoke_blocks(a * inv_cell, d * inv_cell, ha, hb - ha)


## ¿La recta A + t·D (t en 0..1, altura ha + dh·t) atraviesa alguna nube por debajo de su tope?
## Intersección analítica con cada círculo: no agrega muestras al bucle del terreno.
func _smoke_blocks(a: Vector2, d: Vector2, ha: float, dh: float) -> bool:
	var dd: float = d.dot(d)
	for cloud: Dictionary in smoke:
		var c: Vector2 = cloud["center"]
		var r: float = cloud["radius"]
		var f: Vector2 = a - c
		var t0: float = 0.0
		var t1: float = 1.0
		if dd < 0.000001:
			if f.length_squared() > r * r:
				continue
		else:
			var b: float = f.dot(d)
			var disc: float = b * b - dd * (f.dot(f) - r * r)
			if disc < 0.0:
				continue
			var sq: float = sqrt(disc)
			t0 = maxf(0.0, (-b - sq) / dd)
			t1 = minf(1.0, (-b + sq) / dd)
			if t0 > t1:
				continue
		# La altura de la recta es lineal: su mínimo en el tramo está en un extremo
		if minf(ha + dh * t0, ha + dh * t1) < float(cloud["top_h"]):
			return true
	return false


## Distancia en metros entre dos celdas.
static func dist_m(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a).distance_to(Vector2(b)) * Config.CELL_SIZE


## Exposición por celda: fracción de amenazas (a <= MAX_RANGE) que ven el casco.
## 0 = cubierta; 1 = vista por todas.
func exposure_map(threats: Array[Vector2i], target_h: float = Config.HULL_H) -> PackedFloat32Array:
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
				if dist_m(th, c) <= Config.MAX_RANGE and los(th, Config.EYE_H, c, target_h):
					seen += 1
			result[y * size + x] = float(seen) * inv
	print("exposure_map: %d ms (%d amenazas)" % [Time.get_ticks_msec() - start_ms, threats.size()])
	return result


## Candidatos hull-down alrededor de origin, ordenados por puntaje descendente.
## Cada uno: {cell, score, can_fire, hull_hidden}.
## eye_h, hull_h y center_h: alturas de la unidad que busca posición (por defecto, un tanque).
func hulldown_candidates(origin: Vector2i, threats: Array[Vector2i], radius: int,
		eye_h: float = Config.EYE_H, hull_h: float = Config.HULL_H, center_h: float = Config.CENTER_H,
		cover_weight: float = 0.0) -> Array[Dictionary]:
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
				if not can_fire and dist_m(c, th) <= Config.MAX_RANGE and los(c, eye_h, th, center_h):
					can_fire = true
				if hull_hidden and los(th, Config.EYE_H, c, hull_h):
					hull_hidden = false
			var score: float = Config.HULLDOWN_W_HIDDEN * float(hull_hidden) \
				+ Config.HULLDOWN_W_FIRE * float(can_fire) \
				- Vector2(origin).distance_to(Vector2(c)) / Config.HULLDOWN_DIST_DIV
			if cover != null and cover_weight > 0.0:
				score += cover_weight * cover.cover_at(c)
			out.append({"cell": c, "score": score, "can_fire": can_fire, "hull_hidden": hull_hidden})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	return out
