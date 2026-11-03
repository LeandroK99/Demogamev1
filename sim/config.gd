class_name Config
extends RefCounted
## Constantes ajustables de la simulación (ver docs/PLAN.md).

const GRID_SIZE: int = 96 # celdas por lado
const CELL_SIZE: float = 4.0 # metros por celda (mapa de 384 m)
const MAX_HEIGHT: float = 28.0 # metros
const SEED: int = 1337 # semilla del mapa y de la simulación
const TICK: float = 0.1 # segundos por tick
const TURN_SECONDS: float = 30.0 # duración de un turno (300 ticks)
const EYE_H: float = 2.4 # altura del ojo y la óptica del tanque
const HULL_H: float = 1.0 # altura del punto de casco
const CENTER_H: float = 1.6 # altura del centro de masa (para disparar)
const TANK_SPEED: float = 6.0 # m/s en llano
const SLOPE_SPEED_PENALTY: float = 0.5 # factor de velocidad en pendiente fuerte
const TANK_HP: int = 3 # impactos para destruir
const RELOAD_SECONDS: float = 7.0
const MAX_RANGE: float = 350.0 # metros
const P_HIT_BASE: float = 0.55
const HULLDOWN_HIT_FACTOR: float = 0.5 # si el casco del blanco no es visible (0,35 en el plan; subido en el ajuste de la fase 6)
const MOVING_SHOOTER_FACTOR: float = 0.4 # si el que dispara se mueve
const EXPOSURE_WEIGHT_K: float = 8.0 # peso de la exposición en el costo del A*
const HULLDOWN_RADIUS: int = 15 # celdas de búsqueda de candidatos
const MAX_TURNS: int = 12 # al llegar, gana el bando con más tanques vivos
const P_HIT_MAX: float = 0.95 # tope de la probabilidad de impacto

# --- Blindaje por ángulo ---
const ARMOR_FRONT_COS: float = 0.5 # coseno del semiángulo frontal (0,5 = ±60°); el trasero es el simétrico
const ARMOR_FRONT_FACTOR: float = 0.6 # multiplicador de impacto si el tirador está al frente del blanco
const ARMOR_FLANK_FACTOR: float = 1.0
const ARMOR_REAR_FACTOR: float = 1.4

# --- Infantería ---
const INF_MEN: int = 9 # hombres por escuadra
const INF_EYE_H: float = 1.7 # altura del ojo de pie
const INF_STAND_H: float = 1.0 # perfil de una escuadra de pie (agachada, en movimiento)
const INF_PRONE_H: float = 0.4 # perfil cuerpo a tierra
const INF_CENTER_FRACTION: float = 0.6 # fracción del perfil a la que se apunta
const INF_SPEED: float = 1.5 # m/s en llano
const INF_MAX_SLOPE: float = 8.0 # metros; la infantería sube pendientes que el tanque no
const INF_PRONE_SECONDS: float = 3.0 # quieta este tiempo, se tira cuerpo a tierra
const INF_SPOT_MOVING: float = 250.0 # metros: alcance para detectar a una escuadra en movimiento (o que dispara)
const INF_SPOT_STILL: float = 120.0 # ... quieta de pie
const INF_SPOT_PRONE: float = 60.0 # ... cuerpo a tierra

# --- Armas cruzadas (el cañón usa MAX_RANGE, RELOAD_SECONDS y P_HIT_BASE) ---
const COAX_RANGE: float = 300.0 # metros
const COAX_RELOAD: float = 2.0 # segundos entre ráfagas
const COAX_P_HIT: float = 0.3
const RIFLES_RANGE: float = 300.0
const RIFLES_RELOAD: float = 2.5
const RIFLES_P_HIT: float = 0.3
const AT_RANGE: float = 150.0
const AT_RELOAD: float = 10.0
const AT_P_HIT: float = 0.5
const INF_AT_CHARGES: int = 2
const INF_PRONE_HIT_FACTOR: float = 0.5 # contra una escuadra cuerpo a tierra
const INF_WEAK_MEN: int = 3 # con estos hombres o menos, la escuadra tira peor
const INF_WEAK_FACTOR: float = 0.5

# --- Cobertura fina ---
const COVER_FOREST: float = 0.4 # cobertura para la infantería (0..1)
const COVER_WALL: float = 0.6
const COVER_PIT: float = 0.7
const COVER_SPOT_FACTOR: float = 0.5 # la cobertura achica la detección de infantería en cobertura x esto
const FOREST_TREE_H: float = 10.0 # metros: altura de los árboles para la línea de visión
const FOREST_LOS_CELLS: float = 2.0 # celdas de bosque que la línea de visión atraviesa antes de cortarse
const FOREST_TANK_SPEED: float = 0.5 # multiplicador de velocidad del tanque en el bosque
const FOREST_TANK_PATH_COST: float = 1.0 # costo extra del A* del tanque por celda de bosque
const COVER_W_TAKE_POSITION: float = 2.0 # peso de la cobertura al tomar posición (infantería)
const COVER_DEPLOY_CLEAR: int = 4 # celdas libres de cobertura más allá del margen de despliegue
const FOREST_COUNT: int = 7
const FOREST_R_MIN: float = 3.0 # celdas
const FOREST_R_MAX: float = 6.0
const WALL_COUNT: int = 6
const WALL_LEN_MIN: int = 5
const WALL_LEN_MAX: int = 10
const PIT_COUNT: int = 25

