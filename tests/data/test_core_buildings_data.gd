extends GdUnitTestSuite
## Tests for core building data files — validates all buildings load correctly.


func before_test() -> void:
	DataLoader.reload()


func after_test() -> void:
	DataLoader.reload()


# --- Required schema fields ---


func test_all_core_buildings_have_required_fields() -> void:
	var buildings := [
		"house",
		"town_center",
		"river_dock",
		"farm",
		"barracks",
		"dock",
		"market",
		"library",
		"wonder",
	]
	for building_name in buildings:
		var stats := DataLoader.get_building_stats(building_name)
		assert_dict(stats).is_not_empty()
		assert_bool(stats.has("name")).is_true()
		assert_bool(stats.has("hp")).is_true()
		assert_bool(stats.has("footprint")).is_true()
		assert_bool(stats.has("build_time")).is_true()
		assert_bool(stats.has("build_cost")).is_true()


# --- Farm ---


func test_farm_loads_with_expected_name() -> void:
	var stats := DataLoader.get_building_stats("farm")
	assert_dict(stats).contains_key_value("name", "Farm")


func test_farm_has_food_rate() -> void:
	var stats := DataLoader.get_building_stats("farm")
	assert_float(stats["food_rate"]).is_equal(0.4)


func test_farm_has_max_food() -> void:
	var stats := DataLoader.get_building_stats("farm")
	assert_float(stats["max_food"]).is_equal(300.0)


func test_farm_age_required_is_zero() -> void:
	var stats := DataLoader.get_building_stats("farm")
	assert_float(stats["age_required"]).is_equal(0.0)


# --- Barracks ---


func test_barracks_loads_with_expected_name() -> void:
	var stats := DataLoader.get_building_stats("barracks")
	assert_dict(stats).contains_key_value("name", "Barracks")


func test_barracks_units_produced() -> void:
	var stats := DataLoader.get_building_stats("barracks")
	var units: Array = stats["units_produced"]
	assert_bool(units.has("infantry")).is_true()
	assert_bool(units.has("archer")).is_true()
	assert_bool(units.has("cavalry")).is_true()


func test_barracks_age_required_is_one() -> void:
	var stats := DataLoader.get_building_stats("barracks")
	assert_float(stats["age_required"]).is_equal(1.0)


# --- Dock ---


func test_dock_loads_with_expected_name() -> void:
	var stats := DataLoader.get_building_stats("dock")
	assert_dict(stats).contains_key_value("name", "Dock")


func test_dock_is_drop_off() -> void:
	var stats := DataLoader.get_building_stats("dock")
	assert_bool(stats["is_drop_off"]).is_true()


func test_dock_placement_constraint() -> void:
	var stats := DataLoader.get_building_stats("dock")
	assert_str(stats["placement_constraint"]).is_equal("adjacent_to_water")


func test_dock_age_required_is_one() -> void:
	var stats := DataLoader.get_building_stats("dock")
	assert_float(stats["age_required"]).is_equal(1.0)


# --- Market ---


func test_market_loads_with_expected_name() -> void:
	var stats := DataLoader.get_building_stats("market")
	assert_dict(stats).contains_key_value("name", "Market")


func test_market_has_trade_rates() -> void:
	var stats := DataLoader.get_building_stats("market")
	assert_bool(stats.has("trade_rates")).is_true()
	var rates: Dictionary = stats["trade_rates"]
	assert_bool(rates.has("food")).is_true()
	assert_bool(rates.has("wood")).is_true()
	assert_bool(rates.has("stone")).is_true()
	assert_bool(rates.has("gold")).is_true()


func test_market_age_required_is_one() -> void:
	var stats := DataLoader.get_building_stats("market")
	assert_float(stats["age_required"]).is_equal(1.0)


# --- Library ---


func test_library_loads_with_expected_name() -> void:
	var stats := DataLoader.get_building_stats("library")
	assert_dict(stats).contains_key_value("name", "Library")


func test_library_has_knowledge_rate() -> void:
	var stats := DataLoader.get_building_stats("library")
	assert_float(stats["knowledge_rate"]).is_equal(0.5)


func test_library_age_required_is_two() -> void:
	var stats := DataLoader.get_building_stats("library")
	assert_float(stats["age_required"]).is_equal(2.0)


# --- Wonder ---


func test_wonder_loads_with_expected_name() -> void:
	var stats := DataLoader.get_building_stats("wonder")
	assert_dict(stats).contains_key_value("name", "Wonder")


func test_wonder_hp() -> void:
	var stats := DataLoader.get_building_stats("wonder")
	assert_float(stats["hp"]).is_equal(5000.0)


func test_wonder_has_victory_countdown() -> void:
	var stats := DataLoader.get_building_stats("wonder")
	assert_float(stats["victory_countdown"]).is_equal(600.0)


func test_wonder_age_required_is_three() -> void:
	var stats := DataLoader.get_building_stats("wonder")
	assert_float(stats["age_required"]).is_equal(3.0)


# --- Town Center garrison ---


func test_town_center_has_garrison_capacity() -> void:
	var stats := DataLoader.get_building_stats("town_center")
	assert_float(stats["garrison_capacity"]).is_equal(15.0)


# --- Age requirements summary ---


func test_age_requirements_correct() -> void:
	var expected := {
		"farm": 0,
		"house": 0,
		"town_center": 0,
		"barracks": 1,
		"dock": 1,
		"market": 1,
		"library": 2,
		"wonder": 3,
	}
	for building_name in expected:
		var stats := DataLoader.get_building_stats(building_name)
		assert_float(stats["age_required"]).is_equal(float(expected[building_name]))
