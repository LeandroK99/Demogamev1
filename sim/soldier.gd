class_name Soldier
extends RefCounted
## Un soldado de una escuadra. La escuadra (Unit de infantería) tiene la orden, la ruta y la moral;
## el soldado tiene su posición en metros, su postura, su estado y su supresión.

enum Posture { STAND, CROUCH, PRONE }
## Evacuando: herido (o camillero) que va hacia atrás; evacuado: fuera del campo.
enum State { OK, WOUNDED, DEAD, EVACUATING, EVACUATED }
## Jefe, fusilero, ametralladorista, proveedor, tirador antitanque y médico (reemplaza a un fusilero).
enum Role { LEADER, RIFLE, MG, ASSISTANT, AT, MEDIC }

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
## Sistema médico (fases 45–47)
var bleed_left: float = 0.0 # herido sin estabilizar: segundos hasta morir desangrado
var stabilized: bool = false # herido estabilizado: ya no se desangra
var care_target: int = -1 # índice del herido de su escuadra que está atendiendo (-1 = ninguno)
var care_time: float = 0.0 # segundos que lleva atendiéndolo
var drag_target: int = -1 # rescate: índice del herido que va a buscar y arrastrar a cubierto
var drag_dest: Vector2 = Vector2.ZERO # adónde lo arrastra
var dragged: bool = false # herido al que están arrastrando
var evac_left: float = 0.0 # evacuando: segundos hasta salir del campo
var evac_wounded: bool = false # evacuando: es el herido (si no, el camillero)
## Avance (dispersión y carreras)
var jitter: Vector2 = Vector2.ZERO # corrimiento de su lugar en la formación (x a la derecha, y hacia atrás)
var rush_until: int = 0 # bajo fuego: tick en que termina su carrera (0 = no está corriendo)
var down_until: int = 0 # bajo fuego: tick hasta el que queda tirado entre carreras
## Munición (fase 48): tiros (fusil) o ráfagas (ametralladora) que le quedan; el proveedor carga extra.
var ammo: int = 0
var ammo_carry: int = 0
## Granadas (fase 49): de mano, y las del fusil lanzagranadas si es el granadero.
var grenades: int = 0
var gl_rounds: int = 0
## Sectores (fase 55): dirección y semiancho del sector del soldado (cero = sin sector); la
## ametralladora tiene además su línea final de tiro rasante.
var sector_dir: Vector2 = Vector2.ZERO
var sector_half_deg: float = 0.0
var fpl_dir: Vector2 = Vector2.ZERO
var dig_time: float = 0.0 # segundos cavando en su lugar (fase 57)
var bursts_here: int = 0 # ráfagas desde su posición actual (la ametralladora cambia de lugar)
var avoid_pos: Vector2 = Vector2(-1.0, -1.0) # posición que dejó por estar ubicada
var route: PackedVector2Array = PackedVector2Array() # con casas: puntos por los que va (fase 60)
var route_goal: Vector2 = Vector2.ZERO # destino para el que se armó la ruta
var slot_goal: Vector2 = Vector2.ZERO # su lugar en la formación, corrido afuera de una casa ajena
var has_slot_goal: bool = false
var post_pos: Vector2 = Vector2(-1.0, -1.0) # puesto fijo (la ametralladora en la aspillera, fase 63)
var unreachable: bool = false # no hay ruta a su lugar: la escuadra no lo espera
var marksman: bool = false # tirador selecto (fase 54): fusil con mira, ve y tira más lejos


func _init(p_index: int, p_role: int, p_pos: Vector2) -> void:
	index = p_index
	role = p_role
	pos = p_pos
	team = team_of(p_index)
	ammo = max_ammo(p_role)
	if p_role == Role.ASSISTANT:
		ammo_carry = Config.AMMO_ASSISTANT_CARRY
	grenades = 0 if p_role == Role.MG else Config.GRENADES_PER_SOLDIER
	if p_index == Config.GRENADIER_INDEX:
		gl_rounds = Config.GL_ROUNDS
	marksman = p_index == Config.MARKSMAN_INDEX


## Equipo de fuego del soldado i.
static func team_of(i: int) -> int:
	return 0 if i in [1, 2, 4, 6] else 1


func is_ok() -> bool:
	return state == State.OK


## Herido que se está desangrando.
func is_bleeding() -> bool:
	return state == State.WOUNDED and not stabilized


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


## Munición llena según el rol (el antitanque usa las cargas de la escuadra, y su fusil).
static func max_ammo(r: int) -> int:
	return Config.AMMO_MG if r == Role.MG else Config.AMMO_RIFLE


func ammo_fraction() -> float:
	return float(ammo) / float(max_ammo(role))


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
		Config.MEDIC_INDEX:
			return Role.MEDIC
	return Role.RIFLE