# --- Supresión y moral ---
const SUPP_CANNON: float = 30.0 # supresión por disparo recibido, según el arma
const SUPP_COAX: float = 25.0
const SUPP_RIFLES: float = 20.0
const SUPP_AT: float = 30.0
const SUPP_HIT_MULT: float = 1.5 # si además impacta
const SUPP_NEAR_RADIUS: float = 2.0 # celdas: las unidades del blanco a esta distancia reciben la mitad
const SUPP_DECAY: float = 5.0 # por segundo, pasados SUPP_DECAY_DELAY sin fuego
const SUPP_DECAY_DELAY: float = 2.0
const SUPPRESSED: float = 50.0 # desde acá la escuadra no avanza, tira a la mitad y se tira al suelo
const PINNED: float = 85.0 # desde acá no tira
const SUPPRESSED_FIRE_FACTOR: float = 0.5
const TANK_BUTTONED_SPOT_FACTOR: float = 0.5 # tanque con supresión alta (abotonado): ve a esta fracción
const MORALE_PER_CASUALTY: float = 8.0
const MORALE_SUPP_DRAIN: float = 0.3 # por segundo mientras está suprimida
const MORALE_RECOVER_PER_TURN: float = 15.0 # al terminar el turno sin estar suprimida
const MORALE_BREAK: float = 25.0 # por debajo, se quiebra
const MORALE_RALLY: float = 40.0 # quebrada, se recupera al llegar a esto
const SUPPRESS_AREA_RADIUS: float = 3.0 # celdas: zona que bate la orden suprimir
const SUPPRESS_AREA_SUPP: float = 0.7 # fracción de la supresión del arma que recibe cada unidad en la zona
const SUPPRESS_AREA_HIT_FACTOR: float = 0.2 # el fuego de área casi no mata

# --- Escenario "La loma" (infantería + tanque contra infantería + tanque) ---
const LOMA_SQUADS: int = 3 # escuadras por bando
const LOMA_TANKS: int = 1 # tanques por bando
const LOMA_TURN_SECONDS: float = 45.0
const LOMA_SQUAD_SPACING: int = 7 # celdas entre unidades al desplegar
const LOMA_RED_BEHIND_CREST: int = 4 # celdas detrás del eje de la cresta donde despliega el rojo
const LOMA_FOREST_FROM: int = 3 # bosque de la contrapendiente: de esta distancia detrás del eje...
const LOMA_FOREST_TO: int = 8 # ... hasta esta
const LOMA_FOREST_X_STEP: int = 18 # celdas entre manchas de bosque a lo largo de la cresta
const LOMA_FOREST_HALF_W: int = 6 # medio ancho (en x) de cada mancha
const LOMA_OBJECTIVE_RADIUS: float = 8.0 # celdas alrededor del centro de la cresta que hay que ocupar
const TANK_SUPPORT_BACK: float = 12.0 # celdas: el tanque de un pelotón mixto se queda esto detrás de la infantería

# --- IA de infantería ---
const AI_INF_AMBUSH_RANGE: float = 150.0 # metros: la escuadra roja no abre fuego más lejos si no la atacaron
const AI_INF_POSITION_RADIUS: int = 6 # celdas para buscar cobertura alrededor de la escuadra
const AI_INF_W_COVER: float = 3.0 # puntaje de la cobertura al elegir posición
const AI_INF_W_VIEW: float = 2.0 # puntaje de ver hacia adelante (o a las amenazas)
const AI_DEPTH_FORWARD: Vector2i = Vector2i(-6, 0) # defensa en profundidad de la loma: celdas desde el objetivo
const AI_DEPTH_MAIN: Vector2i = Vector2i(6, -5) # (x al costado; y hacia atrás, del lado rojo)...
const AI_DEPTH_RESERVE: Vector2i = Vector2i(0, -12)
const AI_DEPTH_ANCHOR_SLACK: int = 3 # más lejos que esto de su lugar, la escuadra vuelve
const AI_MONITOR_TICKS: int = 20 # durante la ejecución, el comandante rojo mira la situación cada 2 s
const AI_PRESSED_SECONDS: float = 10.0 # adelantada frenada este tiempo (o diezmada): se repliega
const AI_PRESSED_ENEMY_M: float = 50.0 # ... o con un enemigo a menos de esto
const AI_REINFORCE_FIRED_SECONDS: float = 10.0 # una escuadra a la que le tiraron hace menos pide refuerzo
const AI_FRESH_MEN: int = 5 # una escuadra con al menos estos hombres y poca supresión está fresca
const AI_COUNTER_RADIUS: float = 12.0 # celdas: azules a esta distancia del objetivo cuentan para el contraataque
const AI_COUNTER_FROM: float = 25.0 # celdas: la escuadra que contraataca está a menos de esto del objetivo
const AI_INF_SUPPRESS_MAX: float = 30.0 # suprime una zona solo si su propia supresión es menor

# --- Microcobertura (1 m) ---
const MICRO_PER_CELL: int = 4 # micro-celdas por lado de cada celda de 4 m (1 m cada una)
const MICRO_ROCK_H: float = 0.6 # metros: tapa a un soldado cuerpo a tierra, no agachado
const MICRO_CRATER_DEPTH: float = 0.5 # metros: el que está adentro queda más bajo
const MICRO_WALL_H: float = 1.0 # tapa a uno agachado
const MICRO_BUSH_H: float = 1.2 # oculta, no protege
const MICRO_TRUNK_P: float = 0.5 # probabilidad de un tronco por celda de bosque
const MICRO_EDGE_BUSHES: int = 2 # arbustos por celda de borde de bosque
const MICRO_ROCK_CLUSTERS: int = 60
const MICRO_ROCKS_MIN: int = 3
const MICRO_ROCKS_MAX: int = 6
const MICRO_CRATERS: int = 40
const MICRO_LOS_STEP: float = 0.5 # metros entre muestras de microcobertura en la línea de visión
const MICRO_NEAR_M: float = 15.0 # solo se mira la microcobertura a esta distancia de cada extremo
const MICRO_SELF_M: float = 0.8 # la micro-celda propia (y la del blanco) no tapa

