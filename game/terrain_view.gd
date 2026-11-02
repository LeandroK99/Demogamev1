class_name TerrainView
extends Node3D
## Malla del terreno generada desde el HeightField: un vértice por celda.

const COLOR_LOW: Color = Color(0.13, 0.27, 0.11) # verde oscuro
const COLOR_HIGH: Color = Color(0.72, 0.58, 0.32) # ocre

var height_field: HeightField
var _mesh: ArrayMesh = ArrayMesh.new()
var _arrays: Array = []
var _base_colors: PackedColorArray = PackedColorArray()
var _material: StandardMaterial3D = StandardMaterial3D.new()


func setup(hf: HeightField) -> void:
	height_field = hf
	var n: int = hf.size
	var cs: float = Config.CELL_SIZE
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	vertices.resize(n * n)
	normals.resize(n * n)
	_base_colors.resize(n * n)

	for y: int in n:
		for x: int in n:
			var c: Vector2i = Vector2i(x, y)
			var i: int = y * n + x
			vertices[i] = hf.cell_to_world(c)
			# Normal por diferencias centrales
			var hl: float = hf.height_at_cell(c + Vector2i(-1, 0))
			var hr: float = hf.height_at_cell(c + Vector2i(1, 0))
			var hu: float = hf.height_at_cell(c + Vector2i(0, -1))
			var hd: float = hf.height_at_cell(c + Vector2i(0, 1))
			normals[i] = Vector3(hl - hr, 2.0 * cs, hu - hd).normalized()
			var t: float = clampf(hf.heights[i] / Config.MAX_HEIGHT, 0.0, 1.0)
			_base_colors[i] = COLOR_LOW.lerp(COLOR_HIGH, t)

	# Dos triángulos por cuadro, en sentido horario visto desde arriba
	for y: int in n - 1:
		for x: int in n - 1:
			var i00: int = y * n + x
			var i10: int = i00 + 1
			var i01: int = i00 + n
			var i11: int = i01 + 1
			indices.append_array([i00, i10, i01, i10, i11, i01])

	_arrays.resize(Mesh.ARRAY_MAX)
	_arrays[Mesh.ARRAY_VERTEX] = vertices
	_arrays[Mesh.ARRAY_NORMAL] = normals
	_arrays[Mesh.ARRAY_INDEX] = indices

	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 1.0

	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = _material
	add_child(mi)
	_apply_colors(_base_colors)


## Reemplaza los colores de vértice (uno por celda) para mostrar un overlay.
func set_overlay_colors(colors: PackedColorArray) -> void:
	if colors.size() != _base_colors.size():
		push_error("set_overlay_colors: se esperaban %d colores" % _base_colors.size())
		return
	_apply_colors(colors)


func clear_overlay() -> void:
	_apply_colors(_base_colors)


func _apply_colors(colors: PackedColorArray) -> void:
	_arrays[Mesh.ARRAY_COLOR] = colors
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays)


## Intersección rayo–terreno hecha a mano. Devuelve Vector3 o null si no toca el mapa.
func raycast(origin: Vector3, dir: Vector3) -> Variant:
	var d: Vector3 = dir.normalized()
	var step: float = Config.CELL_SIZE * 0.5
	var max_dist: float = 3000.0
	var prev_t: float = 0.0
	var t: float = step
	while t < max_dist:
		var p: Vector3 = origin + d * t
		if p.y <= _terrain_y(p):
			# Bisección entre el último punto sobre el terreno y este
			var lo: float = prev_t
			var hi: float = t
			for _i: int in 12:
				var mid: float = (lo + hi) * 0.5
				var pm: Vector3 = origin + d * mid
				if pm.y <= _terrain_y(pm):
					hi = mid
				else:
					lo = mid
			var hit: Vector3 = origin + d * hi
			return hit if _inside_map(hit) else null
		prev_t = t
		t += step
	return null


func _terrain_y(p: Vector3) -> float:
	return height_field.height_at(Vector2(p.x, p.z) / Config.CELL_SIZE)


func _inside_map(p: Vector3) -> bool:
	var limit: float = (height_field.size - 1) * Config.CELL_SIZE
	return p.x >= 0.0 and p.z >= 0.0 and p.x <= limit and p.z <= limit
