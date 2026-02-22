extends GdUnitTestSuite
## Tests for GameManager autoload.


func test_initial_age_is_stone() -> void:
	assert_int(GameManager.current_age).is_equal(0)


func test_age_names_count() -> void:
	assert_int(GameManager.AGE_NAMES.size()).is_equal(7)


func test_get_age_name_returns_stone_age() -> void:
	GameManager.current_age = 0
	assert_str(GameManager.get_age_name()).is_equal("Stone Age")


func test_get_age_name_returns_singularity_age() -> void:
	var original_age: int = GameManager.current_age
	GameManager.current_age = 6
	assert_str(GameManager.get_age_name()).is_equal("Singularity Age")
	GameManager.current_age = original_age


func test_initial_pause_state_is_false() -> void:
	assert_bool(GameManager.is_paused).is_false()


func test_initial_game_speed_is_one() -> void:
	assert_float(GameManager.game_speed).is_equal(1.0)