# --- Soldados ---
const SOLDIER_EYE_STAND: float = 1.7 # altura del ojo según la postura
const SOLDIER_EYE_CROUCH: float = 1.1
const SOLDIER_EYE_PRONE: float = 0.4
const SOLDIER_CENTER_STAND: float = 1.2 # altura del centro del cuerpo
const SOLDIER_CENTER_CROUCH: float = 0.8
const SOLDIER_CENTER_PRONE: float = 0.25
const SOLDIER_TOP_STAND: float = 1.8 # altura de la cabeza
const SOLDIER_TOP_CROUCH: float = 1.2
const SOLDIER_TOP_PRONE: float = 0.45
const SOLDIER_SPACING: float = 3.0 # metros entre soldados en la formación
const SOLDIER_CATCHUP: float = 1.3 # el soldado puede ir a esta fracción de la velocidad de la escuadra para alcanzarla
const SOLDIER_LAG_M: float = 6.0 # si alguno queda más lejos que esto de su lugar, la escuadra lo espera
const SOLDIER_TELEPORT_M: float = 40.0 # más lejos que esto de su lugar, el soldado se reubica de golpe (escuadra movida a mano)
const SOLDIER_ARRIVE_M: float = 0.3 # a esta distancia de su lugar ya llegó
const SOLDIER_WOUND_P: float = 0.5 # un impacto hiere (si no, mata); herido otra vez, muere

# --- Cobertura de cada soldado ---
const SOLDIER_COVER_SEARCH_M: float = 6.0 # radio alrededor de su lugar en la formación
const SOLDIER_COVER_PROBE_M: float = 2.5 # busca el obstáculo que lo protege hasta esta distancia hacia la amenaza
const SOLDIER_COVER_SPACING: float = 2.0 # metros mínimos entre puntos de cobertura de la misma escuadra
const SOLDIER_COVER_W_PROTECT: float = 3.0 # puntaje: protegido del fuego
const SOLDIER_COVER_W_FIRE: float = 2.0 # puntaje: puede tirar hacia la amenaza
const SOLDIER_COVER_W_FIRE_MG: float = 4.0 # la ametralladora prioriza poder tirar
const SOLDIER_COVER_W_CONCEAL: float = 1.0 # puntaje: oculto por un arbusto
const SOLDIER_COVER_W_DIST: float = 1.5 # castigo por alejarse de su lugar (a SOLDIER_COVER_SEARCH_M)
const SOLDIER_COVER_LOS_CHECKS: int = 6 # líneas de visión largas por soldado al elegir (las mejores candidatas)
const SOLDIER_COVER_REEVAL_DEG: float = 30.0 # si la amenaza se corre más que esto, se vuelve a buscar
const SOLDIER_NO_THREAT_M: float = 200.0 # sin amenazas conocidas, cubre hacia adelante a esta distancia

# --- Visión de cada soldado ---
const SOLDIER_OBSERVERS: int = 3 # soldados por escuadra que miran en cada detección (el jefe y dos que rotan)
const SOLDIER_HEAD_M: float = 0.1 # se lo detecta si se le ve hasta esto por debajo de la cabeza
const SOLDIER_PROTECTED_SPOT_FACTOR: float = 0.6 # quieto detrás de algo que lo protege, se lo detecta más cerca
const SOLDIER_PAIR_MARGIN_M: float = 30.0 # escuadras más lejos que el alcance más esto ni se miran

# --- Fuego de cada soldado ---
const SOLDIER_RIFLE_P_HIT: float = 0.05 # por tiro de fusil a un soldado de pie, quieto y al descubierto, a quemarropa
const SOLDIER_RIFLE_RELOAD: float = 2.5 # segundos entre tiros (con un azar de ±25 %)
const SOLDIER_MG_RANGE: float = 350.0
const SOLDIER_MG_RELOAD: float = 1.5 # entre ráfagas
const SOLDIER_MG_P_HIT: float = 0.10 # por soldado dentro de la ráfaga
const SOLDIER_COAX_P_HIT: float = 0.12 # ráfaga de la coaxial, por soldado dentro
const SOLDIER_BURST_M: float = 3.0 # radio de una ráfaga alrededor del punto apuntado
const SOLDIER_CROUCH_HIT_FACTOR: float = 0.75 # contra un soldado agachado (cuerpo a tierra: INF_PRONE_HIT_FACTOR)
const SOLDIER_COVER_HIT_FACTOR: float = 0.2 # contra uno protegido por un obstáculo o el terreno
const SOLDIER_TARGET_SPREAD: int = 5 # los tiradores de una escuadra se reparten entre estos blancos más cercanos
const SOLDIER_TARGET_CHECKS: int = 3 # líneas de visión por soldado al elegir blanco (los más cercanos)
const SOLDIER_SHOT_SUPP_SCALE: float = 0.12 # fuego de área de un soldado: fracción de la supresión del arma a cada escuadra

