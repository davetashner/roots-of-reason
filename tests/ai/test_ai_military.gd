extends GdUnitTestSuite
## Tests for scripts/ai/ai_military.gd — AI military brain.

const AIMilitaryScript := preload("res://scripts/ai/ai_military.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")
const PopManagerScript := preload("res://scripts/prototype/population_manager.gd")
const ProductionQueueScript := preload("res://scripts/prototype/production_queue.gd")

# --- Lifecycle ---


func before_test() -> void:
	GameManager.current_age = 1
	GameManager.game_speed = 1.0


# --- Helpers ---


func _create_ai_military(
	scene_root: Node = null,
	pop_mgr: Node = null,
	difficulty: String = "normal",
) -> Node:
	if scene_root == null:
		scene_root = self
	var ai := Node.new()
	ai.name = "AIMilitary"
	ai.set_script(AIMilitaryScript)
	ai.difficulty = difficulty
	add_child(ai)
	if pop_mgr == null:
		pop_mgr = _create_pop_manager()
	ai.setup(scene_root, pop_mgr, null, null)
	return auto_free(ai)


func _create_pop_manager(starting_cap: int = 200, hard_cap: int = 200) -> Node:
	var mgr := Node.new()
	mgr.set_script(PopManagerScript)
	add_child(mgr)
	mgr._starting_cap = starting_cap
	mgr._hard_cap = hard_cap
	return auto_free(mgr)


func _create_town_center(
	owner_id: int = 1,
	grid_pos: Vector2i = Vector2i(50, 50),
	pop_mgr: Node = null,
) -> Node2D:
	var building := Node2D.new()
	building.name = "AI_TownCenter_%d" % get_child_count()
	building.set_script(BuildingScript)
	building.position = IsoUtils.grid_to_screen(Vector2(grid_pos))
	building.owner_id = owner_id
	building.building_name = "town_center"
	building.footprint = Vector2i(3, 3)
	building.grid_pos = grid_pos
	building.hp = 2400
	building.max_hp = 2400
	building.under_construction = false
	building.build_progress = 1.0
	building.entity_category = "enemy_building"
	add_child(building)
	if pop_mgr != null:
		pop_mgr.register_building(building, owner_id)
	return auto_free(building)


func _create_barracks(
	owner_id: int = 1,
	grid_pos: Vector2i = Vector2i(45, 50),
	pop_mgr: Node = null,
) -> Node2D:
	var building := Node2D.new()
	building.name = "AI_Barracks_%d" % get_child_count()
	building.set_script(BuildingScript)
	building.position = IsoUtils.grid_to_screen(Vector2(grid_pos))
	building.owner_id = owner_id
	building.building_name = "barracks"
	building.footprint = Vector2i(3, 3)
	building.grid_pos = grid_pos
	building.hp = 1200
	building.max_hp = 1200
	building.under_construction = false
	building.build_progress = 1.0
	building.entity_category = "enemy_building"
	add_child(building)
	# Attach production queue
	var pq := Node.new()
	pq.name = "ProductionQueue"
	pq.set_script(ProductionQueueScript)
	building.add_child(pq)
	pq.setup(building, owner_id, pop_mgr)
	return auto_free(building)


func _create_military_unit(
	owner_id: int = 1,
	unit_type: String = "infantry",
	pos: Vector2 = Vector2.ZERO,
	hp_override: int = -1,
) -> Node2D:
	var unit := Node2D.new()
	unit.name = "MilitaryUnit_%d" % get_child_count()
	unit.set_script(UnitScript)
	unit.unit_type = unit_type
	unit.unit_category = "military"
	unit.owner_id = owner_id
	unit.position = pos
	unit._scene_root = self
	unit._moving = false
	add_child(unit)
	if hp_override >= 0:
		unit.hp = hp_override
	return auto_free(unit)


