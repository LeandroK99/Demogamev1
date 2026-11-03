class_name CoverView
extends Node3D
## Vista de la cobertura fina: conos verdes para el bosque, cajas bajas para los muros
## y discos oscuros para los pozos (todo por código, con MultiMesh).

const COLOR_TREE: Color = Color(0.16, 0.36, 0.14)
const COLOR_WALL: Color = Color(0.55, 0.52, 0.47)
const COLOR_PIT: Color = Color(0.2, 0.16, 0.12)


func setup(cm: CoverMap, hf: HeightField) -> void:
	var trees: Array[Vector3] = []
	var walls: Array[Vector3] = []
	var pits: Array[Vector3] = []
	for y: int in cm.size:
		for x: int in cm.size:
			var c: Vector2i = Vector2i(x, y)
			var p: Vector3 = hf.cell_to_world(c)
			match cm.type_at(c):
				CoverMap.Type.FOREST:
					trees.append(p)
				CoverMap.Type.WALL:
					walls.append(p)
				CoverMap.Type.PIT:
					pits.append(p)
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 2.2
	cone.height = Config.FOREST_TREE_H
	var wall: BoxMesh = BoxMesh.new()
	wall.size = Vector3(Config.CELL_SIZE, 1.0, 1.0)
	var pit: CylinderMesh = CylinderMesh.new()
	pit.top_radius = 1.6
	pit.bottom_radius = 1.6
	pit.height = 0.15
	_add(cone, COLOR_TREE, trees, Config.FOREST_TREE_H * 0.5)
	_add(wall, COLOR_WALL, walls, 0.5)
	_add(pit, COLOR_PIT, pits, 0.05)


func _add(mesh: PrimitiveMesh, color: Color, points: Array[Vector3], lift: float) -> void:
	if points.is_empty():
		return
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = points.size()
	for i: int in points.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, points[i] + Vector3.UP * lift))
	var inst: MultiMeshInstance3D = MultiMeshInstance3D.new()
	inst.multimesh = mm
	add_child(inst)
