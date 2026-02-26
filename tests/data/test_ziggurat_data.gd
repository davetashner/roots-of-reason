extends GdUnitTestSuite
## Tests for ziggurat building data — Mesopotamia unique building replacing Library.


func test_ziggurat_loads() -> void:
	var stats := DataLoader.get_building_stats("ziggurat")
	assert_dict(stats).is_not_empty()


func test_ziggurat_name() -> void:
	var stats := DataLoader.get_building_stats("ziggurat")
	assert_str(str(stats.get("name", ""))).is_equal("Ziggurat")


func test_ziggurat_has_required_fields() -> void:
	var stats := DataLoader.get_building_stats("ziggurat")
	var required := ["name", "hp", "footprint", "build_time", "build_cost", "age_required", "knowledge_rate"]
	for field in required:
		assert_bool(stats.has(field)).is_true()


func test_ziggurat_knowledge_rate_is_0_75() -> void:
	var stats := DataLoader.get_building_stats("ziggurat")
	assert_float(float(stats.get("knowledge_rate", 0.0))).is_equal_approx(0.75, 0.001)


func test_ziggurat_hp_matches_library() -> void:
	var stats := DataLoader.get_building_stats("ziggurat")
	assert_int(int(stats.get("hp", 0))).is_equal(800)


func test_ziggurat_footprint_matches_library() -> void:
	var stats := DataLoader.get_building_stats("ziggurat")
	var fp: Array = stats.get("footprint", [])
	assert_int(int(fp[0])).is_equal(2)
	assert_int(int(fp[1])).is_equal(2)


func test_ziggurat_age_required() -> void:
	var stats := DataLoader.get_building_stats("ziggurat")
	assert_int(int(stats.get("age_required", 0))).is_equal(2)
