extends GdUnitTestSuite
## Tests for Singularity Age tech chain: GPU Foundry -> Transformer Lab -> AGI Core.

const TechManagerScript := preload("res://scripts/prototype/tech_manager.gd")
const VictoryManagerScript := preload("res://scripts/prototype/victory_manager.gd")

var _original_age: int
var _original_stockpiles: Dictionary
var _original_game_time: float


func before_test() -> void:
	_original_age = GameManager.current_age
	_original_stockpiles = ResourceManager._stockpiles.duplicate(true)
	_original_game_time = GameManager.game_time
	GameManager.current_age = 6
	GameManager.is_paused = false
	GameManager.game_speed = 1.0
	GameManager.game_time = 0.0


func after_test() -> void:
	GameManager.current_age = _original_age
	GameManager.is_paused = false
	GameManager.game_speed = 1.0
	GameManager.game_time = _original_game_time
	ResourceManager._stockpiles = _original_stockpiles


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
	## Starts and immediately completes a tech by simulating enough time.
	tm.start_research(player_id, tech_id)
	var tech_data: Dictionary = tm.get_tech_data(tech_id)
	var research_time: int = int(tech_data.get("research_time", 0)) + 1
	for i in research_time:
		tm._process(1.0)


func _research_prereq_chain(tm: Node, player_id: int) -> void:
	## Researches the prerequisite chain up to machine_learning so the
	## singularity techs become available. Gives massive resources first.
	_give_resources(player_id, 99999, 99999, 99999, 99999, 99999)
	# machine_learning requires: computing_theory, statistics
	# computing_theory requires: electricity, mathematics
	# electricity requires: mathematics, steam_power
	# steam_power requires: engineering
	# engineering requires: mathematics
	# mathematics requires: writing
	# statistics requires: mathematics
	# Set age high enough to allow all techs
	GameManager.current_age = 6
	var chain: Array = [
		"writing",
		"mathematics",
		"engineering",
		"steam_power",
		"electricity",
		"computing_theory",
		"statistics",
		"machine_learning",
	]
	for tech_id: String in chain:
		_give_resources(player_id, 99999, 99999, 99999, 99999, 99999)
		_quick_research(tm, player_id, tech_id)


# -- Tech data validation --


func test_gpu_foundry_exists_with_correct_data() -> void:
	var tm := _create_tech_manager()
	var data: Dictionary = tm.get_tech_data("gpu_foundry")
	assert_dict(data).is_not_empty()
	assert_str(data.get("id", "")).is_equal("gpu_foundry")
	assert_int(int(data.get("age", -1))).is_equal(6)
	assert_int(int(data.get("research_time", 0))).is_equal(120)
	var cost: Dictionary = data.get("cost", {})
	assert_int(int(cost.get("knowledge", 0))).is_equal(2000)
	assert_int(int(cost.get("gold", 0))).is_equal(1000)


func test_transformer_lab_exists_with_correct_data() -> void:
	var tm := _create_tech_manager()
	var data: Dictionary = tm.get_tech_data("transformer_lab")
	assert_dict(data).is_not_empty()
	assert_str(data.get("id", "")).is_equal("transformer_lab")
	assert_int(int(data.get("age", -1))).is_equal(6)
	assert_int(int(data.get("research_time", 0))).is_equal(180)
	var cost: Dictionary = data.get("cost", {})
	assert_int(int(cost.get("knowledge", 0))).is_equal(3000)
	assert_int(int(cost.get("gold", 0))).is_equal(1500)


func test_agi_core_exists_with_correct_data() -> void:
	var tm := _create_tech_manager()
	var data: Dictionary = tm.get_tech_data("agi_core")
	assert_dict(data).is_not_empty()
	assert_str(data.get("id", "")).is_equal("agi_core")
	assert_int(int(data.get("age", -1))).is_equal(6)
	assert_int(int(data.get("research_time", 0))).is_equal(300)
	var cost: Dictionary = data.get("cost", {})
	assert_int(int(cost.get("knowledge", 0))).is_equal(5000)
	assert_int(int(cost.get("gold", 0))).is_equal(3000)


# -- Prerequisite chain validation --


func test_gpu_foundry_requires_machine_learning() -> void:
	var tm := _create_tech_manager()
	var data: Dictionary = tm.get_tech_data("gpu_foundry")
	var prereqs: Array = data.get("prerequisites", [])
	assert_array(prereqs).contains(["machine_learning"])


func test_transformer_lab_requires_gpu_foundry() -> void:
	var tm := _create_tech_manager()
	var data: Dictionary = tm.get_tech_data("transformer_lab")
	var prereqs: Array = data.get("prerequisites", [])
	assert_array(prereqs).contains(["gpu_foundry"])


func test_agi_core_requires_transformer_lab() -> void:
	var tm := _create_tech_manager()
	var data: Dictionary = tm.get_tech_data("agi_core")
	var prereqs: Array = data.get("prerequisites", [])
	assert_array(prereqs).contains(["transformer_lab"])


