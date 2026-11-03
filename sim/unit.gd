class_name Unit
extends RefCounted
## Una unidad de la simulación: un tanque o una escuadra de infantería (ver kind).

enum Kind { TANK, INFANTRY }
## Armas: el tanque lleva cañón (contra tanques) y coaxial (contra infantería); la escuadra,
## fusiles y ametralladora (contra infantería) y un antitanque con pocas cargas. Cada soldado
## tira con la suya: fusil, ametralladora (MG, en ráfagas) o antitanque.
enum Weapon { CANNON, COAX, RIFLES, AT, MG, GRENADE }

enum Order { NONE, MOVE, HULLDOWN, HOLD, ATTACK, OVERWATCH, SCOOT, ASSAULT, WITHDRAW, SUPPRESS }
## Reglas de fuego: libre, solo si te dispararon hace poco, o retener.
enum Roe { FREE, RETURN_FIRE, HOLD }
## Ritmo de marcha: normal, rápido (más veloz, tira peor) o cauto (lento, se detecta como si estuviera quieto).
enum Pace { NORMAL, FAST, CAUTIOUS }
## Formación de la escuadra: cuña, fila india o línea.
enum Formation { WEDGE, FILE, LINE, ECHELON }

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
var suppression: float = 0.0 # 0..100: sube con el fuego recibido, aunque no impacte
var last_suppressed_tick: int = -1000000 # tick global de la última vez que la suprimieron
var morale: float = 100.0 # 0..100 (solo infantería): baja con bajas y supresión
var broken: bool = false # moral quebrada: se repliega sola e ignora órdenes hasta recuperarse
var suppress_cell: Vector2i = Vector2i.ZERO # orden SUPPRESS: centro de la zona a batir
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
## Infantería: los soldados de la escuadra. pos es el ancla de la formación, que sigue la ruta.
var soldiers: Array[Soldier] = []
var formation: int = Formation.WEDGE # la que eligió el jugador
## Formación en uso (fase 50): con la cuña elegida, la escuadra la adapta al terreno (fila en el bosque,
## línea para el asalto final, escalón hacia un contacto de costado). spread abre o cierra los lugares.
var shape: int = Formation.WEDGE
var spread: float = 1.0
var echelon_side: float = 1.0 # 1 = escalón a la derecha, -1 a la izquierda
## Infantería: la cabeza de la escuadra (autonomía, ver MindSim). null en los tanques.
var mind: SquadMind = null
var jitter_at: Vector2 = Vector2(-1.0e9, -1.0e9) # dónde estaba el ancla la última vez que se reacomodaron
var low_ammo_reported: bool = false # ya avisó por radio que le queda poca munición
var mg_dry_reported: bool = false # ya avisó que la ametralladora se quedó sin munición


func _init(p_id: int, p_side: int, p_pos: Vector2, p_kind: int = Kind.TANK) -> void:
	id = p_id
	side = p_side
	pos = p_pos
	kind = p_kind
	hp = max_hp()
	heading = Vector2(0.0, -1.0) if side == 0 else Vector2(0.0, 1.0)
	if is_infantry():
		for i: int in Config.INF_MEN:
			var s: Soldier = Soldier.new(i, Soldier.role_for(i), Vector2.ZERO)
			s.heading = heading
			soldiers.append(s)
			s.pos = slot_pos_m(i)
		smoke_charges = Config.INF_SMOKE_CHARGES
		mind = SquadMind.new(Config.MIND_AUTONOMY_BLUE if side == 0 else Config.MIND_AUTONOMY_RED)
		mind.next_think_tick = p_id % Config.MIND_THINK_TICKS


## Fracción de munición que le queda a los soldados en condiciones (1 = llena). Los tanques, 1.
func ammo_fraction() -> float:
	var have: int = 0
	var full: int = 0
	for s: Soldier in soldiers:
		if s.is_ok():
			have += s.ammo
			full += Soldier.max_ammo(s.role)
	return 1.0 if full == 0 else float(have) / float(full)


## Ancla de la formación en metros.
func pos_m() -> Vector2:
	return pos * Config.CELL_SIZE


## Lugar del soldado i en la formación, en metros (según el ancla y el rumbo).
func slot_pos_m(i: int) -> Vector2:
	var base: Vector2 = formation_offset(i, shape, echelon_side) * spread
	var off: Vector2 = base + soldiers[i].jitter if i < soldiers.size() else base
	var right: Vector2 = Vector2(-heading.y, heading.x)
	return pos_m() + right * off.x - heading * off.y


## Desplazamiento del lugar i en una formación: x a la derecha, y hacia atrás, en metros.
static func formation_offset(i: int, f: int, side: float = 1.0) -> Vector2:
	var s: float = Config.SOLDIER_SPACING
	match f:
		Formation.ECHELON:
			# En diagonal hacia atrás y hacia el lado del escalón
			return Vector2(side * float(i) * s, float(i) * s * 0.7)
		Formation.FILE:
			return Vector2(0.0, float(i) * s)
		Formation.LINE:
			# El jefe en el medio, los demás alternando a los costados
			var k: int = (i + 1) / 2
			return Vector2(float(k if i % 2 == 1 else -k) * s, 0.0)
	# Cuña: el jefe adelante, los demás alternando en dos brazos hacia atrás
	var j: int = (i + 1) / 2
	return Vector2(float(j if i % 2 == 1 else -j) * s, float(j) * s)


## Pone a cada soldado en su lugar de la formación (al mover la escuadra a mano).
func snap_soldiers() -> void:
	for s: Soldier in soldiers:
		if s.is_ok():
			s.pos = slot_pos_m(s.index)
			s.has_cover = false


## Postura de todos los soldados en condiciones (escenarios y tests; la simulación la recalcula).
func set_posture(p: int) -> void:
	for s: Soldier in soldiers:
		if s.is_ok():
			s.posture = p


## Supresión de la unidad (y de cada soldado, si es una escuadra). Para escenarios y tests.
func set_suppression(value: float, tick: int) -> void:
	suppression = value
	last_suppressed_tick = tick
	for s: Soldier in soldiers:
		s.suppression = value
		s.last_suppressed_tick = tick


## Deja n soldados en condiciones (los demás, muertos). Para escenarios y tests.
func set_men(n: int) -> void:
	for s: Soldier in soldiers:
		if s.index >= n:
			s.state = Soldier.State.DEAD
	hp = ok_count()


## Soldados en condiciones de combatir.
func ok_count() -> int:
	var n: int = 0
	for s: Soldier in soldiers:
		if s.is_ok():
			n += 1
	return n


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
