class_name Unit
extends RefCounted
## Un tanque de la simulación.

enum Order { NONE, MOVE, HULLDOWN, HOLD, ATTACK }

var id: int = 0
var side: int = 0 # 0 azul, 1 rojo
var pos: Vector2 = Vector2.ZERO # en celdas, continua
var heading: Vector2 = Vector2(0.0, -1.0) # dirección de marcha en la grilla
var hp: int = Config.TANK_HP
var reload_left: float = 0.0
var path: Array[Vector2i] = []
var final_heading: Vector2 = Vector2.ZERO # orientación al llegar (cero = la de la marcha)
var direct_route: bool = false # el primer tramo de la ruta es directo (ignora la exposición)
var waypoints: Array[Dictionary] = [] # fin de cada tramo de la ruta: {cell: Vector2i, direct: bool}
var attack_target: int = -1 # id del enemigo a atacar (-1 = ninguno)
var order: int = Order.NONE
var moving: bool = false
var alive: bool = true
var last_fire_tick: int = -1000000 # tick global del último disparo
var shots_received: int = 0 # disparos recibidos (impacten o no)


func _init(p_id: int, p_side: int, p_pos: Vector2) -> void:
	id = p_id
	side = p_side
	pos = p_pos
	heading = Vector2(0.0, -1.0) if side == 0 else Vector2(0.0, 1.0)


func cell() -> Vector2i:
	return Vector2i(roundi(pos.x), roundi(pos.y))
