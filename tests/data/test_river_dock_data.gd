extends GdUnitTestSuite
## Tests for river_dock.json data file — validates stats load correctly via DataLoader.


func before_test() -> void:
	DataLoader.reload()


func after_test() -> void:
	DataLoader.reload()


func test_river_dock_stats_load_correctly() -> void:
	var stats := DataLoader.get_building_stats("river_dock")
	assert_dict(stats).is_not_empty()
	assert_dict(stats).contains_key_value("name", "River Dock")
	assert_float(stats.get("hp")).is_equal(400.0)
	var footprint: Array = stats.get("footprint", [])
	assert_int(footprint.size()).is_equal(2)
	assert_float(footprint[0]).is_equal(1.0)
	assert_float(footprint[1]).is_equal(1.0)
	assert_float(stats.get("build_time")).is_equal(30.0)
	var cost: Dictionary = stats.get("build_cost", {})
	assert_float(cost.get("wood")).is_equal(100.0)


func test_river_dock_is_universal_drop_off() -> void:
	var stats := DataLoader.get_building_stats("river_dock")
	assert_bool(stats.get("is_drop_off", false)).is_true()
	var types: Array = stats.get("drop_off_types", [])
	for resource_type in ["food", "wood", "stone", "gold", "knowledge"]:
		assert_bool(types.has(resource_type)).is_true()


func test_river_dock_has_placement_constraint() -> void:
	var stats := DataLoader.get_building_stats("river_dock")
	assert_str(stats.get("placement_constraint", "")).is_equal("adjacent_to_river")
