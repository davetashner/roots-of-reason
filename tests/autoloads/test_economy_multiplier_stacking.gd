extends GdUnitTestSuite
## End-to-end test verifying tech bonus + civ bonus + gather multiplier
## compose correctly through ResourceManager.add_resource.

const FOOD := ResourceManager.ResourceType.FOOD
const WOOD := ResourceManager.ResourceType.WOOD
const GOLD := ResourceManager.ResourceType.GOLD
const KNOWLEDGE := ResourceManager.ResourceType.KNOWLEDGE
const PLAYER_ID := 50

const RMGuard := preload("res://tests/helpers/resource_manager_guard.gd")
const CBMGuard := preload("res://tests/helpers/civ_bonus_manager_guard.gd")

var _rm_guard: RefCounted
var _cbm_guard: RefCounted


func before_test() -> void:
	_rm_guard = RMGuard.new()
	_cbm_guard = CBMGuard.new()
	ResourceManager.reset()
	CivBonusManager.reset()


func after_test() -> void:
	_cbm_guard.dispose()
	_rm_guard.dispose()


## Composes multipliers the way the game would: difficulty gather rate *
## tech gather_rate bonus * civ bonus, then sets the result on ResourceManager.
func _compose_and_set_multiplier(
	player_id: int,
	difficulty_multiplier: float,
	tech_gather_rate_bonus: float,
	civ_bonus_key: String,
) -> float:
	var civ_multiplier: float = CivBonusManager.get_bonus_value(player_id, civ_bonus_key)
	var composed: float = difficulty_multiplier * (1.0 + tech_gather_rate_bonus) * civ_multiplier
	ResourceManager.set_gather_multiplier(player_id, composed)
	return composed


# --- Core stacking tests ---


func test_all_three_multipliers_compose_on_add_resource() -> void:
	## Difficulty 1.2x + tech gather_rate +10% + civ build_speed 1.15x
	## Composed: 1.2 * 1.10 * 1.15 = 1.518
	## Adding 100 food: int(100 * 1.518) = 151
	ResourceManager.init_player(PLAYER_ID, {FOOD: 0})
	CivBonusManager.apply_civ_bonuses(PLAYER_ID, "mesopotamia")
	var composed := _compose_and_set_multiplier(PLAYER_ID, 1.2, 0.10, "build_speed")
	ResourceManager.add_resource(PLAYER_ID, FOOD, 100)
	var expected: int = int(100.0 * composed)
	assert_int(ResourceManager.get_amount(PLAYER_ID, FOOD)).is_equal(expected)


func test_stacked_multipliers_with_corruption() -> void:
	## Difficulty 1.5x + tech gather_rate +25% + civ build_speed 1.15x
	## Composed: 1.5 * 1.25 * 1.15 = 2.15625
	## Corruption 20%: amount after multiplier then reduced by corruption
	## Adding 100 food: int(100 * 2.15625) = 215
	## After corruption: maxi(int(215 * 0.80), 1) = 172
	ResourceManager.init_player(PLAYER_ID, {FOOD: 0})
	CivBonusManager.apply_civ_bonuses(PLAYER_ID, "mesopotamia")
	var composed := _compose_and_set_multiplier(PLAYER_ID, 1.5, 0.25, "build_speed")
	ResourceManager.set_corruption_rate(PLAYER_ID, 0.20)
	ResourceManager.add_resource(PLAYER_ID, FOOD, 100)
	var after_gather: int = int(100.0 * composed)
	var expected: int = maxi(int(float(after_gather) * 0.80), 1)
	assert_int(ResourceManager.get_amount(PLAYER_ID, FOOD)).is_equal(expected)


func test_knowledge_exempt_from_corruption_but_receives_multiplier() -> void:
	## Knowledge is exempt from corruption but still receives gather multiplier.
	## Difficulty 1.2x + tech +10% + civ 1.15x = 1.518
	## Adding 100 knowledge with 50% corruption: int(100 * 1.518) = 151
	## Corruption does NOT apply to knowledge.
	ResourceManager.init_player(PLAYER_ID, {KNOWLEDGE: 0})
	CivBonusManager.apply_civ_bonuses(PLAYER_ID, "mesopotamia")
	var composed := _compose_and_set_multiplier(PLAYER_ID, 1.2, 0.10, "build_speed")
	ResourceManager.set_corruption_rate(PLAYER_ID, 0.50)
	ResourceManager.add_resource(PLAYER_ID, KNOWLEDGE, 100)
	var expected: int = int(100.0 * composed)
	assert_int(ResourceManager.get_amount(PLAYER_ID, KNOWLEDGE)).is_equal(expected)


