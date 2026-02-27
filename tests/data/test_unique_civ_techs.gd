extends GdUnitTestSuite
## Tests for unique civilization technologies — validates civ-exclusive techs
## load correctly with proper fields, effects, ages, and civ restrictions.

const UNIQUE_TECH_IDS: Array[String] = [
	"cuneiform_writing",
	"hanging_gardens_legacy",
	"roman_roads",
	"testudo",
	"wayfinding",
	"haka",
]


func before_test() -> void:
	DataLoader.reload()


func after_test() -> void:
	DataLoader.reload()


# -- Both unique techs exist --


func test_cuneiform_writing_exists() -> void:
	var data: Dictionary = DataLoader.get_tech_data("cuneiform_writing")
	assert_dict(data).is_not_empty()
	assert_str(data.get("id", "")).is_equal("cuneiform_writing")


func test_hanging_gardens_legacy_exists() -> void:
	var data: Dictionary = DataLoader.get_tech_data("hanging_gardens_legacy")
	assert_dict(data).is_not_empty()
	assert_str(data.get("id", "")).is_equal("hanging_gardens_legacy")


# -- Required fields present --


func test_unique_techs_have_required_fields() -> void:
	var required_fields: Array[String] = [
		"id",
		"name",
		"age",
		"cost",
		"research_time",
		"prerequisites",
		"effects",
	]
	for tech_id in UNIQUE_TECH_IDS:
		var data: Dictionary = DataLoader.get_tech_data(tech_id)
		for field in required_fields:
			assert_bool(data.has(field)).is_true()


# -- Age assignments --


func test_cuneiform_writing_is_iron_age() -> void:
	var data: Dictionary = DataLoader.get_tech_data("cuneiform_writing")
	assert_int(int(data["age"])).is_equal(2)


func test_hanging_gardens_legacy_is_industrial_age() -> void:
	var data: Dictionary = DataLoader.get_tech_data("hanging_gardens_legacy")
	assert_int(int(data["age"])).is_equal(4)


# -- Effects --


func test_cuneiform_writing_has_research_bonus() -> void:
	var data: Dictionary = DataLoader.get_tech_data("cuneiform_writing")
	assert_float(float(data["effects"]["research_bonus"])).is_equal_approx(0.10, 0.001)


func test_hanging_gardens_has_farm_food_rate() -> void:
	var data: Dictionary = DataLoader.get_tech_data("hanging_gardens_legacy")
	var econ: Dictionary = data["effects"]["economic_bonus"]
	assert_float(float(econ["farm_food_rate"])).is_equal_approx(0.20, 0.001)


func test_hanging_gardens_has_building_cost_reduction() -> void:
	var data: Dictionary = DataLoader.get_tech_data("hanging_gardens_legacy")
	var econ: Dictionary = data["effects"]["economic_bonus"]
	assert_float(float(econ["building_cost_reduction"])).is_equal_approx(0.10, 0.001)


# -- Civ exclusivity --


func test_cuneiform_writing_is_mesopotamia_exclusive() -> void:
	var data: Dictionary = DataLoader.get_tech_data("cuneiform_writing")
	assert_str(data.get("civ_exclusive", "")).is_equal("mesopotamia")


func test_hanging_gardens_is_mesopotamia_exclusive() -> void:
	var data: Dictionary = DataLoader.get_tech_data("hanging_gardens_legacy")
	assert_str(data.get("civ_exclusive", "")).is_equal("mesopotamia")


# -- Flavor text --


func test_unique_techs_have_flavor_text() -> void:
	for tech_id in UNIQUE_TECH_IDS:
		var data: Dictionary = DataLoader.get_tech_data(tech_id)
		assert_bool(data.has("flavor_text")).is_true()
		assert_str(data["flavor_text"]).is_not_empty()


# -- Prerequisites exist in tree --


func test_cuneiform_writing_requires_writing() -> void:
	var data: Dictionary = DataLoader.get_tech_data("cuneiform_writing")
	var prereqs: Array = data["prerequisites"]
	assert_bool("writing" in prereqs).is_true()


func test_hanging_gardens_requires_agriculture() -> void:
	var data: Dictionary = DataLoader.get_tech_data("hanging_gardens_legacy")
	var prereqs: Array = data["prerequisites"]
	assert_bool("agriculture" in prereqs).is_true()


func test_unique_tech_prereqs_exist_in_tree() -> void:
	for tech_id in UNIQUE_TECH_IDS:
		var data: Dictionary = DataLoader.get_tech_data(tech_id)
		var prereqs: Array = data["prerequisites"]
		for prereq_id in prereqs:
			var prereq_data: Dictionary = DataLoader.get_tech_data(prereq_id)
			assert_dict(prereq_data).is_not_empty()


# -- Costs are non-empty --


func test_unique_techs_have_costs() -> void:
	for tech_id in UNIQUE_TECH_IDS:
		var data: Dictionary = DataLoader.get_tech_data(tech_id)
		assert_dict(data["cost"]).is_not_empty()


# -- Total tech count (86 base + 6 unique = 92) --


func test_total_tech_count_is_92() -> void:
	var data: Variant = DataLoader.load_json("res://data/tech/tech_tree.json")
	assert_int(data.size()).is_equal(92)


# -- Mesopotamia civ data references unique techs --


func test_mesopotamia_civ_has_unique_techs_array() -> void:
	var civ_data: Dictionary = DataLoader.get_civ_data("mesopotamia")
	assert_bool(civ_data.has("unique_techs")).is_true()
	var techs: Array = civ_data["unique_techs"]
	assert_int(techs.size()).is_equal(2)
	assert_bool("cuneiform_writing" in techs).is_true()
	assert_bool("hanging_gardens_legacy" in techs).is_true()


