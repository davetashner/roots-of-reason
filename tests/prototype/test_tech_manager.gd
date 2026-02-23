extends GdUnitTestSuite
## Tests for tech_manager.gd — per-age technology research system.

const TechManagerScript := preload("res://scripts/prototype/tech_manager.gd")

var _original_age: int
var _original_stockpiles: Dictionary


func before_test() -> void:
	_original_age = GameManager.current_age
	_original_stockpiles = ResourceManager._stockpiles.duplicate(true)
	GameManager.current_age = 0
	GameManager.is_paused = false
	GameManager.game_speed = 1.0


func after_test() -> void:
	GameManager.current_age = _original_age
	GameManager.is_paused = false
	GameManager.game_speed = 1.0
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


# -- Tech tree loading --


func test_tech_tree_loads() -> void:
	var tm := _create_tech_manager()
	# stone_tools is a known tech in the tree
	var data: Dictionary = tm.get_tech_data("stone_tools")
	assert_dict(data).is_not_empty()
	assert_str(data.get("id", "")).is_equal("stone_tools")


# -- can_research tests --


func test_can_research_valid_tech() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 100)
	GameManager.current_age = 0
	# stone_tools: age 0, no prereqs, costs 50 food
	assert_bool(tm.can_research(0, "stone_tools")).is_true()


func test_cannot_research_future_age_tech() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 5000, 5000, 5000, 5000, 5000)
	GameManager.current_age = 0
	# bronze_working: age 1
	assert_bool(tm.can_research(0, "bronze_working")).is_false()


func test_cannot_research_already_researched() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 200)
	GameManager.current_age = 0
	# Research stone_tools
	tm.start_research(0, "stone_tools")
	# Complete it (research_time = 25s)
	for i in 26:
		tm._process(1.0)
	assert_bool(tm.is_tech_researched("stone_tools", 0)).is_true()
	# Cannot research again
	assert_bool(tm.can_research(0, "stone_tools")).is_false()


func test_cannot_research_missing_prerequisites() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 200)
	GameManager.current_age = 0
	# animal_husbandry requires stone_tools
	assert_bool(tm.can_research(0, "animal_husbandry")).is_false()


func test_prerequisites_met_after_research() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 500)
	GameManager.current_age = 0
	# Research stone_tools first
	tm.start_research(0, "stone_tools")
	for i in 26:
		tm._process(1.0)
	assert_bool(tm.is_tech_researched("stone_tools", 0)).is_true()
	# Now animal_husbandry should be available
	assert_bool(tm.can_research(0, "animal_husbandry")).is_true()


# -- start_research tests --


func test_start_research_spends_resources() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 100)
	GameManager.current_age = 0
	tm.start_research(0, "stone_tools")
	# stone_tools costs 50 food
	assert_int(ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)).is_equal(50)


func test_start_research_adds_to_queue() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 500)
	GameManager.current_age = 0
	tm.start_research(0, "stone_tools")
	var queue: Array = tm.get_research_queue(0)
	assert_int(queue.size()).is_equal(1)
	assert_str(queue[0]).is_equal("stone_tools")


func test_queue_limit_enforced() -> void:
	var tm := _create_tech_manager()
	# Give plenty of resources
	_give_resources(0, 5000, 5000, 5000, 5000, 5000)
	GameManager.current_age = 0
	# Queue 4 techs (the max): stone_tools, fire_mastery, basket_weaving, animal_husbandry
	# But basket_weaving and animal_husbandry need stone_tools as prereq.
	# We need 4 techs without blocking prereqs at age 0.
	# stone_tools and fire_mastery have no prereqs.
	# basket_weaving needs stone_tools — so it would fail can_research.
	# Let's just use stone_tools and fire_mastery, then manually complete stone_tools
	# to unlock basket_weaving and animal_husbandry.
	tm.start_research(0, "stone_tools")
	tm.start_research(0, "fire_mastery")
	# Complete stone_tools to unlock the next two
	for i in 26:
		tm._process(1.0)
	assert_bool(tm.is_tech_researched("stone_tools", 0)).is_true()
	# Queue should now have fire_mastery as active
	tm.start_research(0, "basket_weaving")
	tm.start_research(0, "animal_husbandry")
	# Queue should be: fire_mastery, basket_weaving, animal_husbandry (3 items, under limit of 4)
	assert_int(tm.get_research_queue(0).size()).is_equal(3)
	# Try to add a 4th — need another tech without prereqs at age 0.
	# There are no more age-0 techs without prereqs except the ones already used.
	# Let's advance age and try bronze_working (age 1, no prereqs)
	GameManager.current_age = 1
	var result: bool = tm.start_research(0, "bronze_working")
	assert_bool(result).is_true()
	assert_int(tm.get_research_queue(0).size()).is_equal(4)
	# Now queue is full, 5th should fail
	var result2: bool = tm.start_research(0, "writing")
	assert_bool(result2).is_false()
	assert_int(tm.get_research_queue(0).size()).is_equal(4)


