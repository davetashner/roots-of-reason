extends GdUnitTestSuite
## Tests for AI difficulty tiers — config loading, gather multiplier, propagation, save/load.

const AIEconomyScript := preload("res://scripts/ai/ai_economy.gd")
const AIMilitaryScript := preload("res://scripts/ai/ai_military.gd")
const AITechScript := preload("res://scripts/ai/ai_tech.gd")
const TechManagerScript := preload("res://scripts/prototype/tech_manager.gd")
const PopManagerScript := preload("res://scripts/prototype/population_manager.gd")

var _original_stockpiles: Dictionary
var _original_multipliers: Dictionary
var _original_ai_difficulty: String
var _original_game_time: float
var _original_age: int


func before_test() -> void:
	_original_stockpiles = ResourceManager._stockpiles.duplicate(true)
	_original_multipliers = ResourceManager._gather_multipliers.duplicate(true)
	_original_ai_difficulty = GameManager.ai_difficulty
	_original_game_time = GameManager.game_time
	_original_age = GameManager.current_age
	ResourceManager._stockpiles.clear()
	ResourceManager._gather_multipliers.clear()
	GameManager.ai_difficulty = "normal"
	GameManager.game_time = 0.0
	GameManager.current_age = 0


func after_test() -> void:
	ResourceManager._stockpiles = _original_stockpiles
	ResourceManager._gather_multipliers = _original_multipliers
	GameManager.ai_difficulty = _original_ai_difficulty
	GameManager.game_time = _original_game_time
	GameManager.current_age = _original_age


# --- Helpers ---


func _empty_resources() -> Dictionary:
	var empty: Dictionary = {}
	for rt: ResourceManager.ResourceType in ResourceManager.ResourceType.values():
		empty[rt] = 0
	return empty


# --- Config Loading ---


func test_ai_difficulty_json_loads_all_four_tiers() -> void:
	var data: Variant = DataLoader.load_json("res://data/ai/ai_difficulty.json")
	assert_that(data).is_not_null()
	var tiers: Dictionary = data["tiers"]
	assert_that(tiers.has("easy")).is_true()
	assert_that(tiers.has("normal")).is_true()
	assert_that(tiers.has("hard")).is_true()
	assert_that(tiers.has("expert")).is_true()


func test_ai_difficulty_default_is_normal() -> void:
	var data: Variant = DataLoader.load_json("res://data/ai/ai_difficulty.json")
	assert_that(data["default"]).is_equal("normal")


func test_each_tier_has_required_keys() -> void:
	var data: Variant = DataLoader.load_json("res://data/ai/ai_difficulty.json")
	var tiers: Dictionary = data["tiers"]
	for tier_name: String in tiers:
		var tier: Dictionary = tiers[tier_name]
		assert_that(tier.has("gather_rate_multiplier")).is_true()
		assert_that(tier.has("starting_villagers")).is_true()
		assert_that(tier.has("personality")).is_true()


func test_gather_multiplier_values_ascending() -> void:
	var data: Variant = DataLoader.load_json("res://data/ai/ai_difficulty.json")
	var tiers: Dictionary = data["tiers"]
	var easy_m: float = tiers["easy"]["gather_rate_multiplier"]
	var normal_m: float = tiers["normal"]["gather_rate_multiplier"]
	var hard_m: float = tiers["hard"]["gather_rate_multiplier"]
	var expert_m: float = tiers["expert"]["gather_rate_multiplier"]
	assert_that(easy_m).is_less(normal_m)
	assert_that(normal_m).is_less(hard_m)
	assert_that(hard_m).is_less(expert_m)


# --- Gather Multiplier in ResourceManager ---


func test_set_and_get_gather_multiplier() -> void:
	ResourceManager.set_gather_multiplier(1, 1.5)
	assert_that(ResourceManager.get_gather_multiplier(1)).is_equal(1.5)


func test_get_gather_multiplier_defaults_to_one() -> void:
	assert_that(ResourceManager.get_gather_multiplier(99)).is_equal(1.0)


func test_add_resource_applies_multiplier() -> void:
	var empty: Dictionary = _empty_resources()
	ResourceManager.init_player(1, empty)
	ResourceManager.set_gather_multiplier(1, 1.5)
	ResourceManager.add_resource(1, ResourceManager.ResourceType.FOOD, 100)
	# 100 * 1.5 = 150
	assert_that(ResourceManager.get_amount(1, ResourceManager.ResourceType.FOOD)).is_equal(150)


func test_add_resource_no_multiplier_for_spending() -> void:
	var empty: Dictionary = _empty_resources()
	ResourceManager.init_player(1, empty)
	ResourceManager.set_gather_multiplier(1, 1.5)
	ResourceManager.add_resource(1, ResourceManager.ResourceType.FOOD, 200)
	# Negative amounts (spending) should not be multiplied
	ResourceManager.add_resource(1, ResourceManager.ResourceType.FOOD, -50)
	# 200 * 1.5 = 300, then -50 = 250
	assert_that(ResourceManager.get_amount(1, ResourceManager.ResourceType.FOOD)).is_equal(250)


