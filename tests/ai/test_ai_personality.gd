extends GdUnitTestSuite
## Tests for scripts/ai/ai_personality.gd — AI gameplay personality system.

const AIPersonalityScript := preload("res://scripts/ai/ai_personality.gd")
const AIEconomyScript := preload("res://scripts/ai/ai_economy.gd")
const AIMilitaryScript := preload("res://scripts/ai/ai_military.gd")
const AITechScript := preload("res://scripts/ai/ai_tech.gd")
const TechManagerScript := preload("res://scripts/prototype/tech_manager.gd")
const PopManagerScript := preload("res://scripts/prototype/population_manager.gd")

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
	AIPersonality.clear_cache()


func after_test() -> void:
	_gm_guard.dispose()
	_rm_guard.dispose()
	AIPersonality.clear_cache()


# --- Helpers ---


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


func _create_pop_manager() -> Node:
	var mgr := Node.new()
	mgr.set_script(PopManagerScript)
	add_child(mgr)
	return auto_free(mgr)


func _create_tech_manager() -> Node:
	var node := Node.new()
	node.set_script(TechManagerScript)
	add_child(node)
	return auto_free(node)


# --- Loading tests ---


func test_load_all_returns_four_personalities() -> void:
	var all := AIPersonality.load_all()
	assert_int(all.size()).is_equal(4)
	assert_bool(all.has("builder")).is_true()
	assert_bool(all.has("rusher")).is_true()
	assert_bool(all.has("boomer")).is_true()
	assert_bool(all.has("turtle")).is_true()


func test_get_personality_returns_valid_instance() -> void:
	var p := AIPersonality.get_personality("builder")
	assert_that(p).is_not_null()
	assert_str(p.personality_id).is_equal("builder")


func test_get_personality_returns_null_for_invalid() -> void:
	var p := AIPersonality.get_personality("nonexistent")
	assert_that(p).is_null()


func test_get_random_id_returns_valid_personality() -> void:
	var pid: String = AIPersonality.get_random_id()
	var valid := ["builder", "rusher", "boomer", "turtle"]
	assert_bool(pid in valid).is_true()


# --- Name and description tests ---


func test_builder_name() -> void:
	var p := AIPersonality.get_personality("builder")
	assert_str(p.get_name()).is_equal("Builder")


func test_rusher_description_not_empty() -> void:
	var p := AIPersonality.get_personality("rusher")
	assert_str(p.get_description()).is_not_empty()


# --- Tech personality mapping ---


func test_builder_tech_personality_is_economic() -> void:
	var p := AIPersonality.get_personality("builder")
	assert_str(p.get_tech_personality()).is_equal("economic")


func test_rusher_tech_personality_is_aggressive() -> void:
	var p := AIPersonality.get_personality("rusher")
	assert_str(p.get_tech_personality()).is_equal("aggressive")


func test_boomer_tech_personality_is_economic() -> void:
	var p := AIPersonality.get_personality("boomer")
	assert_str(p.get_tech_personality()).is_equal("economic")


func test_turtle_tech_personality_is_balanced() -> void:
	var p := AIPersonality.get_personality("turtle")
	assert_str(p.get_tech_personality()).is_equal("balanced")


# --- Build order override ---


func test_builder_has_no_build_order_override() -> void:
	var p := AIPersonality.get_personality("builder")
	assert_str(p.get_build_order_override()).is_equal("")


func test_rusher_has_build_order_override() -> void:
	var p := AIPersonality.get_personality("rusher")
	assert_str(p.get_build_order_override()).is_equal("rusher")


func test_boomer_has_build_order_override() -> void:
	var p := AIPersonality.get_personality("boomer")
	assert_str(p.get_build_order_override()).is_equal("boomer")


func test_turtle_has_build_order_override() -> void:
	var p := AIPersonality.get_personality("turtle")
	assert_str(p.get_build_order_override()).is_equal("turtle")


# --- Military modifier application ---


func test_rusher_lowers_attack_threshold() -> void:
	var p := AIPersonality.get_personality("rusher")
	var base := {"army_attack_threshold": 8}
	var result := p.apply_military_modifiers(base)
	# 8 * 0.5 = 4
	assert_int(int(result["army_attack_threshold"])).is_equal(4)


func test_builder_raises_attack_threshold() -> void:
	var p := AIPersonality.get_personality("builder")
	var base := {"army_attack_threshold": 8}
	var result := p.apply_military_modifiers(base)
	# 8 * 1.5 = 12
	assert_int(int(result["army_attack_threshold"])).is_equal(12)


