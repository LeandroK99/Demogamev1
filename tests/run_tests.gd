extends SceneTree
## Corredor de tests headless:
## godot --headless --path . --script res://tests/run_tests.gd

const TESTS_DIR: String = "res://tests"


func _initialize() -> void:
	var passed: int = 0
	var failed: int = 0
	var files: PackedStringArray = DirAccess.get_files_at(TESTS_DIR)
	files.sort()
	for file_name: String in files:
		if not (file_name.begins_with("test_") and file_name.ends_with(".gd")):
			continue
		if file_name == "test_base.gd":
			continue
		var script: GDScript = load(TESTS_DIR.path_join(file_name)) as GDScript
		if script == null:
			print("FAIL %s: no se pudo cargar" % file_name)
			failed += 1
			continue
		for method: Dictionary in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			var instance: Object = script.new()
			if not ("failures" in instance):
				print("FAIL %s: no extiende TestBase" % file_name)
				failed += 1
				break
			instance.call(method_name)
			var failures: Array[String] = instance.get("failures")
			if failures.is_empty():
				print("PASS %s::%s" % [file_name, method_name])
				passed += 1
			else:
				print("FAIL %s::%s" % [file_name, method_name])
				for f: String in failures:
					print("    " + f)
				failed += 1
	print("\n%d pasaron, %d fallaron" % [passed, failed])
	quit(0 if failed == 0 else 1)
