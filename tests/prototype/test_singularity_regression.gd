extends GdUnitTestSuite
## Tests for singularity_regression.gd — tech regression interaction
## with the Singularity victory path.

const TechManagerScript := preload("res://scripts/prototype/tech_manager.gd")
const SingularityRegressionScript := preload("res://scripts/prototype/singularity_regression.gd")

const RMGuard := preload("res://tests/helpers/resource_manager_guard.gd")
const GMGuard := preload("res://tests/helpers/game_manager_guard.gd")

var _rm_guard: RefCounted
var _gm_guard: RefCounted


func before_test() -> void:
	_rm_guard = RMGuard.new()
	_gm_guard = GMGuard.new()
	GameManager.current_age = 6
	GameManager.is_paused = false
	GameManager.game_speed = 1.0
	GameManager.game_time = 100.0


func after_test() -> void:
	_gm_guard.dispose()
	_rm_guard.dispose()


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


func _quick_research(tm: Node, player_id: int, tech_id: String) -> void:
	tm.start_research(player_id, tech_id)
	var tech_data: Dictionary = tm.get_tech_data(tech_id)
	var research_time: int = int(tech_data.get("research_time", 0)) + 1
	for i in research_time:
		tm._process(1.0)


# -- Signal emission tests --


func test_singularity_tech_research_emits_signal() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	var emitted: Array = []
	tm.singularity_tech_researched.connect(
		func(pid: int, tid: String, tname: String) -> void: emitted.append({"pid": pid, "tid": tid, "name": tname})
	)
	# Inject prereqs as already researched, then research computing_theory
	# (singularity_chain: true, prereqs: electricity + mathematics)
	tm._researched_techs[0] = ["electricity", "mathematics"]
	_quick_research(tm, 0, "computing_theory")
	assert_int(emitted.size()).is_greater(0)
	assert_str(emitted[-1]["tid"]).is_equal("computing_theory")


func test_non_singularity_tech_does_not_emit_singularity_signal() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	var emitted: Array = []
	tm.singularity_tech_researched.connect(func(_pid: int, _tid: String, _tname: String) -> void: emitted.append(true))
	_quick_research(tm, 0, "stone_tools")
	assert_int(emitted.size()).is_equal(0)


func test_singularity_tech_regression_emits_lost_signal() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	var lost: Array = []
	tm.singularity_tech_lost.connect(func(pid: int, tid: String) -> void: lost.append({"pid": pid, "tid": tid}))
	# Inject a singularity tech into research history and regress it
	tm._researched_techs[0] = ["stone_tools", "computing_theory"]
	tm.regress_latest_tech(0)
	assert_int(lost.size()).is_greater(0)
	assert_str(lost[-1]["tid"]).is_equal("computing_theory")


# -- AGI pause tests --


func test_agi_not_paused_by_default() -> void:
	var tm := _create_tech_manager()
	var sr := _create_singularity_regression(tm)
	assert_bool(sr.is_agi_paused(0)).is_false()


func test_agi_paused_when_prereq_regressed() -> void:
	var tm := _create_tech_manager()
	var sr := _create_singularity_regression(tm)
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	# Directly inject transformer_lab as researched (it's a singularity_chain
	# tech and direct prereq of agi_core)
	var tl_data: Dictionary = tm.get_tech_data("transformer_lab")
	if tl_data.is_empty():
		return
	# Manually add to research history to bypass prereq chain
	tm._researched_techs[0] = ["stone_tools", "transformer_lab"]
	# Now regress the most recent (transformer_lab) — should trigger pause
	tm.regress_latest_tech(0)
	assert_bool(sr.is_agi_paused(0)).is_true()


func test_agi_unpaused_when_prereq_re_researched() -> void:
	var tm := _create_tech_manager()
	var sr := _create_singularity_regression(tm)
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	var tl_data: Dictionary = tm.get_tech_data("transformer_lab")
	if tl_data.is_empty():
		return
	# Inject transformer_lab as researched and regress it
	tm._researched_techs[0] = ["stone_tools", "transformer_lab"]
	tm.regress_latest_tech(0)
	assert_bool(sr.is_agi_paused(0)).is_true()
	# Re-research triggers singularity_tech_researched signal which unpauses
	# Manually inject it back and emit the signal
	tm._researched_techs[0].append("transformer_lab")
	tm.singularity_tech_researched.emit(0, "transformer_lab", "Transformer Lab")
	assert_bool(sr.is_agi_paused(0)).is_false()


# -- Knowledge at risk tests --


func test_knowledge_at_risk_empty_when_no_singularity_techs() -> void:
	var tm := _create_tech_manager()
	var sr := _create_singularity_regression(tm)
	var at_risk: Array = sr.get_knowledge_at_risk(0)
	assert_int(at_risk.size()).is_equal(0)


func test_knowledge_at_risk_label_from_config() -> void:
	var tm := _create_tech_manager()
	var sr := _create_singularity_regression(tm)
	assert_str(sr.get_knowledge_at_risk_label()).is_equal("Knowledge at Risk")


# -- Save/load tests --


func test_save_load_roundtrip() -> void:
	var tm := _create_tech_manager()
	var sr := _create_singularity_regression(tm)
	sr._agi_paused[0] = true
	sr._agi_paused[1] = false
	var state: Dictionary = sr.save_state()
	var sr2 := _create_singularity_regression(tm)
	sr2.load_state(state)
	assert_bool(sr2.is_agi_paused(0)).is_true()
	assert_bool(sr2.is_agi_paused(1)).is_false()


func test_save_load_empty_state() -> void:
	var tm := _create_tech_manager()
	var sr := _create_singularity_regression(tm)
	var state: Dictionary = sr.save_state()
	var sr2 := _create_singularity_regression(tm)
	sr2.load_state(state)
	assert_bool(sr2.is_agi_paused(0)).is_false()
