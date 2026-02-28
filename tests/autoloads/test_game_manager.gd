extends GdUnitTestSuite
## Tests for GameManager autoload.

var _original_state: Dictionary


func before_test() -> void:
	_original_state = {
		"is_paused": GameManager.is_paused,
		"game_speed": GameManager.game_speed,
		"game_time": GameManager.game_time,
		"current_age": GameManager.current_age,
		"speed_index": GameManager._speed_index,
	}
	# Reset to clean defaults so tests don't depend on execution order
	GameManager.is_paused = false
	GameManager.game_speed = 1.0
	GameManager.game_time = 0.0
	GameManager.current_age = 0
	GameManager._speed_index = 1


func after_test() -> void:
	GameManager.is_paused = _original_state["is_paused"]
	GameManager.game_speed = _original_state["game_speed"]
	GameManager.game_time = _original_state["game_time"]
	GameManager.current_age = _original_state["current_age"]
	GameManager._speed_index = _original_state["speed_index"]


# --- Age tests ---


func test_initial_age_is_stone() -> void:
	assert_int(GameManager.current_age).is_equal(0)


func test_age_names_count() -> void:
	assert_int(GameManager.AGE_NAMES.size()).is_equal(7)


func test_get_age_name_returns_stone_age() -> void:
	GameManager.current_age = 0
	assert_str(GameManager.get_age_name()).is_equal("Stone Age")


func test_get_age_name_returns_singularity_age() -> void:
	GameManager.current_age = 6
	assert_str(GameManager.get_age_name()).is_equal("Singularity Age")


func test_initial_pause_state_is_false() -> void:
	assert_bool(GameManager.is_paused).is_false()


func test_initial_game_speed_is_one() -> void:
	assert_float(GameManager.game_speed).is_equal(1.0)


# --- get_game_delta tests ---


func test_get_game_delta_normal_speed() -> void:
	GameManager.game_speed = 1.0
	GameManager.is_paused = false
	assert_float(GameManager.get_game_delta(0.016)).is_equal_approx(0.016, 0.001)


func test_get_game_delta_double_speed() -> void:
	GameManager.game_speed = 2.0
	GameManager.is_paused = false
	assert_float(GameManager.get_game_delta(0.016)).is_equal_approx(0.032, 0.001)


func test_get_game_delta_triple_speed() -> void:
	GameManager.game_speed = 3.0
	GameManager.is_paused = false
	assert_float(GameManager.get_game_delta(0.016)).is_equal_approx(0.048, 0.001)


func test_get_game_delta_half_speed() -> void:
	GameManager.game_speed = 1.5
	GameManager.is_paused = false
	assert_float(GameManager.get_game_delta(0.016)).is_equal_approx(0.024, 0.001)


func test_get_game_delta_when_paused() -> void:
	GameManager.is_paused = true
	assert_float(GameManager.get_game_delta(0.016)).is_equal(0.0)


# --- Pause/resume tests ---


func test_pause_sets_is_paused() -> void:
	GameManager.pause()
	assert_bool(GameManager.is_paused).is_true()


func test_resume_clears_is_paused() -> void:
	GameManager.pause()
	GameManager.resume()
	assert_bool(GameManager.is_paused).is_false()


func test_toggle_pause() -> void:
	GameManager.is_paused = false
	GameManager.toggle_pause()
	assert_bool(GameManager.is_paused).is_true()
	GameManager.toggle_pause()
	assert_bool(GameManager.is_paused).is_false()


# --- Speed stepping tests ---


func test_step_speed_up() -> void:
	GameManager._speed_index = 0
	GameManager.game_speed = GameManager._speed_steps[0]
	GameManager.step_speed(1)
	assert_float(GameManager.game_speed).is_equal(GameManager._speed_steps[1])


func test_step_speed_down() -> void:
	GameManager._speed_index = 1
	GameManager.game_speed = GameManager._speed_steps[1]
	GameManager.step_speed(-1)
	assert_float(GameManager.game_speed).is_equal(GameManager._speed_steps[0])


func test_step_speed_clamps_max() -> void:
	var max_index := GameManager._speed_steps.size() - 1
	GameManager._speed_index = max_index
	GameManager.game_speed = GameManager._speed_steps[max_index]
	GameManager.step_speed(1)
	assert_int(GameManager._speed_index).is_equal(max_index)
	assert_float(GameManager.game_speed).is_equal(GameManager._speed_steps[max_index])


func test_step_speed_clamps_min() -> void:
	GameManager._speed_index = 0
	GameManager.game_speed = GameManager._speed_steps[0]
	GameManager.step_speed(-1)
	assert_int(GameManager._speed_index).is_equal(0)
	assert_float(GameManager.game_speed).is_equal(GameManager._speed_steps[0])


# --- Clock display tests ---


func test_clock_display_zero() -> void:
	GameManager.game_time = 0.0
	assert_str(GameManager.get_clock_display()).is_equal("00:00")


func test_clock_display_one_minute() -> void:
	GameManager.game_time = 60.0
	assert_str(GameManager.get_clock_display()).is_equal("01:00")


func test_clock_display_mixed() -> void:
	GameManager.game_time = 125.0
	assert_str(GameManager.get_clock_display()).is_equal("02:05")


func test_clock_display_large() -> void:
	GameManager.game_time = 3661.0
	assert_str(GameManager.get_clock_display()).is_equal("61:01")


# --- Speed display tests ---


func test_speed_display_integer() -> void:
	GameManager.game_speed = 1.0
	assert_str(GameManager.get_speed_display()).is_equal("1x")


func test_speed_display_decimal() -> void:
	GameManager.game_speed = 1.5
	assert_str(GameManager.get_speed_display()).is_equal("1.5x")


# --- Save/load tests ---


func test_save_load_roundtrip() -> void:
	GameManager.game_time = 123.4
	GameManager.game_speed = 2.0
	GameManager._speed_index = 2
	GameManager.is_paused = true
	GameManager.current_age = 3
	var state := GameManager.save_state()
	# Reset
	GameManager.game_time = 0.0
	GameManager.game_speed = 1.0
	GameManager._speed_index = 0
	GameManager.is_paused = false
	GameManager.current_age = 0
	# Load
	GameManager.load_state(state)
	assert_float(GameManager.game_time).is_equal_approx(123.4, 0.01)
	assert_float(GameManager.game_speed).is_equal(2.0)
	assert_int(GameManager._speed_index).is_equal(2)
	assert_bool(GameManager.is_paused).is_true()
	assert_int(GameManager.current_age).is_equal(3)


func test_save_state_keys() -> void:
	var state := GameManager.save_state()
	assert_bool(state.has("game_time")).is_true()
	assert_bool(state.has("game_speed")).is_true()
	assert_bool(state.has("speed_index")).is_true()
	assert_bool(state.has("is_paused")).is_true()
	assert_bool(state.has("current_age")).is_true()