func test_no_bonuses_yields_base_amount() -> void:
	## With no tech, no civ, and default gather multiplier, amount is unchanged.
	ResourceManager.init_player(PLAYER_ID, {WOOD: 0})
	ResourceManager.add_resource(PLAYER_ID, WOOD, 100)
	assert_int(ResourceManager.get_amount(PLAYER_ID, WOOD)).is_equal(100)


func test_only_difficulty_multiplier() -> void:
	## Only difficulty gather multiplier (1.5x), no tech or civ bonuses.
	ResourceManager.init_player(PLAYER_ID, {GOLD: 0})
	ResourceManager.set_gather_multiplier(PLAYER_ID, 1.5)
	ResourceManager.add_resource(PLAYER_ID, GOLD, 100)
	assert_int(ResourceManager.get_amount(PLAYER_ID, GOLD)).is_equal(150)


func test_tech_plus_difficulty_without_civ() -> void:
	## Difficulty 1.2x + tech +25% = 1.2 * 1.25 = 1.5
	## No civ bonus (defaults to 1.0).
	ResourceManager.init_player(PLAYER_ID, {FOOD: 0})
	var difficulty_mult := 1.2
	var tech_bonus := 0.25
	var composed: float = difficulty_mult * (1.0 + tech_bonus)
	ResourceManager.set_gather_multiplier(PLAYER_ID, composed)
	ResourceManager.add_resource(PLAYER_ID, FOOD, 200)
	var expected: int = int(200.0 * composed)
	assert_int(ResourceManager.get_amount(PLAYER_ID, FOOD)).is_equal(expected)


func test_civ_plus_difficulty_without_tech() -> void:
	## Difficulty 0.7x (easy) + civ build_speed 1.15x, no tech bonus.
	## Composed: 0.7 * 1.0 * 1.15 = 0.805
	ResourceManager.init_player(PLAYER_ID, {WOOD: 0})
	CivBonusManager.apply_civ_bonuses(PLAYER_ID, "mesopotamia")
	var composed := _compose_and_set_multiplier(PLAYER_ID, 0.7, 0.0, "build_speed")
	ResourceManager.add_resource(PLAYER_ID, WOOD, 100)
	var expected: int = int(100.0 * composed)
	assert_int(ResourceManager.get_amount(PLAYER_ID, WOOD)).is_equal(expected)


func test_multiple_adds_accumulate_with_stacked_multipliers() -> void:
	## Verify that stacked multipliers apply consistently across multiple adds.
	## Difficulty 1.2x + tech +10% + civ 1.15x = 1.518
	ResourceManager.init_player(PLAYER_ID, {FOOD: 0})
	CivBonusManager.apply_civ_bonuses(PLAYER_ID, "mesopotamia")
	var composed := _compose_and_set_multiplier(PLAYER_ID, 1.2, 0.10, "build_speed")
	ResourceManager.add_resource(PLAYER_ID, FOOD, 50)
	ResourceManager.add_resource(PLAYER_ID, FOOD, 50)
	var single_add: int = int(50.0 * composed)
	assert_int(ResourceManager.get_amount(PLAYER_ID, FOOD)).is_equal(single_add * 2)


func test_spending_not_affected_by_multiplier() -> void:
	## Negative amounts (spending) should bypass the gather multiplier entirely.
	ResourceManager.init_player(PLAYER_ID, {GOLD: 500})
	CivBonusManager.apply_civ_bonuses(PLAYER_ID, "mesopotamia")
	_compose_and_set_multiplier(PLAYER_ID, 1.5, 0.25, "build_speed")
	ResourceManager.add_resource(PLAYER_ID, GOLD, -100)
	assert_int(ResourceManager.get_amount(PLAYER_ID, GOLD)).is_equal(400)
