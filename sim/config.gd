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
