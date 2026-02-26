extends GdUnitTestSuite
## Tests for scripts/ai/ai_singularity.gd — AI Singularity awareness brain.

const AISingularityScript := preload("res://scripts/ai/ai_singularity.gd")
const AIMilitaryScript := preload("res://scripts/ai/ai_military.gd")
const AITechScript := preload("res://scripts/ai/ai_tech.gd")
const TechManagerScript := preload("res://scripts/prototype/tech_manager.gd")
const PopManagerScript := preload("res://scripts/prototype/population_manager.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")

var _original_age: int
var _original_stockpiles: Dictionary
var _original_game_time: float


func before_test() -> void:
	_original_age = GameManager.current_age
	_original_stockpiles = ResourceManager._stockpiles.duplicate(true)
	_original_game_time = GameManager.game_time
	GameManager.current_age = 1
	GameManager.game_speed = 1.0
	GameManager.game_time = 0.0


func after_test() -> void:
	GameManager.current_age = _original_age
	GameManager.game_speed = 1.0
	GameManager.game_time = _original_game_time
	ResourceManager._stockpiles = _original_stockpiles


# --- Helpers ---


func _create_tech_manager() -> Node:
	var node := Node.new()
	node.set_script(TechManagerScript)
	add_child(node)
	return auto_free(node)


func _create_pop_manager() -> Node:
	var mgr := Node.new()
	mgr.set_script(PopManagerScript)
	add_child(mgr)
	mgr._starting_cap = 200
	mgr._hard_cap = 200
	return auto_free(mgr)


func _create_ai_military(
	scene_root: Node = null,
	pop_mgr: Node = null,
	tech_manager: Node = null,
	difficulty: String = "normal",
) -> Node:
	if scene_root == null:
		scene_root = self
	var ai := Node.new()
	ai.name = "AIMilitary_%d" % get_child_count()
	ai.set_script(AIMilitaryScript)
	ai.difficulty = difficulty
	add_child(ai)
	if pop_mgr == null:
		pop_mgr = _create_pop_manager()
	ai.setup(scene_root, pop_mgr, null, null, tech_manager)
	return auto_free(ai)


func _create_ai_tech(tech_manager: Node, difficulty: String = "normal") -> Node:
	var ai := Node.new()
	ai.name = "AITech_%d" % get_child_count()
	ai.set_script(AITechScript)
	ai.difficulty = difficulty
	ai.personality = "balanced"
	add_child(ai)
	ai.setup(tech_manager)
	return auto_free(ai)


func _create_singularity(
	tech_manager: Node,
	ai_military: Node,
	ai_tech: Node,
	difficulty: String = "normal",
	pers: AIPersonality = null,
) -> Node:
	var ai := Node.new()
	ai.name = "AISingularity_%d" % get_child_count()
	ai.set_script(AISingularityScript)
	ai.difficulty = difficulty
	ai.personality = pers
	add_child(ai)
	ai.setup(tech_manager, ai_military, ai_tech)
	return auto_free(ai)


func _give_enemy_singularity_techs(tm: Node, enemy_pid: int, count: int) -> void:
	var chain: Array = [
		"computing_theory",
		"neural_networks",
		"big_data",
		"parallel_computing",
		"deep_learning",
		"transformer_architecture",
		"alignment_research",
		"gpu_foundry",
		"transformer_lab",
		"agi_core",
	]
	var techs: Array = []
	for i in mini(count, chain.size()):
		techs.append(chain[i])
	tm._researched_techs[enemy_pid] = techs


func _create_enemy_building(
	building_name: String,
	owner_id: int = 0,
	grid_pos: Vector2i = Vector2i(10, 10),
) -> Node2D:
	var building := Node2D.new()
	building.name = "Building_%d" % get_child_count()
	building.set_script(BuildingScript)
	building.position = IsoUtils.grid_to_screen(Vector2(grid_pos))
	building.owner_id = owner_id
	building.building_name = building_name
	building.footprint = Vector2i(3, 3)
	building.grid_pos = grid_pos
	building.hp = 1000
	building.max_hp = 1000
	building.under_construction = false
	building.build_progress = 1.0
	add_child(building)
	return auto_free(building)


# --- Threat Assessment ---


func test_zero_techs_returns_no_threat() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm)
	var tech := _create_ai_tech(tm)
	var sing := _create_singularity(tm, mil, tech)
	var threat: Dictionary = sing.assess_enemy_threat(0)
	assert_str(threat.get("stage", "x")).is_equal("")
	assert_int(int(threat.get("count", -1))).is_equal(0)


func test_one_tech_returns_early() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm)
	var tech := _create_ai_tech(tm)
	var sing := _create_singularity(tm, mil, tech)
	_give_enemy_singularity_techs(tm, 0, 1)
	var threat: Dictionary = sing.assess_enemy_threat(0)
	assert_str(threat.get("stage", "")).is_equal("early")
	assert_int(int(threat.get("count", 0))).is_equal(1)


