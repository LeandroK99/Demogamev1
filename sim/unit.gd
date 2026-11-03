class_name Unit
extends RefCounted
## Una unidad de la simulación: un tanque o una escuadra de infantería (ver kind).

enum Kind { TANK, INFANTRY }
## Armas: el tanque lleva cañón (contra tanques) y coaxial (contra infantería); la escuadra,
## fusiles y ametralladora (contra infantería) y un antitanque con pocas cargas.
enum Weapon { CANNON, COAX, RIFLES, AT }

enum Order { NONE, MOVE, HULLDOWN, HOLD, ATTACK, OVERWATCH, SCOOT, ASSAULT, WITHDRAW }
## Reglas de fuego: libre, solo si te dispararon hace poco, o retener.
enum Roe { FREE, RETURN_FIRE, HOLD }
## Ritmo de marcha: normal, rápido (más veloz, tira peor) o cauto (lento, se detecta como si estuviera quieto).
enum Pace { NORMAL, FAST, CAUTIOUS }

var id: int = 0
var kind: int = Kind.TANK
var side: int = 0 # 0 azul, 1 rojo
var pos: Vector2 = Vector2.ZERO # en celdas, continua
var heading: Vector2 = Vector2(0.0, -1.0) # dirección de marcha en la grilla
var hp: int = Config.TANK_HP
var reload_left: float = 0.0 # arma principal (cañón o fusiles)
var reload2_left: float = 0.0 # arma secundaria (coaxial o antitanque)
var at_charges: int = Config.INF_AT_CHARGES # cargas del antitanque (solo infantería)
var path: Array[Vector2i] = []
var final_heading: Vector2 = Vector2.ZERO # orientación al llegar (cero = la de la marcha)
var direct_route: bool = false # el primer tramo de la ruta es directo (ignora la exposición)
## Fin de cada tramo de la ruta: {cell: Vector2i, direct: bool} y, opcionales, gate (condición para
## arrancar el tramo, ver SimWorld.gate_*), gate_open (ya se cumplió) y signal (señal que emite al llegar).
var waypoints: Array[Dictionary] = []
var attack_target: int = -1 # id del enemigo a atacar (-1 = ninguno)
var overwatch_dir: Vector2 = Vector2.ZERO # centro del sector de tiro en vigilancia
var overwatch_ready: bool = false # le queda el disparo de emboscada de este turno
var return_cell: Vector2i = Vector2i.ZERO # disparar y replegarse: celda cubierta a la que vuelve
var scoot_fired: bool = false # disparar y replegarse: ya hizo su disparo
var reversing: bool = false # marcha atrás: no gira el casco al moverse
var order: int = Order.NONE
var moving: bool = false
var prone: bool = false # infantería cuerpo a tierra
var still_time: float = 0.0 # segundos quieta (la infantería se tira cuerpo a tierra)
var waiting: bool = false # tiene ruta pero espera la condición del tramo actual
var alive: bool = true
var last_fire_tick: int = -1000000 # tick global del último disparo
var smoke_charges: int = Config.SMOKE_CHARGES
var shots_received: int = 0 # disparos recibidos (impacten o no)
var roe: int = Roe.FREE # reglas de fuego; duran hasta que se cambien (no las borra otra orden)
var fire_arc_dir: Vector2 = Vector2.ZERO # centro del arco de tiro (cero = sin arco)
var max_engage_m: float = Config.MAX_RANGE # distancia máxima de enganche
var last_fired_upon_tick: int = -1000000 # tick global del último disparo recibido
var pace: int = Pace.NORMAL # ritmo; dura hasta que se cambie (ASSAULT siempre va rápido)


func _init(p_id: int, p_side: int, p_pos: Vector2, p_kind: int = Kind.TANK) -> void:
	id = p_id
	side = p_side
	pos = p_pos
	kind = p_kind
	hp = max_hp()
	heading = Vector2(0.0, -1.0) if side == 0 else Vector2(0.0, 1.0)


func cell() -> Vector2i:
	return Vector2i(roundi(pos.x), roundi(pos.y))


func is_infantry() -> bool:
	return kind == Kind.INFANTRY


## Vida máxima: impactos para destruir un tanque, hombres de una escuadra.
func max_hp() -> int:
	return Config.INF_MEN if is_infantry() else Config.TANK_HP


## Altura del ojo (o la óptica) sobre el terreno.
func eye_h() -> float:
	return Config.INF_EYE_H if is_infantry() else Config.EYE_H


## Altura del perfil que hay que ver para "verle el casco" (o a la escuadra entera).
func profile_h() -> float:
	if is_infantry():
		return Config.INF_PRONE_H if prone else Config.INF_STAND_H
	return Config.HULL_H


## Altura a la que se apunta (y que hay que ver para detectarla).
func center_h() -> float:
	return profile_h() * Config.INF_CENTER_FRACTION if is_infantry() else Config.CENTER_H


## Arma del slot 0 (principal) o 1 (secundaria).
func weapon(slot: int) -> int:
	if is_infantry():
		return Weapon.RIFLES if slot == 0 else Weapon.AT
	return Weapon.CANNON if slot == 0 else Weapon.COAX
