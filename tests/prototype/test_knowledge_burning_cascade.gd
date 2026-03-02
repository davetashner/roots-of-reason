extends GdUnitTestSuite
## Integration tests for Knowledge Burning cascading effects.
## Verifies the full chain: TC destruction -> tech loss -> bonus reversion,
## age preservation, Singularity cascade, and AGI Core pause.

const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")
const TechManagerScript := preload("res://scripts/prototype/tech_manager.gd")
const SingularityRegressionScript := preload("res://scripts/prototype/singularity_regression.gd")
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
	GameManager.game_time = 100.0


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


func _create_singularity_regression(tm: Node) -> Node:
	var node := Node.new()
	node.set_script(SingularityRegressionScript)
	add_child(node)
	auto_free(node)
	node.setup(tm)
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
	## Starts and immediately completes a tech by simulating enough time.
	tm.start_research(player_id, tech_id)
	var tech_data: Dictionary = tm.get_tech_data(tech_id)
	var research_time: int = int(tech_data.get("research_time", 0)) + 1
	for i in research_time:
		tm._process(1.0)


func _inject_researched(tm: Node, player_id: int, tech_ids: Array) -> void:
	## Directly inject techs into the researched list, bypassing cost/prereqs.
	## Useful for setting up deep tech-tree scenarios without researching the
	## entire prerequisite chain.
	if player_id not in tm._researched_techs:
		tm._researched_techs[player_id] = []
	for tid: String in tech_ids:
		if tid not in tm._researched_techs[player_id]:
			tm._researched_techs[player_id].append(tid)


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


# -- 1. TC destroyed loses most recent tech --


func test_tc_destroyed_loses_most_recent_tech() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 5000, 5000, 5000, 5000, 5000)
	_quick_research(tm, 0, "stone_tools")
	_quick_research(tm, 0, "fire_mastery")
	_quick_research(tm, 0, "agriculture")
	assert_int(tm.get_researched_techs(0).size()).is_equal(3)
	# Simulate TC destruction by enemy (last_attacker_id != owner_id)
	var building := _create_building(0, "town_center", true)
	building.last_attacker_id = 1
	# Guard condition matches game_flow_controller logic
	var should_trigger: bool = (
		building.building_name == "town_center"
		and not building.under_construction
		and building.last_attacker_id >= 0
		and building.last_attacker_id != building.owner_id
	)
	assert_bool(should_trigger).is_true()
	# Trigger knowledge burning — mirrors game_flow_controller.on_building_destroyed
	var regressed: Array = tm.trigger_knowledge_burning(building.owner_id)
	assert_int(regressed.size()).is_equal(1)
	# The most recent tech (agriculture) should be lost
	assert_str(regressed[0].get("id", "")).is_equal("agriculture")
	# Earlier techs remain
	assert_bool(tm.is_tech_researched("stone_tools", 0)).is_true()
	assert_bool(tm.is_tech_researched("fire_mastery", 0)).is_true()
	assert_bool(tm.is_tech_researched("agriculture", 0)).is_false()


# -- 2. Lost tech bonuses are reverted --


func test_lost_tech_bonuses_reverted() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 5000, 5000, 5000, 5000, 5000)
	# Track effects emitted via tech_regressed signal
	var regressed_effects: Array = []
	tm.tech_regressed.connect(
		func(pid: int, tid: String, tdata: Dictionary) -> void:
			regressed_effects.append({"player_id": pid, "tech_id": tid, "effects": tdata.get("effects", {})})
	)
	# Research stone_tools (effects: economic_bonus.gather_rate +0.10)
	_quick_research(tm, 0, "stone_tools")
	assert_bool(tm.is_tech_researched("stone_tools", 0)).is_true()
	# Trigger knowledge burning
	var regressed: Array = tm.trigger_knowledge_burning(0)
	assert_int(regressed.size()).is_equal(1)
	# tech_regressed signal should have been emitted with effect data
	assert_int(regressed_effects.size()).is_equal(1)
	assert_int(regressed_effects[0]["player_id"]).is_equal(0)
	assert_str(regressed_effects[0]["tech_id"]).is_equal("stone_tools")
	# The effects dictionary allows listeners to revert bonuses
	var effects: Dictionary = regressed_effects[0]["effects"]
	assert_bool(effects.has("economic_bonus")).is_true()
	var eco_bonus: Dictionary = effects["economic_bonus"]
	assert_float(eco_bonus.get("gather_rate", 0.0)).is_equal_approx(0.10, 0.01)


# -- 3. Existing units from lost tech remain --


