extends GdUnitTestSuite
## Tests for the 13-tech historical expansion — validates all new techs load
## correctly with proper fields, prereqs, costs, effects, and age assignments.

const NEW_TECH_IDS: Array[String] = [
	"agriculture",
	"the_wheel",
	"road_building",
	"astronomy",
	"mechanical_power",
	"optics",
	"telegraph_comm",
	"aviation",
	"democracy",
	"spaceflight",
	"renewable_energy",
	"brain_computer_interface",
	"trade_routes",
]

## Expected age index for each new tech.
var _expected_ages: Dictionary = {
	"agriculture": 0,
	"the_wheel": 1,
	"road_building": 2,
	"astronomy": 2,
	"mechanical_power": 3,
	"optics": 3,
	"telegraph_comm": 4,
	"aviation": 4,
	"democracy": 4,
	"spaceflight": 5,
	"renewable_energy": 5,
	"brain_computer_interface": 6,
	"trade_routes": 3,
}

## Expected prerequisites for each new tech.
var _expected_prereqs: Dictionary = {
	"agriculture": [],
	"the_wheel": ["agriculture"],
	"road_building": ["the_wheel"],
	"astronomy": ["mathematics"],
	"mechanical_power": ["engineering"],
	"optics": ["astronomy"],
	"telegraph_comm": ["electricity"],
	"aviation": ["steam_power"],
	"democracy": ["philosophy"],
	"spaceflight": ["rocketry"],
	"renewable_energy": ["electricity"],
	"brain_computer_interface": ["machine_learning"],
	"trade_routes": ["sailing"],
}


func before_test() -> void:
	DataLoader.reload()


func after_test() -> void:
	DataLoader.reload()


# -- All 13 techs load --


func test_all_new_techs_exist() -> void:
	for tech_id in NEW_TECH_IDS:
		var data: Dictionary = DataLoader.get_tech_data(tech_id)
		assert_dict(data).is_not_empty()
		assert_str(data.get("id", "")).is_equal(tech_id)


# -- Required fields present --


func test_all_new_techs_have_required_fields() -> void:
	var required_fields: Array[String] = [
		"id",
		"name",
		"age",
		"cost",
		"research_time",
		"prerequisites",
		"effects",
	]
	for tech_id in NEW_TECH_IDS:
		var data: Dictionary = DataLoader.get_tech_data(tech_id)
		for field in required_fields:
			assert_bool(data.has(field)).is_true()


# -- Age assignments --


func test_agriculture_is_stone_age() -> void:
	var data: Dictionary = DataLoader.get_tech_data("agriculture")
	assert_int(int(data["age"])).is_equal(0)


func test_the_wheel_is_bronze_age() -> void:
	var data: Dictionary = DataLoader.get_tech_data("the_wheel")
	assert_int(int(data["age"])).is_equal(1)


func test_road_building_is_iron_age() -> void:
	var data: Dictionary = DataLoader.get_tech_data("road_building")
	assert_int(int(data["age"])).is_equal(2)


func test_astronomy_is_iron_age() -> void:
	var data: Dictionary = DataLoader.get_tech_data("astronomy")
	assert_int(int(data["age"])).is_equal(2)


func test_mechanical_power_is_medieval_age() -> void:
	var data: Dictionary = DataLoader.get_tech_data("mechanical_power")
	assert_int(int(data["age"])).is_equal(3)


func test_optics_is_medieval_age() -> void:
	var data: Dictionary = DataLoader.get_tech_data("optics")
	assert_int(int(data["age"])).is_equal(3)


func test_trade_routes_is_medieval_age() -> void:
	var data: Dictionary = DataLoader.get_tech_data("trade_routes")
	assert_int(int(data["age"])).is_equal(3)


func test_telegraph_comm_is_industrial_age() -> void:
	var data: Dictionary = DataLoader.get_tech_data("telegraph_comm")
	assert_int(int(data["age"])).is_equal(4)


func test_aviation_is_industrial_age() -> void:
	var data: Dictionary = DataLoader.get_tech_data("aviation")
	assert_int(int(data["age"])).is_equal(4)


func test_democracy_is_industrial_age() -> void:
	var data: Dictionary = DataLoader.get_tech_data("democracy")
	assert_int(int(data["age"])).is_equal(4)


func test_spaceflight_is_information_age() -> void:
	var data: Dictionary = DataLoader.get_tech_data("spaceflight")
	assert_int(int(data["age"])).is_equal(5)


func test_renewable_energy_is_information_age() -> void:
	var data: Dictionary = DataLoader.get_tech_data("renewable_energy")
	assert_int(int(data["age"])).is_equal(5)


func test_brain_computer_interface_is_singularity_age() -> void:
	var data: Dictionary = DataLoader.get_tech_data("brain_computer_interface")
	assert_int(int(data["age"])).is_equal(6)


# -- All age assignments correct --


func test_all_new_techs_age_assignments() -> void:
	for tech_id in NEW_TECH_IDS:
		var data: Dictionary = DataLoader.get_tech_data(tech_id)
		var expected_age: int = _expected_ages[tech_id]
		assert_int(int(data["age"])).is_equal(expected_age)


