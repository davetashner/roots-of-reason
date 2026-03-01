extends GdUnitTestSuite
## Tests for age_advancement.gd — age advancement research system.

const AdvancementScript := preload("res://scripts/prototype/age_advancement.gd")

const RMGuard := preload("res://tests/helpers/resource_manager_guard.gd")
const GMGuard := preload("res://tests/helpers/game_manager_guard.gd")

var _rm_guard: RefCounted
var _gm_guard: RefCounted
var _age_advanced_args: Array = []


func before_test() -> void:
	_rm_guard = RMGuard.new()
	_gm_guard = GMGuard.new()
	GameManager.current_age = 0
	GameManager.is_paused = false
	GameManager.game_speed = 1.0


func after_test() -> void:
	_gm_guard.dispose()
	_rm_guard.dispose()


func _create_advancement() -> Node:
	var node := Node.new()
	node.set_script(AdvancementScript)
	add_child(node)
	auto_free(node)
	return node


func _give_resources(player_id: int, food: int = 0, gold: int = 0, knowledge: int = 0) -> void:
	(
		ResourceManager
		. init_player(
			player_id,
			{
				ResourceManager.ResourceType.FOOD: food,
				ResourceManager.ResourceType.WOOD: 0,
				ResourceManager.ResourceType.STONE: 0,
				ResourceManager.ResourceType.GOLD: gold,
				ResourceManager.ResourceType.KNOWLEDGE: knowledge,
			}
		)
	)


# -- can_advance tests --


func test_can_advance_from_stone_age() -> void:
	var adv := _create_advancement()
	_give_resources(0, 500)
	GameManager.current_age = 0
	assert_bool(adv.can_advance(0)).is_true()


func test_cannot_advance_without_resources() -> void:
	var adv := _create_advancement()
	_give_resources(0, 0)
	GameManager.current_age = 0
	assert_bool(adv.can_advance(0)).is_false()


func test_cannot_advance_at_max_age() -> void:
	var adv := _create_advancement()
	_give_resources(0, 9999, 9999, 9999)
	GameManager.current_age = 6
	assert_bool(adv.can_advance(0)).is_false()


func test_cannot_advance_while_advancing() -> void:
	var adv := _create_advancement()
	_give_resources(0, 500)
	GameManager.current_age = 0
	adv.start_advancement(0)
	assert_bool(adv.can_advance(0)).is_false()


# -- start_advancement tests --


func test_start_advancement_spends_resources() -> void:
	var adv := _create_advancement()
	_give_resources(0, 600)
	GameManager.current_age = 0
	adv.start_advancement(0)
	# Bronze Age costs 500 food
	assert_int(ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)).is_equal(100)


func test_start_advancement_returns_false_without_resources() -> void:
	var adv := _create_advancement()
	_give_resources(0, 0)
	GameManager.current_age = 0
	assert_bool(adv.start_advancement(0)).is_false()


func test_start_advancement_sets_advancing_state() -> void:
	var adv := _create_advancement()
	_give_resources(0, 500)
	GameManager.current_age = 0
	adv.start_advancement(0)
	assert_bool(adv.is_advancing()).is_true()
	assert_int(adv.get_advance_target()).is_equal(1)


# -- progress tests --


func test_advancement_progress_increases() -> void:
	var adv := _create_advancement()
	_give_resources(0, 500)
	GameManager.current_age = 0
	adv.start_advancement(0)
	# Bronze Age research_time = 40s, simulate 10s of _process calls
	for i in 10:
		adv._process(1.0)
	# Progress should be ~10/40 = 0.25
	assert_float(adv.get_advance_progress()).is_equal_approx(0.25, 0.01)


func test_advancement_completes_at_full_progress() -> void:
	var adv := _create_advancement()
	_give_resources(0, 500)
	GameManager.current_age = 0
	adv.start_advancement(0)
	# Simulate enough time to complete (40s for Bronze Age)
	for i in 41:
		adv._process(1.0)
	assert_bool(adv.is_advancing()).is_false()
	assert_int(GameManager.current_age).is_equal(1)


# -- signal tests --


func test_advancement_emits_started_signal() -> void:
	var adv := _create_advancement()
	_give_resources(0, 500)
	GameManager.current_age = 0
	var monitor := monitor_signals(adv)
	adv.start_advancement(0)
	await assert_signal(monitor).is_emitted("advancement_started", [0, 1])


func test_advancement_emits_completed_signal() -> void:
	var adv := _create_advancement()
	_give_resources(0, 500)
	GameManager.current_age = 0
	var monitor := monitor_signals(adv)
	adv.start_advancement(0)
	# Complete the advancement
	for i in 41:
		adv._process(1.0)
	await assert_signal(monitor).is_emitted("advancement_completed", [1])


func test_advancement_emits_cancelled_signal() -> void:
	var adv := _create_advancement()
	_give_resources(0, 500)
	GameManager.current_age = 0
	var monitor := monitor_signals(adv)
	adv.start_advancement(0)
	adv.cancel_advancement(0)
	await assert_signal(monitor).is_emitted("advancement_cancelled", [1])


# -- cancel tests --


func test_cancel_advancement_refunds_resources() -> void:
	var adv := _create_advancement()
	_give_resources(0, 500)
	GameManager.current_age = 0
	adv.start_advancement(0)
	# Food should be 0 after spending 500
	assert_int(ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)).is_equal(0)
	adv.cancel_advancement(0)
	# Food should be refunded
	assert_int(ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)).is_equal(500)
	assert_bool(adv.is_advancing()).is_false()