func test_add_resource_easy_multiplier() -> void:
	var empty: Dictionary = _empty_resources()
	ResourceManager.init_player(1, empty)
	ResourceManager.set_gather_multiplier(1, 0.7)
	ResourceManager.add_resource(1, ResourceManager.ResourceType.WOOD, 100)
	# 100 * 0.7 = 70
	assert_that(ResourceManager.get_amount(1, ResourceManager.ResourceType.WOOD)).is_equal(70)


func test_multiplier_does_not_affect_other_player() -> void:
	var empty: Dictionary = _empty_resources()
	ResourceManager.init_player(0, empty)
	ResourceManager.init_player(1, empty)
	ResourceManager.set_gather_multiplier(1, 1.5)
	ResourceManager.add_resource(0, ResourceManager.ResourceType.FOOD, 100)
	ResourceManager.add_resource(1, ResourceManager.ResourceType.FOOD, 100)
	assert_that(ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)).is_equal(100)
	assert_that(ResourceManager.get_amount(1, ResourceManager.ResourceType.FOOD)).is_equal(150)


# --- Expert Tier in Per-Brain Configs ---


func test_build_orders_has_expert_tier() -> void:
	var data: Variant = DataLoader.load_json("res://data/ai/build_orders.json")
	assert_that(data).is_not_null()
	assert_that(data.has("expert")).is_true()
	assert_that(data["expert"].has("steps")).is_true()
	assert_that(data["expert"].has("villager_allocation")).is_true()


func test_military_config_has_expert_tier() -> void:
	var data: Variant = DataLoader.load_json("res://data/ai/military_config.json")
	assert_that(data).is_not_null()
	assert_that(data.has("expert")).is_true()
	assert_that(data["expert"]["tick_interval"]).is_equal(1.5)


func test_tech_config_has_expert_tier() -> void:
	var data: Variant = DataLoader.load_json("res://data/ai/tech_config.json")
	assert_that(data).is_not_null()
	assert_that(data.has("expert")).is_true()
	assert_that(int(data["expert"]["max_queue_size"])).is_equal(4)


# --- GameManager Save/Load ---


func test_game_manager_ai_difficulty_default() -> void:
	assert_that(GameManager.ai_difficulty).is_equal("normal")


func test_game_manager_saves_ai_difficulty() -> void:
	GameManager.ai_difficulty = "expert"
	var state: Dictionary = GameManager.save_state()
	assert_that(state["ai_difficulty"]).is_equal("expert")


func test_game_manager_loads_ai_difficulty() -> void:
	GameManager.ai_difficulty = "normal"
	var state: Dictionary = GameManager.save_state()
	state["ai_difficulty"] = "hard"
	GameManager.load_state(state)
	assert_that(GameManager.ai_difficulty).is_equal("hard")


func test_game_manager_loads_missing_difficulty_as_normal() -> void:
	GameManager.ai_difficulty = "hard"
	var state: Dictionary = GameManager.save_state()
	state.erase("ai_difficulty")
	GameManager.load_state(state)
	assert_that(GameManager.ai_difficulty).is_equal("normal")


# --- ResourceManager Save/Load with Multipliers ---


func test_resource_manager_saves_gather_multipliers() -> void:
	ResourceManager.init_player(1)
	ResourceManager.set_gather_multiplier(1, 1.5)
	var state: Dictionary = ResourceManager.save_state()
	assert_that(state.has("_gather_multipliers")).is_true()
	assert_that(state["_gather_multipliers"]["1"]).is_equal(1.5)


func test_resource_manager_loads_gather_multipliers() -> void:
	ResourceManager.init_player(1)
	ResourceManager.set_gather_multiplier(1, 1.5)
	var state: Dictionary = ResourceManager.save_state()
	ResourceManager.reset()
	ResourceManager.load_state(state)
	assert_that(ResourceManager.get_gather_multiplier(1)).is_equal(1.5)


func test_resource_manager_reset_clears_multipliers() -> void:
	ResourceManager.set_gather_multiplier(1, 1.5)
	ResourceManager.reset()
	assert_that(ResourceManager.get_gather_multiplier(1)).is_equal(1.0)


# --- Starting Villagers per Tier ---


func test_starting_villagers_vary_by_tier() -> void:
	var data: Variant = DataLoader.load_json("res://data/ai/ai_difficulty.json")
	var tiers: Dictionary = data["tiers"]
	assert_that(int(tiers["easy"]["starting_villagers"])).is_equal(3)
	assert_that(int(tiers["normal"]["starting_villagers"])).is_equal(3)
	assert_that(int(tiers["hard"]["starting_villagers"])).is_equal(4)
	assert_that(int(tiers["expert"]["starting_villagers"])).is_equal(5)
