extends GdUnitTestSuite
## Tests for colosseum building data — Rome unique building replacing Market.


func test_colosseum_loads() -> void:
	var stats := DataLoader.get_building_stats("colosseum")
	assert_dict(stats).is_not_empty()


func test_colosseum_name() -> void:
	var stats := DataLoader.get_building_stats("colosseum")
	assert_str(str(stats.get("name", ""))).is_equal("Colosseum")


func test_colosseum_has_required_fields() -> void:
	var stats := DataLoader.get_building_stats("colosseum")
	var required := [
		"name",
		"hp",
		"footprint",
		"build_time",
		"build_cost",
		"age_required",
	]
	for field in required:
		assert_bool(stats.has(field)).is_true()


func test_colosseum_has_morale_aura() -> void:
	var stats := DataLoader.get_building_stats("colosseum")
	assert_bool(bool(stats.get("morale_aura", false))).is_true()


func test_colosseum_morale_speed_bonus() -> void:
	var stats := DataLoader.get_building_stats("colosseum")
	assert_float(float(stats.get("morale_speed_bonus", 0.0))).is_equal_approx(0.05, 0.001)


func test_colosseum_hp_matches_market() -> void:
	var stats := DataLoader.get_building_stats("colosseum")
	assert_int(int(stats.get("hp", 0))).is_equal(1000)


func test_colosseum_footprint_matches_market() -> void:
	var stats := DataLoader.get_building_stats("colosseum")
	var fp: Array = stats.get("footprint", [])
	assert_int(int(fp[0])).is_equal(3)
	assert_int(int(fp[1])).is_equal(3)


func test_colosseum_produces_trade_cart() -> void:
	var stats := DataLoader.get_building_stats("colosseum")
	var units: Array = stats.get("units_produced", [])
	assert_array(units).contains(["trade_cart"])


func test_colosseum_has_trade_rates() -> void:
	var stats := DataLoader.get_building_stats("colosseum")
	assert_bool(stats.has("trade_rates")).is_true()