# -- Rome unique techs --


func test_roman_roads_exists() -> void:
	var data: Dictionary = DataLoader.get_tech_data("roman_roads")
	assert_dict(data).is_not_empty()
	assert_str(data.get("id", "")).is_equal("roman_roads")


func test_testudo_exists() -> void:
	var data: Dictionary = DataLoader.get_tech_data("testudo")
	assert_dict(data).is_not_empty()
	assert_str(data.get("id", "")).is_equal("testudo")


func test_roman_roads_is_iron_age() -> void:
	var data: Dictionary = DataLoader.get_tech_data("roman_roads")
	assert_int(int(data["age"])).is_equal(2)


func test_testudo_is_classical_age() -> void:
	var data: Dictionary = DataLoader.get_tech_data("testudo")
	assert_int(int(data["age"])).is_equal(3)


func test_roman_roads_has_speed_bonus() -> void:
	var data: Dictionary = DataLoader.get_tech_data("roman_roads")
	assert_float(float(data["effects"]["unit_speed_bonus"])).is_equal_approx(0.15, 0.001)


func test_testudo_has_ranged_defense_bonus() -> void:
	var data: Dictionary = DataLoader.get_tech_data("testudo")
	assert_float(float(data["effects"]["ranged_defense_bonus"])).is_equal_approx(0.20, 0.001)


func test_roman_roads_is_rome_exclusive() -> void:
	var data: Dictionary = DataLoader.get_tech_data("roman_roads")
	assert_str(data.get("civ_exclusive", "")).is_equal("rome")


func test_testudo_is_rome_exclusive() -> void:
	var data: Dictionary = DataLoader.get_tech_data("testudo")
	assert_str(data.get("civ_exclusive", "")).is_equal("rome")


func test_roman_roads_requires_engineering() -> void:
	var data: Dictionary = DataLoader.get_tech_data("roman_roads")
	assert_bool("engineering" in data["prerequisites"]).is_true()


func test_testudo_requires_iron_working() -> void:
	var data: Dictionary = DataLoader.get_tech_data("testudo")
	assert_bool("iron_working" in data["prerequisites"]).is_true()


func test_rome_civ_has_unique_techs_array() -> void:
	var civ_data: Dictionary = DataLoader.get_civ_data("rome")
	assert_bool(civ_data.has("unique_techs")).is_true()
	var techs: Array = civ_data["unique_techs"]
	assert_int(techs.size()).is_equal(2)
	assert_bool("roman_roads" in techs).is_true()
	assert_bool("testudo" in techs).is_true()


# -- Polynesia unique techs --


func test_wayfinding_exists() -> void:
	var data: Dictionary = DataLoader.get_tech_data("wayfinding")
	assert_dict(data).is_not_empty()
	assert_str(data.get("id", "")).is_equal("wayfinding")


func test_haka_exists() -> void:
	var data: Dictionary = DataLoader.get_tech_data("haka")
	assert_dict(data).is_not_empty()
	assert_str(data.get("id", "")).is_equal("haka")


func test_wayfinding_is_iron_age() -> void:
	var data: Dictionary = DataLoader.get_tech_data("wayfinding")
	assert_int(int(data["age"])).is_equal(2)


func test_haka_is_classical_age() -> void:
	var data: Dictionary = DataLoader.get_tech_data("haka")
	assert_int(int(data["age"])).is_equal(3)


func test_wayfinding_has_naval_los_bonus() -> void:
	var data: Dictionary = DataLoader.get_tech_data("wayfinding")
	assert_float(float(data["effects"]["naval_los_bonus"])).is_equal_approx(0.30, 0.001)


func test_haka_has_battle_cry_attack_bonus() -> void:
	var data: Dictionary = DataLoader.get_tech_data("haka")
	assert_float(float(data["effects"]["battle_cry_attack_bonus"])).is_equal_approx(0.15, 0.001)


func test_haka_has_battle_cry_duration() -> void:
	var data: Dictionary = DataLoader.get_tech_data("haka")
	assert_float(float(data["effects"]["battle_cry_duration"])).is_equal_approx(30.0, 0.1)


func test_wayfinding_is_polynesia_exclusive() -> void:
	var data: Dictionary = DataLoader.get_tech_data("wayfinding")
	assert_str(data.get("civ_exclusive", "")).is_equal("polynesia")


func test_haka_is_polynesia_exclusive() -> void:
	var data: Dictionary = DataLoader.get_tech_data("haka")
	assert_str(data.get("civ_exclusive", "")).is_equal("polynesia")


func test_wayfinding_requires_sailing() -> void:
	var data: Dictionary = DataLoader.get_tech_data("wayfinding")
	assert_bool("sailing" in data["prerequisites"]).is_true()


func test_haka_requires_iron_working() -> void:
	var data: Dictionary = DataLoader.get_tech_data("haka")
	assert_bool("iron_working" in data["prerequisites"]).is_true()


func test_polynesia_civ_has_unique_techs_array() -> void:
	var civ_data: Dictionary = DataLoader.get_civ_data("polynesia")
	assert_bool(civ_data.has("unique_techs")).is_true()
	var techs: Array = civ_data["unique_techs"]
	assert_int(techs.size()).is_equal(2)
	assert_bool("wayfinding" in techs).is_true()
	assert_bool("haka" in techs).is_true()
