extends GdUnitTestSuite
## Tests for DataLoader autoload.


func before_test() -> void:
	DataLoader.reload()


func after_test() -> void:
	DataLoader.reload()


# --- get_unit_stats tests ---


func test_get_unit_stats_villager_returns_expected_keys() -> void:
	var stats := DataLoader.get_unit_stats("villager")
	assert_dict(stats).contains_key_value("name", "Villager")
	assert_bool(stats.has("hp")).is_true()
	assert_bool(stats.has("attack")).is_true()
	assert_bool(stats.has("defense")).is_true()
	assert_bool(stats.has("speed")).is_true()


func test_get_unit_stats_nonexistent_returns_empty() -> void:
	var stats := DataLoader.get_unit_stats("nonexistent")
	assert_dict(stats).is_empty()


# --- get_building_stats / get_building_data tests ---


func test_get_building_stats_house_returns_expected_keys() -> void:
	var stats := DataLoader.get_building_stats("house")
	assert_dict(stats).contains_key_value("name", "House")
	assert_bool(stats.has("hp")).is_true()
	assert_bool(stats.has("footprint")).is_true()
	assert_bool(stats.has("build_time")).is_true()
	assert_bool(stats.has("build_cost")).is_true()


func test_get_building_stats_nonexistent_returns_empty() -> void:
	var stats := DataLoader.get_building_stats("nonexistent")
	assert_dict(stats).is_empty()


func test_get_building_data_is_alias_for_building_stats() -> void:
	var stats := DataLoader.get_building_stats("house")
	var data := DataLoader.get_building_data("house")
	assert_dict(data).is_equal(stats)


# --- get_tech_data tests ---


func test_get_tech_data_stone_tools_returns_expected_keys() -> void:
	var tech := DataLoader.get_tech_data("stone_tools")
	assert_dict(tech).contains_key_value("id", "stone_tools")
	assert_dict(tech).contains_key_value("name", "Stone Tools")
	assert_bool(tech.has("age")).is_true()
	assert_bool(tech.has("cost")).is_true()
	assert_bool(tech.has("research_time")).is_true()
	assert_bool(tech.has("prerequisites")).is_true()
	assert_bool(tech.has("effects")).is_true()


func test_get_tech_data_nonexistent_returns_empty() -> void:
	var tech := DataLoader.get_tech_data("nonexistent")
	assert_dict(tech).is_empty()


# --- get_ages_data tests ---


func test_get_ages_data_returns_seven_entries() -> void:
	var ages := DataLoader.get_ages_data()
	assert_int(ages.size()).is_equal(7)


func test_get_ages_data_first_is_stone_age() -> void:
	var ages := DataLoader.get_ages_data()
	assert_str(ages[0]["id"]).is_equal("stone_age")
	assert_str(ages[0]["name"]).is_equal("Stone Age")
	assert_float(ages[0]["index"]).is_equal(0.0)


# --- get_civ_data tests ---


func test_get_civ_data_mesopotamia_returns_expected_keys() -> void:
	var civ := DataLoader.get_civ_data("mesopotamia")
	assert_dict(civ).contains_key_value("name", "Mesopotamia")
	assert_bool(civ.has("description")).is_true()
	assert_bool(civ.has("bonuses")).is_true()


func test_get_civ_data_nonexistent_returns_empty() -> void:
	var civ := DataLoader.get_civ_data("nonexistent")
	assert_dict(civ).is_empty()


# --- get_resource_data tests ---


func test_get_resource_data_berry_bush_returns_expected_keys() -> void:
	var res := DataLoader.get_resource_data("berry_bush")
	assert_dict(res).contains_key_value("resource_type", "food")
	assert_bool(res.has("total_yield")).is_true()
	assert_bool(res.has("color")).is_true()


func test_get_resource_data_nonexistent_returns_empty() -> void:
	var res := DataLoader.get_resource_data("nonexistent")
	assert_dict(res).is_empty()


# --- get_resource_config tests ---


func test_get_resource_config_returns_all_resources() -> void:
	var config := DataLoader.get_resource_config()
	assert_bool(config.has("berry_bush")).is_true()
	assert_bool(config.has("tree")).is_true()
	assert_bool(config.has("stone_mine")).is_true()
	assert_bool(config.has("gold_mine")).is_true()
	assert_int(config.size()).is_equal(4)


# --- get_settings / get_setting tests ---


func test_get_settings_camera_returns_dict() -> void:
	var settings := DataLoader.get_settings("camera")
	assert_dict(settings).is_not_empty()


func test_get_setting_is_alias_for_get_settings() -> void:
	var settings := DataLoader.get_settings("camera")
	var setting := DataLoader.get_setting("camera")
	assert_dict(setting).is_equal(settings)


func test_get_settings_nonexistent_returns_empty() -> void:
	var settings := DataLoader.get_settings("nonexistent")
	assert_dict(settings).is_empty()


# --- load_json tests ---


func test_load_json_invalid_path_returns_null() -> void:
	var result: Variant = DataLoader.load_json("res://data/does_not_exist.json")
	assert_that(result).is_null()


# --- Cache tests ---


func test_cache_returns_same_reference() -> void:
	var first := DataLoader.get_unit_stats("villager")
	var second := DataLoader.get_unit_stats("villager")
	assert_bool(first == second).is_true()


func test_reload_clears_cache() -> void:
	var first := DataLoader.get_unit_stats("villager")
	first["_test_marker"] = true
	DataLoader.reload()
	var second := DataLoader.get_unit_stats("villager")
	# After reload, cache is fresh so the marker should be gone
	assert_bool(second.has("_test_marker")).is_false()


func test_clear_cache_clears_cache() -> void:
	var first := DataLoader.get_unit_stats("villager")
	first["_test_marker"] = true
	DataLoader.clear_cache()
	var second := DataLoader.get_unit_stats("villager")
	assert_bool(second.has("_test_marker")).is_false()


# --- Integration tests ---


func test_all_unit_files_parse() -> void:
	for unit_name in ["villager", "infantry"]:
		var stats := DataLoader.get_unit_stats(unit_name)
		assert_dict(stats).is_not_empty()
		assert_bool(stats.has("name")).is_true()


func test_all_building_files_parse() -> void:
	for building_name in ["house", "town_center", "river_dock"]:
		var stats := DataLoader.get_building_stats(building_name)
		assert_dict(stats).is_not_empty()
		assert_bool(stats.has("name")).is_true()


func test_all_resource_files_parse() -> void:
	for resource_name in DataLoader.RESOURCE_NAMES:
		var data := DataLoader.get_resource_data(resource_name)
		assert_dict(data).is_not_empty()
		assert_bool(data.has("resource_type")).is_true()
		assert_bool(data.has("total_yield")).is_true()


func test_tech_tree_all_entries_have_required_keys() -> void:
	var data: Variant = DataLoader.load_json("res://data/tech/tech_tree.json")
	assert_that(data).is_not_null()
	for entry in data:
		assert_bool(entry.has("id")).is_true()
		assert_bool(entry.has("name")).is_true()
		assert_bool(entry.has("age")).is_true()
		assert_bool(entry.has("cost")).is_true()
		assert_bool(entry.has("research_time")).is_true()
		assert_bool(entry.has("prerequisites")).is_true()
		assert_bool(entry.has("effects")).is_true()


func test_ages_all_entries_have_required_keys() -> void:
	var ages := DataLoader.get_ages_data()
	for age in ages:
		assert_bool(age.has("id")).is_true()
		assert_bool(age.has("name")).is_true()
		assert_bool(age.has("index")).is_true()
