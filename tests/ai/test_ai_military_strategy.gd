extends GdUnitTestSuite
## Tests for scripts/ai/ai_military_strategy.gd — army composition and attack decisions.

const AIMilitaryStrategyScript := preload("res://scripts/ai/ai_military_strategy.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")
const PopManagerScript := preload("res://scripts/prototype/population_manager.gd")
const ProductionQueueScript := preload("res://scripts/prototype/production_queue.gd")

# --- Lifecycle ---


func before_test() -> void:
	GameManager.current_age = 1
	GameManager.game_speed = 1.0


# --- Helpers ---


func _create_strategy(
	pop_mgr: Node = null,
	tech_mgr: Node = null,
	config: Dictionary = {},
	tr_config: Dictionary = {},
) -> AIMilitaryStrategy:
	var strat := AIMilitaryStrategyScript.new()
	strat.player_id = 1
	if config.is_empty():
		config = {
			"army_attack_threshold": 8,
			"attack_cooldown": 90.0,
			"min_attack_game_time": 420.0,
			"max_military_pop_ratio": 0.50,
			"military_budget_ratio": 0.60,
			"scout_scan_radius": 35,
			"default_composition": {"infantry": 0.6, "archer": 0.3, "cavalry": 0.1},
			"counter_weights": {"infantry": "cavalry", "archer": "infantry"},
			"counter_bias": 0.5,
		}
	if pop_mgr == null:
		pop_mgr = _create_pop_manager()
	strat.setup(pop_mgr, tech_mgr, config, tr_config)
	return strat


func _create_pop_manager(starting_cap: int = 200, hard_cap: int = 200) -> Node:
	var mgr := Node.new()
	mgr.set_script(PopManagerScript)
	add_child(mgr)
	mgr._starting_cap = starting_cap
	mgr._hard_cap = hard_cap
	return auto_free(mgr)


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