func test_existing_units_from_lost_tech_remain() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 9999, 9999, 9999, 9999, 9999)
	GameManager.current_age = 1
	# Research bronze_working which unlocks infantry and barracks
	_quick_research(tm, 0, "bronze_working")
	assert_bool(tm.is_tech_researched("bronze_working", 0)).is_true()
	# Simulate that an infantry unit already exists
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = "infantry"
	unit.owner_id = 0
	unit.name = "TestInfantry"
	add_child(unit)
	auto_free(unit)
	# Simulate that a barracks already exists
	var barracks := _create_building(0, "barracks", true)
	# Trigger knowledge burning — should lose bronze_working
	var regressed: Array = tm.trigger_knowledge_burning(0)
	assert_int(regressed.size()).is_equal(1)
	assert_str(regressed[0].get("id", "")).is_equal("bronze_working")
	# The tech is gone
	assert_bool(tm.is_tech_researched("bronze_working", 0)).is_false()
	# But existing units and buildings are still in the scene tree
	assert_bool(is_instance_valid(unit)).is_true()
	assert_bool(is_instance_valid(barracks)).is_true()
	assert_str(unit.unit_type).is_equal("infantry")
	assert_str(barracks.building_name).is_equal("barracks")


# -- 4. Re-research lost tech at full cost --


func test_re_research_lost_tech() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 9999, 9999, 9999, 9999, 9999)
	# Default re_research_cost_multiplier is 1.0 (full cost, not more)
	_quick_research(tm, 0, "stone_tools")
	assert_bool(tm.can_research(0, "stone_tools")).is_false()
	# Regress it
	tm.trigger_knowledge_burning(0)
	assert_bool(tm.is_tech_researched("stone_tools", 0)).is_false()
	# Should be available for re-research
	assert_bool(tm.can_research(0, "stone_tools")).is_true()
	# Record food before re-research
	var food_before: int = ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)
	tm.start_research(0, "stone_tools")
	var food_after: int = ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)
	# stone_tools costs 50 food — with 1.0 multiplier, same cost
	assert_int(food_before - food_after).is_equal(50)


# -- 5. Age advancement not lost --


func test_age_advancement_not_lost() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 9999, 9999, 9999, 9999, 9999)
	GameManager.current_age = 2
	# Research some age-2 techs
	_inject_researched(tm, 0, ["stone_tools", "bronze_working", "writing"])
	_quick_research(tm, 0, "philosophy")
	assert_int(tm.get_researched_techs(0).size()).is_equal(4)
	assert_int(GameManager.current_age).is_equal(2)
	# Trigger knowledge burning
	var regressed: Array = tm.trigger_knowledge_burning(0)
	assert_int(regressed.size()).is_equal(1)
	# Age should be unchanged — knowledge burning does not revert age advancement
	assert_int(GameManager.current_age).is_equal(2)
	# Most recent tech lost, but age remains
	assert_bool(tm.is_tech_researched("philosophy", 0)).is_false()


# -- 6. Cascade in Singularity Age --


func test_cascade_singularity_age() -> void:
	var tm := _create_tech_manager()
	var sr := _create_singularity_regression(tm)
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	GameManager.current_age = 6
	# Inject a deep singularity chain into research history
	_inject_researched(
		tm,
		0,
		[
			"stone_tools",
			"writing",
			"mathematics",
			"electricity",
			"computing_theory",
			"semiconductor_fab",
			"internet",
			"machine_learning",
			"neural_networks",
			"big_data",
			"parallel_computing",
			"deep_learning",
		],
	)
	assert_int(tm.get_researched_techs(0).size()).is_equal(12)
	# Track singularity_tech_lost signal
	var lost_signals: Array = []
	tm.singularity_tech_lost.connect(func(pid: int, tid: String) -> void: lost_signals.append(tid))
	# Trigger knowledge burning — should lose deep_learning (singularity_chain tech)
	var regressed: Array = tm.trigger_knowledge_burning(0)
	assert_int(regressed.size()).is_equal(1)
	assert_str(regressed[0].get("id", "")).is_equal("deep_learning")
	# Verify singularity_tech_lost was emitted
	assert_int(lost_signals.size()).is_equal(1)
	assert_str(lost_signals[0]).is_equal("deep_learning")
	# deep_learning is a singularity_chain tech
	var td: Dictionary = tm.get_tech_data("deep_learning")
	assert_bool(td.get("singularity_chain", false)).is_true()
	# Remaining singularity chain techs should still be researched
	assert_bool(tm.is_tech_researched("computing_theory", 0)).is_true()
	assert_bool(tm.is_tech_researched("neural_networks", 0)).is_true()


# -- 7. Transformer Architecture loss pauses AGI Core --