func test_turtle_raises_min_attack_time() -> void:
	var p := AIPersonality.get_personality("turtle")
	var base := {"min_attack_game_time": 420.0}
	var result := p.apply_military_modifiers(base)
	# 420 * 1.5 = 630
	assert_float(result["min_attack_game_time"]).is_equal(630.0)


func test_rusher_lowers_min_attack_time() -> void:
	var p := AIPersonality.get_personality("rusher")
	var base := {"min_attack_game_time": 420.0}
	var result := p.apply_military_modifiers(base)
	# 420 * 0.5 = 210
	assert_float(result["min_attack_game_time"]).is_equal(210.0)


func test_turtle_raises_retreat_hp_ratio() -> void:
	var p := AIPersonality.get_personality("turtle")
	var base := {"retreat_hp_ratio": 0.25}
	var result := p.apply_military_modifiers(base)
	# 0.25 * 1.3 = 0.325
	assert_float(result["retreat_hp_ratio"]).is_equal_approx(0.325, 0.001)


func test_military_modifiers_dont_touch_missing_keys() -> void:
	var p := AIPersonality.get_personality("rusher")
	var base := {"tick_interval": 3.0}
	var result := p.apply_military_modifiers(base)
	assert_float(result["tick_interval"]).is_equal(3.0)


func test_rusher_raises_military_pop_ratio() -> void:
	var p := AIPersonality.get_personality("rusher")
	var base := {"max_military_pop_ratio": 0.50}
	var result := p.apply_military_modifiers(base)
	# 0.50 * 1.3 = 0.65
	assert_float(result["max_military_pop_ratio"]).is_equal_approx(0.65, 0.001)


# --- Economy modifier application ---


func test_builder_raises_max_villagers() -> void:
	var p := AIPersonality.get_personality("builder")
	var base := {"max_villagers": 30}
	var result := p.apply_economy_modifiers(base)
	# 30 * 1.3 = 39
	assert_int(int(result["max_villagers"])).is_equal(39)


func test_rusher_lowers_max_villagers() -> void:
	var p := AIPersonality.get_personality("rusher")
	var base := {"max_villagers": 30}
	var result := p.apply_economy_modifiers(base)
	# 30 * 0.7 = 21
	assert_int(int(result["max_villagers"])).is_equal(21)


func test_boomer_raises_max_villagers() -> void:
	var p := AIPersonality.get_personality("boomer")
	var base := {"max_villagers": 30}
	var result := p.apply_economy_modifiers(base)
	# 30 * 1.5 = 45
	assert_int(int(result["max_villagers"])).is_equal(45)


func test_economy_modifiers_no_max_villagers_key() -> void:
	var p := AIPersonality.get_personality("builder")
	var base := {"tick_interval": 2.0}
	var result := p.apply_economy_modifiers(base)
	assert_float(result["tick_interval"]).is_equal(2.0)
	assert_bool(result.has("max_villagers")).is_false()


# --- Personalities produce different configs ---


func test_all_personalities_produce_different_military_configs() -> void:
	var base := {
		"army_attack_threshold": 8,
		"min_attack_game_time": 420.0,
		"attack_cooldown": 90.0,
		"max_military_pop_ratio": 0.50,
		"military_budget_ratio": 0.60,
	}
	var results: Array[Dictionary] = []
	for pid: String in ["builder", "rusher", "boomer", "turtle"]:
		var p := AIPersonality.get_personality(pid)
		results.append(p.apply_military_modifiers(base))
	# Each should be distinct from the others
	for i in range(results.size()):
		for j in range(i + 1, results.size()):
			assert_bool(results[i] == results[j]).is_false()


# --- Integration with AIEconomy build order ---


func test_rusher_uses_personality_build_order() -> void:
	var p := AIPersonality.get_personality("rusher")
	var ai := Node.new()
	ai.name = "AIEconomy"
	ai.set_script(AIEconomyScript)
	ai.difficulty = "normal"
	ai.personality = p
	add_child(ai)
	ai.setup(self, _create_pop_manager(), null, null, null)
	# Rusher build order starts with fewer villagers than normal
	var first_step: Dictionary = ai._build_order[0]
	assert_str(str(first_step.get("action", ""))).is_equal("train")
	assert_int(int(first_step.get("count", 0))).is_equal(3)
	ai.queue_free()