func test_cancel_advancement_wrong_player_does_nothing() -> void:
	var adv := _create_advancement()
	_give_resources(0, 500)
	GameManager.current_age = 0
	adv.start_advancement(0)
	adv.cancel_advancement(1)
	# Should still be advancing
	assert_bool(adv.is_advancing()).is_true()


# -- get_advance_cost tests --


func test_get_advance_cost_returns_correct_values() -> void:
	var adv := _create_advancement()
	# Bronze Age (index 1) costs 500 food
	var costs: Dictionary = adv.get_advance_cost(1)
	assert_int(costs.get(ResourceManager.ResourceType.FOOD, 0)).is_equal(500)


func test_get_advance_cost_iron_age() -> void:
	var adv := _create_advancement()
	# Iron Age (index 2) costs 800 food, 200 gold
	var costs: Dictionary = adv.get_advance_cost(2)
	assert_int(costs.get(ResourceManager.ResourceType.FOOD, 0)).is_equal(800)
	assert_int(costs.get(ResourceManager.ResourceType.GOLD, 0)).is_equal(200)


func test_get_advance_cost_invalid_index_returns_empty() -> void:
	var adv := _create_advancement()
	var costs: Dictionary = adv.get_advance_cost(99)
	assert_dict(costs).is_empty()


# -- research_time tests --


func test_get_research_time_bronze_age() -> void:
	var adv := _create_advancement()
	assert_float(adv.get_research_time(1)).is_equal(40.0)


func test_get_research_time_singularity_age() -> void:
	var adv := _create_advancement()
	assert_float(adv.get_research_time(6)).is_equal(200.0)


# -- game speed tests --


func test_game_speed_affects_advancement() -> void:
	var adv := _create_advancement()
	_give_resources(0, 500)
	GameManager.current_age = 0
	GameManager.game_speed = 2.0
	adv.start_advancement(0)
	# At 2x speed, 20 real seconds = 40 game seconds (enough for Bronze Age)
	for i in 21:
		adv._process(1.0)
	assert_bool(adv.is_advancing()).is_false()
	assert_int(GameManager.current_age).is_equal(1)


func test_paused_game_stops_advancement() -> void:
	var adv := _create_advancement()
	_give_resources(0, 500)
	GameManager.current_age = 0
	adv.start_advancement(0)
	GameManager.is_paused = true
	# Process while paused — should not progress
	for i in 50:
		adv._process(1.0)
	assert_bool(adv.is_advancing()).is_true()
	assert_float(adv.get_advance_progress()).is_equal_approx(0.0, 0.01)


# -- save/load tests --


func test_save_load_state() -> void:
	var adv := _create_advancement()
	_give_resources(0, 500)
	GameManager.current_age = 0
	adv.start_advancement(0)
	# Progress a bit
	for i in 10:
		adv._process(1.0)
	var state: Dictionary = adv.save_state()
	assert_bool(state.has("advancing")).is_true()
	assert_bool(state.has("advance_target")).is_true()
	assert_bool(state.has("advance_progress")).is_true()
	assert_bool(state.has("advance_time")).is_true()
	assert_bool(state.has("advance_cost")).is_true()
	assert_bool(state.has("player_id")).is_true()
	# Load into a new instance
	var adv2 := _create_advancement()
	adv2.load_state(state)
	assert_bool(adv2.is_advancing()).is_true()
	assert_int(adv2.get_advance_target()).is_equal(1)
	assert_float(adv2.get_advance_progress()).is_equal_approx(adv.get_advance_progress(), 0.01)


func test_save_state_when_not_advancing() -> void:
	var adv := _create_advancement()
	var state: Dictionary = adv.save_state()
	assert_bool(state["advancing"]).is_false()
	assert_int(state["advance_target"]).is_equal(-1)


# -- multi-age advancement tests --


func test_can_advance_through_multiple_ages() -> void:
	var adv := _create_advancement()
	# Start at Stone Age, advance to Bronze
	_give_resources(0, 500)
	GameManager.current_age = 0
	adv.start_advancement(0)
	for i in 41:
		adv._process(1.0)
	assert_int(GameManager.current_age).is_equal(1)
	# Now advance to Iron Age (costs 800 food, 200 gold)
	_give_resources(0, 800, 200)
	assert_bool(adv.can_advance(0)).is_true()
	adv.start_advancement(0)
	for i in 61:
		adv._process(1.0)
	assert_int(GameManager.current_age).is_equal(2)


# -- GameManager.advance_age tests --


func _on_age_advanced(new_age: int) -> void:
	_age_advanced_args.append(new_age)


func test_game_manager_advance_age_emits_signal() -> void:
	_age_advanced_args.clear()
	GameManager.age_advanced.connect(_on_age_advanced)
	GameManager.advance_age(3)
	assert_int(GameManager.current_age).is_equal(3)
	assert_int(_age_advanced_args.size()).is_equal(1)
	assert_int(_age_advanced_args[0]).is_equal(3)
	GameManager.age_advanced.disconnect(_on_age_advanced)


func test_game_manager_advance_age_rejects_invalid() -> void:
	GameManager.current_age = 2
	GameManager.advance_age(-1)
	assert_int(GameManager.current_age).is_equal(2)
	GameManager.advance_age(7)
	assert_int(GameManager.current_age).is_equal(2)
