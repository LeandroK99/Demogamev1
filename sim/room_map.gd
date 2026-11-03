class_name RoomMap
extends RefCounted
## Cuartos de las casas (fase 66): el piso de cada casa partido por las paredes interiores. Un paso
## de 1 m en una pared interior (piso con pared a los dos lados) no es de ningún cuarto: es un portal
## entre los dos. Las puertas y los boquetes de la pared de afuera son portales entre un cuarto y
## la calle (cuarto -1). Se rehace cuando cambian las casas (un boquete nuevo es un portal nuevo).

var version: int = -1 # versión del BuildingMap con la que se armó
var room_of: PackedInt32Array = PackedInt32Array() # por micro-celda: índice del cuarto o -1
## Cada cuarto: {house: int, cells: Array[Vector2i], rect: Rect2 (metros, el piso), center: Vector2}
var rooms: Array[Dictionary] = []
## Cada portal: {cells: Array[Vector2i], center: Vector2 (metros), a: int, b: int, n: Vector2}.
## n apunta de a hacia b (unitario, horizontal o vertical). b = -1 es la calle.
var portals: Array[Dictionary] = []
var _size: int = 0


static func build(bm: BuildingMap) -> RoomMap:
	var rm: RoomMap = RoomMap.new()
	rm._build(bm)
	return rm


func _build(bm: BuildingMap) -> void:
	version = bm.version
	_size = bm.size
	room_of.resize(_size * _size)
	room_of.fill(-1)
	var doorway: Dictionary = {} # celdas de paso entre cuartos
	for h: int in bm.houses.size():
		var r: Rect2i = bm.houses[h]
		for y: int in range(r.position.y + 1, r.end.y - 1):
			for x: int in range(r.position.x + 1, r.end.x - 1):
				var c: Vector2i = Vector2i(x, y)
				if bm.type_at(c) == BuildingMap.Type.FLOOR and _is_doorway(bm, c):
					doorway[c] = true
		# Cuartos: piso conectado sin cruzar pasos
		for y: int in range(r.position.y + 1, r.end.y - 1):
			for x: int in range(r.position.x + 1, r.end.x - 1):
				var c: Vector2i = Vector2i(x, y)
				if bm.type_at(c) != BuildingMap.Type.FLOOR or doorway.has(c) or room_of[_i(c)] >= 0:
					continue
				_flood(bm, h, c, doorway)
	# Portales entre cuartos (los pasos, juntando los contiguos)
	var seen: Dictionary = {}
	for c: Vector2i in doorway:
		if seen.has(c):
			continue
		var n: Vector2i = Vector2i(1, 0) if _wall(bm, c + Vector2i(0, -1)) and _wall(bm, c + Vector2i(0, 1)) else Vector2i(0, 1)
		var group: Array[Vector2i] = _group(c, Vector2i(n.y, n.x), doorway, seen)
		_add_portal(group, _room_near(group, -n), _room_near(group, n), Vector2(n))
	# Portales a la calle: puertas y boquetes de la pared de afuera
	seen.clear()
	for h: int in bm.houses.size():
		var r: Rect2i = bm.houses[h]
		var openings: Dictionary = {}
		for y: int in range(r.position.y, r.end.y):
			for x: int in range(r.position.x, r.end.x):
				var t: int = bm.type_at(Vector2i(x, y))
				if t == BuildingMap.Type.DOOR or t == BuildingMap.Type.BREACH:
					openings[Vector2i(x, y)] = true
		for c: Vector2i in openings:
			if seen.has(c):
				continue
			var out: Vector2i = Vector2i(-1 if c.x == r.position.x else (1 if c.x == r.end.x - 1 else 0),
					-1 if c.y == r.position.y else (1 if c.y == r.end.y - 1 else 0))
			if out == Vector2i.ZERO or (out.x != 0 and out.y != 0):
				continue # una esquina o una abertura interior: no da a la calle
			var group: Array[Vector2i] = _group(c, Vector2i(absi(out.y), absi(out.x)), openings, seen)
			_add_portal(group, _room_near(group, -out), -1, Vector2(out))


func _i(c: Vector2i) -> int:
	return c.y * _size + c.x