# --- Supresión de cada soldado ---
const SOLDIER_SUPP_RIFLE: float = 8.0 # supresión de un tiro de fusil al soldado al que apuntó
const SOLDIER_SUPP_BURST: float = 15.0 # ... de una ráfaga (ametralladora o coaxial)
const SOLDIER_SUPP_NEAR_M: float = 5.0 # los soldados a esta distancia del tiro reciben la mitad
const SOLDIER_SUPP_COVER_FACTOR: float = 0.6 # protegido, recibe esta fracción
const SOLDIER_SUPP_HALT: float = 0.5 # con más de esta fracción de soldados clavados, la escuadra no avanza (la orden pesa más que la supresión)
const MORALE_LEADER_LOSS: float = 10.0 # baja extra de moral si cae el jefe
const SUPP_MG: float = 25.0 # supresión de una ráfaga de ametralladora

# --- Autonomía de las escuadras ---
const MIND_THINK_TICKS: int = 10 # ticks entre decisiones de una escuadra (jefe regular)
const MIND_SWITCH_MARGIN: float = 0.5 # una opción nueva tiene que superar a la actual por esto
const MIND_MIN_TICKS: int = 100 # una decisión propia dura al menos esto (10 s) salvo que deje de valer
const MIND_FOLLOW_SCORE: float = 1.0 # puntaje de seguir la orden del jugador
const MIND_AUTONOMY_BLUE: int = 1 # SquadMind.Autonomy.NORMAL
const MIND_AUTONOMY_RED: int = 2 # SquadMind.Autonomy.HIGH
const RADIO_LOG_MAX: int = 40 # mensajes de radio que se guardan
const MIND_THINK_TICKS_VETERAN: int = 5 # un jefe veterano piensa cada medio segundo...
const MIND_THINK_TICKS_GREEN: int = 20 # ... uno novato, cada dos
const MIND_NOISE_VETERAN: float = 0.0 # error al puntuar las opciones (± esto)
const MIND_NOISE_REGULAR: float = 0.1
const MIND_NOISE_GREEN: float = 0.25
const MIND_LOMA_QUALITY: Array[int] = [1, 0, 2] # calidad de las escuadras de la loma: regular, veterano, novato
const LEADERLESS_MIN_SECONDS: float = 20.0 # cae el jefe: la escuadra queda desorganizada entre esto...
const LEADERLESS_MAX_SECONDS: float = 30.0 # ... y esto, y después el segundo toma el mando
const DRILL_SCORE: float = 3.0 # puntaje del drill de contacto
const DRILL_FIRED_SECONDS: float = 3.0 # le tiraron hace menos que esto: contacto
const DRILL_SPOT_M: float = 200.0 # ve a un enemigo nuevo a menos que esto: contacto
const DRILL_COVER_M: float = 4.0 # en el drill, cada uno busca cobertura a esta distancia de su lugar
const DRILL_CALM_SUPP: float = 25.0 # retoma la marcha con la supresión media por debajo de esto...
const DRILL_CALM_SECONDS: float = 5.0 # ... durante este tiempo
const DRILL_REACT_SECONDS: float = 5.0 # con orden de avanzar, la reacción al contacto dura esto y sigue por fuego y movimiento
const DRILL_COOLDOWN_SECONDS: float = 30.0 # tras una reacción corta, no vuelve a frenar por contacto hasta pasado esto
const DRILL_STAY_FRACTION: float = 0.5 # salvo que haya perdido más de esta fracción de los hombres: entonces se queda
const RELOCATE_SCORE: float = 2.5 # puntaje base de reubicarse (más la fracción al descubierto)
const RELOCATE_FIRED_SECONDS: float = 5.0 # solo si le tiraron hace menos que esto
const RELOCATE_EXPOSED: float = 0.5 # fracción de soldados al descubierto desde la que se reubica
const RELOCATE_RADIUS: int = 5 # celdas (20 m) para buscar una posición mejor
const RELOCATE_W_DEFILADE: float = 3.0 # el terreno la tapa de la amenaza
const RELOCATE_W_COVER: float = 2.0 # cobertura de la celda (bosque, muro, pozo)
const RELOCATE_W_MICRO: float = 1.0 # hay microcobertura cerca
const RELOCATE_MIN_GAIN: float = 1.0 # la nueva celda tiene que ser al menos esto mejor que la actual
const AMBUSH_SCORE: float = 2.0
const AMBUSH_FIRE_M: float = 100.0 # en emboscada retiene el fuego hasta que el enemigo esté a esto
const AMBUSH_WATCH_M: float = 300.0 # contactos a menos de esto la ponen en emboscada
const AMBUSH_QUIET_SECONDS: float = 30.0 # solo si no tiró ni le tiraron en este tiempo
const BREAK_SCORE: float = 4.0 # romper el contacto
const BREAK_MEN: int = 3 # con estos hombres o menos rompe el contacto (solo diezmada de verdad)
const BREAK_MORALE: float = 40.0
const BREAK_HALTED_SECONDS: float = 20.0 # o si lleva esto frenada por la supresión
const BREAK_CALM_SECONDS: float = 10.0 # ya replegada, sin fuego este tiempo, deja de romper el contacto
const BOUND_SCORE: float = 2.0 # avanzar por saltos de equipo
const BOUND_CONTACT_M: float = 250.0 # con un contacto a menos de esto, avanza por saltos
const BOUND_M: float = 25.0 # largo de cada salto del equipo que maniobra
const BOUND_SMOKE_FIRED_SECONDS: float = 5.0 # al arrancar los saltos bajo fuego, humo para cubrir el avance
const RUSH_FIRED_SECONDS: float = 10.0 # bajo fuego reciente, los que avanzan lo hacen a carreras cortas
const RUSH_MIN_SECONDS: float = 3.0 # cada carrera dura entre esto...
const RUSH_MAX_SECONDS: float = 5.0
const RUSH_DOWN_MIN_SECONDS: float = 2.0 # ... y después se tira entre esto...
const RUSH_DOWN_MAX_SECONDS: float = 3.0
const RUSH_SPEED: float = 1.6 # en la carrera, más rápido que la marcha
const JITTER_M: float = 3.5 # cada soldado anda corrido hasta esto de su lugar en la formación
const JITTER_REROLL_M: float = 15.0 # cada tanto que avanza el ancla, se reacomoda
const JITTER_TRIES: int = 6 # puntos que prueba al reacomodarse (prefiere los pegados a una roca, arbusto o tronco)
const JITTER_SEPARATION_M: float = 1.5 # sin pegarse a los demás
const FLANK_SCORE: float = 2.2
const FLANK_BASE_M: float = 200.0 # otra escuadra propia tirando a menos de esto del contacto hace de base de fuego
const FLANK_BASE_FIRED_SECONDS: float = 5.0 # ... si tiró hace menos que esto
const FLANK_QUIET_SECONDS: float = 10.0 # flanquea solo si a ella no le tiraron en este tiempo
const FLANK_MAX_M: float = 300.0 # contactos más lejos que esto no los flanquea
const FLANK_OFFSET_M: float = 60.0 # el punto de flanqueo, a esto del contacto, de costado