func _create_town_center(
	owner_id: int = 1,
	grid_pos: Vector2i = Vector2i(50, 50),
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
	add_child(building)
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
	add_child(building)
	var pq := Node.new()
	pq.name = "ProductionQueue"
	pq.set_script(ProductionQueueScript)
	building.add_child(pq)
	pq.setup(building, owner_id, pop_mgr)
	return auto_free(building)


func _init_resources(
	food: int = 1000,
	wood: int = 1000,
	stone: int = 1000,
	gold: int = 1000,
) -> void:
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


# --- Enemy composition scanning ---


func test_scan_empty_when_no_enemies() -> void:
	var strat := _create_strategy()
	var tc := _create_town_center()
	var enemy_units: Array[Node2D] = []
	var comp: Dictionary = strat.scan_enemy_composition(enemy_units, tc)
	assert_dict(comp).is_empty()


func test_scan_returns_empty_when_no_town_center() -> void:
	var strat := _create_strategy()
	var enemy: Node2D = _create_military_unit(0, "infantry", Vector2.ZERO)
	var enemy_units: Array[Node2D] = [enemy]
	var comp: Dictionary = strat.scan_enemy_composition(enemy_units, null)
	assert_dict(comp).is_empty()


func test_scan_counts_nearby_enemies() -> void:
	var strat := _create_strategy()
	var tc := _create_town_center(1, Vector2i(50, 50))
	var tc_pos := tc.global_position
	# Place enemies close to TC (within 35-tile scan radius = 2240px)
	var e1 := _create_military_unit(0, "infantry", tc_pos + Vector2(50, 0))
	var e2 := _create_military_unit(0, "infantry", tc_pos + Vector2(100, 0))
	var e3 := _create_military_unit(0, "archer", tc_pos + Vector2(150, 0))
	var enemy_units: Array[Node2D] = [e1, e2, e3]
	var comp: Dictionary = strat.scan_enemy_composition(enemy_units, tc)
	assert_int(int(comp.get("infantry", 0))).is_equal(2)
	assert_int(int(comp.get("archer", 0))).is_equal(1)


func test_scan_excludes_distant_enemies() -> void:
	var strat := _create_strategy()
	var tc := _create_town_center(1, Vector2i(50, 50))
	var tc_pos := tc.global_position
	# Enemy far beyond scan radius (35 tiles * 64px = 2240px)
	var enemy := _create_military_unit(0, "infantry", tc_pos + Vector2(5000, 0))
	var enemy_units: Array[Node2D] = [enemy]
	var comp: Dictionary = strat.scan_enemy_composition(enemy_units, tc)
	assert_dict(comp).is_empty()


func test_scan_excludes_dead_enemies() -> void:
	var strat := _create_strategy()
	var tc := _create_town_center(1, Vector2i(50, 50))
	var tc_pos := tc.global_position
	var enemy := _create_military_unit(0, "infantry", tc_pos + Vector2(100, 0), 0)
	# hp = 0 means dead
	var enemy_units: Array[Node2D] = [enemy]
	var comp: Dictionary = strat.scan_enemy_composition(enemy_units, tc)
	assert_dict(comp).is_empty()


# --- Desired composition ---


func test_default_composition_when_no_enemies() -> void:
	var strat := _create_strategy()
	var enemy_comp: Dictionary = {}
	var desired: Dictionary = strat.compute_desired_composition(enemy_comp)
	# Should match default_composition from config
	assert_float(float(desired.get("infantry", 0.0))).is_equal_approx(0.6, 0.01)
	assert_float(float(desired.get("archer", 0.0))).is_equal_approx(0.3, 0.01)
	assert_float(float(desired.get("cavalry", 0.0))).is_equal_approx(0.1, 0.01)


func test_counter_boosts_cavalry_vs_infantry() -> void:
	var strat := _create_strategy()
	# All enemies are infantry — cavalry counter should be boosted
	var enemy_comp: Dictionary = {"infantry": 5}
	var desired: Dictionary = strat.compute_desired_composition(enemy_comp)
	var default_cavalry: float = 0.1
	assert_float(float(desired.get("cavalry", 0.0))).is_greater(default_cavalry)


func test_composition_ratios_sum_to_one() -> void:
	var strat := _create_strategy()
	var enemy_comp: Dictionary = {"infantry": 3, "archer": 2}
	var desired: Dictionary = strat.compute_desired_composition(enemy_comp)
	var total: float = 0.0
	for val: float in desired.values():
		total += val
	assert_float(total).is_equal_approx(1.0, 0.01)


func test_composition_ratios_sum_to_one_with_no_enemies() -> void:
	var strat := _create_strategy()
	var desired: Dictionary = strat.compute_desired_composition({})
	var total: float = 0.0
	for val: float in desired.values():
		total += val
	assert_float(total).is_equal_approx(1.0, 0.01)


# --- Training deficit ---


func test_deficit_returns_most_underrepresented_type() -> void:
	var strat := _create_strategy()
	# 5 infantry, no archers or cavalry — should want archer or cavalry
	var own_military: Array[Node2D] = []
	for i in 5:
		own_military.append(_create_military_unit(1, "infantry", Vector2(i * 10, 0)))
	var deficit: String = strat.get_training_deficit(own_military, {})
	assert_str(deficit).is_not_equal("infantry")


func test_deficit_returns_infantry_when_desired_empty() -> void:
	# Config with no default_composition — should fallback to infantry
	var strat := _create_strategy(
		null,
		null,
		{
			"army_attack_threshold": 8,
			"attack_cooldown": 90.0,
			"min_attack_game_time": 420.0,
			"max_military_pop_ratio": 0.50,
			"military_budget_ratio": 0.60,
			"scout_scan_radius": 35,
		},
	)
	var own_military: Array[Node2D] = []
	var deficit: String = strat.get_training_deficit(own_military, {})
	assert_str(deficit).is_equal("infantry")


func test_deficit_with_balanced_army_returns_consistent_type() -> void:
	var strat := _create_strategy()
	# Exactly balanced: 6 infantry, 3 archer, 1 cavalry (= 60/30/10 of 10)
	var own_military: Array[Node2D] = []
	for i in 6:
		own_military.append(_create_military_unit(1, "infantry", Vector2(i * 10, 0)))
	for i in 3:
		own_military.append(_create_military_unit(1, "archer", Vector2(i * 10, 50)))
	own_military.append(_create_military_unit(1, "cavalry", Vector2.ZERO))
	var deficit: String = strat.get_training_deficit(own_military, {})
	# Should be a string — either any type that's at or below target
	assert_bool(deficit is String).is_true()
	assert_bool(deficit != "").is_true()


# --- Can train military ---


func test_can_train_blocked_with_no_barracks() -> void:
	_init_resources()
	var pop_mgr := _create_pop_manager()
	var strat := _create_strategy(pop_mgr)
	var own_barracks: Array[Node2D] = []
	var own_factories: Array[Node2D] = []
	var own_military: Array[Node2D] = []
	assert_bool(strat.can_train_military(own_barracks, own_factories, own_military)).is_false()


func test_can_train_blocked_by_pop_cap() -> void:
	_init_resources()
	# Pop cap = 0 (starting=0) + 5 (TC bonus) = 5
	var pop_mgr := _create_pop_manager(0)
	var tc := _create_town_center(1, Vector2i(50, 50))
	pop_mgr.register_building(tc, 1)
	var strat := _create_strategy(pop_mgr)
	var barracks := _create_barracks(1, Vector2i(45, 50), pop_mgr)
	var own_barracks: Array[Node2D] = [barracks]
	var own_factories: Array[Node2D] = []
	# 3 military units / 5 cap = 60% >= 50% threshold
	var own_military: Array[Node2D] = []
	for i in 3:
		var unit := _create_military_unit(1, "infantry", Vector2(i * 10, 0))
		pop_mgr.register_unit(unit, 1)
		own_military.append(unit)
	assert_bool(strat.can_train_military(own_barracks, own_factories, own_military)).is_false()


func test_can_train_allowed_when_below_ratio() -> void:
	_init_resources()
	var pop_mgr := _create_pop_manager(200)
	var strat := _create_strategy(pop_mgr)
	var barracks := _create_barracks(1, Vector2i(45, 50), pop_mgr)
	var own_barracks: Array[Node2D] = [barracks]
	var own_factories: Array[Node2D] = []
	# 1 military / 200 cap = 0.5% — well below 50%
	var unit := _create_military_unit(1, "infantry", Vector2.ZERO)
	var own_military: Array[Node2D] = [unit]
	assert_bool(strat.can_train_military(own_barracks, own_factories, own_military)).is_true()


func test_can_train_blocked_by_zero_resources() -> void:
	_init_resources(0, 0, 0, 0)
	var pop_mgr := _create_pop_manager(200)
	var strat := _create_strategy(pop_mgr)
	var barracks := _create_barracks(1, Vector2i(45, 50), pop_mgr)
	var own_barracks: Array[Node2D] = [barracks]
	var own_factories: Array[Node2D] = []
	var own_military: Array[Node2D] = []
	assert_bool(strat.can_train_military(own_barracks, own_factories, own_military)).is_false()


# --- Military budget ---


func test_budget_check_passes_with_resources() -> void:
	_init_resources(500, 0, 0, 0)
	var strat := _create_strategy()
	assert_bool(strat.check_military_budget()).is_true()


func test_budget_check_fails_with_no_resources() -> void:
	_init_resources(0, 0, 0, 0)
	var strat := _create_strategy()
	assert_bool(strat.check_military_budget()).is_false()


# --- Should attack ---


func test_should_attack_returns_idle_units_when_threshold_met() -> void:
	GameManager.current_age = 1
	var strat := _create_strategy()
	var own_military: Array[Node2D] = []
	# Create 10 idle military units (threshold = 8)
	for i in 10:
		own_military.append(_create_military_unit(1, "infantry", Vector2(i * 10, 0)))
	var result: Array[Node2D] = strat.should_attack(500.0, 0.0, own_military)
	assert_int(result.size()).is_greater_equal(8)


func test_should_attack_blocked_when_age_zero() -> void:
	GameManager.current_age = 0
	var strat := _create_strategy()
	var own_military: Array[Node2D] = []
	for i in 10:
		own_military.append(_create_military_unit(1, "infantry", Vector2(i * 10, 0)))
	var result: Array[Node2D] = strat.should_attack(500.0, 0.0, own_military)
	assert_int(result.size()).is_equal(0)


func test_should_attack_blocked_before_min_game_time() -> void:
	GameManager.current_age = 1
	var strat := _create_strategy()
	var own_military: Array[Node2D] = []
	for i in 10:
		own_military.append(_create_military_unit(1, "infantry", Vector2(i * 10, 0)))
	# game_time = 100 < min_attack_game_time = 420
	var result: Array[Node2D] = strat.should_attack(100.0, 0.0, own_military)
	assert_int(result.size()).is_equal(0)


func test_should_attack_blocked_during_cooldown() -> void:
	GameManager.current_age = 1
	var strat := _create_strategy()
	var own_military: Array[Node2D] = []
	for i in 10:
		own_military.append(_create_military_unit(1, "infantry", Vector2(i * 10, 0)))
	# game_time=500, last_attack=450: gap=50 < cooldown=90
	var result: Array[Node2D] = strat.should_attack(500.0, 450.0, own_military)
	assert_int(result.size()).is_equal(0)


func test_should_attack_blocked_below_threshold() -> void:
	GameManager.current_age = 1
	var strat := _create_strategy()
	var own_military: Array[Node2D] = []
	# Only 3 units — below threshold of 8
	for i in 3:
		own_military.append(_create_military_unit(1, "infantry", Vector2(i * 10, 0)))
	var result: Array[Node2D] = strat.should_attack(500.0, 0.0, own_military)
	assert_int(result.size()).is_equal(0)


func test_should_attack_excludes_dead_units() -> void:
	GameManager.current_age = 1
	var strat := _create_strategy()
	var own_military: Array[Node2D] = []
	# 8 alive + 5 dead: only alive count toward threshold
	for i in 8:
		own_military.append(_create_military_unit(1, "infantry", Vector2(i * 10, 0)))
	for i in 5:
		own_military.append(_create_military_unit(1, "infantry", Vector2((i + 8) * 10, 0), 0))
	var result: Array[Node2D] = strat.should_attack(500.0, 0.0, own_military)
	# Should still meet threshold with the 8 alive units
	assert_int(result.size()).is_equal(8)


# --- Aggression override ---


func test_set_aggression_override_lowers_threshold() -> void:
	var strat := _create_strategy()
	var base_threshold: int = strat.base_attack_threshold
	var base_cooldown: float = strat.base_attack_cooldown
	strat.set_aggression_override(2.0, 0.5)
	var new_threshold: int = int(strat.config.get("army_attack_threshold", 0))
	var new_cooldown: float = float(strat.config.get("attack_cooldown", 0.0))
	assert_int(new_threshold).is_equal(maxi(int(float(base_threshold) / 2.0), 1))
	assert_float(new_cooldown).is_equal_approx(base_cooldown * 0.5, 0.01)


func test_clear_aggression_override_restores_base_values() -> void:
	var strat := _create_strategy()
	var base_threshold: int = strat.base_attack_threshold
	var base_cooldown: float = strat.base_attack_cooldown
	strat.set_aggression_override(2.0, 0.5)
	strat.clear_aggression_override()
	var threshold: int = int(strat.config.get("army_attack_threshold", 0))
	var cooldown: float = float(strat.config.get("attack_cooldown", 0.0))
	assert_int(threshold).is_equal(base_threshold)
	assert_float(cooldown).is_equal_approx(base_cooldown, 0.01)


func test_aggression_override_multiplier_of_one_preserves_threshold() -> void:
	var strat := _create_strategy()
	var base_threshold: int = strat.base_attack_threshold
	strat.set_aggression_override(1.0, 1.0)
	var new_threshold: int = int(strat.config.get("army_attack_threshold", 0))
	assert_int(new_threshold).is_equal(base_threshold)


# --- Tech regression response ---


func test_tech_loss_boost_timer_set_on_regression() -> void:
	var strat := _create_strategy(
		null,
		null,
		{
			"army_attack_threshold": 8,
			"attack_cooldown": 90.0,
			"min_attack_game_time": 420.0,
			"max_military_pop_ratio": 0.50,
			"military_budget_ratio": 0.60,
			"scout_scan_radius": 35,
			"default_composition": {"infantry": 0.6, "archer": 0.3, "cavalry": 0.1},
			"counter_weights": {"infantry": "cavalry"},
			"counter_bias": 0.5,
		},
		{"tech_loss_response": {"military_boost_duration": 120.0, "military_pop_ratio_boost": 0.15}},
	)
	strat.player_id = 1
	assert_float(strat.tech_loss_boost_timer).is_equal(0.0)
	strat.on_tech_regressed(1, "ballistics", {})
	assert_float(strat.tech_loss_boost_timer).is_equal(120.0)


func test_tech_loss_boost_ignores_other_players() -> void:
	var strat := _create_strategy(
		null,
		null,
		{
			"army_attack_threshold": 8,
			"attack_cooldown": 90.0,
			"min_attack_game_time": 420.0,
			"max_military_pop_ratio": 0.50,
			"military_budget_ratio": 0.60,
			"scout_scan_radius": 35,
			"default_composition": {},
			"counter_weights": {},
			"counter_bias": 0.5,
		},
		{"tech_loss_response": {"military_boost_duration": 120.0}},
	)
	strat.player_id = 1
	# Regression for player 0 — strat is player 1, should be ignored
	strat.on_tech_regressed(0, "ballistics", {})
	assert_float(strat.tech_loss_boost_timer).is_equal(0.0)


func test_tech_loss_boosts_military_pop_ratio() -> void:
	_init_resources()
	var tr_config := {"tech_loss_response": {"military_boost_duration": 120.0, "military_pop_ratio_boost": 0.15}}
	var pop_mgr := _create_pop_manager(200)
	var strat := _create_strategy(
		pop_mgr,
		null,
		{
			"army_attack_threshold": 8,
			"attack_cooldown": 90.0,
			"min_attack_game_time": 420.0,
			"max_military_pop_ratio": 0.50,
			"military_budget_ratio": 0.60,
			"scout_scan_radius": 35,
			"default_composition": {"infantry": 0.6, "archer": 0.3, "cavalry": 0.1},
			"counter_weights": {},
			"counter_bias": 0.5,
		},
		tr_config,
	)
	# Trigger tech regression
	strat.on_tech_regressed(1, "ballistics", {})
	# With boost active, effective ratio = 0.50 + 0.15 = 0.65
	# 100 military / 200 cap = 50% which would normally be blocked, but 50% < 65% now allows it
	var barracks := _create_barracks(1, Vector2i(45, 50), pop_mgr)
	var own_barracks: Array[Node2D] = [barracks]
	# Create units that fill exactly 50% normally — with boost, training should be allowed
	var own_military: Array[Node2D] = []
	for i in 100:
		own_military.append(_create_military_unit(1, "infantry", Vector2(i * 10, 0)))
	# With boost timer active (120s) and ratio boosted to 0.65, 100/200=0.50 < 0.65 → allowed
	assert_bool(strat.can_train_military(own_barracks, [], own_military)).is_true()


# --- Best production building ---


func test_find_best_production_building_prefers_shorter_queue() -> void:
	var pop_mgr := _create_pop_manager()
	var strat := _create_strategy(pop_mgr)
	var barracks1 := _create_barracks(1, Vector2i(40, 50), pop_mgr)
	var barracks2 := _create_barracks(1, Vector2i(45, 50), pop_mgr)
	# Add a unit to barracks1's queue to make it longer
	var pq1: Node = barracks1.get_node_or_null("ProductionQueue")
	_init_resources()
	pq1.add_to_queue("infantry")
	var own_barracks: Array[Node2D] = [barracks1, barracks2]
	var best: Node2D = strat.find_best_production_building("infantry", own_barracks, [])
	# barracks2 has an empty queue — should be preferred
	assert_object(best).is_equal(barracks2)


func test_find_best_production_building_returns_null_with_no_buildings() -> void:
	var strat := _create_strategy()
	var best: Node2D = strat.find_best_production_building("infantry", [], [])
	assert_object(best).is_null()
