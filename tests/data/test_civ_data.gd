extends GdUnitTestSuite
## Tests for civilization JSON data files.


func test_mesopotamia_loads() -> void:
	var data: Dictionary = DataLoader.get_civ_data("mesopotamia")
	assert_dict(data).is_not_empty()
	assert_str(str(data.get("name", ""))).is_equal("Mesopotamia")


func test_rome_loads() -> void:
	var data: Dictionary = DataLoader.get_civ_data("rome")
	assert_dict(data).is_not_empty()
	assert_str(str(data.get("name", ""))).is_equal("Rome")


func test_polynesia_loads() -> void:
	var data: Dictionary = DataLoader.get_civ_data("polynesia")
	assert_dict(data).is_not_empty()
	assert_str(str(data.get("name", ""))).is_equal("Polynesia")


func test_mesopotamia_has_build_speed() -> void:
	var data: Dictionary = DataLoader.get_civ_data("mesopotamia")
	var bonuses: Dictionary = data.get("bonuses", {})
	assert_float(float(bonuses.get("build_speed", 0.0))).is_equal_approx(1.15, 0.001)


func test_rome_has_military_bonuses() -> void:
	var data: Dictionary = DataLoader.get_civ_data("rome")
	var bonuses: Dictionary = data.get("bonuses", {})
	assert_float(float(bonuses.get("military_attack", 0.0))).is_equal_approx(1.10, 0.001)
	assert_float(float(bonuses.get("military_defense", 0.0))).is_equal_approx(1.10, 0.001)


func test_polynesia_has_naval_speed() -> void:
	var data: Dictionary = DataLoader.get_civ_data("polynesia")
	var bonuses: Dictionary = data.get("bonuses", {})
	assert_float(float(bonuses.get("naval_speed", 0.0))).is_equal_approx(1.20, 0.001)


func test_china_loads() -> void:
	var data: Dictionary = DataLoader.get_civ_data("china")
	assert_dict(data).is_not_empty()
	assert_str(str(data.get("name", ""))).is_equal("China")


func test_china_has_research_speed() -> void:
	var data: Dictionary = DataLoader.get_civ_data("china")
	var bonuses: Dictionary = data.get("bonuses", {})
	assert_float(float(bonuses.get("research_speed", 0.0))).is_equal_approx(1.20, 0.001)


func test_china_has_knowledge_generation() -> void:
	var data: Dictionary = DataLoader.get_civ_data("china")
	var bonuses: Dictionary = data.get("bonuses", {})
	assert_float(float(bonuses.get("knowledge_generation", 0.0))).is_equal_approx(1.10, 0.001)


func test_maya_loads() -> void:
	var data: Dictionary = DataLoader.get_civ_data("maya")
	assert_dict(data).is_not_empty()
	assert_str(str(data.get("name", ""))).is_equal("Maya")


func test_maya_has_knowledge_generation() -> void:
	var data: Dictionary = DataLoader.get_civ_data("maya")
	var bonuses: Dictionary = data.get("bonuses", {})
	assert_float(float(bonuses.get("knowledge_generation", 0.0))).is_equal_approx(1.15, 0.001)


func test_maya_has_age_advancement_cost() -> void:
	var data: Dictionary = DataLoader.get_civ_data("maya")
	var bonuses: Dictionary = data.get("bonuses", {})
	assert_float(float(bonuses.get("age_advancement_cost", 0.0))).is_equal_approx(0.85, 0.001)


func test_egypt_loads() -> void:
	var data: Dictionary = DataLoader.get_civ_data("egypt")
	assert_dict(data).is_not_empty()
	assert_str(str(data.get("name", ""))).is_equal("Egypt")


func test_egypt_has_stone_gather_rate() -> void:
	var data: Dictionary = DataLoader.get_civ_data("egypt")
	var bonuses: Dictionary = data.get("bonuses", {})
	assert_float(float(bonuses.get("stone_gather_rate", 0.0))).is_equal_approx(1.15, 0.001)


func test_egypt_has_building_hp() -> void:
	var data: Dictionary = DataLoader.get_civ_data("egypt")
	var bonuses: Dictionary = data.get("bonuses", {})
	assert_float(float(bonuses.get("building_hp", 0.0))).is_equal_approx(1.10, 0.001)


func test_vikings_loads() -> void:
	var data: Dictionary = DataLoader.get_civ_data("vikings")
	assert_dict(data).is_not_empty()
	assert_str(str(data.get("name", ""))).is_equal("Vikings")


func test_vikings_has_naval_speed() -> void:
	var data: Dictionary = DataLoader.get_civ_data("vikings")
	var bonuses: Dictionary = data.get("bonuses", {})
	assert_float(float(bonuses.get("naval_speed", 0.0))).is_equal_approx(1.15, 0.001)


func test_vikings_has_infantry_attack() -> void:
	var data: Dictionary = DataLoader.get_civ_data("vikings")
	var bonuses: Dictionary = data.get("bonuses", {})
	assert_float(float(bonuses.get("infantry_attack", 0.0))).is_equal_approx(1.10, 0.001)


func test_all_civs_have_starting_bonuses() -> void:
	for civ_id in ["mesopotamia", "rome", "polynesia", "china", "maya", "egypt", "vikings"]:
		var data: Dictionary = DataLoader.get_civ_data(civ_id)
		assert_bool(data.has("starting_bonuses")).is_true()


func test_all_civs_have_required_fields() -> void:
	for civ_id in ["mesopotamia", "rome", "polynesia", "china", "maya", "egypt", "vikings"]:
		var data: Dictionary = DataLoader.get_civ_data(civ_id)
		assert_bool(data.has("name")).is_true()
		assert_bool(data.has("description")).is_true()
		assert_bool(data.has("bonuses")).is_true()
		assert_bool(data.has("unique_building")).is_true()
		assert_bool(data.has("unique_unit")).is_true()