# --- Conocimiento de cada escuadra y radio ---
const CONTACT_OWN_M: float = 150.0 # lo que la escuadra ve a menos de esto lo sabe en el acto y exacto
const CONTACT_FLASH_ERROR: float = 0.1 # el fogonazo de un tirador que no ve: error de esta fracción de la distancia
const CONTACT_FORGET_SECONDS: float = 60.0 # un contacto sin noticias nuevas se olvida
const RADIO_DELAY_MIN: float = 3.0 # segundos que tarda un contacto en llegar por radio a otra escuadra
const RADIO_DELAY_MAX: float = 5.0
const RADIO_REPORT_SECONDS: float = 30.0 # un bando no vuelve a anunciar el mismo contacto antes de esto

# --- Sistema médico ---
const BLEED_MIN_SECONDS: float = 90.0 # un herido sin atender se desangra entre esto...
const BLEED_MAX_SECONDS: float = 240.0 # ... y esto
const MORALE_BLEEDING_DRAIN: float = 0.1 # por segundo y por herido que se desangra (la escuadra lo oye)
const MORALE_BLED_OUT: float = 5.0 # baja de moral cuando uno se muere desangrado
const MEDIC_INDEX: int = 8 # el soldado 9 es el médico (en lugar de un fusilero)
const MEDIC_STABILIZE_SECONDS: float = 15.0 # lo que tarda el médico en estabilizar a un herido...
const BUDDY_STABILIZE_SECONDS: float = 40.0 # ... y un compañero sin entrenamiento
const CARE_REACH_M: float = 1.0 # a esta distancia del herido ya lo puede atender
const RESCUE_SCORE: float = 3.5 # rescatar a un herido al descubierto
const RESCUE_FIRED_SECONDS: float = 10.0 # solo bajo fuego reciente (si no, alcanza con atenderlo)
const RESCUE_SEARCH_M: float = 10.0 # busca adónde arrastrarlo a esta distancia
const DRAG_SPEED: float = 0.6 # m/s arrastrando a un herido
const EVAC_SPEED: float = 0.8 # m/s del herido y el camillero hacia atrás
const EVAC_SECONDS: float = 60.0 # a los que evacúan les toma esto salir del campo
const MORALE_EVAC: float = 5.0 # la escuadra recupera moral por cada herido evacuado

# --- Reflejos del soldado ---
const REFLEX_DIVE_SUPP: float = 8.0 # un tiro que le suma esto en marcha y al descubierto lo tira al suelo
const REFLEX_DIVE_SECONDS: float = 2.0 # ... por este tiempo
const REFLEX_INCOMING_SECONDS: float = 4.0 # un tiro recibido cuenta para revisar la cobertura este tiempo
const REFLEX_PEEK_RADIUS_M: float = 3.0 # busca desde dónde asomar a esta distancia de su cobertura
const REFLEX_PEEK_LOS_CHECKS: int = 3 # líneas de visión para encontrar ese punto
const REFLEX_PEEK_FIRE_SECONDS: float = 5.0 # asomado tirando
const REFLEX_PEEK_HIDE_SECONDS: float = 6.0 # de vuelta a cubierto
const INF_SMOKE_CHARGES: int = 2 # granadas de humo de mano por escuadra
const INF_SMOKE_SUPPRESSED_SECONDS: float = 15.0 # frenada por la supresión este tiempo, tira humo
const INF_SMOKE_DIST_M: float = 15.0 # metros hacia la amenaza donde cae la granada
const INF_SMOKE_RADIUS: float = 2.0 # celdas
const INF_SMOKE_HEIGHT: float = 4.0 # metros sobre el terreno
const INF_SMOKE_SECONDS: float = 40.0 # lo que dura la nube de mano

