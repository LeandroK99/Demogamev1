extends SceneTree
func _key(k: Key, shift: bool = false) -> void:
	var ev: InputEventKey = InputEventKey.new(); ev.physical_keycode = k; ev.pressed = true; ev.shift_pressed = shift; root.push_input(ev)
func _initialize() -> void:
	var main: Node3D = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for _i: int in 3: await process_frame
	var world: SimWorld = main.get("world")
	main.get("input_controller")._set_selection([1, 2])
	_key(KEY_H); await process_frame
	_key(KEY_SPACE); await process_frame
	for _i: int in 150: main.get("turn_controller")._process(0.1)
	for _i: int in 3: await process_frame
	root.get_texture().get_image().save_png("/tmp/claude-0/shot/f6_hud.png")
	_key(KEY_R); for _i: int in 3: await process_frame
	var w2: SimWorld = main.get("world")
	print("R: mundo nuevo=%s turno=%d tick=%d semilla=%d hijos=%d" % [w2 != world, w2.turn, w2.tick_in_turn, main.get("map_seed"), main.get_child_count()])
	_key(KEY_R, true); for _i: int in 3: await process_frame
	print("Shift+R: semilla=%d hijos=%d" % [main.get("map_seed"), main.get_child_count()])
	root.get_texture().get_image().save_png("/tmp/claude-0/shot/f6_newmap.png")
	quit()
