class_name UnitView
extends Node3D
## Vista de una unidad: tanque (caja de casco + torreta) o escuadra (un muñeco por soldado, con
## su postura, y el número de hombres encima), y anillo de selección. De una escuadra enemiga
## se dibujan solo los soldados que el jugador ve; de fantasma, una caja en la última celda conocida.
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
var world: SimWorld = null # para saber qué soldados enemigos ve el jugador
var player_side: int = 0
var _soldiers: Array[MeshInstance3D] = []
var _soldier_prev: Array[Vector2] = []
var _mat_wounded: StandardMaterial3D = StandardMaterial3D.new()
var _mat_dead: StandardMaterial3D = StandardMaterial3D.new()
var _mode: int = Display.NORMAL
var _mat_normal: StandardMaterial3D = StandardMaterial3D.new()
var _mat_ghost: StandardMaterial3D = StandardMaterial3D.new()
var _mat_wreck: StandardMaterial3D = StandardMaterial3D.new()


func setup(p_unit: Unit, hf: HeightField, p_world: SimWorld = null) -> void:
	unit = p_unit
	height_field = hf
	world = p_world
	prev_pos = unit.pos
	var color: Color = COLOR_BLUE if unit.side == 0 else COLOR_RED
	_mat_normal.albedo_color = color
	_mat_ghost.albedo_color = Color(color, 0.3)
	_mat_ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_ghost.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_wreck.albedo_color = Color(0.12, 0.11, 0.1)
	_mat_wounded.albedo_color = color.darkened(0.45)
	_mat_dead.albedo_color = Color(0.18, 0.16, 0.14)
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

	if inf:
		# Un muñeco por soldado (el jefe y la ametralladora, más anchos) que se achata según la postura
		_hull.visible = false # la caja de la escuadra queda solo para el fantasma
		var body: BoxMesh = BoxMesh.new()
		body.size = Vector3(0.6, 1.0, 0.6)
		var mg_body: BoxMesh = BoxMesh.new()
		mg_body.size = Vector3(0.9, 1.0, 0.9)
		for s: Soldier in unit.soldiers:
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.mesh = mg_body if s.role == Soldier.Role.MG or s.role == Soldier.Role.LEADER else body
			mi.material_override = mat
			add_child(mi)
			_soldiers.append(mi)
			_soldier_prev.append(s.pos)

	var turret_mesh: BoxMesh = BoxMesh.new()
	turret_mesh.size = Vector3(1.0, 0.5, 1.0) if inf else Vector3(2.2, 0.9, 3.0)
	turret_mesh.material = mat
	_turret = MeshInstance3D.new()
	_turret.mesh = turret_mesh
	_turret.position = Vector3(0.0, 1.05, -1.4) if inf else Vector3(0.0, 2.65, -0.4)
	_turret.visible = not inf
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
	if not unit.is_infantry():
		rotation.y = atan2(-unit.heading.x, -unit.heading.y)
	else:
		_sync_soldiers(alpha)
	if _label != null:
		var mark: String = ""
		if unit.broken:
			mark = " !"
		elif unit.suppression >= Config.SUPPRESSED:
			mark = " ▼"
		_label.text = "%d%s" % [unit.hp, mark]
		if unit.mind != null and unit.side == player_side and world != null:
			var intent: String = unit.mind.intent_short(world.total_ticks)
			if intent != "":
				_label.text += "\n" + intent # lo que decidió por su cuenta
		_label.modulate = Color.WHITE.lerp(Color(1.0, 0.35, 0.2), clampf(unit.suppression / 100.0, 0.0, 1.0))


## Guarda las posiciones del tick actual (para interpolar hasta el siguiente).
func remember() -> void:
	prev_pos = unit.pos
	for i: int in _soldiers.size():
		_soldier_prev[i] = unit.soldiers[i].pos


## Cada muñeco en su soldado (en coordenadas locales del ancla), con la altura de su postura.
func _sync_soldiers(alpha: float) -> void:
	var enemy: bool = unit.side != player_side and world != null
	for i: int in _soldiers.size():
		var s: Soldier = unit.soldiers[i]
		var mi: MeshInstance3D = _soldiers[i]
		var p: Vector2 = _soldier_prev[i].lerp(s.pos, alpha)
		var ground: float = height_field.height_at(p / Config.CELL_SIZE)
		if world != null and world.micro != null:
			ground += InfantrySim.ground_offset(world, p)
		var h: float = s.top_h() if s.is_ok() else 0.3
		mi.scale = Vector3(1.0, h, 1.0)
		if s.posture == Soldier.Posture.PRONE or not s.is_ok():
			mi.scale = Vector3(1.0, h, 2.2) # acostado: más largo que alto
		mi.position = Vector3(p.x - position.x, ground + h * 0.5 - position.y, p.y - position.z)
		mi.rotation.y = atan2(-s.heading.x, -s.heading.y)
		var shown: bool = _mode == Display.NORMAL or _mode == Display.WRECK
		if enemy and _mode == Display.NORMAL and s.is_ok():
			shown = world.inf.is_soldier_visible(player_side, unit.id, s.index)
		elif enemy and not s.is_ok():
			shown = _mode != Display.HIDDEN and _mode != Display.GHOST
		mi.visible = shown
		if _mode == Display.NORMAL:
			var hurt: bool = s.state == Soldier.State.WOUNDED or s.state == Soldier.State.EVACUATING
			mi.material_override = _mat_normal if s.is_ok() else (_mat_wounded if hurt else _mat_dead)
		if s.state == Soldier.State.EVACUATED:
			mi.visible = false # ya salió del campo
		else:
			mi.material_override = _mat_dead


func _place(p: Vector2) -> void:
	position = Vector3(p.x * Config.CELL_SIZE, height_field.height_at(p), p.y * Config.CELL_SIZE)


## Fantasma: se dibuja en la última celda conocida.
func show_ghost_at(c: Vector2i) -> void:
	_place(Vector2(c))
	set_display(Display.GHOST)
	for mi: MeshInstance3D in _soldiers:
		mi.visible = false


func set_display(mode: int) -> void:
	_mode = mode
	visible = mode != Display.HIDDEN
	if unit.is_infantry():
		_hull.visible = mode == Display.GHOST # la caja marca la última posición conocida
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