# --- Generación del terreno ---
const NOISE_FREQUENCY: float = 0.02 # frecuencia del Simplex
const NOISE_OCTAVES: int = 3
const NOISE_WEIGHT: float = 0.3 # aporte del ruido (0..1 de MAX_HEIGHT)
const RIDGE_MIN_H: float = 0.5 # altura mínima de la cresta central (fracción de MAX_HEIGHT)
const RIDGE_MAX_H: float = 0.7 # altura máxima de la cresta central
const RIDGE_WIDTH: float = 6.0 # celdas; a esta distancia del eje la cresta vale ~37 %
const RIDGE_TILT: float = 0.2 # pendiente de la diagonal (celdas en y por celda en x)
const RIDGE_WAVE_AMP: float = 4.0 # ondulación sinusoidal del eje, en celdas
const MINOR_HILL_H_MIN: float = 0.2
const MINOR_HILL_H_MAX: float = 0.35
const MINOR_HILL_R_MIN: float = 5.0 # celdas
const MINOR_HILL_R_MAX: float = 8.0

# --- Línea de visión y exposición ---
const LOS_STEP: float = 0.5 # celdas entre muestras de la recta
const LOS_EPSILON: float = 0.05 # margen en metros para considerar que el terreno tapa
const HULLDOWN_MAX_SLOPE: float = 3.0 # metros; celdas más empinadas no son candidatas
const HULLDOWN_W_HIDDEN: float = 3.0 # peso de "casco oculto" en el puntaje
const HULLDOWN_W_FIRE: float = 2.0 # peso de "puede disparar" en el puntaje
const HULLDOWN_DIST_DIV: float = 10.0 # celdas de distancia que restan 1 punto

# --- Unidades y movimiento ---
const UNITS_PER_SIDE: int = 4
const DEPLOY_SPACING: int = 8 # celdas entre tanques al desplegar
const DEPLOY_EDGE_MARGIN: int = 6 # celdas desde el borde del mapa
const SECTIONS_PER_PLATOON: int = 2 # el pelotón de cada bando se reparte en estas secciones
const FORMATION_GAP: int = 3 # celdas entre tanques de una misma sección (o de una selección suelta)
const SECTION_GAP: int = 10 # celdas entre los centros de las secciones de un pelotón
const PATH_MAX_SLOPE: float = 4.0 # metros; celdas más empinadas son intransitables
const PATH_SLOPE_COST: float = 1.0 # costo extra en el A* a pendiente máxima

# --- Detección ---
const DETECTION_INTERVAL_TICKS: int = 5 # cada cuántos ticks se recalcula quién ve a quién
const SPOT_RANGE_STATIONARY: float = 220.0 # metros: alcance para detectar a un blanco quieto
const SPOT_RANGE_HULLDOWN: float = 150.0 # metros: blanco quieto con el casco oculto para el observador
const FIRE_REVEAL_SECONDS: float = 3.0 # tras disparar, se lo detecta a MAX_RANGE aunque esté quieto

# --- Vigilancia (overwatch) ---
const OVERWATCH_HALF_ANGLE_DEG: float = 35.0 # semiángulo del sector de tiro
const OVERWATCH_FIRST_SHOT_FACTOR: float = 1.5 # primer disparo del turno contra un blanco en movimiento

# --- Disparar y replegarse ---
const REVERSE_SPEED_FACTOR: float = 0.6 # velocidad en reversa (volviendo a cubierto mirando al enemigo)
const AI_SCOOT_RADIUS: int = 6 # celdas para buscar una posición de tiro desde la que asomar

# --- Humo ---
const SMOKE_CHARGES: int = 2 # granadas de humo por tanque
const SMOKE_RADIUS: float = 3.0 # celdas
const SMOKE_HEIGHT: float = 8.0 # metros sobre el terreno en el centro de la nube
const SMOKE_RANGE: float = 150.0 # metros: alcance del lanzador
const SMOKE_TURNS: int = 2 # turnos de ejecución que dura la nube
const AI_SMOKE_EXPOSURE: float = 0.5 # la IA tira humo al retroceder si su celda está más expuesta que esto
const AI_SMOKE_DIST: float = 5.0 # celdas hacia la amenaza donde la IA pone la nube

# --- Reglas de fuego (ROE) ---
const ROE_RETURN_FIRE_SECONDS: float = 15.0 # "solo si te disparan": queda liberado este tiempo tras recibir un disparo
const FIRE_ARC_HALF_ANGLE_DEG: float = 45.0 # semiángulo del arco de tiro
const AI_AMBUSH_RANGE: float = 250.0 # metros: la IA en vigilancia no tira más lejos que esto si no la atacaron

# --- Ritmo, asalto y retirada ---
const PACE_FAST_SPEED: float = 1.4 # multiplicador de velocidad a ritmo rápido
const PACE_CAUTIOUS_SPEED: float = 0.5 # multiplicador de velocidad a ritmo cauto
const PACE_FAST_FIRE_FACTOR: float = 0.6 # se suma al de tirador en movimiento a ritmo rápido
const PACE_CAUTIOUS_FIRE_FACTOR: float = 0.75 # reemplaza al de tirador en movimiento a ritmo cauto
const WITHDRAW_RADIUS: int = 10 # celdas: dónde buscar cubierta al retirarse sin destino

# --- Vista previa de riesgo ---
const RISK_MEDIUM_HITS: float = 0.3 # impactos esperados en la ruta a partir de los que el riesgo es medio
const RISK_HIGH_HITS: float = 1.0 # ... y alto

