extends GdUnitTestSuite
## Tests for marae building data — Polynesia unique building replacing Library.


func test_marae_loads() -> void:
	var stats := DataLoader.get_building_stats("marae")
	assert_dict(stats).is_not_empty()


func test_marae_name() -> void:
	var stats := DataLoader.get_building_stats("marae")
	assert_str(str(stats.get("name", ""))).is_equal("Marae")


func test_marae_has_required_fields() -> void:
	var stats := DataLoader.get_building_stats("marae")
	var required := [
		"name",
		"hp",
		"footprint",
		"build_time",
		"build_cost",
		"age_required",
		"knowledge_rate",
	]
	for field in required:
		assert_bool(stats.has(field)).is_true()


func test_marae_has_coastline_reveal() -> void:
	var stats := DataLoader.get_building_stats("marae")
	assert_bool(bool(stats.get("coastline_reveal", false))).is_true()


func test_marae_knowledge_rate_matches_library() -> void:
	var stats := DataLoader.get_building_stats("marae")
	assert_float(float(stats.get("knowledge_rate", 0.0))).is_equal_approx(0.5, 0.001)


func test_marae_hp_matches_library() -> void:
	var stats := DataLoader.get_building_stats("marae")
	assert_int(int(stats.get("hp", 0))).is_equal(800)


func test_marae_footprint_matches_library() -> void:
	var stats := DataLoader.get_building_stats("marae")
	var fp: Array = stats.get("footprint", [])
	assert_int(int(fp[0])).is_equal(2)
	assert_int(int(fp[1])).is_equal(2)


func test_marae_age_required() -> void:
	var stats := DataLoader.get_building_stats("marae")
	assert_int(int(stats.get("age_required", 0))).is_equal(2)
