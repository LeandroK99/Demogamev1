extends Node3D
## Punto de entrada: construye todo por código.

var world: SimWorld
var height_field: HeightField
var terrain_view: TerrainView
var camera_rig: CameraRTS
var overlay: Overlay
var input_controller: InputController
var unit_views: Array[UnitView] = []

var _tick_accum: float = 0.0


func _ready() -> void:
	world = SimWorld.new(Config.SEED)
	height_field = world.height_field

	terrain_view = TerrainView.new()
	add_child(terrain_view)
	terrain_view.setup(height_field)

	camera_rig = CameraRTS.new()
	add_child(camera_rig)
	camera_rig.setup(height_field)
	# Arrancar mirando al despliegue azul
	camera_rig.position.z = (height_field.size - 20) * Config.CELL_SIZE
	camera_rig.zoom = 160.0
	camera_rig._clamp_to_map()

	_build_environment()

	for u: Unit in world.units:
		var v: UnitView = UnitView.new()
		add_child(v)
		v.setup(u, height_field)
		unit_views.append(v)

	overlay = Overlay.new()
	add_child(overlay)
	overlay.setup(terrain_view, world)

	input_controller = InputController.new()
	add_child(input_controller)
	input_controller.setup(world, camera_rig.camera, terrain_view, unit_views)
	input_controller.selection_changed.connect(_update_overlay_selection)

	print("Hull-Down OK")


## Provisorio hasta la fase 4 (ciclo WeGo): la simulación corre en tiempo real.
func _process(delta: float) -> void:
	_tick_accum += delta
	while _tick_accum >= Config.TICK:
		world.step()
		_tick_accum -= Config.TICK
	for v: UnitView in unit_views:
		v.sync_from_sim()
	_update_overlay_selection()


func _update_overlay_selection() -> void:
	var u: Unit = input_controller.primary_unit()
	overlay.set_selected_cell(u.cell() if u != null else Vector2i(-1, -1))


func _build_environment() -> void:
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