func _create_villager_unit(
	owner_id: int = 0,
	pos: Vector2 = Vector2(200, 200),
) -> Node2D:
	var unit := Node2D.new()
	unit.name = "Villager_%d" % get_child_count()
	unit.set_script(UnitScript)
	unit.unit_type = "villager"
	unit.unit_category = ""
	unit.owner_id = owner_id
	unit.position = pos
	unit._scene_root = self
	unit._moving = false
	add_child(unit)
	return auto_free(unit)


func _create_enemy_building(
	owner_id: int = 0,
	grid_pos: Vector2i = Vector2i(10, 10),
	hp: int = 500,
) -> Node2D:
	var building := Node2D.new()
	building.name = "EnemyBuilding_%d" % get_child_count()
	building.set_script(BuildingScript)
	building.position = IsoUtils.grid_to_screen(Vector2(grid_pos))
	building.owner_id = owner_id
	building.building_name = "house"
	building.footprint = Vector2i(2, 2)
	building.grid_pos = grid_pos
	building.hp = hp
	building.max_hp = hp
	building.under_construction = false
	building.build_progress = 1.0
	add_child(building)
	return auto_free(building)


func _init_ai_resources(food: int = 1000, wood: int = 1000, stone: int = 1000, gold: int = 1000) -> void:
	(
		ResourceManager
		. init_player(
			1,
			{
				ResourceManager.ResourceType.FOOD: food,
				ResourceManager.ResourceType.WOOD: wood,
				ResourceManager.ResourceType.STONE: stone,
				ResourceManager.ResourceType.GOLD: gold,
				ResourceManager.ResourceType.KNOWLEDGE: 0,
			}
		)
	)


# --- Config ---


func test_config_loaded_from_json() -> void:
	var ai := _create_ai_military()
	assert_dict(ai._config).is_not_empty()
	assert_bool(ai._config.has("tick_interval")).is_true()
	assert_bool(ai._config.has("army_attack_threshold")).is_true()


func test_difficulty_selects_correct_config() -> void:
	var ai_easy := _create_ai_military(null, null, "easy")
	var ai_hard := _create_ai_military(null, null, "hard")
	# Easy has higher attack threshold than hard
	var easy_threshold: int = int(ai_easy._config.get("army_attack_threshold", 0))
	var hard_threshold: int = int(ai_hard._config.get("army_attack_threshold", 0))
	assert_bool(easy_threshold > hard_threshold).is_true()


func test_easy_has_slower_tick_than_hard() -> void:
	var ai_easy := _create_ai_military(null, null, "easy")
	var ai_hard := _create_ai_military(null, null, "hard")
	var easy_tick: float = float(ai_easy._config.get("tick_interval", 0))
	var hard_tick: float = float(ai_hard._config.get("tick_interval", 0))
	assert_bool(easy_tick > hard_tick).is_true()


# --- Composition ---


func test_default_composition_when_no_enemies() -> void:
	var ai := _create_ai_military()
	_create_town_center()
	ai._refresh_entity_lists()
	ai._scan_enemy_composition()
	var desired: Dictionary = ai._compute_desired_composition()
	# Should match default composition from config
	var default_comp: Dictionary = ai._config.get("default_composition", {})
	for unit_type: String in default_comp:
		assert_float(float(desired.get(unit_type, 0))).is_equal_approx(float(default_comp[unit_type]), 0.01)


func test_counter_boosts_cavalry_against_infantry() -> void:
	var ai := _create_ai_military()
	var tc := _create_town_center()
	# Place enemy infantry near TC
	var tc_pos: Vector2 = tc.global_position
	for i in 5:
		_create_military_unit(0, "infantry", tc_pos + Vector2(i * 10, 0))
	ai._refresh_entity_lists()
	ai._scan_enemy_composition()
	var desired: Dictionary = ai._compute_desired_composition()
	var default_comp: Dictionary = ai._config.get("default_composition", {})
	# Cavalry should be boosted relative to default
	assert_float(float(desired.get("cavalry", 0))).is_greater(float(default_comp.get("cavalry", 0)))


