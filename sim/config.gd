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

# --- Orden hull-down e IA ---
const HULLDOWN_MIN_SEPARATION: float = 3.0 # celdas mínimas entre destinos de una misma orden
const NO_THREAT_ADVANCE: int = 20 # celdas hacia el centro si no hay amenazas conocidas
const AI_RETREAT_RADIUS: int = 10 # celdas de búsqueda para retroceder con hp == 1
const AI_CREST_SEARCH_DEPTH: int = 50 # celdas hacia adelante para buscar la cresta
const AI_CREST_PROBE_DIST: int = 20 # observador hipotético a esta distancia delante de la cresta
const AI_CREST_CAND_RADIUS: int = 6 # radio de candidatos alrededor de la cresta