func test_three_techs_returns_mid() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm)
	var tech := _create_ai_tech(tm)
	var sing := _create_singularity(tm, mil, tech)
	_give_enemy_singularity_techs(tm, 0, 3)
	var threat: Dictionary = sing.assess_enemy_threat(0)
	assert_str(threat.get("stage", "")).is_equal("mid")


func test_five_techs_returns_late() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm)
	var tech := _create_ai_tech(tm)
	var sing := _create_singularity(tm, mil, tech)
	_give_enemy_singularity_techs(tm, 0, 5)
	var threat: Dictionary = sing.assess_enemy_threat(0)
	assert_str(threat.get("stage", "")).is_equal("late")


func test_seven_techs_returns_critical() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm)
	var tech := _create_ai_tech(tm)
	var sing := _create_singularity(tm, mil, tech)
	_give_enemy_singularity_techs(tm, 0, 7)
	var threat: Dictionary = sing.assess_enemy_threat(0)
	assert_str(threat.get("stage", "")).is_equal("critical")


func test_progress_ratio_scales_with_count() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm)
	var tech := _create_ai_tech(tm)
	var sing := _create_singularity(tm, mil, tech)
	_give_enemy_singularity_techs(tm, 0, 5)
	var threat: Dictionary = sing.assess_enemy_threat(0)
	# 5 out of 10 chain techs = 0.5
	assert_float(float(threat.get("progress_ratio", 0.0))).is_equal_approx(0.5, 0.01)


# --- Aggression Response ---


func test_early_threat_does_not_change_threshold() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm)
	var tech := _create_ai_tech(tm)
	var sing := _create_singularity(tm, mil, tech)
	var base_threshold: int = int(mil._config.get("army_attack_threshold", 0))
	_give_enemy_singularity_techs(tm, 0, 1)
	var threat: Dictionary = sing.assess_enemy_threat(0)
	sing.apply_aggression_response(threat)
	# Early multiplier is 1.0 — no change
	var new_threshold: int = int(mil._config.get("army_attack_threshold", 0))
	assert_int(new_threshold).is_equal(base_threshold)


func test_mid_threat_lowers_threshold() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm)
	var tech := _create_ai_tech(tm)
	var sing := _create_singularity(tm, mil, tech)
	var base_threshold: int = int(mil._config.get("army_attack_threshold", 0))
	_give_enemy_singularity_techs(tm, 0, 3)
	var threat: Dictionary = sing.assess_enemy_threat(0)
	sing.apply_aggression_response(threat)
	var new_threshold: int = int(mil._config.get("army_attack_threshold", 0))
	# Mid multiplier = 1.3, threshold should be lower (base / 1.3)
	assert_int(new_threshold).is_less(base_threshold)


func test_critical_threat_greatly_lowers_threshold() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm)
	var tech := _create_ai_tech(tm)
	var sing := _create_singularity(tm, mil, tech)
	var base_threshold: int = int(mil._config.get("army_attack_threshold", 0))
	_give_enemy_singularity_techs(tm, 0, 7)
	var threat: Dictionary = sing.assess_enemy_threat(0)
	sing.apply_aggression_response(threat)
	var new_threshold: int = int(mil._config.get("army_attack_threshold", 0))
	# Critical multiplier = 2.0, threshold halved
	assert_int(new_threshold).is_equal(maxi(int(float(base_threshold) / 2.0), 1))


func test_cooldown_reduced_at_mid_stage() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm)
	var tech := _create_ai_tech(tm)
	var sing := _create_singularity(tm, mil, tech)
	var base_cooldown: float = float(mil._config.get("attack_cooldown", 0.0))
	_give_enemy_singularity_techs(tm, 0, 3)
	var threat: Dictionary = sing.assess_enemy_threat(0)
	sing.apply_aggression_response(threat)
	var new_cooldown: float = float(mil._config.get("attack_cooldown", 0.0))
	# Mid cooldown multiplier = 0.8
	assert_float(new_cooldown).is_equal_approx(base_cooldown * 0.8, 0.01)


func test_cooldown_reduced_at_critical_stage() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm)
	var tech := _create_ai_tech(tm)
	var sing := _create_singularity(tm, mil, tech)
	var base_cooldown: float = float(mil._config.get("attack_cooldown", 0.0))
	_give_enemy_singularity_techs(tm, 0, 7)
	var threat: Dictionary = sing.assess_enemy_threat(0)
	sing.apply_aggression_response(threat)
	var new_cooldown: float = float(mil._config.get("attack_cooldown", 0.0))
	# Critical cooldown multiplier = 0.4
	assert_float(new_cooldown).is_equal_approx(base_cooldown * 0.4, 0.01)


