class_name BuildingView
extends Node3D
## Las casas del pueblo (fase 61): paredes de 1 m (las ventanas con antepecho y dintel, las puertas
## con dintel), un piso de madera y un techo por casa. Los techos se ocultan solos con la cámara
## cerca (zoom < ROOF_HIDE_ZOOM) o con O.

const ROOF_HIDE_ZOOM: float = 110.0
const ROOF_T: float = 0.25
const FLOOR_T: float = 0.08

var _bm: BuildingMap
var _hf: HeightField
var _rig: CameraRTS
var _roofs: Array[MeshInstance3D] = []
var _walls: MeshInstance3D
var _roofs_on: bool = true
var _version: int = -1
var _wall_mat: StandardMaterial3D = StandardMaterial3D.new()
var world: SimWorld = null # para marcar las casas limpias (fase 70)
var _marks: MeshInstance3D = null
var _marked: int = -1 # cantidad de cuartos limpios ya dibujados


func setup(bm: BuildingMap, hf: HeightField, rig: CameraRTS) -> void:
	_bm = bm
	_hf = hf
	_rig = rig
	var wall_mat: StandardMaterial3D = _wall_mat
	wall_mat.albedo_color = Color(0.6, 0.55, 0.47)
	var floor_mat: StandardMaterial3D = StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.45, 0.33, 0.22)
	var roof_mat: StandardMaterial3D = StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.55, 0.22, 0.16)
	_build_walls()
	var fl: SurfaceTool = SurfaceTool.new()
	fl.begin(Mesh.PRIMITIVE_TRIANGLES)
	var m: float = MicroCover.MICRO_M
	for r: Rect2i in bm.houses:
		var ground: float = _ground(MicroCover.center_m(r.position + r.size / 2))
		# Piso y techo de la casa entera
		var a: Vector2 = MicroCover.center_m(r.position) - Vector2.ONE * m * 0.5
		var size: Vector2 = Vector2(r.size) * m
		_slab(fl, a, size, ground, 0.0, FLOOR_T)
		var rs: SurfaceTool = SurfaceTool.new()
		rs.begin(Mesh.PRIMITIVE_TRIANGLES)
		_slab(rs, a, size, ground, Config.BUILDING_H, Config.BUILDING_H + ROOF_T)
		rs.set_material(roof_mat)
		var roof: MeshInstance3D = MeshInstance3D.new()
		roof.mesh = rs.commit()
		add_child(roof)
		_roofs.append(roof)
	# Calles y plaza: franjas de tierra apisonada apenas sobre el terreno plano del pueblo
	var cm: Vector2 = Vector2(TownGenerator.center_cell(hf)) * Config.CELL_SIZE
	var reach: float = float(Config.TOWN_RADIUS_CELLS) * Config.CELL_SIZE
	var half_s: float = float(Config.TOWN_STREET_HALF_M)
	var half_p: float = float(Config.TOWN_PLAZA_HALF_M)
	var g: float = _ground(cm)
	var road: SurfaceTool = SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	_slab(road, cm - Vector2(half_s, reach), Vector2(2.0 * half_s, 2.0 * reach), g, 0.0, 0.15)
	_slab(road, cm - Vector2(reach, half_s), Vector2(2.0 * reach, 2.0 * half_s), g, 0.0, 0.15)
	_slab(road, cm - Vector2(half_p, half_p), Vector2(2.0 * half_p, 2.0 * half_p), g, 0.0, 0.17)
	var road_mat: StandardMaterial3D = StandardMaterial3D.new()
	road_mat.albedo_color = Color(0.42, 0.38, 0.31)
	road.set_material(road_mat)
	var roads: MeshInstance3D = MeshInstance3D.new()
	roads.mesh = road.commit()
	add_child(roads)
	fl.set_material(floor_mat)
	var floors: MeshInstance3D = MeshInstance3D.new()
	floors.mesh = fl.commit()
	add_child(floors)


