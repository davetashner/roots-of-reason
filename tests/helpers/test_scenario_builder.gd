extends GdUnitTestSuite
## Tests for ScenarioBuilder integration test helper.

const ScenarioBuilder := preload("res://tests/helpers/scenario_builder.gd")
const RMGuard := preload("res://tests/helpers/resource_manager_guard.gd")
const CBMGuard := preload("res://tests/helpers/civ_bonus_manager_guard.gd")
const GMGuard := preload("res://tests/helpers/game_manager_guard.gd")

var _rm_guard: RefCounted
var _cbm_guard: RefCounted
var _gm_guard: RefCounted


func before_test() -> void:
	_rm_guard = RMGuard.new()
	_cbm_guard = CBMGuard.new()
	_gm_guard = GMGuard.new()
	CivBonusManager.reset()


func after_test() -> void:
	_gm_guard.dispose()
	_cbm_guard.dispose()
	_rm_guard.dispose()


# --- Chaining ---


func test_methods_return_self_for_chaining() -> void:
	var sb := ScenarioBuilder.new()
	var result: RefCounted = sb.set_civ(0, "rome")
	assert_object(result).is_same(sb)
	result = sb.set_age(0, "bronze")
	assert_object(result).is_same(sb)
	result = sb.give_resources(0, {"food": 100})
	assert_object(result).is_same(sb)
	result = sb.spawn_units(0, "infantry", 1, Vector2i(5, 5))
	assert_object(result).is_same(sb)
	result = sb.build(0, "house", Vector2i(3, 3))
	assert_object(result).is_same(sb)


func test_execute_returns_self() -> void:
	var sb := ScenarioBuilder.new()
	ResourceManager.init_player(0, {})
	var result: RefCounted = sb.give_resources(0, {"food": 100}).execute()
	assert_object(result).is_same(sb)


func test_chained_calls_accumulate_steps() -> void:
	var sb := ScenarioBuilder.new()
	sb.set_civ(0, "rome").give_resources(0, {"food": 100}).set_age(0, "bronze")
	assert_int(sb.pending_step_count()).is_equal(3)


func test_execute_clears_pending_steps() -> void:
	var sb := ScenarioBuilder.new()
	ResourceManager.init_player(0, {})
	sb.give_resources(0, {"food": 100}).execute()
	assert_int(sb.pending_step_count()).is_equal(0)


# --- set_civ ---


func test_set_civ_applies_bonuses() -> void:
	var sb := ScenarioBuilder.new()
	sb.set_civ(0, "rome").execute()
	assert_str(CivBonusManager.get_active_civ(0)).is_equal("rome")


func test_set_civ_sets_game_manager_civilization() -> void:
	var sb := ScenarioBuilder.new()
	sb.set_civ(0, "mesopotamia").execute()
	assert_str(GameManager.get_player_civilization(0)).is_equal("mesopotamia")


func test_set_civ_initializes_resource_manager() -> void:
	var sb := ScenarioBuilder.new()
	sb.set_civ(0, "rome").execute()
	assert_bool(ResourceManager.has_player(0)).is_true()


func test_set_civ_rome_military_attack_bonus() -> void:
	var sb := ScenarioBuilder.new()
	sb.set_civ(0, "rome").execute()
	assert_float(CivBonusManager.get_bonus_value(0, "military_attack")).is_equal_approx(1.10, 0.001)


# --- give_resources ---


func test_give_resources_sets_exact_amounts() -> void:
	var sb := ScenarioBuilder.new()
	ResourceManager.init_player(0, {})
	sb.give_resources(0, {"food": 500, "wood": 300, "stone": 200, "gold": 100}).execute()
	assert_int(ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)).is_equal(500)
	assert_int(ResourceManager.get_amount(0, ResourceManager.ResourceType.WOOD)).is_equal(300)
	assert_int(ResourceManager.get_amount(0, ResourceManager.ResourceType.STONE)).is_equal(200)
	assert_int(ResourceManager.get_amount(0, ResourceManager.ResourceType.GOLD)).is_equal(100)


func test_give_resources_initializes_player_if_needed() -> void:
	var sb := ScenarioBuilder.new()
	sb.give_resources(77, {"food": 42}).execute()
	assert_bool(ResourceManager.has_player(77)).is_true()
	assert_int(ResourceManager.get_amount(77, ResourceManager.ResourceType.FOOD)).is_equal(42)


func test_give_resources_overwrites_previous() -> void:
	var sb := ScenarioBuilder.new()
	ResourceManager.init_player(0, {ResourceManager.ResourceType.FOOD: 9999})
	sb.give_resources(0, {"food": 100}).execute()
	assert_int(ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)).is_equal(100)


# --- Combined scenario ---


func test_civ_then_resources_scenario() -> void:
	var sb := ScenarioBuilder.new()
	sb.set_civ(0, "rome").give_resources(0, {"food": 1000, "wood": 800}).execute()
	assert_str(CivBonusManager.get_active_civ(0)).is_equal("rome")
	assert_int(ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)).is_equal(1000)
	assert_int(ResourceManager.get_amount(0, ResourceManager.ResourceType.WOOD)).is_equal(800)


func test_multiple_players_scenario() -> void:
	var sb := ScenarioBuilder.new()
	(
		sb
		. set_civ(0, "rome")
		. set_civ(1, "mesopotamia")
		. give_resources(0, {"food": 500})
		. give_resources(1, {"food": 300})
		. execute()
	)
	assert_str(CivBonusManager.get_active_civ(0)).is_equal("rome")
	assert_str(CivBonusManager.get_active_civ(1)).is_equal("mesopotamia")
	assert_int(ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)).is_equal(500)
	assert_int(ResourceManager.get_amount(1, ResourceManager.ResourceType.FOOD)).is_equal(300)


# --- with_scene_root ---


func test_with_scene_root_returns_self() -> void:
	var sb := ScenarioBuilder.new()
	var dummy := Node.new()
	var result: RefCounted = sb.with_scene_root(dummy)
	assert_object(result).is_same(sb)
	dummy.free()
