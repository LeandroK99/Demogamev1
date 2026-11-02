extends Node3D
## Punto de entrada: construye todo por código.

var height_field: HeightField
var terrain_view: TerrainView
var camera_rig: CameraRTS


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

	print("Hull-Down OK")
