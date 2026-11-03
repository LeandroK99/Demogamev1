extends Node3D
## Punto de entrada: construye todo por código.

var height_field: HeightField
var terrain_view: TerrainView
var camera_rig: CameraRTS
var analysis: TerrainAnalysis
var overlay: Overlay

# Provisorio hasta la fase 3 (unidades): posiciones fijas para probar los overlays
var placeholder_blue: Array[Vector2i] = [Vector2i(36, 89), Vector2i(44, 89), Vector2i(52, 89), Vector2i(60, 89)]
var placeholder_red: Array[Vector2i] = [Vector2i(36, 6), Vector2i(44, 6), Vector2i(52, 6), Vector2i(60, 6)]


func _ready() -> void:
	height_field = HeightField.new()
	height_field.generate(Config.SEED)

	terrain_view = TerrainView.new()
	add_child(terrain_view)
	terrain_view.setup(height_field)

	camera_rig = CameraRTS.new()
	add_child(camera_rig)
	camera_rig.setup(height_field)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -60.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 600.0
	add_child(sun)

	var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_mat.ground_bottom_color = Color(0.2, 0.22, 0.24)
	sky_mat.ground_horizon_color = Color(0.45, 0.5, 0.55)
	var sky: Sky = Sky.new()
	sky.sky_material = sky_mat
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	analysis = TerrainAnalysis.new(height_field)
	overlay = Overlay.new()
	add_child(overlay)
	overlay.setup(terrain_view, analysis)
	overlay.set_context(placeholder_red, placeholder_blue[0])
	for c: Vector2i in placeholder_blue:
		_spawn_placeholder(c, Color(0.2, 0.4, 1.0))
	for c: Vector2i in placeholder_red:
		_spawn_placeholder(c, Color(1.0, 0.2, 0.15))

	print("Hull-Down OK")


## Poste de color en una celda (provisorio hasta la fase 3).
func _spawn_placeholder(c: Vector2i, color: Color) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(3.5, 2.2, 7.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = height_field.cell_to_world(c) + Vector3.UP * 1.1
	add_child(mi)
