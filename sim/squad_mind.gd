class_name SquadMind
extends RefCounted
## La cabeza de una escuadra: qué está haciendo por su cuenta (la opción actual), con qué
## autonomía y qué orden del jugador guardó para retomarla. La lógica que puntúa y ejecuta
## las opciones está en MindSim; acá queda el estado y la regla para cambiar de opción.

## FOLLOW cumple la orden del jugador; las demás son decisiones propias.
enum Option { FOLLOW, CONTACT_DRILL, RELOCATE, AMBUSH, BREAK_CONTACT, BOUND, FLANK, RESCUE }
## Estricta: solo cumple la orden. Normal: reacciona (drill, reubicarse, emboscar, rescatar).
## Alta: además maniobra (saltos, flanqueo) y rompe el contacto sola.
enum Autonomy { STRICT, NORMAL, HIGH }

## Para la radio y el HUD.
const OPTION_NAMES: Array[String] = ["sigue la orden", "contacto", "se reubica", "emboscada",
	"rompe el contacto", "avanza por saltos", "flanquea", "rescata un herido"]
const AUTONOMY_NAMES: Array[String] = ["estricta", "normal", "alta"]

var autonomy: int = Autonomy.NORMAL
var option: int = Option.FOLLOW
var since_tick: int = 0 # tick global en que empezó la opción actual
var next_think_tick: int = 0
var hold: bool = false # la escuadra no avanza por su ruta (lo decidió ella)
## Orden del jugador guardada al salir de FOLLOW: {path, waypoints, order, final_heading, pace}.
var saved: Dictionary = {}
var rerouted: bool = false # la opción actual le cambió la ruta (al volver hay que rehacerla)
var data: Dictionary = {} # estado propio de la opción actual
var scores: Dictionary = {} # últimos puntajes (para el HUD y los tests)


func _init(p_autonomy: int = Autonomy.NORMAL) -> void:
	autonomy = p_autonomy


## ¿La autonomía deja elegir esa opción?
static func allowed(p_autonomy: int, opt: int) -> bool:
	match opt:
		Option.FOLLOW:
			return true
		Option.CONTACT_DRILL, Option.RELOCATE, Option.AMBUSH, Option.RESCUE:
			return p_autonomy >= Autonomy.NORMAL
	return p_autonomy >= Autonomy.HIGH


## Elige la opción: la de mayor puntaje (desempate: la primera del enum). Cambia de la actual solo
## si la nueva la supera por margin y la actual ya duró min_ticks (FOLLOW se deja en el acto); si la
## actual ya no figura en los puntajes, cambia sin esperar. Pura, para poder probarla.
static func choose(current: int, since: int, p_scores: Dictionary, now: int,
		margin: float = Config.MIND_SWITCH_MARGIN, min_ticks: int = Config.MIND_MIN_TICKS) -> int:
	var best: int = current
	var best_score: float = -INF
	for opt: int in Option.values():
		if p_scores.has(opt) and float(p_scores[opt]) > best_score:
			best = opt
			best_score = float(p_scores[opt])
	if best == current or best_score == -INF:
		return current
	if not p_scores.has(current):
		return best
	if current != Option.FOLLOW and now - since < min_ticks:
		return current
	return best if best_score > float(p_scores[current]) + margin else current


## El jugador (o el comandante) dio una orden nueva: se olvida de lo que hacía por su cuenta.
func reset(now: int) -> void:
	option = Option.FOLLOW
	since_tick = now
	hold = false
	saved = {}
	rerouted = false
	data = {}


func is_following() -> bool:
	return option == Option.FOLLOW


func option_name() -> String:
	return OPTION_NAMES[option]
