extends GdUnitTestSuite
## Tests for war canoe unit data — Polynesia unique unit replacing War Galley (naval).


func test_war_canoe_loads() -> void:
	var stats := DataLoader.get_unit_stats("war_canoe")
	assert_dict(stats).is_not_empty()


func test_war_canoe_name() -> void:
	var stats := DataLoader.get_unit_stats("war_canoe")
	assert_str(str(stats.get("name", ""))).is_equal("War Canoe")


func test_war_canoe_speed_is_faster() -> void:
	var stats := DataLoader.get_unit_stats("war_canoe")
	var naval_stats := DataLoader.get_unit_stats("war_galley")
	assert_bool(float(stats.get("speed", 0)) > float(naval_stats.get("speed", 0))).is_true()


func test_war_canoe_has_transport_capacity() -> void:
	var stats := DataLoader.get_unit_stats("war_canoe")
	assert_int(int(stats.get("transport_capacity", 0))).is_equal(5)


func test_war_canoe_is_water_movement() -> void:
	var stats := DataLoader.get_unit_stats("war_canoe")
	assert_str(str(stats.get("movement_type", ""))).is_equal("water")


func test_war_canoe_has_required_fields() -> void:
	var stats := DataLoader.get_unit_stats("war_canoe")
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
		"movement_type",
		"transport_capacity",
	]
	for field in required:
		assert_bool(stats.has(field)).is_true()


func test_war_canoe_is_military() -> void:
	var stats := DataLoader.get_unit_stats("war_canoe")
	assert_str(str(stats.get("unit_category", ""))).is_equal("military")


func test_war_canoe_attack_matches_naval() -> void:
	var stats := DataLoader.get_unit_stats("war_canoe")
	assert_int(int(stats.get("attack", 0))).is_equal(8)


func test_war_canoe_hp_matches_naval() -> void:
	var stats := DataLoader.get_unit_stats("war_canoe")
	assert_int(int(stats.get("hp", 0))).is_equal(120)
