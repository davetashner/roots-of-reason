extends GdUnitTestSuite
## Tests for ResourceManager autoload.

var _original_stockpiles: Dictionary
var _signal_args: Array = []


func before_test() -> void:
	_original_stockpiles = ResourceManager._stockpiles.duplicate(true)


func after_test() -> void:
	ResourceManager._stockpiles = _original_stockpiles.duplicate(true)
	ResourceManager._corruption_rates.clear()


# --- init_player tests ---


func test_init_player_sets_starting_resources() -> void:
	(
		ResourceManager
		. init_player(
			99,
			{
				ResourceManager.ResourceType.FOOD: 500,
				ResourceManager.ResourceType.WOOD: 300,
				ResourceManager.ResourceType.STONE: 0,
				ResourceManager.ResourceType.GOLD: 0,
				ResourceManager.ResourceType.KNOWLEDGE: 0,
			},
		)
	)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.FOOD)).is_equal(500)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.WOOD)).is_equal(300)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.STONE)).is_equal(0)


func test_init_player_defaults_from_config() -> void:
	ResourceManager.init_player(99)
	# Normal difficulty defaults from resource_config.json
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.FOOD)).is_equal(200)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.WOOD)).is_equal(200)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.STONE)).is_equal(100)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.GOLD)).is_equal(100)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.KNOWLEDGE)).is_equal(0)


# --- has_player tests ---


func test_has_player_returns_true_after_init() -> void:
	ResourceManager.init_player(99, {})
	assert_bool(ResourceManager.has_player(99)).is_true()


func test_has_player_returns_false_for_unknown() -> void:
	assert_bool(ResourceManager.has_player(999)).is_false()


# --- get_amount tests ---


func test_get_amount_unknown_player_returns_zero() -> void:
	assert_int(ResourceManager.get_amount(999, ResourceManager.ResourceType.FOOD)).is_equal(0)


# --- add_resource tests ---


func test_add_resource_increases_amount() -> void:
	ResourceManager.init_player(99, {})
	ResourceManager.add_resource(99, ResourceManager.ResourceType.FOOD, 50)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.FOOD)).is_equal(50)
	ResourceManager.add_resource(99, ResourceManager.ResourceType.FOOD, 30)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.FOOD)).is_equal(80)


func _on_signal_received(pid: int, rtype: String, old_amt: int, new_amt: int) -> void:
	_signal_args = [pid, rtype, old_amt, new_amt]


func test_add_resource_emits_signal_with_old_and_new() -> void:
	ResourceManager.init_player(99, {ResourceManager.ResourceType.GOLD: 100})
	_signal_args = []
	ResourceManager.resources_changed.connect(_on_signal_received)
	ResourceManager.add_resource(99, ResourceManager.ResourceType.GOLD, 25)
	ResourceManager.resources_changed.disconnect(_on_signal_received)
	assert_array(_signal_args).is_equal([99, "Gold", 100, 125])


# --- can_afford tests ---


func test_can_afford_returns_true_when_sufficient() -> void:
	ResourceManager.init_player(99, {ResourceManager.ResourceType.FOOD: 200})
	assert_bool(ResourceManager.can_afford(99, {ResourceManager.ResourceType.FOOD: 200})).is_true()


func test_can_afford_returns_false_when_insufficient() -> void:
	ResourceManager.init_player(99, {ResourceManager.ResourceType.FOOD: 50})
	assert_bool(ResourceManager.can_afford(99, {ResourceManager.ResourceType.FOOD: 100})).is_false()


func test_can_afford_multi_resource() -> void:
	(
		ResourceManager
		. init_player(
			99,
			{
				ResourceManager.ResourceType.FOOD: 200,
				ResourceManager.ResourceType.WOOD: 100,
			},
		)
	)
	# Can afford both
	(
		assert_bool(
			(
				ResourceManager
				. can_afford(
					99,
					{
						ResourceManager.ResourceType.FOOD: 100,
						ResourceManager.ResourceType.WOOD: 50,
					},
				)
			)
		)
		. is_true()
	)
	# Cannot afford wood
	(
		assert_bool(
			(
				ResourceManager
				. can_afford(
					99,
					{
						ResourceManager.ResourceType.FOOD: 100,
						ResourceManager.ResourceType.WOOD: 200,
					},
				)
			)
		)
		. is_false()
	)


# --- spend tests ---


func test_spend_deducts_and_returns_true() -> void:
	ResourceManager.init_player(99, {ResourceManager.ResourceType.FOOD: 200})
	var result := ResourceManager.spend(99, {ResourceManager.ResourceType.FOOD: 150})
	assert_bool(result).is_true()
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.FOOD)).is_equal(50)


