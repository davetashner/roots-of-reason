extends GdUnitTestSuite
## Tests for DebugAPI — spawn, resource, and tech manipulation methods.

const RMGuard := preload("res://tests/helpers/resource_manager_guard.gd")
const GMGuard := preload("res://tests/helpers/game_manager_guard.gd")

var _rm_guard: RefCounted
var _gm_guard: RefCounted


func before_test() -> void:
	_rm_guard = RMGuard.new()
	_gm_guard = GMGuard.new()


func after_test() -> void:
	_rm_guard.dispose()
	_gm_guard.dispose()


# --- give_resources tests ---


func test_give_resources_adds_food() -> void:
	ResourceManager.init_player(99, {})
	DebugAPI.give_resources(99, "food", 500)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.FOOD)).is_equal(500)


func test_give_resources_adds_wood() -> void:
	ResourceManager.init_player(99, {})
	DebugAPI.give_resources(99, "wood", 300)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.WOOD)).is_equal(300)


func test_give_resources_adds_gold() -> void:
	ResourceManager.init_player(99, {})
	DebugAPI.give_resources(99, "gold", 750)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.GOLD)).is_equal(750)


func test_give_resources_adds_stone() -> void:
	ResourceManager.init_player(99, {})
	DebugAPI.give_resources(99, "stone", 200)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.STONE)).is_equal(200)


func test_give_resources_adds_knowledge() -> void:
	ResourceManager.init_player(99, {})
	DebugAPI.give_resources(99, "knowledge", 100)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.KNOWLEDGE)).is_equal(100)


func test_give_resources_case_insensitive() -> void:
	ResourceManager.init_player(99, {})
	DebugAPI.give_resources(99, "FOOD", 250)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.FOOD)).is_equal(250)


func test_give_resources_unknown_type_does_nothing() -> void:
	ResourceManager.init_player(99, {})
	DebugAPI.give_resources(99, "mana", 100)
	# Should not crash — just prints a warning
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.FOOD)).is_equal(0)


func test_give_resources_inits_player_if_needed() -> void:
	# Player 88 doesn't exist yet
	DebugAPI.give_resources(88, "food", 100)
	assert_int(ResourceManager.get_amount(88, ResourceManager.ResourceType.FOOD)).is_equal(100)


# --- give_all_resources tests ---


func test_give_all_sets_all_resources() -> void:
	ResourceManager.init_player(99, {})
	DebugAPI.give_all_resources(99, 9999)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.FOOD)).is_equal(9999)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.WOOD)).is_equal(9999)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.STONE)).is_equal(9999)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.GOLD)).is_equal(9999)
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.KNOWLEDGE)).is_equal(9999)


# --- advance_age tests ---


func test_advance_age_increments_current_age() -> void:
	GameManager.current_age = 0
	DebugAPI.advance_age(0)
	assert_int(GameManager.current_age).is_equal(1)


func test_advance_age_from_iron_to_medieval() -> void:
	GameManager.current_age = 2
	DebugAPI.advance_age(0)
	assert_int(GameManager.current_age).is_equal(3)


func test_advance_age_at_max_stays() -> void:
	GameManager.current_age = 6
	DebugAPI.advance_age(0)
	# Should stay at max (6 is Singularity)
	assert_int(GameManager.current_age).is_equal(6)


# --- set_age tests ---


func test_set_age_by_full_name() -> void:
	GameManager.current_age = 0
	DebugAPI.set_age("Bronze Age", 0)
	assert_int(GameManager.current_age).is_equal(1)


func test_set_age_by_short_name() -> void:
	GameManager.current_age = 0
	DebugAPI.set_age("iron", 0)
	assert_int(GameManager.current_age).is_equal(2)


func test_set_age_unknown_name_stays() -> void:
	GameManager.current_age = 0
	DebugAPI.set_age("nonexistent", 0)
	assert_int(GameManager.current_age).is_equal(0)
