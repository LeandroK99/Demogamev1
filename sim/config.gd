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