func test_builder_uses_default_difficulty_build_order() -> void:
	var p := AIPersonality.get_personality("builder")
	var ai := Node.new()
	ai.name = "AIEconomy"
	ai.set_script(AIEconomyScript)
	ai.difficulty = "normal"
	ai.personality = p
	add_child(ai)
	ai.setup(self, _create_pop_manager(), null, null, null)
	# Builder has no override, so uses normal difficulty build order
	var first_step: Dictionary = ai._build_order[0]
	assert_int(int(first_step.get("count", 0))).is_equal(4)
	ai.queue_free()


# --- Integration with AIMilitary config ---


func test_rusher_modifies_military_config() -> void:
	var p := AIPersonality.get_personality("rusher")
	var ai := Node.new()
	ai.name = "AIMilitary"
	ai.set_script(AIMilitaryScript)
	ai.difficulty = "normal"
	ai.personality = p
	add_child(ai)
	ai.setup(self, _create_pop_manager(), null, null)
	# Normal base: army_attack_threshold=8, rusher multiplier=0.5 → 4
	assert_int(int(ai._config.get("army_attack_threshold", 0))).is_equal(4)
	ai.queue_free()


# --- Integration with AITech ---


func test_gameplay_personality_overrides_tech_personality() -> void:
	var p := AIPersonality.get_personality("rusher")
	var tm := _create_tech_manager()
	var ai := Node.new()
	ai.name = "AITech"
	ai.set_script(AITechScript)
	ai.difficulty = "normal"
	ai.gameplay_personality = p
	add_child(ai)
	ai.setup(tm)
	# Rusher's tech personality is "aggressive"
	assert_str(ai.personality).is_equal("aggressive")
	ai.queue_free()


# --- Save/load round-trip ---


func test_economy_save_load_preserves_personality() -> void:
	var p := AIPersonality.get_personality("boomer")
	var ai := Node.new()
	ai.name = "AIEconomy"
	ai.set_script(AIEconomyScript)
	ai.difficulty = "normal"
	ai.personality = p
	add_child(ai)
	ai.setup(self, _create_pop_manager(), null, null, null)
	var state: Dictionary = ai.save_state()
	assert_str(str(state.get("personality_id", ""))).is_equal("boomer")
	# Load into fresh instance
	var ai2 := Node.new()
	ai2.name = "AIEconomy2"
	ai2.set_script(AIEconomyScript)
	add_child(ai2)
	ai2.setup(self, _create_pop_manager(), null, null, null)
	ai2.load_state(state)
	assert_that(ai2.personality).is_not_null()
	assert_str(ai2.personality.personality_id).is_equal("boomer")
	ai.queue_free()
	ai2.queue_free()


func test_military_save_load_preserves_personality() -> void:
	var p := AIPersonality.get_personality("turtle")
	var ai := Node.new()
	ai.name = "AIMilitary"
	ai.set_script(AIMilitaryScript)
	ai.difficulty = "normal"
	ai.personality = p
	add_child(ai)
	ai.setup(self, _create_pop_manager(), null, null)
	var state: Dictionary = ai.save_state()
	assert_str(str(state.get("personality_id", ""))).is_equal("turtle")
	var ai2 := Node.new()
	ai2.name = "AIMilitary2"
	ai2.set_script(AIMilitaryScript)
	add_child(ai2)
	ai2.setup(self, _create_pop_manager(), null, null)
	ai2.load_state(state)
	assert_that(ai2.personality).is_not_null()
	assert_str(ai2.personality.personality_id).is_equal("turtle")
	ai.queue_free()
	ai2.queue_free()


func test_tech_save_load_preserves_gameplay_personality() -> void:
	var p := AIPersonality.get_personality("rusher")
	var tm := _create_tech_manager()
	var ai := Node.new()
	ai.name = "AITech"
	ai.set_script(AITechScript)
	ai.difficulty = "normal"
	ai.gameplay_personality = p
	add_child(ai)
	ai.setup(tm)
	var state: Dictionary = ai.save_state()
	assert_str(str(state.get("gameplay_personality_id", ""))).is_equal("rusher")
	var ai2 := Node.new()
	ai2.name = "AITech2"
	ai2.set_script(AITechScript)
	add_child(ai2)
	ai2.setup(tm)
	ai2.load_state(state)
	assert_that(ai2.gameplay_personality).is_not_null()
	assert_str(ai2.gameplay_personality.personality_id).is_equal("rusher")
	assert_str(ai2.personality).is_equal("aggressive")
	ai.queue_free()
	ai2.queue_free()