func test_agi_core_marked_as_victory_tech() -> void:
	var tm := _create_tech_manager()
	var data: Dictionary = tm.get_tech_data("agi_core")
	assert_bool(bool(data.get("victory_tech", false))).is_true()


func test_research_chain_is_valid() -> void:
	## Verifies the full chain can be researched in sequence when prereqs are met.
	var tm := _create_tech_manager()
	_research_prereq_chain(tm, 0)
	# Now research the singularity chain
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	_quick_research(tm, 0, "gpu_foundry")
	assert_bool(tm.is_tech_researched("gpu_foundry", 0)).is_true()
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	_quick_research(tm, 0, "transformer_lab")
	assert_bool(tm.is_tech_researched("transformer_lab", 0)).is_true()
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	_quick_research(tm, 0, "agi_core")
	assert_bool(tm.is_tech_researched("agi_core", 0)).is_true()


# -- Victory trigger --


func test_victory_tech_completed_signal_on_agi_core() -> void:
	## AGI Core completion should emit victory_tech_completed signal.
	var tm := _create_tech_manager()
	_research_prereq_chain(tm, 0)
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	_quick_research(tm, 0, "gpu_foundry")
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	_quick_research(tm, 0, "transformer_lab")
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	var victory_signals: Array = []
	tm.victory_tech_completed.connect(func(pid: int, tid: String) -> void: victory_signals.append([pid, tid]))
	_quick_research(tm, 0, "agi_core")
	assert_int(victory_signals.size()).is_equal(1)
	assert_int(int(victory_signals[0][0])).is_equal(0)
	assert_str(victory_signals[0][1]).is_equal("agi_core")


func test_singularity_victory_triggers_via_victory_manager() -> void:
	## When victory_tech_completed fires, VictoryManager should trigger singularity victory.
	var tm := _create_tech_manager()
	var vm := Node.new()
	vm.set_script(VictoryManagerScript)
	add_child(vm)
	auto_free(vm)
	vm._defeat_delay = 0.0
	vm._singularity_age = 6
	# Connect tech manager victory signal to victory manager
	tm.victory_tech_completed.connect(vm.on_victory_tech_completed)
	var victory_results: Array = []
	vm.player_victorious.connect(func(pid: int, cond: String) -> void: victory_results.append([pid, cond]))
	# Research the full chain
	_research_prereq_chain(tm, 0)
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	_quick_research(tm, 0, "gpu_foundry")
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	_quick_research(tm, 0, "transformer_lab")
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	_quick_research(tm, 0, "agi_core")
	assert_int(victory_results.size()).is_equal(1)
	assert_int(int(victory_results[0][0])).is_equal(0)
	assert_str(victory_results[0][1]).is_equal("singularity")


# -- Tech regression --


func test_tech_regression_can_undo_agi_core() -> void:
	## AGI Core can be regressed, removing it from researched techs.
	var tm := _create_tech_manager()
	_research_prereq_chain(tm, 0)
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	_quick_research(tm, 0, "gpu_foundry")
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	_quick_research(tm, 0, "transformer_lab")
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	_quick_research(tm, 0, "agi_core")
	assert_bool(tm.is_tech_researched("agi_core", 0)).is_true()
	# Regress — should remove agi_core (last researched)
	var result: Dictionary = tm.regress_latest_tech(0)
	assert_str(result.get("id", "")).is_equal("agi_core")
	assert_bool(tm.is_tech_researched("agi_core", 0)).is_false()


func test_victory_tech_disrupted_signal_on_regression() -> void:
	## Reverting a victory tech should emit victory_tech_disrupted.
	var tm := _create_tech_manager()
	_research_prereq_chain(tm, 0)
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	_quick_research(tm, 0, "gpu_foundry")
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	_quick_research(tm, 0, "transformer_lab")
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	_quick_research(tm, 0, "agi_core")
	var disrupted_signals: Array = []
	tm.victory_tech_disrupted.connect(func(pid: int, tid: String) -> void: disrupted_signals.append([pid, tid]))
	tm.revert_tech_effects(0, "agi_core")
	assert_int(disrupted_signals.size()).is_equal(1)
	assert_str(disrupted_signals[0][1]).is_equal("agi_core")


func test_victory_tech_research_started_signal() -> void:
	## Starting AGI Core research should emit victory_tech_research_started.
	var tm := _create_tech_manager()
	_research_prereq_chain(tm, 0)
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	_quick_research(tm, 0, "gpu_foundry")
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	_quick_research(tm, 0, "transformer_lab")
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	var started_signals: Array = []
	tm.victory_tech_research_started.connect(func(pid: int, tid: String) -> void: started_signals.append([pid, tid]))
	tm.start_research(0, "agi_core")
	assert_int(started_signals.size()).is_equal(1)
	assert_str(started_signals[0][1]).is_equal("agi_core")