# --- Orden hull-down e IA ---
const HULLDOWN_MIN_SEPARATION: float = 3.0 # celdas mínimas entre destinos de una misma orden
const NO_THREAT_ADVANCE: int = 20 # celdas hacia el centro si no hay amenazas conocidas
const AI_RETREAT_RADIUS: int = 10 # celdas de búsqueda para retroceder con hp == 1
const AI_CREST_SEARCH_DEPTH: int = 50 # celdas hacia adelante para buscar la cresta
const AI_CREST_PROBE_DIST: int = 20 # observador hipotético a esta distancia delante de la cresta
const AI_CREST_CAND_RADIUS: int = 6 # radio de candidatos alrededor de la cresta

# --- Munición y disciplina de fuego (fase 48) ---
const AMMO_RIFLE: int = 120 # tiros por fusilero (cada tiro del modelo es un par de disparos)
const AMMO_MG: int = 150 # ráfagas que lleva la ametralladora
const AMMO_ASSISTANT_CARRY: int = 150 # ráfagas extra que carga el proveedor para la ametralladora
const AMMO_PASS_M: float = 6.0 # el proveedor le pasa cintas a la ametralladora si está a esta distancia
const AMMO_PASS_PER_SECOND: int = 5 # ráfagas que pasa por segundo
const AMMO_PASS_BELOW: float = 0.5 # le pasa cuando a la ametralladora le queda menos de esta fracción
const AMMO_LOW_FRACTION: float = 0.25 # por debajo de esto, la escuadra tiene poca munición y dosifica
const FIRE_RAPID_RELOAD: float = 0.6 # fuego rápido: multiplica el tiempo entre tiros (asalto, suprimir, ritmo rápido)
const FIRE_CONSERVE_RELOAD: float = 1.5 # con poca munición: tira más espaciado

# --- Granadas de mano y granadero (fase 49) ---
const GRENADES_PER_SOLDIER: int = 2 # de fragmentación (la ametralladora no lleva)
const GRENADE_RANGE_M: float = 30.0 # alcance de la granada de mano
const GRENADE_MIN_M: float = 8.0 # más cerca no la tira: lo alcanzaría a él
const GRENADE_RADIUS_M: float = 5.0 # radio letal (ignora la protección frontal de rocas y muros)
const GRENADE_P_HIT: float = 0.6 # en el punto de la explosión; baja hacia el borde del radio
const GRENADE_PRONE_FACTOR: float = 0.6 # cuerpo a tierra o en un cráter, recibe menos esquirlas
const GRENADE_SUPP: float = 45.0 # supresión en el punto; la mitad al doble del radio
const GRENADE_FUSE_SECONDS: float = 2.5 # entre que la tira y explota
const GRENADE_THROW_SECONDS: float = 2.0 # el que la tira no hace otra cosa este tiempo
const GRENADE_SCATTER: float = 0.1 # error de puntería: fracción de la distancia
const GRENADE_FRIENDLY_M: float = 7.0 # no la tira si un propio queda a esta distancia de donde apunta
const GRENADIER_INDEX: int = 4 # el soldado 5 lleva el fusil lanzagranadas
const GL_ROUNDS: int = 8
const GL_RANGE: float = 150.0
const GL_MIN_M: float = 30.0
const GL_FLIGHT_SECONDS: float = 1.0
const GL_SCATTER: float = 0.05
const GL_RELOAD: float = 6.0

# --- Formación según terreno y escalón (fase 50) ---
const FORM_UPDATE_SECONDS: float = 1.0 # cada cuánto la escuadra revisa su formación en marcha
const FORM_SPREAD_OPEN: float = 2.0 # en terreno limpio la cuña se abre a esto por SOLDIER_SPACING (6 m)
const FORM_ROUGH_SLOPE: float = 2.0 # metros de desnivel con los vecinos: terreno quebrado, se cierra
const FORM_FOREST_NEAR: int = 2 # celdas: con bosque así de cerca se cierra
const FORM_LINE_ASSAULT_M: float = 60.0 # al asaltar, a esta distancia del objetivo forma en línea
const FORM_ECHELON_RANGE_M: float = 300.0 # contacto conocido a esta distancia y de costado: escalón
const FORM_ECHELON_MIN_DEG: float = 40.0 # ... a más de esto del rumbo (y a menos de 140°)
const FORM_SPREAD_STEP: float = 0.1 # cuánto se abre o se cierra por revisión (de a poco, para que nadie quede atrás)

# --- Técnicas de movimiento (fase 51) ---
const OVERWATCH_CONTACT_M: float = 600.0 # con un contacto conocido a esta distancia, desplazamiento con vigilancia
const OVERWATCH_TRAIL_M: float = 20.0 # el equipo A (con la ametralladora) va esto más atrás
const OVERWATCH_TRAIL_STEP: float = 2.0 # metros por revisión (de a poco)

# --- Emboscada cercana y lejana (fase 52) ---
const NEAR_AMBUSH_M: float = 35.0 # le tiran desde más cerca que esto (a distancia de granada): asalta
const NEAR_AMBUSH_FIRED_SECONDS: float = 2.0 # ... si le tiraron hace menos que esto
const NEAR_AMBUSH_SCORE: float = 4.0 # le gana a todo: en la zona de muerte no se piensa
const NEAR_AMBUSH_MAX_SECONDS: float = 25.0 # el asalto dura a lo sumo esto
const NEAR_AMBUSH_DONE_M: float = 6.0 # llegó a la posición del emboscador