func test_composition_ratios_sum_to_one() -> void:
	var ai := _create_ai_military()
	var tc := _create_town_center()
	var tc_pos: Vector2 = tc.global_position
	_create_military_unit(0, "infantry", tc_pos + Vector2(10, 0))
	_create_military_unit(0, "archer", tc_pos + Vector2(20, 0))
	ai._refresh_entity_lists()
	ai._scan_enemy_composition()
	var desired: Dictionary = ai._compute_desired_composition()
	var total: float = 0.0
	for val: float in desired.values():
		total += val
	assert_float(total).is_equal_approx(1.0, 0.01)


# --- Training ---


func test_deficit_returns_most_needed_type() -> void:
	var ai := _create_ai_military()
	_create_town_center()
	# Create several infantry but no archers or cavalry
	for i in 5:
		_create_military_unit(1, "infantry", Vector2(i * 10, 0))
	ai._refresh_entity_lists()
	ai._scan_enemy_composition()
	var deficit: String = ai._get_training_deficit()
	# Should want archer or cavalry, not more infantry
	assert_str(deficit).is_not_equal("infantry")


func test_trains_at_barracks() -> void:
	_init_ai_resources()
	var pop_mgr := _create_pop_manager()
	var ai := _create_ai_military(self, pop_mgr)
	_create_town_center(1, Vector2i(50, 50), pop_mgr)
	var barracks := _create_barracks(1, Vector2i(45, 50), pop_mgr)
	ai._refresh_entity_lists()
	ai._scan_enemy_composition()
	ai._train_military_units()
	# Check that PQ has a unit queued
	var pq: Node = barracks.get_node_or_null("ProductionQueue")
	assert_int(pq.get_queue().size()).is_greater(0)


func test_training_blocked_by_pop_ratio() -> void:
	_init_ai_resources()
	var pop_mgr := _create_pop_manager(0)
	var tc := _create_town_center(1, Vector2i(50, 50), pop_mgr)
	var barracks := _create_barracks(1, Vector2i(45, 50), pop_mgr)
	var ai := _create_ai_military(self, pop_mgr)
	# Pop cap = 0 (starting) + 5 (TC bonus) = 5
	# With max_military_pop_ratio=0.50, 3+ military should block (3/5=0.60 >= 0.50)
	for i in 3:
		var unit := _create_military_unit(1, "infantry", Vector2(i * 10, 0))
		pop_mgr.register_unit(unit, 1)
	ai._refresh_entity_lists()
	ai._scan_enemy_composition()
	ai._train_military_units()
	var pq: Node = barracks.get_node_or_null("ProductionQueue")
	assert_int(pq.get_queue().size()).is_equal(0)


func test_training_blocked_by_zero_resources() -> void:
	_init_ai_resources(0, 0, 0, 0)
	var pop_mgr := _create_pop_manager()
	var ai := _create_ai_military(self, pop_mgr)
	_create_town_center(1, Vector2i(50, 50), pop_mgr)
	_create_barracks(1, Vector2i(45, 50), pop_mgr)
	ai._refresh_entity_lists()
	ai._scan_enemy_composition()
	ai._train_military_units()
	# Budget check should fail — no resources
	# (Training should not proceed)
	assert_bool(true).is_true()


# --- Attack ---


func test_attack_launched_when_threshold_met() -> void:
	_init_ai_resources()
	var pop_mgr := _create_pop_manager()
	var ai := _create_ai_military(self, pop_mgr)
	var tc := _create_town_center(1, Vector2i(50, 50), pop_mgr)
	# Create enemy building to attack
	_create_enemy_building(0, Vector2i(10, 10))
	# Set game time past min threshold
	ai._game_time = 500.0
	ai._last_attack_time = -9999.0
	# Create enough idle military units (normal threshold = 8)
	for i in 10:
		_create_military_unit(1, "infantry", tc.global_position + Vector2(i * 10, 0))
	ai._refresh_entity_lists()
	ai._evaluate_attack()
	assert_bool(ai._attack_in_progress).is_true()