## Paredes (se rehacen cuando se abre un boquete).
func _build_walls() -> void:
	_version = _bm.version
	if _walls != null:
		_walls.queue_free()
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var m: float = MicroCover.MICRO_M
	for r: Rect2i in _bm.houses:
		var ground: float = _ground(MicroCover.center_m(r.position + r.size / 2))
		for y: int in range(r.position.y, r.end.y):
			for x: int in range(r.position.x, r.end.x):
				var c: Vector2i = Vector2i(x, y)
				var p: Vector2 = MicroCover.center_m(c)
				match _bm.type_at(c):
					BuildingMap.Type.WALL:
						_box(st, p, ground, 0.0, Config.BUILDING_H, m)
					BuildingMap.Type.WINDOW:
						_box(st, p, ground, 0.0, Config.WINDOW_SILL_H, m)
						_box(st, p, ground, Config.WINDOW_TOP_H, Config.BUILDING_H, m)
					BuildingMap.Type.DOOR:
						_box(st, p, ground, Config.DOOR_H, Config.BUILDING_H, m)
					BuildingMap.Type.LOOPHOLE:
						_box(st, p, ground, 0.0, Config.LOOPHOLE_LOW_H, m)
						_box(st, p, ground, Config.LOOPHOLE_TOP_H, Config.BUILDING_H, m)
					BuildingMap.Type.BREACH:
						_box(st, p, ground, 0.0, Config.BREACH_RUBBLE_H, m)
						_box(st, p, ground, Config.DOOR_H, Config.BUILDING_H, m)
	st.set_material(_wall_mat)
	_walls = MeshInstance3D.new()
	_walls.mesh = st.commit()
	add_child(_walls)


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_O:
		_roofs_on = not _roofs_on


func _process(_delta: float) -> void:
	if _bm.version != _version:
		_build_walls()
	var show: bool = _roofs_on and (_rig == null or _rig.zoom >= ROOF_HIDE_ZOOM)
	for r: MeshInstance3D in _roofs:
		r.visible = show
	if world != null and world.cleared_rooms.size() != _marked:
		_build_marks()


## Cuartos limpios: el piso pintado del color del bando; una casa limpia entera, con una franja en
## el techo.
func _build_marks() -> void:
	_marked = world.cleared_rooms.size()
	if _marks != null:
		_marks.queue_free()
		_marks = null
	var rm: RoomMap = world.rooms()
	if rm == null or world.cleared_rooms.is_empty():
		return
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r: int in world.cleared_rooms:
		if r >= rm.rooms.size():
			continue
		var col: Color = Color(0.3, 0.5, 0.95) if int(world.cleared_rooms[r]) == 0 else Color(0.9, 0.3, 0.25)
		var rect: Rect2 = rm.rooms[r]["rect"]
		var ground: float = _ground(rect.get_center())
		st.set_color(col)
		_slab(st, rect.position + Vector2.ONE * 0.3, rect.size - Vector2.ONE * 0.6, ground, FLOOR_T, FLOOR_T + 0.03)
	for h: int in world.cleared_houses:
		var col2: Color = Color(0.3, 0.5, 0.95) if int(world.cleared_houses[h]) == 0 else Color(0.9, 0.3, 0.25)
		var hr: Rect2 = _bm.rect_m(h)
		st.set_color(col2)
		_slab(st, Vector2(hr.position.x, hr.get_center().y - 0.6), Vector2(hr.size.x, 1.2), _ground(hr.get_center()),
			Config.BUILDING_H + ROOF_T, Config.BUILDING_H + ROOF_T + 0.05)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	st.set_material(mat)
	_marks = MeshInstance3D.new()
	_marks.mesh = st.commit()
	add_child(_marks)


func _ground(p: Vector2) -> float:
	return _hf.height_at(p / Config.CELL_SIZE)


## Prisma de una micro-celda centrada en p, de h0 a h1 metros sobre ground.
func _box(st: SurfaceTool, p: Vector2, ground: float, h0: float, h1: float, side: float) -> void:
	_slab(st, p - Vector2.ONE * side * 0.5, Vector2.ONE * side, ground, h0, h1)


## Prisma de base a (esquina, metros) y tamaño size, de h0 a h1 sobre ground.
func _slab(st: SurfaceTool, a: Vector2, size: Vector2, ground: float, h0: float, h1: float) -> void:
	var x0: float = a.x
	var x1: float = a.x + size.x
	var z0: float = a.y
	var z1: float = a.y + size.y
	var y0: float = ground + h0
	var y1: float = ground + h1
	var v: Array[Vector3] = [
		Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1),
		Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1),
	]
	# Caras: arriba, abajo, -z, +z, -x, +x (cada una con su normal)
	_quad(st, v[4], v[5], v[6], v[7], Vector3.UP)
	_quad(st, v[3], v[2], v[1], v[0], Vector3.DOWN)
	_quad(st, v[0], v[1], v[5], v[4], Vector3.FORWARD)
	_quad(st, v[2], v[3], v[7], v[6], Vector3.BACK)
	_quad(st, v[3], v[0], v[4], v[7], Vector3.LEFT)
	_quad(st, v[1], v[2], v[6], v[5], Vector3.RIGHT)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	for v: Vector3 in [a, b, c, a, c, d]:
		st.set_normal(n)
		st.add_vertex(v)
