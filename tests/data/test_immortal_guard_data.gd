extends GdUnitTestSuite
## Tests for immortal guard unit data — Mesopotamia unique unit replacing Infantry.


func test_immortal_guard_loads() -> void:
	var stats := DataLoader.get_unit_stats("immortal_guard")
	assert_dict(stats).is_not_empty()


func test_immortal_guard_name() -> void:
	var stats := DataLoader.get_unit_stats("immortal_guard")
	assert_str(str(stats.get("name", ""))).is_equal("Immortal Guard")


func test_immortal_guard_hp_is_60() -> void:
	var stats := DataLoader.get_unit_stats("immortal_guard")
	assert_int(int(stats.get("hp", 0))).is_equal(60)


func test_immortal_guard_armor_type_is_heavy() -> void:
	var stats := DataLoader.get_unit_stats("immortal_guard")
	assert_str(str(stats.get("armor_type", ""))).is_equal("heavy")


func test_immortal_guard_self_heal_rate_is_0_5() -> void:
	var stats := DataLoader.get_unit_stats("immortal_guard")
	assert_float(float(stats.get("self_heal_rate", 0.0))).is_equal_approx(0.5, 0.001)


func test_immortal_guard_has_required_fields() -> void:
	var stats := DataLoader.get_unit_stats("immortal_guard")
	var required := [
		"name",
		"hp",
		"attack",
		"defense",
		"speed",
		"range",
		"train_cost",
		"armor_type",
		"attack_type",
		"unit_category",
		"self_heal_rate",
	]
	for field in required:
		assert_bool(stats.has(field)).is_true()


func test_immortal_guard_is_military() -> void:
	var stats := DataLoader.get_unit_stats("immortal_guard")
	assert_str(str(stats.get("unit_category", ""))).is_equal("military")


func test_immortal_guard_attack_matches_infantry() -> void:
	var stats := DataLoader.get_unit_stats("immortal_guard")
	assert_int(int(stats.get("attack", 0))).is_equal(6)
