class_name SquadMind
extends RefCounted
## La cabeza de una escuadra: qué está haciendo por su cuenta (la opción actual), con qué
## autonomía y qué orden del jugador guardó para retomarla. La lógica que puntúa y ejecuta
## las opciones está en MindSim; acá queda el estado y la regla para cambiar de opción.

## FOLLOW cumple la orden del jugador; las demás son decisiones propias.
enum Option { FOLLOW, CONTACT_DRILL, RELOCATE, AMBUSH, BREAK_CONTACT, BOUND, FLANK, RESCUE, NEAR_AMBUSH, CROSS, CORNER }
## Estricta: solo cumple la orden. Normal: reacciona (drill, reubicarse, emboscar, rescatar).
## Normal también avanza por fuego y movimiento. Alta: además flanquea y rompe el contacto sola
## (solo diezmada de verdad).
enum Autonomy { STRICT, NORMAL, HIGH }
## Técnica de movimiento (fase 51): simple sin contactos, con vigilancia si el contacto es posible
## (un equipo va detrás cubriendo), por saltos si se espera (la opción BOUND).
enum Technique { TRAVEL, OVERWATCH, BOUNDING }
const TECHNIQUE_NAMES: Array[String] = ["simple", "con vigilancia", "por saltos"]
## Calidad del jefe: cada cuánto piensa y cuánto se equivoca al puntuar.
enum Quality { VETERAN, REGULAR, GREEN }

## Para la radio y el HUD.
const OPTION_NAMES: Array[String] = ["sigue la orden", "contacto", "se reubica", "emboscada",
	"rompe el contacto", "avanza por saltos", "flanquea", "rescata un herido", "asalta la emboscada", "cruza la zona de peligro", "corta la torta en la esquina"]
## Ícono de intención sobre la escuadra (vacío = cumple la orden).
const INTENT_SHORT: Array[String] = ["", "CONTACTO", "REUBICA", "EMBOSCADA", "SE REPLIEGA", "SALTOS", "FLANQUEA", "RESCATE", "ASALTO", "CRUZA", "ESQUINA"]
const AUTONOMY_NAMES: Array[String] = ["estricta", "normal", "alta"]
const QUALITY_NAMES: Array[String] = ["veterano", "regular", "novato"]

var autonomy: int = Autonomy.NORMAL
var quality: int = Quality.REGULAR
var disorganized_until: int = -1 # cayó el jefe: hasta este tick no piensa ni avanza
var option: int = Option.FOLLOW
var since_tick: int = 0 # tick global en que empezó la opción actual
var next_think_tick: int = 0
var hold: bool = false # la escuadra no avanza por su ruta (lo decidió ella)
## Orden del jugador guardada al salir de FOLLOW: {path, waypoints, order, final_heading, pace}.
var saved: Dictionary = {}
var rerouted: bool = false # la opción actual le cambió la ruta (al volver hay que rehacerla)
var data: Dictionary = {} # estado propio de la opción actual
var scores: Dictionary = {} # últimos puntajes (para el HUD y los tests)
var cover_m: float = Config.SOLDIER_COVER_SEARCH_M # radio en que cada soldado busca cobertura
var reacted: Dictionary = {} # enemigos (id) que ya provocaron un drill de contacto
## Lo que la escuadra sabe de los enemigos: id -> {pos (metros), tick, exact}. Lo propio cercano
## es exacto y al momento; el fogonazo de un tirador que no ve, aproximado; lo demás llega por radio.
var contacts: Dictionary = {}
var target_cell: Vector2i = Vector2i(-1, -1) # destino de la opción que se mueve (reubicarse, flanquear)
var flank_enemy: int = -1 # contacto que está flanqueando
var rescue_index: int = -1 # herido elegido para rescatar
var drill_end_tick: int = -1000000 # cuándo terminó la última reacción al contacto
var technique: int = Technique.TRAVEL
var bound_alternate: bool = true # el último salto fue alternado (si no, sucesivo)
var path_order: int = 0 # la orden con la que iba en marcha
var had_path: bool = false # el tick anterior tenía ruta (para detectar la llegada y consolidar)
var crawling: bool = false # clavada en marcha: repta en vez de quedarse quieta (fase 53)
var corner: Dictionary = {} # la esquina ciega que vio al pensar (fase 64)
var rushing: bool = false # bajo fuego, los que avanzan van a carreras cortas (ver InfantrySim)
var pending: Dictionary = {} # enemigos con un aviso de radio en camino
var halted_since: int = -1 # tick desde el que la supresión la tiene frenada (-1 = no lo está)


func _init(p_autonomy: int = Autonomy.NORMAL) -> void:
	autonomy = p_autonomy


## ¿La autonomía deja elegir esa opción?
static func allowed(p_autonomy: int, opt: int) -> bool:
	match opt:
		Option.FOLLOW:
			return true
		Option.CONTACT_DRILL, Option.RELOCATE, Option.AMBUSH, Option.RESCUE, Option.BOUND, Option.NEAR_AMBUSH, Option.CROSS, Option.CORNER:
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
	cover_m = Config.SOLDIER_COVER_SEARCH_M


## Anota (o actualiza) un contacto si la noticia es más nueva que la que tiene.
func learn(enemy_id: int, pos: Vector2, tick: int, exact: bool) -> bool:
	var old: Dictionary = contacts.get(enemy_id, {})
	if not old.is_empty() and (int(old["tick"]) > tick or (bool(old["exact"]) and not exact and int(old["tick"]) == tick)):
		return false
	contacts[enemy_id] = {"pos": pos, "tick": tick, "exact": exact}
	return old.is_empty()


## Ticks entre decisiones según el jefe.
func think_ticks() -> int:
	match quality:
		Quality.VETERAN:
			return Config.MIND_THINK_TICKS_VETERAN
		Quality.GREEN:
			return Config.MIND_THINK_TICKS_GREEN
	return Config.MIND_THINK_TICKS


## Error al puntuar según el jefe (amplitud del ruido).
func score_noise() -> float:
	match quality:
		Quality.VETERAN:
			return Config.MIND_NOISE_VETERAN
		Quality.GREEN:
			return Config.MIND_NOISE_GREEN
	return Config.MIND_NOISE_REGULAR


func is_disorganized(now: int) -> bool:
	return now < disorganized_until


func is_following() -> bool:
	return option == Option.FOLLOW


func option_name() -> String:
	return OPTION_NAMES[option]


## Texto corto de lo que está haciendo por su cuenta (para el ícono sobre la escuadra).
func intent_short(now: int) -> String:
	return "SIN JEFE" if is_disorganized(now) else INTENT_SHORT[option]