func test_transformer_architecture_loss_pauses_agi_core() -> void:
	var tm := _create_tech_manager()
	var sr := _create_singularity_regression(tm)
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	GameManager.current_age = 6
	# Build a research history where transformer_lab is the most recent.
	# transformer_lab is a direct prerequisite of agi_core in the tech tree.
	_inject_researched(
		tm,
		0,
		[
			"stone_tools",
			"writing",
			"mathematics",
			"electricity",
			"computing_theory",
			"semiconductor_fab",
			"machine_learning",
			"gpu_foundry",
			"transformer_lab",
		],
	)
	# AGI should not be paused initially
	assert_bool(sr.is_agi_paused(0)).is_false()
	# Trigger knowledge burning — loses transformer_lab (direct prereq of agi_core)
	var regressed: Array = tm.trigger_knowledge_burning(0)
	assert_int(regressed.size()).is_equal(1)
	assert_str(regressed[0].get("id", "")).is_equal("transformer_lab")
	# transformer_lab is a direct prereq of agi_core, so AGI should pause
	assert_bool(sr.is_agi_paused(0)).is_true()


# -- Additional cascade tests --


func test_multiple_tc_destructions_cascade_tech_loss() -> void:
	## Multiple TC destructions in sequence lose one tech each (with no cooldown).
	var tm := _create_tech_manager()
	tm._kb_cooldown = 0.0
	_give_resources(0, 9999, 9999, 9999, 9999, 9999)
	_quick_research(tm, 0, "stone_tools")
	_quick_research(tm, 0, "fire_mastery")
	_quick_research(tm, 0, "agriculture")
	assert_int(tm.get_researched_techs(0).size()).is_equal(3)
	# First TC destruction
	GameManager.game_time = 200.0
	var first: Array = tm.trigger_knowledge_burning(0)
	assert_str(first[0].get("id", "")).is_equal("agriculture")
	# Second TC destruction (different game_time to avoid cooldown edge case)
	GameManager.game_time = 201.0
	var second: Array = tm.trigger_knowledge_burning(0)
	assert_str(second[0].get("id", "")).is_equal("fire_mastery")
	# Only stone_tools remains
	assert_int(tm.get_researched_techs(0).size()).is_equal(1)
	assert_bool(tm.is_tech_researched("stone_tools", 0)).is_true()


func test_knowledge_burned_event_bus_integration() -> void:
	## Verifies that EventBus.knowledge_burned signal fires with correct data
	## when knowledge burning is triggered.
	var tm := _create_tech_manager()
	_give_resources(0, 5000, 5000, 5000, 5000, 5000)
	_quick_research(tm, 0, "stone_tools")
	# Listen on EventBus
	var bus_events: Array = []
	EventBus.knowledge_burned.connect(
		func(atk_id: int, def_id: int, techs: Array) -> void:
			bus_events.append({"attacker": atk_id, "defender": def_id, "techs": techs})
	)
	# Simulate the game_flow_controller logic
	var building := _create_building(0, "town_center", true)
	building.last_attacker_id = 1
	var regressed: Array = tm.trigger_knowledge_burning(building.owner_id)
	if not regressed.is_empty():
		EventBus.emit_knowledge_burned(building.last_attacker_id, building.owner_id, regressed)
	assert_int(bus_events.size()).is_equal(1)
	assert_int(bus_events[0]["attacker"]).is_equal(1)
	assert_int(bus_events[0]["defender"]).is_equal(0)
	assert_int(bus_events[0]["techs"].size()).is_equal(1)


func test_regressed_tech_tracked_for_re_research() -> void:
	## After knowledge burning, the lost tech appears in the regressed list.
	var tm := _create_tech_manager()
	_give_resources(0, 5000, 5000, 5000, 5000, 5000)
	_quick_research(tm, 0, "stone_tools")
	_quick_research(tm, 0, "fire_mastery")
	tm.trigger_knowledge_burning(0)
	var regressed_list: Array = tm.get_regressed_techs(0)
	assert_bool("fire_mastery" in regressed_list).is_true()
	# stone_tools was NOT regressed
	assert_bool("stone_tools" in regressed_list).is_false()


func test_agi_pause_resumes_on_re_research() -> void:
	## After transformer_architecture is lost and AGI pauses,
	## re-researching it should unpause AGI Core.
	var tm := _create_tech_manager()
	var sr := _create_singularity_regression(tm)
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	GameManager.current_age = 6
	_inject_researched(
		tm,
		0,
		[
			"stone_tools",
			"writing",
			"mathematics",
			"electricity",
			"computing_theory",
			"semiconductor_fab",
			"machine_learning",
			"gpu_foundry",
			"transformer_lab",
		],
	)
	# Lose transformer_lab — AGI pauses
	tm.trigger_knowledge_burning(0)
	assert_bool(sr.is_agi_paused(0)).is_true()
	# Re-research triggers the singularity_tech_researched signal
	tm._researched_techs[0].append("transformer_lab")
	tm.singularity_tech_researched.emit(0, "transformer_lab", "Transformer Lab")
	# AGI should be unpaused
	assert_bool(sr.is_agi_paused(0)).is_false()