# --- Reptar (fase 53) ---
const PACE_CRAWL_SPEED: float = 0.2 # multiplicador de velocidad reptando (0,3 m/s)
const CRAWL_AFTER_SECONDS: float = 3.0 # clavada en marcha este tiempo, la escuadra sigue reptando

# --- Tirador selecto (fase 54) ---
const MARKSMAN_INDEX: int = 6 # el soldado 7 lleva fusil con mira (equipo A)
const MARKSMAN_RANGE: float = 500.0
const MARKSMAN_P_HIT: float = 0.2 # por tiro contra un blanco quieto de pie y al descubierto, a quemarropa
const MARKSMAN_MOVING_FACTOR: float = 0.4 # contra un blanco en marcha
const MARKSMAN_RELOAD: float = 4.0 # segundos entre tiros (apunta)
const MARKSMAN_SPOT_FACTOR: float = 2.0 # con la mira ve a esto por el alcance normal
const MARKSMAN_PRIORITY: float = 0.25 # jefes y ametralladoras cuentan como así de cerca al elegir blanco

# --- Sectores, línea final y cambio de posición (fase 55) ---
const SECTOR_FRONT_DEG: float = 120.0 # frente que se reparten los soldados de una escuadra quieta
const SECTOR_OVERLAP_DEG: float = 10.0 # cada sector se pisa con el vecino
const SECTOR_OUT_RANK: float = 3.0 # un blanco fuera de su sector cuenta como así de más lejos
const SECTOR_RETHINK_DEG: float = 20.0 # se reparten de nuevo si la amenaza se corre más que esto
const SECTOR_DRAW_M: float = 40.0 # largo de los sectores en el mapa
const FPL_ANGLE_DEG: float = 25.0 # la línea final de la ametralladora cruza el frente oblicua
const FPL_WIDTH_M: float = 2.0 # tiro rasante: barre a los que están a esto de la línea
const FPL_GRAZE_FACTOR: float = 0.3 # a cada uno de ellos, esta fracción del impacto de la ráfaga
const FPL_RANK: float = 0.5 # la ametralladora prefiere blancos sobre su línea
const MG_DISPLACE_BURSTS: int = 3 # ráfagas desde el mismo lugar ya ubicada (le tiraron): se mueve
const MG_DISPLACE_FIRED_SECONDS: float = 5.0 # "ya la ubicaron": le tiraron hace menos que esto
const MG_DISPLACE_MIN_M: float = 3.0 # la nueva posición, al menos a esto de la anterior

# --- Cruzar una zona de peligro (fase 56) ---
const DANGER_MIN_CELLS: int = 4 # tramo abierto entre dos cubiertas de al menos esto (16 m)...
const DANGER_MAX_CELLS: int = 15 # ... y a lo sumo esto (60 m): un claro, un camino
const DANGER_SCORE: float = 2.5
const DANGER_FIRED_SECONDS: float = 10.0 # bajo fuego no: ahí avanza por saltos

# --- Pozos de tirador y consolidar (fase 57) ---
const DIG_SECONDS: float = 45.0 # quieto en su lugar este tiempo (un turno), el soldado cava un pozo
const DIG_MAX_SUPP: float = 50.0 # suprimido no cava

# --- Pelotón como un cuerpo y misión (fase 58) ---
const PLT_CONTACT_M: float = 300.0 # un contacto así de cerca de una escuadra del pelotón: la traba como base
const PLT_FIRED_SECONDS: float = 10.0 # ... o que le hayan tirado hace menos que esto
const PLT_FOLLOW_CELLS: int = 10 # las otras escuadras van esto detrás de la de punta
const PLT_SHIFT_M: float = 60.0 # el asalto a esto del enemigo: el apoyo levanta el fuego
const PLT_SHIFT_BEYOND_M: float = 50.0 # ... y lo corre más allá del objetivo
const PLT_FLANK_ARRIVE_CELLS: int = 3 # la maniobra llegó a su puesto de flanco
const PLT_FIX_MAX_SECONDS: float = 90.0 # flanqueando más que esto: asaltan desde donde estén
const PLT_ASSAULT_MAX_SECONDS: float = 135.0 # asaltando más que esto: todos al objetivo

# --- Contraataque local y rendición (fase 59) ---
const COUNTER_DUG_FRACTION: float = 0.5 # el atacante en el objetivo con menos de esto en pozos: todavía no se afirmó
const SURRENDER_ENEMY_M: float = 50.0 # quebrada, con el enemigo a menos de esto...
const SURRENDER_AFTER_SECONDS: float = 8.0 # ... quebrada hace más de esto ...
# ... y sin ruta de repliegue (clavada o sin camino): se rinde

# --- Edificios (fase 60) ---
const BUILDING_H: float = 3.0 # altura de las paredes hasta el techo
const WINDOW_SILL_H: float = 0.9 # la ventana deja ver y tirar entre el antepecho...
const WINDOW_TOP_H: float = 2.0 # ... y el dintel
const DOOR_H: float = 2.1 # la puerta (y el boquete) hasta acá
const BREACH_RUBBLE_H: float = 0.3 # escombros al pie de un boquete
const BUILDING_LOS_STEP: float = 0.5 # metros entre muestras de la línea de visión dentro de una casa
const BUILDING_WALK_STEP: float = 0.4 # ... y del camino recto de un soldado
const ROUTE_REPLAN_M: float = 2.0 # el destino del soldado se corrió esto: rehace la ruta por adentro
const ROUTE_ARRIVE_M: float = 0.4 # llegó a un punto de su ruta
