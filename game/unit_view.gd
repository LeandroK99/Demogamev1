class_name UnitView
extends Node3D
## Vista de una unidad: tanque (caja de casco + torreta) o escuadra (caja baja y ancha con
## el número de hombres encima), y anillo de selección.
## Modos de niebla: normal, fantasma (última posición conocida), oculto, restos.

enum Display { NORMAL, GHOST, HIDDEN, WRECK }

const COLOR_BLUE: Color = Color(0.2, 0.4, 1.0)
const COLOR_RED: Color = Color(1.0, 0.2, 0.15)

var unit: Unit
var height_field: HeightField
var selected: bool = false:
	set(value):
		selected = value
		if _ring != null:
			_ring.visible = value

var prev_pos: Vector2 = Vector2.ZERO # posición en el tick anterior (para interpolar)
var _ring: MeshInstance3D
var _hull: MeshInstance3D
var _turret: MeshInstance3D
var _label: Label3D # hombres de la escuadra (solo infantería)
var _mat_normal: StandardMaterial3D = StandardMaterial3D.new()
var _mat_ghost: StandardMaterial3D = StandardMaterial3D.new()
var _mat_wreck: StandardMaterial3D = StandardMaterial3D.new()


func setup(p_unit: Unit, hf: HeightField) -> void:
	unit = p_unit
	height_field = hf
	prev_pos = unit.pos
	var color: Color = COLOR_BLUE if unit.side == 0 else COLOR_RED
	_mat_normal.albedo_color = color
	_mat_ghost.albedo_color = Color(color, 0.3)
	_mat_ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_ghost.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_wreck.albedo_color = Color(0.12, 0.11, 0.1)
	var mat: StandardMaterial3D = _mat_normal

	var inf: bool = unit.is_infantry()
	var hull_mesh: BoxMesh = BoxMesh.new()
	hull_mesh.size = Vector3(6.0, 0.8, 4.0) if inf else Vector3(3.5, 2.2, 7.0)
	hull_mesh.material = mat
	_hull = MeshInstance3D.new()
	_hull.mesh = hull_mesh
	_hull.position.y = hull_mesh.size.y * 0.5
	add_child(_hull)
	if inf:
		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.font_size = 48
		_label.outline_size = 12
		_label.modulate = color.lightened(0.5)
		_label.position.y = 4.0
		add_child(_label)

	var turret_mesh: BoxMesh = BoxMesh.new()
	turret_mesh.size = Vector3(1.0, 0.5, 1.0) if inf else Vector3(2.2, 0.9, 3.0)
	turret_mesh.material = mat
	_turret = MeshInstance3D.new()
	_turret.mesh = turret_mesh
	_turret.position = Vector3(0.0, 1.05, -1.4) if inf else Vector3(0.0, 2.65, -0.4)
	add_child(_turret)

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


## Copia posición y orientación desde la simulación (alpha: 0..1 entre el tick anterior y el actual).
func sync_from_sim(alpha: float = 1.0) -> void:
	_place(prev_pos.lerp(unit.pos, alpha))
	rotation.y = atan2(-unit.heading.x, -unit.heading.y)
	if _label != null:
		var mark: String = ""
		if unit.broken:
			mark = " !"
		elif unit.suppression >= Config.SUPPRESSED:
			mark = " ▼"
		_label.text = "%d%s" % [unit.hp, mark]
		_label.modulate = Color.WHITE.lerp(Color(1.0, 0.35, 0.2), clampf(unit.suppression / 100.0, 0.0, 1.0))
		_hull.scale.y = 0.5 if unit.prone else 1.0


func _place(p: Vector2) -> void:
	position = Vector3(p.x * Config.CELL_SIZE, height_field.height_at(p), p.y * Config.CELL_SIZE)


## Fantasma: se dibuja en la última celda conocida.
func show_ghost_at(c: Vector2i) -> void:
	_place(Vector2(c))
	set_display(Display.GHOST)


func set_display(mode: int) -> void:
	visible = mode != Display.HIDDEN
	var mat: StandardMaterial3D = _mat_normal
	if mode == Display.GHOST:
		mat = _mat_ghost
	elif mode == Display.WRECK:
		mat = _mat_wreck
	_hull.material_override = mat
	_turret.material_override = mat
	if mode == Display.WRECK:
		_ring.visible = false
	if _label != null:
		_label.visible = mode == Display.NORMAL