func test_clear_aggression_when_no_threat() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm)
	var tech := _create_ai_tech(tm)
	var sing := _create_singularity(tm, mil, tech)
	# First apply a threat
	_give_enemy_singularity_techs(tm, 0, 5)
	var threat: Dictionary = sing.assess_enemy_threat(0)
	sing.apply_aggression_response(threat)
	# Now clear it by applying empty threat
	var no_threat: Dictionary = {"stage": "", "count": 0, "progress_ratio": 0.0}
	sing.apply_aggression_response(no_threat)
	# Should restore base values
	var threshold: int = int(mil._config.get("army_attack_threshold", 0))
	assert_int(threshold).is_equal(mil._base_attack_threshold)


# --- Priority Building Targets ---


func test_priority_targets_populated_when_enemy_has_buildings() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm)
	var tech := _create_ai_tech(tm)
	var sing := _create_singularity(tm, mil, tech)
	# Give enemy 9 chain techs (includes gpu_foundry at index 7 and transformer_lab at index 8)
	_give_enemy_singularity_techs(tm, 0, 9)
	var threat: Dictionary = sing.assess_enemy_threat(0)
	sing.apply_aggression_response(threat)
	# Priority targets should include gpu_foundry and transformer_lab
	assert_bool("gpu_foundry" in mil.singularity_target_buildings).is_true()
	assert_bool("transformer_lab" in mil.singularity_target_buildings).is_true()


func test_priority_targets_empty_when_enemy_has_no_buildings() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm)
	var tech := _create_ai_tech(tm)
	var sing := _create_singularity(tm, mil, tech)
	_give_enemy_singularity_techs(tm, 0, 3)
	var threat: Dictionary = sing.assess_enemy_threat(0)
	sing.apply_aggression_response(threat)
	# None of the priority targets are researched
	assert_int(mil.singularity_target_buildings.size()).is_equal(0)


# --- Pursuit Mode ---


func test_pursuit_activates_on_hard_with_tech_lead() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm, "hard")
	var tech := _create_ai_tech(tm, "hard")
	var sing := _create_singularity(tm, mil, tech, "hard")
	GameManager.current_age = 5
	# Give AI player (1) many techs, enemy (0) few
	tm._researched_techs[1] = ["a", "b", "c", "d", "e", "f", "g", "h"]
	tm._researched_techs[0] = ["x", "y"]
	# Tech lead = 8 - 2 = 6 >= threshold (3)
	sing.evaluate_pursuit()
	assert_bool(sing._pursuit_active).is_true()
	assert_bool(tech.singularity_priority_techs.size() > 0).is_true()


func test_pursuit_does_not_activate_on_easy() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm, "easy")
	var tech := _create_ai_tech(tm, "easy")
	var sing := _create_singularity(tm, mil, tech, "easy")
	GameManager.current_age = 5
	tm._researched_techs[1] = ["a", "b", "c", "d", "e", "f", "g", "h"]
	tm._researched_techs[0] = ["x"]
	sing.evaluate_pursuit()
	assert_bool(sing._pursuit_active).is_false()


func test_pursuit_does_not_activate_on_normal() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm)
	var tech := _create_ai_tech(tm)
	var sing := _create_singularity(tm, mil, tech)
	GameManager.current_age = 5
	tm._researched_techs[1] = ["a", "b", "c", "d", "e", "f", "g", "h"]
	tm._researched_techs[0] = ["x"]
	sing.evaluate_pursuit()
	assert_bool(sing._pursuit_active).is_false()


func test_pursuit_blocked_below_min_age() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm, "hard")
	var tech := _create_ai_tech(tm, "hard")
	var sing := _create_singularity(tm, mil, tech, "hard")
	GameManager.current_age = 3  # Below min_age 5
	tm._researched_techs[1] = ["a", "b", "c", "d", "e", "f", "g", "h"]
	tm._researched_techs[0] = ["x"]
	sing.evaluate_pursuit()
	assert_bool(sing._pursuit_active).is_false()


func test_pursuit_blocked_without_tech_lead() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm, "hard")
	var tech := _create_ai_tech(tm, "hard")
	var sing := _create_singularity(tm, mil, tech, "hard")
	GameManager.current_age = 5
	# Equal tech counts — no lead
	tm._researched_techs[1] = ["a", "b", "c"]
	tm._researched_techs[0] = ["x", "y", "z"]
	sing.evaluate_pursuit()
	assert_bool(sing._pursuit_active).is_false()


func test_pursuit_injects_priority_techs_into_ai_tech() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm, "hard")
	var tech := _create_ai_tech(tm, "hard")
	var sing := _create_singularity(tm, mil, tech, "hard")
	GameManager.current_age = 5
	tm._researched_techs[1] = ["a", "b", "c", "d", "e", "f", "g", "h"]
	tm._researched_techs[0] = ["x"]
	sing.evaluate_pursuit()
	# Should inject pursuit techs
	assert_bool("computing_theory" in tech.singularity_priority_techs).is_true()
	assert_bool("neural_networks" in tech.singularity_priority_techs).is_true()


