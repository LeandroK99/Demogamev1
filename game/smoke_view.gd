class_name SmokeView
extends Node3D
## Nubes de humo: un cilindro gris semitransparente por nube, que se aclara en su último turno.

const ALPHA_FULL: float = 0.55
const ALPHA_LAST_TURN: float = 0.3

var world: SimWorld
var _nodes: Dictionary = {} # id de nube -> MeshInstance3D


func setup(p_world: SimWorld) -> void:
	world = p_world


func _process(_delta: float) -> void:
	var alive: Dictionary = {}
	for cloud: Dictionary in world.smoke_clouds:
		var id: int = cloud["id"]
		alive[id] = true
		if not _nodes.has(id):
			_nodes[id] = _make(cloud)
		var mi: MeshInstance3D = _nodes[id]
		var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
		var fading: bool = int(cloud["ticks_left"]) < 100 if cloud.has("ticks_left") else int(cloud["turns_left"]) <= 1
		mat.albedo_color.a = ALPHA_LAST_TURN if fading else ALPHA_FULL
	for id: int in _nodes.keys():
		if not alive.has(id):
			(_nodes[id] as Node).queue_free()
			_nodes.erase(id)


func _make(cloud: Dictionary) -> MeshInstance3D:
	var center: Vector2 = cloud["center"]
	var r_m: float = float(cloud["radius"]) * Config.CELL_SIZE
	var ground: float = world.height_field.height_at(center)
	var top: float = float(cloud["top_h"])
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = r_m * 0.8
	mesh.bottom_radius = r_m
	mesh.height = top - ground + 2.0 # un poco enterrado para que no flote en pendiente
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.75, 0.72, ALPHA_FULL)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(center.x * Config.CELL_SIZE, (ground - 2.0 + top) * 0.5, center.y * Config.CELL_SIZE)
	add_child(mi)
	return mi
