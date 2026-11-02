class_name CameraRTS
extends Node3D
## Pivote de cámara RTS: WASD/flechas mueven, rueda hace zoom, botón medio rota.

const PITCH_DEG: float = 60.0
const ZOOM_MIN: float = 40.0
const ZOOM_MAX: float = 300.0
const ZOOM_STEP: float = 1.15
const PAN_SPEED: float = 1.0 # fracción del zoom por segundo
const ROTATE_SPEED: float = 0.006 # radianes por píxel

var camera: Camera3D = Camera3D.new()
var zoom: float = 220.0
var _height_field: HeightField


func _ready() -> void:
	camera.far = 3000.0
	add_child(camera)
	_update_camera()


func setup(hf: HeightField) -> void:
	_height_field = hf
	var center: float = (hf.size - 1) * Config.CELL_SIZE * 0.5
	position = Vector3(center, 0.0, center)
	_clamp_to_map()


func _process(delta: float) -> void:
	var dir: Vector3 = Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.z += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if dir != Vector3.ZERO:
		position += dir.normalized().rotated(Vector3.UP, rotation.y) * zoom * PAN_SPEED * delta
		_clamp_to_map()


func _unhandled_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom / ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			_update_camera()
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null and (mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0:
		rotation.y -= mm.relative.x * ROTATE_SPEED


func _update_camera() -> void:
	var pitch: float = deg_to_rad(PITCH_DEG)
	camera.position = Vector3(0.0, sin(pitch) * zoom, cos(pitch) * zoom)
	camera.rotation = Vector3(-pitch, 0.0, 0.0)


## Mantiene el pivote dentro del mapa y apoyado sobre el terreno.
func _clamp_to_map() -> void:
	if _height_field == null:
		return
	var limit: float = (_height_field.size - 1) * Config.CELL_SIZE
	position.x = clampf(position.x, 0.0, limit)
	position.z = clampf(position.z, 0.0, limit)
	position.y = _height_field.height_at(Vector2(position.x, position.z) / Config.CELL_SIZE)