func test_pursuit_activates_on_expert() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm, "expert")
	var tech := _create_ai_tech(tm, "expert")
	var sing := _create_singularity(tm, mil, tech, "expert")
	GameManager.current_age = 5
	tm._researched_techs[1] = ["a", "b", "c", "d", "e", "f", "g", "h"]
	tm._researched_techs[0] = ["x"]
	sing.evaluate_pursuit()
	assert_bool(sing._pursuit_active).is_true()


# --- Personality Overrides ---


func test_rusher_has_higher_aggression_at_mid() -> void:
	var tm := _create_tech_manager()
	var mil_default := _create_ai_military(self, null, tm)
	var tech_default := _create_ai_tech(tm)
	var sing_default := _create_singularity(tm, mil_default, tech_default)
	var mil_rusher := _create_ai_military(self, null, tm)
	var tech_rusher := _create_ai_tech(tm)
	var rusher_pers := AIPersonality.get_personality("rusher")
	var sing_rusher := _create_singularity(tm, mil_rusher, tech_rusher, "normal", rusher_pers)
	_give_enemy_singularity_techs(tm, 0, 3)
	var threat: Dictionary = sing_default.assess_enemy_threat(0)
	sing_default.apply_aggression_response(threat)
	sing_rusher.apply_aggression_response(threat)
	# Rusher should have even lower threshold than default at mid
	var default_threshold: int = int(mil_default._config.get("army_attack_threshold", 0))
	var rusher_threshold: int = int(mil_rusher._config.get("army_attack_threshold", 0))
	assert_int(rusher_threshold).is_less_equal(default_threshold)


func test_builder_has_lower_pursuit_threshold() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm, "hard")
	var tech := _create_ai_tech(tm, "hard")
	var builder_pers := AIPersonality.get_personality("builder")
	var sing := _create_singularity(tm, mil, tech, "hard", builder_pers)
	# Builder overrides pursuit.tech_lead_threshold to 2
	var pursuit: Dictionary = sing._config.get("pursuit", {})
	assert_int(int(pursuit.get("tech_lead_threshold", 0))).is_equal(2)


# --- Signal-driven re-assessment ---


func test_enemy_singularity_tech_triggers_reassessment() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm)
	var tech := _create_ai_tech(tm)
	var sing := _create_singularity(tm, mil, tech)
	# Give enemy 5 techs (late stage)
	_give_enemy_singularity_techs(tm, 0, 5)
	# Simulate signal
	sing._on_enemy_singularity_tech(0, "deep_learning", "Deep Learning")
	assert_str(sing._current_threat_stage).is_equal("late")


func test_own_singularity_tech_does_not_trigger_enemy_response() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm)
	var tech := _create_ai_tech(tm)
	var sing := _create_singularity(tm, mil, tech)
	# AI's own singularity tech should not trigger threat assessment
	sing._on_enemy_singularity_tech(1, "computing_theory", "Computing Theory")
	assert_str(sing._current_threat_stage).is_equal("")


# --- Save / Load ---


func test_save_state_preserves_all_fields() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm)
	var tech := _create_ai_tech(tm)
	var sing := _create_singularity(tm, mil, tech)
	sing._current_threat_stage = "late"
	sing._pursuit_active = true
	sing._base_attack_threshold = 6
	sing._base_attack_cooldown = 60.0
	var state: Dictionary = sing.save_state()
	assert_str(state.get("current_threat_stage", "")).is_equal("late")
	assert_bool(bool(state.get("pursuit_active", false))).is_true()
	assert_int(int(state.get("base_attack_threshold", 0))).is_equal(6)
	assert_float(float(state.get("base_attack_cooldown", 0.0))).is_equal(60.0)


func test_load_state_restores_all_fields() -> void:
	var tm := _create_tech_manager()
	var mil := _create_ai_military(self, null, tm)
	var tech := _create_ai_tech(tm)
	var sing := _create_singularity(tm, mil, tech)
	var state: Dictionary = {
		"player_id": 2,
		"difficulty": "hard",
		"current_threat_stage": "critical",
		"pursuit_active": true,
		"base_attack_threshold": 4,
		"base_attack_cooldown": 45.0,
	}
	sing.load_state(state)
	assert_int(sing.player_id).is_equal(2)
	assert_str(sing.difficulty).is_equal("hard")
	assert_str(sing._current_threat_stage).is_equal("critical")
	assert_bool(sing._pursuit_active).is_true()
	assert_int(sing._base_attack_threshold).is_equal(4)
	assert_float(sing._base_attack_cooldown).is_equal(45.0)
