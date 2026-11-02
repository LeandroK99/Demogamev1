extends TestBase
## Test trivial para validar el corredor.


func test_config_values() -> void:
	assert_eq(Config.GRID_SIZE, 96, "GRID_SIZE")
	assert_lt(0.0, Config.TICK, "TICK positivo")
	assert_true(is_equal_approx(Config.TURN_SECONDS / Config.TICK, 300.0), "300 ticks por turno")
