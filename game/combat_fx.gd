class_name CombatFx
extends Node3D
## Trazadoras de 0,15 s y destello en los impactos (más grande y rojo si entró por flanco o atrás).

const TRACER_SECONDS: float = 0.15
const FLASH_SECONDS: float = 0.3

var height_field: HeightField
var _mesh: ImmediateMesh = ImmediateMesh.new()
var _material: StandardMaterial3D = StandardMaterial3D.new()
var _tracers: Array[Dictionary] = [] # {from, to, left}
var _flashes: Array[Dictionary] = [] # {node, left}


func setup(hf: HeightField) -> void:
	height_field = hf
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = _mesh
	add_child(mi)
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = Color(1.0, 0.95, 0.6)


func _point(u: Unit, h: float) -> Vector3:
	return Vector3(u.pos.x * Config.CELL_SIZE, height_field.height_at(u.pos) + h, u.pos.y * Config.CELL_SIZE)


func add_shot(shooter: Unit, target: Unit, hit: bool, aspect: int = SimWorld.Aspect.FRONT, weapon: int = Unit.Weapon.CANNON) -> void:
	var to: Vector3 = _point(target, target.center_h())
	if weapon == Unit.Weapon.COAX or weapon == Unit.Weapon.RIFLES:
		# Armas livianas: varias trazadoras cortas alrededor del blanco, sin fogonazo de impacto
		for i: int in 3:
			var spread: Vector3 = Vector3(randf_range(-3.0, 3.0), randf_range(0.0, 1.5), randf_range(-3.0, 3.0))
			_tracers.append({"from": _point(shooter, shooter.eye_h()), "to": to + spread, "left": TRACER_SECONDS * 0.5})
		return
	if not hit:
		# Errado: la trazadora pasa un poco por al lado
		to += Vector3(randf_range(-4.0, 4.0), randf_range(0.5, 3.0), randf_range(-4.0, 4.0))
	_tracers.append({"from": _point(shooter, shooter.eye_h()), "to": to, "left": TRACER_SECONDS})
	if hit:
		_flash(to, aspect)


## Destello de impacto (más grande y rojo si entró por flanco o atrás).
func _flash(to: Vector3, aspect: int) -> void:
	var mesh: SphereMesh = SphereMesh.new()
	var r: float = 2.0
	var color: Color = Color(1.0, 0.6, 0.1)
	if aspect == SimWorld.Aspect.FLANK:
		r = 2.6
		color = Color(1.0, 0.4, 0.1)
	elif aspect == SimWorld.Aspect.REAR:
		r = 3.2
		color = Color(1.0, 0.15, 0.1)
	mesh.radius = r
	mesh.height = r * 2.0
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mesh.material = mat
	var flash: MeshInstance3D = MeshInstance3D.new()
	flash.mesh = mesh
	flash.position = to
	add_child(flash)
	_flashes.append({"node": flash, "left": FLASH_SECONDS})


## Tiro de un soldado (o de la coaxial a un soldado), en metros del mundo: el fusil, una trazadora;
## las ráfagas, tres; el antitanque, trazadora y destello si pega.
func add_shot_m(from_m: Vector2, from_h: float, to_m: Vector2, to_h: float, weapon: int, hit: bool, aspect: int = SimWorld.Aspect.FRONT) -> void:
	var from: Vector3 = _point_m(from_m, from_h)
	var to: Vector3 = _point_m(to_m, to_h)
	match weapon:
		Unit.Weapon.AT:
			_tracers.append({"from": from, "to": to, "left": TRACER_SECONDS})
			if hit:
				_flash(to, aspect)
		Unit.Weapon.MG, Unit.Weapon.COAX:
			for i: int in 3:
				var spread: Vector3 = Vector3(randf_range(-1.5, 1.5), randf_range(0.0, 0.8), randf_range(-1.5, 1.5))
				_tracers.append({"from": from, "to": to + spread, "left": TRACER_SECONDS * 0.5})
		_:
			var miss: Vector3 = Vector3.ZERO if hit else Vector3(randf_range(-1.0, 1.0), randf_range(0.0, 0.6), randf_range(-1.0, 1.0))
			_tracers.append({"from": from, "to": to + miss, "left": TRACER_SECONDS * 0.4})


func _point_m(m: Vector2, h: float) -> Vector3:
	return Vector3(m.x, height_field.height_at(m / Config.CELL_SIZE) + h, m.y)


## Explosión de una granada en m (metros del mundo): destello gris anaranjado a ras del suelo.
func add_blast_m(m: Vector2) -> void:
	_flash(_point_m(m, 0.5), SimWorld.Aspect.FLANK)


## Fuego de área (suprimir): trazadoras repartidas sobre la zona.
func add_area_shot(shooter: Unit, cell: Vector2i) -> void:
	var center: Vector3 = height_field.cell_to_world(cell)
	var r: float = Config.SUPPRESS_AREA_RADIUS * Config.CELL_SIZE
	for i: int in 4:
		var to: Vector3 = center + Vector3(randf_range(-r, r), randf_range(0.0, 1.0), randf_range(-r, r))
		_tracers.append({"from": _point(shooter, shooter.eye_h()), "to": to, "left": TRACER_SECONDS * 0.5})


func _process(delta: float) -> void:
	for f: Dictionary in _flashes:
		f["left"] = float(f["left"]) - delta
		if float(f["left"]) <= 0.0:
			(f["node"] as Node).queue_free()
	_flashes = _flashes.filter(func(f: Dictionary) -> bool: return float(f["left"]) > 0.0)
	for t: Dictionary in _tracers:
		t["left"] = float(t["left"]) - delta
	_tracers = _tracers.filter(func(t: Dictionary) -> bool: return float(t["left"]) > 0.0)
	_mesh.clear_surfaces()
	if _tracers.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material)
	for t: Dictionary in _tracers:
		_mesh.surface_add_vertex(t["from"])
		_mesh.surface_add_vertex(t["to"])
	_mesh.surface_end()
