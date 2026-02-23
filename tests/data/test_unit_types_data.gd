extends GdUnitTestSuite
## Tests for unit type data files — validates all 6 unit JSON files load correctly
## and have expected properties.

const ALL_UNITS: Array[String] = [
	"villager",
	"infantry",
	"archer",
	"cavalry",
	"siege",
	"naval",
]


func before_test() -> void:
	DataLoader.reload()


func after_test() -> void:
	DataLoader.reload()


# -- Loading --


func test_all_unit_types_load() -> void:
	for unit_name in ALL_UNITS:
		var stats := DataLoader.get_unit_stats(unit_name)
		assert_dict(stats).is_not_empty()
		assert_bool(stats.has("name")).is_true()
		assert_bool(stats.has("hp")).is_true()
		assert_bool(stats.has("attack")).is_true()
		assert_bool(stats.has("defense")).is_true()
		assert_bool(stats.has("speed")).is_true()


func test_all_units_have_category() -> void:
	for unit_name in ALL_UNITS:
		var stats := DataLoader.get_unit_stats(unit_name)
		assert_bool(stats.has("unit_category")).is_true()
		var cat: String = stats["unit_category"]
		assert_bool(cat == "civilian" or cat == "military").is_true()


func test_all_units_have_train_cost() -> void:
	for unit_name in ALL_UNITS:
		var stats := DataLoader.get_unit_stats(unit_name)
		assert_bool(stats.has("train_cost")).is_true()
		assert_dict(stats["train_cost"]).is_not_empty()


# -- Specific unit properties --


func test_archer_is_ranged() -> void:
	var stats := DataLoader.get_unit_stats("archer")
	assert_str(str(stats["attack_type"])).is_equal("ranged")
	var range_val: float = float(stats["range"])
	assert_float(range_val).is_greater(0.0)


func test_cavalry_is_fast() -> void:
	var infantry := DataLoader.get_unit_stats("infantry")
	var cavalry := DataLoader.get_unit_stats("cavalry")
	assert_float(float(cavalry["speed"])).is_greater(float(infantry["speed"]))


func test_siege_has_high_building_damage() -> void:
	var stats := DataLoader.get_unit_stats("siege")
	assert_bool(stats.has("bonus_vs")).is_true()
	var bonus: Dictionary = stats["bonus_vs"]
	assert_bool(bonus.has("building")).is_true()
	assert_float(float(bonus["building"])).is_greater(1.0)


func test_naval_is_water_unit() -> void:
	var stats := DataLoader.get_unit_stats("naval")
	assert_str(str(stats["movement_type"])).is_equal("water")
	assert_bool(stats.has("transport_capacity")).is_true()
	assert_int(int(stats["transport_capacity"])).is_greater(0)


# -- Rock-paper-scissors --


func test_rock_paper_scissors_complete() -> void:
	var infantry := DataLoader.get_unit_stats("infantry")
	var archer := DataLoader.get_unit_stats("archer")
	var cavalry := DataLoader.get_unit_stats("cavalry")
	# Infantry beats archer
	var inf_bonus: Dictionary = infantry["bonus_vs"]
	assert_bool(inf_bonus.has("archer")).is_true()
	assert_float(float(inf_bonus["archer"])).is_greater(1.0)
	# Archer beats cavalry
	var arc_bonus: Dictionary = archer["bonus_vs"]
	assert_bool(arc_bonus.has("cavalry")).is_true()
	assert_float(float(arc_bonus["cavalry"])).is_greater(1.0)
	# Cavalry beats infantry
	var cav_bonus: Dictionary = cavalry["bonus_vs"]
	assert_bool(cav_bonus.has("infantry")).is_true()
	assert_float(float(cav_bonus["infantry"])).is_greater(1.0)
