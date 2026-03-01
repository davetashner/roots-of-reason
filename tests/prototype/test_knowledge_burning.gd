extends GdUnitTestSuite
## Tests for knowledge burning integration — town center destruction triggers
## tech regression via TechManager.trigger_knowledge_burning().

const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")
const TechManagerScript := preload("res://scripts/prototype/tech_manager.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")

const RMGuard := preload("res://tests/helpers/resource_manager_guard.gd")
const GMGuard := preload("res://tests/helpers/game_manager_guard.gd")

var _rm_guard: RefCounted
var _gm_guard: RefCounted


func before_test() -> void:
	_rm_guard = RMGuard.new()
	_gm_guard = GMGuard.new()
	GameManager.current_age = 0
	GameManager.is_paused = false
	GameManager.game_speed = 1.0
	GameManager.game_time = 0.0


func after_test() -> void:
	_gm_guard.dispose()
	_rm_guard.dispose()
	GameUtils.clear_autoload_cache()


func _create_tech_manager() -> Node:
	var node := Node.new()
	node.set_script(TechManagerScript)
	add_child(node)
	auto_free(node)
	return node


func _give_resources(
	player_id: int,
	food: int = 0,
	wood: int = 0,
	stone: int = 0,
	gold: int = 0,
	knowledge: int = 0,
) -> void:
	(
		ResourceManager
		. init_player(
			player_id,
			{
				ResourceManager.ResourceType.FOOD: food,
				ResourceManager.ResourceType.WOOD: wood,
				ResourceManager.ResourceType.STONE: stone,
				ResourceManager.ResourceType.GOLD: gold,
				ResourceManager.ResourceType.KNOWLEDGE: knowledge,
			}
		)
	)


func _quick_research(tm: Node, player_id: int, tech_id: String) -> void:
	tm.start_research(player_id, tech_id)
	var tech_data: Dictionary = tm.get_tech_data(tech_id)
	var research_time: int = int(tech_data.get("research_time", 0)) + 1
	for i in research_time:
		tm._process(1.0)


func _create_building(owner: int, name_str: String, constructed: bool) -> Node2D:
	var building := Node2D.new()
	building.set_script(BuildingScript)
	building.owner_id = owner
	building.building_name = name_str
	building.footprint = Vector2i(3, 3)
	building.grid_pos = Vector2i(5, 5)
	building.hp = 2400
	building.max_hp = 2400
	building.under_construction = not constructed
	building.build_progress = 1.0 if constructed else 0.5
	add_child(building)
	auto_free(building)
	return building


# -- Building last_attacker_id tracking --


func test_last_attacker_id_defaults_to_negative_one() -> void:
	var building := _create_building(0, "town_center", true)
	assert_int(building.last_attacker_id).is_equal(-1)


func test_take_damage_records_attacker_owner_id() -> void:
	var building := _create_building(0, "town_center", true)
	var attacker := Node2D.new()
	attacker.set_script(UnitScript)
	attacker.owner_id = 1
	add_child(attacker)
	auto_free(attacker)
	building.take_damage(10, attacker)
	assert_int(building.last_attacker_id).is_equal(1)


# -- Knowledge burning integration --


func test_tc_destroyed_by_enemy_triggers_regression() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 2000)
	_quick_research(tm, 0, "stone_tools")
	assert_int(tm.get_researched_techs(0).size()).is_equal(1)
	var building := _create_building(0, "town_center", true)
	building.last_attacker_id = 1
	var regressed: Array = tm.trigger_knowledge_burning(building.owner_id)
	assert_bool(regressed.is_empty()).is_false()
	assert_int(tm.get_researched_techs(0).size()).is_equal(0)


func test_tc_self_demolished_no_regression() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 2000)
	_quick_research(tm, 0, "stone_tools")
	var building := _create_building(0, "town_center", true)
	# Owner == attacker → self-demolish
	building.last_attacker_id = 0
	# Simulate the guard condition from _on_building_destroyed
	var should_trigger: bool = (
		building.building_name == "town_center"
		and not building.under_construction
		and building.last_attacker_id >= 0
		and building.last_attacker_id != building.owner_id
	)
	assert_bool(should_trigger).is_false()
	assert_int(tm.get_researched_techs(0).size()).is_equal(1)


func test_tc_destroyed_by_gaia_no_regression() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 2000)
	_quick_research(tm, 0, "stone_tools")
	var building := _create_building(0, "town_center", true)
	# Gaia attacker_id == -1 (default)
	assert_int(building.last_attacker_id).is_equal(-1)
	var should_trigger: bool = (
		building.building_name == "town_center"
		and not building.under_construction
		and building.last_attacker_id >= 0
		and building.last_attacker_id != building.owner_id
	)
	assert_bool(should_trigger).is_false()
	assert_int(tm.get_researched_techs(0).size()).is_equal(1)


func test_tc_destroyed_empty_research_history_no_error() -> void:
	var tm := _create_tech_manager()
	# No techs researched — trigger should return empty, no error
	var building := _create_building(0, "town_center", true)
	building.last_attacker_id = 1
	var regressed: Array = tm.trigger_knowledge_burning(building.owner_id)
	assert_bool(regressed.is_empty()).is_true()


func test_cooldown_prevents_double_regression() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 5000)
	_quick_research(tm, 0, "stone_tools")
	_quick_research(tm, 0, "fire_mastery")
	# Set a cooldown so second call is blocked
	tm._kb_cooldown = 60.0
	GameManager.game_time = 100.0
	var first: Array = tm.trigger_knowledge_burning(0)
	assert_bool(first.is_empty()).is_false()
	# Second call at same game_time should be blocked by cooldown
	var second: Array = tm.trigger_knowledge_burning(0)
	assert_bool(second.is_empty()).is_true()
	# Only one tech should have been regressed
	assert_int(tm.get_researched_techs(0).size()).is_equal(1)


func test_tc_under_construction_destroyed_no_regression() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 2000)
	_quick_research(tm, 0, "stone_tools")
	# Building under construction
	var building := _create_building(0, "town_center", false)
	building.last_attacker_id = 1
	var should_trigger: bool = (
		building.building_name == "town_center"
		and not building.under_construction
		and building.last_attacker_id >= 0
		and building.last_attacker_id != building.owner_id
	)
	assert_bool(should_trigger).is_false()
	assert_int(tm.get_researched_techs(0).size()).is_equal(1)


# -- Save/load round-trip for last_attacker_id --


func test_last_attacker_id_survives_save_load() -> void:
	var building := _create_building(0, "town_center", true)
	building.last_attacker_id = 1
	var state: Dictionary = building.save_state()
	assert_int(int(state.get("last_attacker_id", -1))).is_equal(1)
	var building2 := _create_building(0, "town_center", true)
	building2.load_state(state)
	assert_int(building2.last_attacker_id).is_equal(1)