func test_spend_returns_false_when_insufficient() -> void:
	ResourceManager.init_player(99, {ResourceManager.ResourceType.FOOD: 50})
	var result := ResourceManager.spend(99, {ResourceManager.ResourceType.FOOD: 100})
	assert_bool(result).is_false()


func test_spend_does_not_deduct_on_failure() -> void:
	ResourceManager.init_player(99, {ResourceManager.ResourceType.FOOD: 50})
	ResourceManager.spend(99, {ResourceManager.ResourceType.FOOD: 100})
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.FOOD)).is_equal(50)


# --- negative starting amount test ---


func test_negative_starting_amount_clamped_to_zero() -> void:
	ResourceManager.init_player(99, {ResourceManager.ResourceType.FOOD: -10})
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.FOOD)).is_equal(0)


# --- save/load tests ---


func test_save_load_roundtrip() -> void:
	(
		ResourceManager
		. init_player(
			99,
			{
				ResourceManager.ResourceType.FOOD: 150,
				ResourceManager.ResourceType.WOOD: 250,
				ResourceManager.ResourceType.STONE: 75,
				ResourceManager.ResourceType.GOLD: 50,
				ResourceManager.ResourceType.KNOWLEDGE: 10,
			},
		)
	)
	var state := ResourceManager.save_state()
	ResourceManager.reset()
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.FOOD)).is_equal(0)
	ResourceManager.load_state(state)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.FOOD)).is_equal(150)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.WOOD)).is_equal(250)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.STONE)).is_equal(75)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.GOLD)).is_equal(50)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.KNOWLEDGE)).is_equal(10)


func test_save_load_multiple_players() -> void:
	ResourceManager.init_player(99, {ResourceManager.ResourceType.FOOD: 100})
	ResourceManager.init_player(98, {ResourceManager.ResourceType.FOOD: 200})
	var state := ResourceManager.save_state()
	ResourceManager.reset()
	ResourceManager.load_state(state)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.FOOD)).is_equal(100)
	assert_int(ResourceManager.get_amount(98, ResourceManager.ResourceType.FOOD)).is_equal(200)


# --- reset test ---


func test_reset_clears_all_stockpiles() -> void:
	ResourceManager.init_player(99, {ResourceManager.ResourceType.FOOD: 500})
	ResourceManager.reset()
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.FOOD)).is_equal(0)


# --- corruption tests ---


func test_corruption_reduces_positive_income() -> void:
	ResourceManager.init_player(99, {})
	ResourceManager.set_corruption_rate(99, 0.20)
	ResourceManager.add_resource(99, ResourceManager.ResourceType.FOOD, 100)
	# 100 * (1 - 0.20) = 80
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.FOOD)).is_equal(80)
	ResourceManager.set_corruption_rate(99, 0.0)


func test_corruption_does_not_affect_knowledge() -> void:
	ResourceManager.init_player(99, {})
	ResourceManager.set_corruption_rate(99, 0.20)
	ResourceManager.add_resource(99, ResourceManager.ResourceType.KNOWLEDGE, 100)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.KNOWLEDGE)).is_equal(100)
	ResourceManager.set_corruption_rate(99, 0.0)


func test_corruption_does_not_affect_spending() -> void:
	ResourceManager.init_player(99, {ResourceManager.ResourceType.FOOD: 200})
	ResourceManager.set_corruption_rate(99, 0.50)
	ResourceManager.add_resource(99, ResourceManager.ResourceType.FOOD, -100)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.FOOD)).is_equal(100)
	ResourceManager.set_corruption_rate(99, 0.0)


func test_corruption_minimum_yield_is_one() -> void:
	ResourceManager.init_player(99, {})
	ResourceManager.set_corruption_rate(99, 0.99)
	ResourceManager.add_resource(99, ResourceManager.ResourceType.FOOD, 1)
	# 1 * (1 - 0.99) = 0.01 -> maxi(0, 1) = 1
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.FOOD)).is_equal(1)
	ResourceManager.set_corruption_rate(99, 0.0)


# --- Difficulty starting resources ---


func test_hard_starting_resources_cover_tc_cost() -> void:
	ResourceManager.init_player(99, null, "hard")
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.FOOD)).is_equal(150)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.WOOD)).is_equal(400)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.STONE)).is_equal(175)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.GOLD)).is_equal(50)


func test_expert_starting_resources_cover_tc_cost() -> void:
	ResourceManager.init_player(99, null, "expert")
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.FOOD)).is_equal(100)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.WOOD)).is_equal(375)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.STONE)).is_equal(150)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.GOLD)).is_equal(50)
