class_name Soldier
extends RefCounted
## Un soldado de una escuadra. La escuadra (Unit de infantería) tiene la orden, la ruta y la moral;
## el soldado tiene su posición en metros, su postura, su estado y su supresión.

enum Posture { STAND, CROUCH, PRONE }
enum State { OK, WOUNDED, DEAD }
## Jefe, fusilero, ametralladorista, proveedor y tirador antitanque.
enum Role { LEADER, RIFLE, MG, ASSISTANT, AT }

var index: int = 0 # dentro de la escuadra (0 = jefe)
var role: int = Role.RIFLE
var pos: Vector2 = Vector2.ZERO # en metros del mundo (la celda (x, y) está en (x, y) * CELL_SIZE)
var heading: Vector2 = Vector2(0.0, -1.0)
var posture: int = Posture.STAND
var state: int = State.OK
var moving: bool = false
var cover_pos: Vector2 = Vector2.ZERO # punto de cobertura elegido al detenerse
var has_cover: bool = false # tiene un punto de cobertura elegido
var protected: bool = false # ese punto lo protege de la amenaza (no solo lo oculta)
var can_fire: bool = true # desde ese punto puede tirar hacia la amenaza
var cover_posture: int = Posture.PRONE # postura que toma en ese punto
var cover_threat: Vector2 = Vector2.ZERO # amenaza (en metros) contra la que eligió el punto
var suppression: float = 0.0 # 0..100
var last_suppressed_tick: int = -1000000
var reload_left: float = 0.0
var last_fire_tick: int = -1000000
## Reflejos (fase 37)
var incoming_from: Vector2 = Vector2.ZERO # de dónde vino el último tiro que le cayó cerca (metros)
var incoming_tick: int = -1000000
var dive_until: int = -1000000 # se tiró al suelo bajo fuego en marcha: quieto hasta este tick
var has_fire_pos: bool = false # su cobertura no tiene tiro: punto cercano desde el que asoma
var fire_pos: Vector2 = Vector2.ZERO
var fire_posture: int = Posture.PRONE
var peeking: bool = false # está asomado en fire_pos
var peek_tick: int = 0 # tick en que cambia entre asomarse y volver a cubierto
## Equipos de fuego (fase 41): 0 = A (base de fuego: ametralladora y 2, 4, 6), 1 = B (maniobra: jefe, AT, 5, 7, 8).
var team: int = 0
var hold_pos: bool = false # se queda donde está (base de fuego mientras el otro equipo avanza)
var suppress_m: Vector2 = Vector2(-1.0, -1.0) # sin blanco a la vista, bate este punto (negativo = nada)


func _init(p_index: int, p_role: int, p_pos: Vector2) -> void:
	index = p_index
	role = p_role
	pos = p_pos
	team = team_of(p_index)


## Equipo de fuego del soldado i.
static func team_of(i: int) -> int:
	return 0 if i in [1, 2, 4, 6] else 1


func is_ok() -> bool:
	return state == State.OK


## Altura del ojo sobre el terreno según la postura.
func eye_h() -> float:
	match posture:
		Posture.CROUCH:
			return Config.SOLDIER_EYE_CROUCH
		Posture.PRONE:
			return Config.SOLDIER_EYE_PRONE
	return Config.SOLDIER_EYE_STAND


## Altura del centro del cuerpo (a donde se apunta).
func center_h() -> float:
	match posture:
		Posture.CROUCH:
			return Config.SOLDIER_CENTER_CROUCH
		Posture.PRONE:
			return Config.SOLDIER_CENTER_PRONE
	return Config.SOLDIER_CENTER_STAND


## Altura de la cabeza (lo más alto que asoma).
func top_h() -> float:
	match posture:
		Posture.CROUCH:
			return Config.SOLDIER_TOP_CROUCH
		Posture.PRONE:
			return Config.SOLDIER_TOP_PRONE
	return Config.SOLDIER_TOP_STAND


## Rol según el lugar en la escuadra: 0 jefe, 1 ametralladora, 2 proveedor, 3 antitanque, el resto fusileros.
static func role_for(i: int) -> int:
	match i:
		0:
			return Role.LEADER
		1:
			return Role.MG
		2:
			return Role.ASSISTANT
		3:
			return Role.AT
	return Role.RIFLE
