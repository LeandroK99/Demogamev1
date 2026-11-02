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
const HULLDOWN_HIT_FACTOR: float = 0.35 # si el casco del blanco no es visible
const MOVING_SHOOTER_FACTOR: float = 0.4 # si el que dispara se mueve
const EXPOSURE_WEIGHT_K: float = 8.0 # peso de la exposición en el costo del A*
const HULLDOWN_RADIUS: int = 15 # celdas de búsqueda de candidatos
const MAX_TURNS: int = 12 # al llegar, gana el bando con más tanques vivos

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
