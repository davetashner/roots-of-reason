extends GdUnitTestSuite
## Tests for data/settings/game/start_config.json integrity.


func test_start_config_loads() -> void:
	var data: Dictionary = DataLoader.load_json("res://data/settings/game/start_config.json")
	assert_bool(data != null and not data.is_empty()).is_true()


func test_all_difficulties_present() -> void:
	var data: Dictionary = DataLoader.load_json("res://data/settings/game/start_config.json")
	for diff in ["easy", "normal", "hard", "expert"]:
		assert_bool(data.has(diff)).is_true()


func test_easy_has_pre_built_tc_and_houses() -> void:
	var data: Dictionary = DataLoader.load_json("res://data/settings/game/start_config.json")
	var easy: Dictionary = data["easy"]
	assert_bool(easy.get("pre_built_tc", false)).is_true()
	assert_int(int(easy.get("starting_houses", 0))).is_equal(2)


func test_normal_has_pre_built_tc_no_houses() -> void:
	var data: Dictionary = DataLoader.load_json("res://data/settings/game/start_config.json")
	var normal: Dictionary = data["normal"]
	assert_bool(normal.get("pre_built_tc", false)).is_true()
	assert_int(int(normal.get("starting_houses", 0))).is_equal(0)


func test_hard_has_no_tc_no_houses() -> void:
	var data: Dictionary = DataLoader.load_json("res://data/settings/game/start_config.json")
	var hard: Dictionary = data["hard"]
	assert_bool(hard.get("pre_built_tc", true)).is_false()
	assert_int(int(hard.get("starting_houses", 0))).is_equal(0)


func test_expert_has_no_tc_no_houses() -> void:
	var data: Dictionary = DataLoader.load_json("res://data/settings/game/start_config.json")
	var expert: Dictionary = data["expert"]
	assert_bool(expert.get("pre_built_tc", true)).is_false()
	assert_int(int(expert.get("starting_houses", 0))).is_equal(0)
