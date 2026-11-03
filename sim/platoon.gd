class_name Platoon
extends RefCounted
## Pelotón: un grupo de tanques de un bando, repartido en secciones.
## La orden al pelotón se reparte entre sus secciones (ver SimWorld.order_platoon_*).

var id: int = 0
var side: int = 0
var sections: Array[PackedInt32Array] = [] # ids de unidad por sección


func _init(p_id: int, p_side: int, p_sections: Array[PackedInt32Array]) -> void:
	id = p_id
	side = p_side
	sections = p_sections


## Todas las unidades del pelotón, sección por sección.
func unit_ids() -> Array[int]:
	var out: Array[int] = []
	for sec: PackedInt32Array in sections:
		for uid: int in sec:
			out.append(uid)
	return out


## Índice de la sección de la unidad (-1 si no es del pelotón).
func section_of(unit_id: int) -> int:
	for i: int in sections.size():
		if sections[i].has(unit_id):
			return i
	return -1


## Letra de la sección para el HUD (A, B, ...).
static func section_letter(idx: int) -> String:
	return String.chr(65 + idx) if idx >= 0 else "?"
