extends Node3D
## Punto de entrada: construye todo por código. R reinicia con la misma semilla; Shift+R con una nueva.

var map_seed: int = Config.SEED
var world: SimWorld
var height_field: HeightField
var terrain_view: TerrainView
var camera_rig: CameraRTS
var overlay: Overlay
var input_controller: InputController
var turn_controller: TurnController
var combat_fx: CombatFx
var smoke_view: SmokeView
var hud: Hud
var unit_views: Array[UnitView] = []

var _game_root: Node3D


func _ready() -> void:
	_build_environment()
	_start_game(map_seed)
	print("Hull-Down OK")


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_R:
		if key.shift_pressed:
			map_seed = randi() % 100000
		_start_game(map_seed)


## Arma una partida nueva (descarta la anterior si existe).
func _start_game(p_seed: int) -> void:
	if _game_root != null:
		remove_child(_game_root)
		_game_root.queue_free()
	_game_root = Node3D.new()
	add_child(_game_root)
	unit_views = []

	world = SimWorld.new(p_seed)
	height_field = world.height_field

	terrain_view = TerrainView.new()
	_game_root.add_child(terrain_view)
	terrain_view.setup(height_field)

	camera_rig = CameraRTS.new()
	_game_root.add_child(camera_rig)
	camera_rig.setup(height_field)
	# Arrancar mirando al despliegue azul
	camera_rig.position.z = (height_field.size - 20) * Config.CELL_SIZE
	camera_rig.zoom = 160.0
	camera_rig._clamp_to_map()
	camera_rig.camera.make_current()

	for u: Unit in world.units:
		var v: UnitView = UnitView.new()
		_game_root.add_child(v)
		v.setup(u, height_field)
		unit_views.append(v)

	overlay = Overlay.new()
	_game_root.add_child(overlay)
	overlay.setup(terrain_view, world)

	input_controller = InputController.new()
	_game_root.add_child(input_controller)
	input_controller.setup(world, camera_rig.camera, terrain_view, unit_views)
	input_controller.selection_changed.connect(_update_overlay_selection)
	input_controller.smoke_placed.connect(_on_plan_started)

	smoke_view = SmokeView.new()
	_game_root.add_child(smoke_view)
	smoke_view.setup(world)

	combat_fx = CombatFx.new()
	_game_root.add_child(combat_fx)
	combat_fx.setup(height_field)

	turn_controller = TurnController.new()
	_game_root.add_child(turn_controller)
	turn_controller.setup(world, unit_views, combat_fx)
	turn_controller.plan_started.connect(_on_plan_started)

	hud = Hud.new()
	_game_root.add_child(hud)
	hud.setup(world, turn_controller, input_controller, p_seed)


func _process(_delta: float) -> void:
	input_controller.prune_dead()
	_update_overlay_selection()


func _update_overlay_selection() -> void:
	var u: Unit = input_controller.primary_unit()
	overlay.set_selected_cell(u.cell() if u != null else Vector2i(-1, -1))


## Nuevo turno: la exposición cambió (amenazas conocidas nuevas).
func _on_plan_started() -> void:
	overlay.refresh()


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