# -- Prerequisites --


func test_agriculture_has_no_prereqs() -> void:
	var data: Dictionary = DataLoader.get_tech_data("agriculture")
	var prereqs: Array = data["prerequisites"]
	assert_int(prereqs.size()).is_equal(0)


func test_the_wheel_requires_agriculture() -> void:
	var data: Dictionary = DataLoader.get_tech_data("the_wheel")
	var prereqs: Array = data["prerequisites"]
	assert_bool("agriculture" in prereqs).is_true()


func test_road_building_requires_the_wheel() -> void:
	var data: Dictionary = DataLoader.get_tech_data("road_building")
	var prereqs: Array = data["prerequisites"]
	assert_bool("the_wheel" in prereqs).is_true()


func test_astronomy_requires_mathematics() -> void:
	var data: Dictionary = DataLoader.get_tech_data("astronomy")
	var prereqs: Array = data["prerequisites"]
	assert_bool("mathematics" in prereqs).is_true()


func test_mechanical_power_requires_engineering() -> void:
	var data: Dictionary = DataLoader.get_tech_data("mechanical_power")
	var prereqs: Array = data["prerequisites"]
	assert_bool("engineering" in prereqs).is_true()


func test_optics_requires_astronomy() -> void:
	var data: Dictionary = DataLoader.get_tech_data("optics")
	var prereqs: Array = data["prerequisites"]
	assert_bool("astronomy" in prereqs).is_true()


func test_telegraph_comm_requires_electricity() -> void:
	var data: Dictionary = DataLoader.get_tech_data("telegraph_comm")
	var prereqs: Array = data["prerequisites"]
	assert_bool("electricity" in prereqs).is_true()


func test_aviation_requires_steam_power() -> void:
	var data: Dictionary = DataLoader.get_tech_data("aviation")
	var prereqs: Array = data["prerequisites"]
	assert_bool("steam_power" in prereqs).is_true()


func test_democracy_requires_philosophy() -> void:
	var data: Dictionary = DataLoader.get_tech_data("democracy")
	var prereqs: Array = data["prerequisites"]
	assert_bool("philosophy" in prereqs).is_true()


func test_spaceflight_requires_rocketry() -> void:
	var data: Dictionary = DataLoader.get_tech_data("spaceflight")
	var prereqs: Array = data["prerequisites"]
	assert_bool("rocketry" in prereqs).is_true()


func test_renewable_energy_requires_electricity() -> void:
	var data: Dictionary = DataLoader.get_tech_data("renewable_energy")
	var prereqs: Array = data["prerequisites"]
	assert_bool("electricity" in prereqs).is_true()


func test_brain_computer_interface_requires_machine_learning() -> void:
	var data: Dictionary = DataLoader.get_tech_data("brain_computer_interface")
	var prereqs: Array = data["prerequisites"]
	assert_bool("machine_learning" in prereqs).is_true()


func test_trade_routes_requires_sailing() -> void:
	var data: Dictionary = DataLoader.get_tech_data("trade_routes")
	var prereqs: Array = data["prerequisites"]
	assert_bool("sailing" in prereqs).is_true()


# -- All prereqs reference existing techs --


func test_all_new_tech_prereqs_exist_in_tree() -> void:
	for tech_id in NEW_TECH_IDS:
		var data: Dictionary = DataLoader.get_tech_data(tech_id)
		var prereqs: Array = data["prerequisites"]
		for prereq_id in prereqs:
			var prereq_data: Dictionary = DataLoader.get_tech_data(prereq_id)
			assert_dict(prereq_data).is_not_empty()


# -- Costs are non-empty --


func test_all_new_techs_have_costs() -> void:
	for tech_id in NEW_TECH_IDS:
		var data: Dictionary = DataLoader.get_tech_data(tech_id)
		assert_dict(data["cost"]).is_not_empty()


# -- Specific cost checks --


func test_agriculture_costs_50_food() -> void:
	var data: Dictionary = DataLoader.get_tech_data("agriculture")
	assert_int(int(data["cost"]["food"])).is_equal(50)


func test_the_wheel_costs_100_wood_50_stone() -> void:
	var data: Dictionary = DataLoader.get_tech_data("the_wheel")
	assert_int(int(data["cost"]["wood"])).is_equal(100)
	assert_int(int(data["cost"]["stone"])).is_equal(50)


func test_brain_computer_interface_costs_1000_knowledge_500_gold() -> void:
	var data: Dictionary = DataLoader.get_tech_data("brain_computer_interface")
	assert_int(int(data["cost"]["knowledge"])).is_equal(1000)
	assert_int(int(data["cost"]["gold"])).is_equal(500)


# -- Effects are non-empty --


func test_all_new_techs_have_effects() -> void:
	for tech_id in NEW_TECH_IDS:
		var data: Dictionary = DataLoader.get_tech_data(tech_id)
		assert_dict(data["effects"]).is_not_empty()


# -- Specific effect checks --


