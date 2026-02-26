extends GdUnitTestSuite
## Tests for legionnaire unit data — Rome unique unit replacing Infantry.


func test_legionnaire_loads() -> void:
	var stats := DataLoader.get_unit_stats("legionnaire")
	assert_dict(stats).is_not_empty()


func test_legionnaire_name() -> void:
	var stats := DataLoader.get_unit_stats("legionnaire")
	assert_str(str(stats.get("name", ""))).is_equal("Legionnaire")


func test_legionnaire_defense_is_4() -> void:
	var stats := DataLoader.get_unit_stats("legionnaire")
	assert_int(int(stats.get("defense", 0))).is_equal(4)


func test_legionnaire_armor_type_is_heavy() -> void:
	var stats := DataLoader.get_unit_stats("legionnaire")
	assert_str(str(stats.get("armor_type", ""))).is_equal("heavy")


func test_legionnaire_has_shield_wall() -> void:
	var stats := DataLoader.get_unit_stats("legionnaire")
	assert_bool(bool(stats.get("shield_wall", false))).is_true()


func test_legionnaire_shield_wall_defense_bonus() -> void:
	var stats := DataLoader.get_unit_stats("legionnaire")
	assert_int(int(stats.get("shield_wall_defense_bonus", 0))).is_equal(3)


func test_legionnaire_has_required_fields() -> void:
	var stats := DataLoader.get_unit_stats("legionnaire")
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
		"shield_wall",
		"shield_wall_defense_bonus",
	]
	for field in required:
		assert_bool(stats.has(field)).is_true()


func test_legionnaire_is_military() -> void:
	var stats := DataLoader.get_unit_stats("legionnaire")
	assert_str(str(stats.get("unit_category", ""))).is_equal("military")


func test_legionnaire_attack_matches_infantry() -> void:
	var stats := DataLoader.get_unit_stats("legionnaire")
	assert_int(int(stats.get("attack", 0))).is_equal(6)


func test_legionnaire_hp_matches_infantry() -> void:
	var stats := DataLoader.get_unit_stats("legionnaire")
	assert_int(int(stats.get("hp", 0))).is_equal(40)