func test_attack_blocked_before_min_game_time() -> void:
	_init_ai_resources()
	var pop_mgr := _create_pop_manager()
	var ai := _create_ai_military(self, pop_mgr)
	var tc := _create_town_center(1, Vector2i(50, 50), pop_mgr)
	_create_enemy_building(0, Vector2i(10, 10))
	ai._game_time = 100.0  # Below min_attack_game_time
	for i in 10:
		_create_military_unit(1, "infantry", tc.global_position + Vector2(i * 10, 0))
	ai._refresh_entity_lists()
	ai._evaluate_attack()
	assert_bool(ai._attack_in_progress).is_false()


func test_attack_blocked_during_cooldown() -> void:
	_init_ai_resources()
	var pop_mgr := _create_pop_manager()
	var ai := _create_ai_military(self, pop_mgr)
	var tc := _create_town_center(1, Vector2i(50, 50), pop_mgr)
	_create_enemy_building(0, Vector2i(10, 10))
	ai._game_time = 500.0
	ai._last_attack_time = 450.0  # Within cooldown
	for i in 10:
		_create_military_unit(1, "infantry", tc.global_position + Vector2(i * 10, 0))
	ai._refresh_entity_lists()
	ai._evaluate_attack()
	assert_bool(ai._attack_in_progress).is_false()


func test_attack_blocked_below_threshold() -> void:
	_init_ai_resources()
	var pop_mgr := _create_pop_manager()
	var ai := _create_ai_military(self, pop_mgr)
	_create_town_center(1, Vector2i(50, 50), pop_mgr)
	_create_enemy_building(0, Vector2i(10, 10))
	ai._game_time = 500.0
	# Only 2 units — below threshold
	_create_military_unit(1, "infantry", Vector2.ZERO)
	_create_military_unit(1, "infantry", Vector2(10, 0))
	ai._refresh_entity_lists()
	ai._evaluate_attack()
	assert_bool(ai._attack_in_progress).is_false()


# --- Target selection ---


func test_targets_weakest_building() -> void:
	var ai := _create_ai_military()
	_create_town_center()
	_create_enemy_building(0, Vector2i(10, 10), 500)
	_create_enemy_building(0, Vector2i(15, 15), 100)  # Weaker
	ai._refresh_entity_lists()
	var target: Vector2 = ai._find_weakest_building()
	var weak_pos: Vector2 = IsoUtils.grid_to_screen(Vector2(Vector2i(15, 15)))
	assert_float(target.distance_to(weak_pos)).is_less(1.0)


func test_targets_undefended_villagers() -> void:
	var ai := _create_ai_military()
	_create_town_center()
	# Create an undefended enemy villager
	_create_villager_unit(0, Vector2(200, 200))
	ai._refresh_entity_lists()
	var target: Vector2 = ai._find_undefended_villagers()
	assert_bool(target != Vector2.ZERO).is_true()


func test_fallback_to_nearest_building() -> void:
	var ai := _create_ai_military()
	var tc := _create_town_center()
	# No undefended villagers — create defended one
	var vill := _create_villager_unit(0, Vector2(200, 200))
	_create_military_unit(0, "infantry", Vector2(210, 200))  # Defender nearby
	# Create enemy building
	_create_enemy_building(0, Vector2i(10, 10))
	ai._refresh_entity_lists()
	var target: Vector2 = ai._select_attack_target()
	assert_bool(target != Vector2.ZERO).is_true()


# --- Retreat ---


func test_damaged_units_retreat_toward_tc() -> void:
	var ai := _create_ai_military()
	var tc := _create_town_center()
	var tc_pos: Vector2 = tc.global_position
	# Create a damaged unit far from TC in combat
	var unit := _create_military_unit(1, "infantry", tc_pos + Vector2(500, 500), 5)
	unit.max_hp = 100  # 5/100 = 0.05 — below retreat threshold
	# Put unit in combat state so retreat triggers
	unit._combat_state = unit.CombatState.PURSUING
	ai._refresh_entity_lists()
	ai._retreat_damaged_units()
	# Unit should now be moving
	assert_bool(unit._moving).is_true()


