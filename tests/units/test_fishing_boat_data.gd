extends GdUnitTestSuite
## Tests for fishing_boat.json — validates unit data integrity.


func _load_fishing_boat() -> Dictionary:
	return DataLoader.get_unit_stats("fishing_boat")


func test_movement_type_is_water() -> void:
	var stats := _load_fishing_boat()
	assert_str(stats.get("movement_type", "")).is_equal("water")


func test_gather_rates_has_food() -> void:
	var stats := _load_fishing_boat()
	var rates: Dictionary = stats.get("gather_rates", {})
	assert_bool(rates.has("food")).is_true()
	assert_float(float(rates["food"])).is_greater(0.0)


func test_carry_capacity_positive() -> void:
	var stats := _load_fishing_boat()
	assert_int(int(stats.get("carry_capacity", 0))).is_greater(0)


func test_unit_category_is_civilian() -> void:
	var stats := _load_fishing_boat()
	assert_str(stats.get("unit_category", "")).is_equal("civilian")


func test_train_cost_has_wood() -> void:
	var stats := _load_fishing_boat()
	var cost: Dictionary = stats.get("train_cost", {})
	assert_bool(cost.has("wood")).is_true()
	assert_int(int(cost["wood"])).is_greater(0)
