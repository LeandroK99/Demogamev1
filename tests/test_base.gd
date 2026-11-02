class_name TestBase
extends RefCounted
## Base de los tests: helpers de aserción. Los fallos se acumulan en `failures`.

var failures: Array[String] = []


func assert_true(cond: bool, msg: String = "") -> void:
	if not cond:
		failures.append("se esperaba verdadero: %s" % msg)


func assert_eq(a: Variant, b: Variant, msg: String = "") -> void:
	if a != b:
		failures.append("%s != %s: %s" % [str(a), str(b), msg])


func assert_lt(a: Variant, b: Variant, msg: String = "") -> void:
	if not (a < b):
		failures.append("%s no es < %s: %s" % [str(a), str(b), msg])