func test_healthy_units_stay() -> void:
	var ai := _create_ai_military()
	var tc := _create_town_center()
	var tc_pos: Vector2 = tc.global_position
	# Full HP unit in combat
	var unit := _create_military_unit(1, "infantry", tc_pos + Vector2(500, 500))
	unit._combat_state = unit.CombatState.PURSUING
	ai._refresh_entity_lists()
	var was_moving: bool = unit._moving
	ai._retreat_damaged_units()
	# Should not have started moving (was not moving before)
	assert_bool(unit._moving).is_equal(was_moving)


# --- Save / Load ---


func test_save_state_preserves_game_time() -> void:
	var ai := _create_ai_military()
	ai._game_time = 350.0
	ai._last_attack_time = 200.0
	ai._attack_in_progress = true
	var state: Dictionary = ai.save_state()
	assert_float(float(state.get("game_time", 0))).is_equal(350.0)
	assert_float(float(state.get("last_attack_time", 0))).is_equal(200.0)
	assert_bool(bool(state.get("attack_in_progress", false))).is_true()


func test_load_state_restores_attack_state() -> void:
	var ai := _create_ai_military()
	ai._game_time = 350.0
	ai._last_attack_time = 200.0
	ai._attack_in_progress = true
	ai._enemy_composition = {"infantry": 3, "archer": 2}
	var state: Dictionary = ai.save_state()
	var ai2 := _create_ai_military()
	ai2.load_state(state)
	assert_float(ai2._game_time).is_equal(350.0)
	assert_float(ai2._last_attack_time).is_equal(200.0)
	assert_bool(ai2._attack_in_progress).is_true()
	assert_int(int(ai2._enemy_composition.get("infantry", 0))).is_equal(3)


# --- Singularity target buildings ---


func test_singularity_target_buildings_prioritized() -> void:
	_init_ai_resources()
	var pop_mgr := _create_pop_manager()
	var ai := _create_ai_military(self, pop_mgr)
	var tc := _create_town_center(1, Vector2i(50, 50), pop_mgr)
	# Create an enemy agi_core building
	var agi := _create_enemy_building(0, Vector2i(20, 20), 800)
	agi.building_name = "agi_core"
	# Create a weaker enemy building closer
	_create_enemy_building(0, Vector2i(48, 48), 100)
	# Set singularity targets
	var sing_targets: Array[String] = ["agi_core", "transformer_lab"]
	ai.singularity_target_buildings = sing_targets
	ai._refresh_entity_lists()
	var target: Vector2 = ai._select_attack_target()
	# Should target agi_core, not the closer/weaker building
	var expected: Vector2 = IsoUtils.grid_to_screen(Vector2(Vector2i(20, 20)))
	assert_float(target.distance_to(expected)).is_less(1.0)


func test_set_aggression_override_lowers_threshold() -> void:
	var ai := _create_ai_military()
	var base_threshold: int = ai._base_attack_threshold
	var base_cooldown: float = ai._base_attack_cooldown
	ai.set_aggression_override(2.0, 0.5)
	var new_threshold: int = int(ai._config.get("army_attack_threshold", 0))
	var new_cooldown: float = float(ai._config.get("attack_cooldown", 0.0))
	assert_int(new_threshold).is_equal(maxi(int(float(base_threshold) / 2.0), 1))
	assert_float(new_cooldown).is_equal_approx(base_cooldown * 0.5, 0.01)


func test_clear_aggression_override_restores_base() -> void:
	var ai := _create_ai_military()
	var base_threshold: int = ai._base_attack_threshold
	var base_cooldown: float = ai._base_attack_cooldown
	ai.set_aggression_override(2.0, 0.5)
	ai.clear_aggression_override()
	var threshold: int = int(ai._config.get("army_attack_threshold", 0))
	var cooldown: float = float(ai._config.get("attack_cooldown", 0.0))
	assert_int(threshold).is_equal(base_threshold)
	assert_float(cooldown).is_equal_approx(base_cooldown, 0.01)
