class_name UnitView
extends Node3D
## Vista de un tanque: caja de casco + torreta, y anillo de selección.

const COLOR_BLUE: Color = Color(0.2, 0.4, 1.0)
const COLOR_RED: Color = Color(1.0, 0.2, 0.15)

var unit: Unit
var height_field: HeightField
var selected: bool = false:
	set(value):
		selected = value
		if _ring != null:
			_ring.visible = value

var _ring: MeshInstance3D


func setup(p_unit: Unit, hf: HeightField) -> void:
	unit = p_unit
	height_field = hf
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = COLOR_BLUE if unit.side == 0 else COLOR_RED

	var hull_mesh: BoxMesh = BoxMesh.new()
	hull_mesh.size = Vector3(3.5, 2.2, 7.0)
	hull_mesh.material = mat
	var hull: MeshInstance3D = MeshInstance3D.new()
	hull.mesh = hull_mesh
	hull.position.y = 1.1
	add_child(hull)

	var turret_mesh: BoxMesh = BoxMesh.new()
	turret_mesh.size = Vector3(2.2, 0.9, 3.0)
	turret_mesh.material = mat
	var turret: MeshInstance3D = MeshInstance3D.new()
	turret.mesh = turret_mesh
	turret.position = Vector3(0.0, 2.65, -0.4)
	add_child(turret)

	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = 5.0
	ring_mesh.outer_radius = 5.8
	var ring_mat: StandardMaterial3D = StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(1.0, 0.9, 0.2)
	ring_mesh.material = ring_mat
	_ring = MeshInstance3D.new()
	_ring.mesh = ring_mesh
	_ring.position.y = 0.4
	_ring.visible = selected
	add_child(_ring)
	sync_from_sim()


## Copia posición y orientación desde la simulación.
func sync_from_sim() -> void:
	var p: Vector2 = unit.pos
	position = Vector3(p.x * Config.CELL_SIZE, height_field.height_at(p), p.y * Config.CELL_SIZE)
	rotation.y = atan2(-unit.heading.x, -unit.heading.y)