func room_at(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= _size or c.y >= _size:
		return -1
	return room_of[_i(c)]


func room_at_m(p: Vector2) -> int:
	return room_at(MicroCover.cell_of(p))


## Cuartos de la casa h.
func rooms_of(h: int) -> Array[int]:
	var out: Array[int] = []
	for i: int in rooms.size():
		if int(rooms[i]["house"]) == h:
			out.append(i)
	return out


## Portales del cuarto r (índices).
func portals_of(r: int) -> Array[int]:
	var out: Array[int] = []
	for i: int in portals.size():
		if int(portals[i]["a"]) == r or int(portals[i]["b"]) == r:
			out.append(i)
	return out


## Lo que hay del otro lado del portal p, visto desde r.
func other(p: int, r: int) -> int:
	return int(portals[p]["b"]) if int(portals[p]["a"]) == r else int(portals[p]["a"])


## Normal del portal p apuntando hacia afuera del cuarto r (del lado de r hacia el otro).
func normal_from(p: int, r: int) -> Vector2:
	var n: Vector2 = portals[p]["n"]
	return n if int(portals[p]["a"]) == r else -n


## Portales a la calle de la casa h.
func street_portals(h: int) -> Array[int]:
	var out: Array[int] = []
	for i: int in portals.size():
		if int(portals[i]["b"]) == -1 and int(portals[i]["a"]) >= 0 and int(rooms[int(portals[i]["a"])]["house"]) == h:
			out.append(i)
	return out


## ¿El cuarto r es un pasillo (angosto y largo)?
func is_corridor(r: int) -> bool:
	var s: Vector2 = (rooms[r]["rect"] as Rect2).size
	return minf(s.x, s.y) <= Config.CQB_CORRIDOR_W_M and maxf(s.x, s.y) >= Config.CQB_CORRIDOR_MIN_LEN_M


## Paso de 1 m en una pared interior: piso con pared a los dos lados y piso adelante y atrás.
static func _is_doorway(bm: BuildingMap, c: Vector2i) -> bool:
	var ew: bool = _wall(bm, c + Vector2i(-1, 0)) and _wall(bm, c + Vector2i(1, 0))
	var ns: bool = _wall(bm, c + Vector2i(0, -1)) and _wall(bm, c + Vector2i(0, 1))
	if ew == ns:
		return false
	var d: Vector2i = Vector2i(0, 1) if ew else Vector2i(1, 0)
	return _open(bm, c + d) and _open(bm, c - d)


static func _wall(bm: BuildingMap, c: Vector2i) -> bool:
	var t: int = bm.type_at(c)
	return t == BuildingMap.Type.WALL or t == BuildingMap.Type.WINDOW or t == BuildingMap.Type.LOOPHOLE


static func _open(bm: BuildingMap, c: Vector2i) -> bool:
	return bm.type_at(c) == BuildingMap.Type.FLOOR


func _flood(bm: BuildingMap, h: int, start: Vector2i, doorway: Dictionary) -> void:
	var id: int = rooms.size()
	var cells: Array[Vector2i] = []
	var stack: Array[Vector2i] = [start]
	room_of[_i(start)] = id
	var lo: Vector2i = start
	var hi: Vector2i = start
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		cells.append(c)
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nc: Vector2i = c + d
			if bm.type_at(nc) == BuildingMap.Type.FLOOR and not doorway.has(nc) and room_of[_i(nc)] < 0:
				room_of[_i(nc)] = id
				stack.append(nc)
	var a: Vector2 = MicroCover.center_m(lo) - Vector2.ONE * MicroCover.MICRO_M * 0.5
	var rect: Rect2 = Rect2(a, Vector2(hi - lo + Vector2i.ONE) * MicroCover.MICRO_M)
	rooms.append({"house": h, "cells": cells, "rect": rect, "center": rect.get_center()})


## Celdas contiguas a c en la dirección along (y la opuesta) que estén en pool.
func _group(c: Vector2i, along: Vector2i, pool: Dictionary, seen: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = [c]
	seen[c] = true
	for dir: Vector2i in [along, -along]:
		var k: Vector2i = c + dir
		while pool.has(k) and not seen.has(k):
			seen[k] = true
			out.append(k)
			k += dir
	return out


## Cuarto que toca al grupo de celdas yendo en la dirección d.
func _room_near(group: Array[Vector2i], d: Vector2i) -> int:
	for c: Vector2i in group:
		var r: int = room_at(c + d)
		if r >= 0:
			return r
	return -1


func _add_portal(group: Array[Vector2i], a: int, b: int, n: Vector2) -> void:
	if a < 0:
		return
	var center: Vector2 = Vector2.ZERO
	for c: Vector2i in group:
		center += MicroCover.center_m(c)
	center /= float(group.size())
	portals.append({"cells": group, "center": center, "a": a, "b": b, "n": n})
