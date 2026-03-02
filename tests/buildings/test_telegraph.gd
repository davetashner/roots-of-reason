extends GdUnitTestSuite
## Tests for Telegraph building — Industrial Age, +15% research speed bonus,
## unlocked by Electricity tech.

const TechManagerScript := preload("res://scripts/prototype/tech_manager.gd")

var _original_age: int = 0


func before() -> void:
	_original_age = GameManager.current_age


func after() -> void:
	GameManager.current_age = _original_age


# -- Data loading tests --


func test_telegraph_data_loads() -> void:
	var stats: Dictionary = DataLoader.get_building_stats("telegraph")
	assert_dict(stats).is_not_empty()


func test_telegraph_name() -> void:
	var stats: Dictionary = DataLoader.get_building_stats("telegraph")
	assert_str(str(stats.get("name", ""))).is_equal("Telegraph")


func test_telegraph_has_required_fields() -> void:
	var stats: Dictionary = DataLoader.get_building_stats("telegraph")
	var required: Array[String] = [
		"name",
		"hp",
		"footprint",
		"build_time",
		"build_cost",
		"age_required",
		"los",
		"effects",
	]
	for field in required:
		assert_bool(stats.has(field)).is_true()


func test_telegraph_footprint_is_2x2() -> void:
	var stats: Dictionary = DataLoader.get_building_stats("telegraph")
	var fp: Array = stats.get("footprint", [])
	assert_int(int(fp[0])).is_equal(2)
	assert_int(int(fp[1])).is_equal(2)


func test_telegraph_hp() -> void:
	var stats: Dictionary = DataLoader.get_building_stats("telegraph")
	assert_int(int(stats.get("hp", 0))).is_equal(600)


func test_telegraph_build_cost() -> void:
	var stats: Dictionary = DataLoader.get_building_stats("telegraph")
	var cost: Dictionary = stats.get("build_cost", {})
	assert_int(int(cost.get("wood", 0))).is_equal(150)
	assert_int(int(cost.get("gold", 0))).is_equal(100)


func test_telegraph_age_required_is_industrial() -> void:
	var stats: Dictionary = DataLoader.get_building_stats("telegraph")
	assert_int(int(stats.get("age_required", -1))).is_equal(4)


func test_telegraph_research_speed_bonus_in_data() -> void:
	var stats: Dictionary = DataLoader.get_building_stats("telegraph")
	var effects: Dictionary = stats.get("effects", {})
	assert_float(float(effects.get("research_speed_bonus", 0.0))).is_equal_approx(0.15, 0.001)


# -- Tech unlock tests --


func test_telegraph_unlocked_by_electricity() -> void:
	var tech_data: Dictionary = DataLoader.get_tech_data("electricity")
	var effects: Dictionary = tech_data.get("effects", {})
	var unlock_buildings: Array = effects.get("unlock_buildings", [])
	assert_array(unlock_buildings).contains(["telegraph"])


func test_telegraph_unavailable_before_electricity() -> void:
	## Verifies electricity tech prerequisites gate Telegraph access.
	var tech_data: Dictionary = DataLoader.get_tech_data("electricity")
	var prereqs: Array = tech_data.get("prerequisites", [])
	assert_bool(prereqs.size() > 0).is_true()
	# Electricity requires mathematics and steam_power
	assert_array(prereqs).contains(["mathematics", "steam_power"])


# -- Research bonus tests --


func test_telegraph_research_bonus_applied() -> void:
	## When add_building_research_bonus is called, the bonus is tracked.
	var tm: Node = Node.new()
	tm.set_script(TechManagerScript)
	add_child(tm)
	auto_free(tm)
	# Initially no building bonus
	assert_float(tm.get_building_research_bonus(0)).is_equal_approx(0.0, 0.001)
	# Apply telegraph bonus
	tm.add_building_research_bonus(0, 0.15)
	assert_float(tm.get_building_research_bonus(0)).is_equal_approx(0.15, 0.001)


func test_telegraph_research_bonus_stacks() -> void:
	## Multiple telegraphs should stack their bonuses.
	var tm: Node = Node.new()
	tm.set_script(TechManagerScript)
	add_child(tm)
	auto_free(tm)
	tm.add_building_research_bonus(0, 0.15)
	tm.add_building_research_bonus(0, 0.15)
	assert_float(tm.get_building_research_bonus(0)).is_equal_approx(0.30, 0.001)


func test_telegraph_research_bonus_removed_on_destroy() -> void:
	## When a telegraph is destroyed, its bonus is removed.
	var tm: Node = Node.new()
	tm.set_script(TechManagerScript)
	add_child(tm)
	auto_free(tm)
	tm.add_building_research_bonus(0, 0.15)
	tm.add_building_research_bonus(0, 0.15)
	tm.remove_building_research_bonus(0, 0.15)
	assert_float(tm.get_building_research_bonus(0)).is_equal_approx(0.15, 0.001)


func test_telegraph_bonus_does_not_go_negative() -> void:
	## Removing more bonus than exists clamps to zero.
	var tm: Node = Node.new()
	tm.set_script(TechManagerScript)
	add_child(tm)
	auto_free(tm)
	tm.add_building_research_bonus(0, 0.15)
	tm.remove_building_research_bonus(0, 0.30)
	assert_float(tm.get_building_research_bonus(0)).is_equal_approx(0.0, 0.001)
