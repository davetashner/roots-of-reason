extends GdUnitTestSuite
## Tests for granary building — food drop-off gated by agriculture tech.


func before_test() -> void:
	DataLoader.reload()


func after_test() -> void:
	DataLoader.reload()


# --- Schema ---


func test_granary_loads_successfully() -> void:
	var stats := DataLoader.get_building_stats("granary")
	assert_dict(stats).is_not_empty()


func test_granary_has_required_fields() -> void:
	var stats := DataLoader.get_building_stats("granary")
	var required := [
		"name",
		"category",
		"hp",
		"footprint",
		"build_time",
		"build_cost",
		"is_drop_off",
		"drop_off_types",
		"required_techs",
	]
	for field in required:
		assert_bool(stats.has(field)).is_true()


func test_granary_name() -> void:
	var stats := DataLoader.get_building_stats("granary")
	assert_dict(stats).contains_key_value("name", "Granary")


func test_granary_category_is_civilian() -> void:
	var stats := DataLoader.get_building_stats("granary")
	assert_str(str(stats["category"])).is_equal("civilian")


func test_granary_hp() -> void:
	var stats := DataLoader.get_building_stats("granary")
	assert_float(stats["hp"]).is_equal(600.0)


# --- Footprint ---


func test_granary_footprint_is_2x2() -> void:
	var stats := DataLoader.get_building_stats("granary")
	var fp: Array = stats["footprint"]
	assert_int(int(fp[0])).is_equal(2)
	assert_int(int(fp[1])).is_equal(2)


# --- Cost ---


func test_granary_costs_100_wood() -> void:
	var stats := DataLoader.get_building_stats("granary")
	var cost: Dictionary = stats["build_cost"]
	assert_float(cost["wood"]).is_equal(100.0)


func test_granary_costs_only_wood() -> void:
	var stats := DataLoader.get_building_stats("granary")
	var cost: Dictionary = stats["build_cost"]
	assert_int(cost.size()).is_equal(1)
	assert_bool(cost.has("wood")).is_true()


# --- Drop-off ---


func test_granary_is_drop_off() -> void:
	var stats := DataLoader.get_building_stats("granary")
	assert_bool(stats["is_drop_off"]).is_true()


func test_granary_drop_off_types_contains_food() -> void:
	var stats := DataLoader.get_building_stats("granary")
	var types: Array = stats["drop_off_types"]
	assert_bool(types.has("food")).is_true()


func test_granary_drop_off_types_only_food() -> void:
	var stats := DataLoader.get_building_stats("granary")
	var types: Array = stats["drop_off_types"]
	assert_int(types.size()).is_equal(1)


# --- Tech gate ---


func test_granary_requires_agriculture_tech() -> void:
	var stats := DataLoader.get_building_stats("granary")
	var req_techs: Array = stats.get("required_techs", [])
	assert_array(req_techs).contains(["agriculture"])


func test_granary_requires_only_agriculture() -> void:
	var stats := DataLoader.get_building_stats("granary")
	var req_techs: Array = stats.get("required_techs", [])
	assert_int(req_techs.size()).is_equal(1)


func test_agriculture_tech_exists_in_tech_tree() -> void:
	var tech_data: Dictionary = DataLoader.get_tech_data("agriculture")
	assert_dict(tech_data).is_not_empty()
	assert_str(str(tech_data["name"])).is_equal("Agriculture")


# --- Age / placement ---


func test_granary_age_required_is_zero() -> void:
	var stats := DataLoader.get_building_stats("granary")
	assert_float(stats["age_required"]).is_equal(0.0)


func test_granary_no_placement_constraint() -> void:
	var stats := DataLoader.get_building_stats("granary")
	assert_str(str(stats["placement_constraint"])).is_equal("")


func test_granary_no_units_produced() -> void:
	var stats := DataLoader.get_building_stats("granary")
	var units: Array = stats["units_produced"]
	assert_int(units.size()).is_equal(0)


func test_granary_no_garrison_capacity() -> void:
	var stats := DataLoader.get_building_stats("granary")
	assert_float(stats["garrison_capacity"]).is_equal(0.0)


func test_granary_los_is_four() -> void:
	var stats := DataLoader.get_building_stats("granary")
	assert_float(stats["los"]).is_equal(4.0)