# -- research completion --


func test_research_completes_after_time() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 100)
	GameManager.current_age = 0
	tm.start_research(0, "stone_tools")
	# research_time = 25s
	for i in 25:
		tm._process(1.0)
	assert_bool(tm.is_tech_researched("stone_tools", 0)).is_true()
	assert_str(tm.get_current_research(0)).is_equal("")


# -- signal tests --


func test_tech_researched_signal_emitted() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 100)
	GameManager.current_age = 0
	var monitor := monitor_signals(tm)
	tm.start_research(0, "stone_tools")
	for i in 26:
		tm._process(1.0)
	var expected_effects: Dictionary = {"economic_bonus": {"gather_rate": 0.10}}
	await assert_signal(monitor).is_emitted("tech_researched", [0, "stone_tools", expected_effects])


func test_tech_research_started_signal_emitted() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 100)
	GameManager.current_age = 0
	var monitor := monitor_signals(tm)
	tm.start_research(0, "stone_tools")
	await assert_signal(monitor).is_emitted("tech_research_started", [0, "stone_tools"])


func test_research_progress_signal_emitted() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 100)
	GameManager.current_age = 0
	tm.start_research(0, "stone_tools")
	var progress_received: Array = []
	tm.research_progress.connect(func(pid: int, tid: String, prog: float) -> void: progress_received.append(prog))
	tm._process(1.0)
	# After 1s of 25s, progress = 0.04
	assert_int(progress_received.size()).is_equal(1)
	assert_float(progress_received[0]).is_equal_approx(1.0 / 25.0, 0.01)


# -- cancel tests --


func test_cancel_refunds_in_progress() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 100)
	GameManager.current_age = 0
	tm.start_research(0, "stone_tools")
	# Food should be 50 after spending 50
	assert_int(ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)).is_equal(50)
	tm.cancel_research(0, "stone_tools")
	# Food should be refunded to 100
	assert_int(ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)).is_equal(100)
	assert_str(tm.get_current_research(0)).is_equal("")


func test_cancel_removes_from_queue() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 500)
	GameManager.current_age = 0
	tm.start_research(0, "stone_tools")
	tm.start_research(0, "fire_mastery")
	assert_int(tm.get_research_queue(0).size()).is_equal(2)
	# Cancel the queued (non-active) one
	tm.cancel_research(0, "fire_mastery")
	assert_int(tm.get_research_queue(0).size()).is_equal(1)
	assert_str(tm.get_current_research(0)).is_equal("stone_tools")


# -- is_tech_researched --


func test_is_tech_researched_returns_correctly() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 100)
	GameManager.current_age = 0
	assert_bool(tm.is_tech_researched("stone_tools")).is_false()
	tm.start_research(0, "stone_tools")
	for i in 26:
		tm._process(1.0)
	assert_bool(tm.is_tech_researched("stone_tools")).is_true()
	assert_bool(tm.is_tech_researched("stone_tools", 0)).is_true()
	# Different player
	assert_bool(tm.is_tech_researched("stone_tools", 1)).is_false()


# -- get_researched_techs --


func test_get_researched_techs_returns_list() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 500)
	GameManager.current_age = 0
	tm.start_research(0, "stone_tools")
	for i in 26:
		tm._process(1.0)
	var techs: Array = tm.get_researched_techs(0)
	assert_int(techs.size()).is_equal(1)
	assert_str(techs[0]).is_equal("stone_tools")


# -- save/load tests --


func test_save_load_preserves_state() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 500)
	GameManager.current_age = 0
	tm.start_research(0, "stone_tools")
	# Progress partway
	for i in 10:
		tm._process(1.0)
	var state: Dictionary = tm.save_state()
	assert_bool(state.has("researched_techs")).is_true()
	assert_bool(state.has("research_queue")).is_true()
	assert_bool(state.has("research_progress")).is_true()
	assert_bool(state.has("active_costs")).is_true()
	# Load into a new instance
	var tm2 := _create_tech_manager()
	tm2.load_state(state)
	assert_str(tm2.get_current_research(0)).is_equal("stone_tools")
	assert_float(tm2.get_research_progress(0)).is_equal_approx(tm.get_research_progress(0), 0.01)


# -- game speed tests --


func test_game_speed_affects_research() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 100)
	GameManager.current_age = 0
	GameManager.game_speed = 2.0
	tm.start_research(0, "stone_tools")
	# At 2x speed, 13 real seconds = 26 game seconds (> 25 research_time)
	for i in 13:
		tm._process(1.0)
	assert_bool(tm.is_tech_researched("stone_tools", 0)).is_true()


func test_paused_game_stops_research() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 100)
	GameManager.current_age = 0
	tm.start_research(0, "stone_tools")
	GameManager.is_paused = true
	for i in 50:
		tm._process(1.0)
	assert_bool(tm.is_tech_researched("stone_tools", 0)).is_false()
	assert_float(tm.get_research_progress(0)).is_equal_approx(0.0, 0.01)