func test_agriculture_has_farm_food_rate_bonus() -> void:
	var data: Dictionary = DataLoader.get_tech_data("agriculture")
	var econ: Dictionary = data["effects"]["economic_bonus"]
	assert_float(float(econ["farm_food_rate"])).is_equal_approx(0.25, 0.001)


func test_the_wheel_has_unit_speed_modifier() -> void:
	var data: Dictionary = DataLoader.get_tech_data("the_wheel")
	var mods: Dictionary = data["effects"]["stat_modifiers"]
	assert_float(float(mods["unit_speed"])).is_equal_approx(0.15, 0.001)


func test_road_building_has_territory_movement() -> void:
	var data: Dictionary = DataLoader.get_tech_data("road_building")
	var mods: Dictionary = data["effects"]["stat_modifiers"]
	assert_float(float(mods["territory_movement_speed"])).is_equal_approx(0.20, 0.001)


func test_astronomy_has_los_bonus() -> void:
	var data: Dictionary = DataLoader.get_tech_data("astronomy")
	var mods: Dictionary = data["effects"]["stat_modifiers"]
	assert_float(float(mods["unit_los"])).is_equal_approx(0.20, 0.001)


func test_mechanical_power_has_gather_rate() -> void:
	var data: Dictionary = DataLoader.get_tech_data("mechanical_power")
	var econ: Dictionary = data["effects"]["economic_bonus"]
	assert_float(float(econ["gather_rate"])).is_equal_approx(0.25, 0.001)


func test_optics_has_archer_range() -> void:
	var data: Dictionary = DataLoader.get_tech_data("optics")
	var mods: Dictionary = data["effects"]["stat_modifiers"]
	assert_float(float(mods["archer_range"])).is_equal_approx(0.30, 0.001)


func test_telegraph_comm_has_research_bonus() -> void:
	var data: Dictionary = DataLoader.get_tech_data("telegraph_comm")
	assert_float(float(data["effects"]["research_bonus"])).is_equal_approx(0.15, 0.001)


func test_aviation_unlocks_scout_plane() -> void:
	var data: Dictionary = DataLoader.get_tech_data("aviation")
	var units: Array = data["effects"]["unlock_units"]
	assert_bool("scout_plane" in units).is_true()


func test_democracy_has_corruption_reduction() -> void:
	var data: Dictionary = DataLoader.get_tech_data("democracy")
	assert_float(float(data["effects"]["corruption_reduction"])).is_equal_approx(0.20, 0.001)


func test_spaceflight_has_knowledge_rate() -> void:
	var data: Dictionary = DataLoader.get_tech_data("spaceflight")
	var econ: Dictionary = data["effects"]["economic_bonus"]
	assert_float(float(econ["knowledge_rate"])).is_equal_approx(0.50, 0.001)


func test_renewable_energy_has_building_cost_reduction() -> void:
	var data: Dictionary = DataLoader.get_tech_data("renewable_energy")
	var econ: Dictionary = data["effects"]["economic_bonus"]
	assert_float(float(econ["building_cost_reduction"])).is_equal_approx(0.30, 0.001)


func test_brain_computer_interface_has_research_bonus() -> void:
	var data: Dictionary = DataLoader.get_tech_data("brain_computer_interface")
	assert_float(float(data["effects"]["research_bonus"])).is_equal_approx(1.0, 0.001)


func test_trade_routes_has_trade_gold_income() -> void:
	var data: Dictionary = DataLoader.get_tech_data("trade_routes")
	var econ: Dictionary = data["effects"]["economic_bonus"]
	assert_float(float(econ["trade_gold_income"])).is_equal_approx(0.50, 0.001)


# -- Research times are positive --


func test_all_new_techs_have_positive_research_time() -> void:
	for tech_id in NEW_TECH_IDS:
		var data: Dictionary = DataLoader.get_tech_data(tech_id)
		assert_float(float(data["research_time"])).is_greater(0.0)


# -- Flavor text present --


func test_all_new_techs_have_flavor_text() -> void:
	for tech_id in NEW_TECH_IDS:
		var data: Dictionary = DataLoader.get_tech_data(tech_id)
		assert_bool(data.has("flavor_text")).is_true()
		assert_str(data["flavor_text"]).is_not_empty()


# -- No circular dependencies --


func test_no_circular_prereqs_in_new_techs() -> void:
	## Verifies that following the prereq chain from any new tech does not
	## create a cycle. Uses recursive path tracking.
	for tech_id in NEW_TECH_IDS:
		var path: Dictionary = {}
		var result: bool = _check_no_cycle(tech_id, path)
		assert_bool(result).is_true()


func _check_no_cycle(tech_id: String, path: Dictionary) -> bool:
	if tech_id in path:
		return false
	path[tech_id] = true
	var data: Dictionary = DataLoader.get_tech_data(tech_id)
	if data.is_empty():
		path.erase(tech_id)
		return true
	for prereq in data["prerequisites"]:
		if not _check_no_cycle(prereq, path):
			return false
	path.erase(tech_id)
	return true


# -- Total tech count --


func test_total_tech_count_is_86() -> void:
	var data: Variant = DataLoader.load_json("res://data/tech/tech_tree.json")
	assert_int(data.size()).is_equal(86)
