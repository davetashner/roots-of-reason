extends GdUnitTestSuite
## Tests for AI tech regression awareness — defense, offense, forward TC,
## tech loss response, and save/load across ai_military, ai_tech, ai_economy.

const AIMilitaryScript := preload("res://scripts/ai/ai_military.gd")
const AITechScript := preload("res://scripts/ai/ai_tech.gd")
const AIEconomyScript := preload("res://scripts/ai/ai_economy.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")
const PopManagerScript := preload("res://scripts/prototype/population_manager.gd")
const TechManagerScript := preload("res://scripts/prototype/tech_manager.gd")
const ProductionQueueScript := preload("res://scripts/prototype/production_queue.gd")

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


func _create_pop_manager(starting_cap: int = 200) -> Node:
	var mgr := Node.new()
	mgr.set_script(PopManagerScript)
	add_child(mgr)
	mgr._starting_cap = starting_cap
	mgr._hard_cap = 200
	return auto_free(mgr)


func _create_ai_military(
	scene_root: Node = null,
	pop_mgr: Node = null,
	tech_manager: Node = null,
) -> Node:
	if scene_root == null:
		scene_root = self
	var ai := Node.new()
	ai.name = "AIMilitary_%d" % get_child_count()
	ai.set_script(AIMilitaryScript)
	ai.difficulty = "normal"
	add_child(ai)
	if pop_mgr == null:
		pop_mgr = _create_pop_manager()
	ai.setup(scene_root, pop_mgr, null, null, tech_manager)
	return auto_free(ai)


func _create_ai_tech(tech_manager: Node) -> Node:
	var ai := Node.new()
	ai.name = "AITech_%d" % get_child_count()
	ai.set_script(AITechScript)
	ai.difficulty = "normal"
	ai.personality = "balanced"
	add_child(ai)
	ai.setup(tech_manager)
	return auto_free(ai)


func _create_town_center(
	owner_id: int = 1,
	grid_pos: Vector2i = Vector2i(50, 50),
) -> Node2D:
	var building := Node2D.new()
	building.name = "TC_%d" % get_child_count()
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
	return auto_free(building)


func _create_military_unit(
	owner_id: int = 1,
	unit_type: String = "infantry",
	pos: Vector2 = Vector2.ZERO,
) -> Node2D:
	var unit := Node2D.new()
	unit.name = "MilUnit_%d" % get_child_count()
	unit.set_script(UnitScript)
	unit.unit_type = unit_type
	unit.unit_category = "military"
	unit.owner_id = owner_id
	unit.position = pos
	unit._scene_root = self
	unit._moving = false
	add_child(unit)
	return auto_free(unit)


func _create_barracks(
	owner_id: int = 1,
	grid_pos: Vector2i = Vector2i(45, 50),
	pop_mgr: Node = null,
) -> Node2D:
	var building := Node2D.new()
	building.name = "Barracks_%d" % get_child_count()
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
	var pq := Node.new()
	pq.name = "ProductionQueue"
	pq.set_script(ProductionQueueScript)
	building.add_child(pq)
	pq.setup(building, owner_id, pop_mgr)
	return auto_free(building)


func _init_ai_resources(
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


func _give_ai_techs(tm: Node, count: int) -> void:
	var fake_techs: Array = []
	for i in count:
		fake_techs.append("fake_tech_%d" % i)
	tm._researched_techs[1] = fake_techs


func _give_player_techs(tm: Node, count: int) -> void:
	var fake_techs: Array = []
	for i in count:
		fake_techs.append("player_tech_%d" % i)
	tm._researched_techs[0] = fake_techs


# --- Defense: vulnerability increases with tech count ---


func test_vulnerability_increases_with_tech_count() -> void:
	var tm := _create_tech_manager()
	var ai := _create_ai_military(self, null, tm)
	var tc := _create_town_center()
	# Low tech count
	_give_ai_techs(tm, 2)
	ai._refresh_entity_lists()
	var vuln_low: float = ai._compute_tc_vulnerability(tc)
	# High tech count
	_give_ai_techs(tm, 20)
	var vuln_high: float = ai._compute_tc_vulnerability(tc)
	assert_float(vuln_high).is_greater(vuln_low)


# --- Defense: vulnerability increases with nearby enemies ---


func test_vulnerability_increases_with_nearby_enemies() -> void:
	var tm := _create_tech_manager()
	var ai := _create_ai_military(self, null, tm)
	var tc := _create_town_center()
	_give_ai_techs(tm, 10)
	ai._refresh_entity_lists()
	var vuln_no_enemies: float = ai._compute_tc_vulnerability(tc)
	# Place enemies near TC
	var tc_pos: Vector2 = tc.global_position
	for i in 4:
		_create_military_unit(0, "infantry", tc_pos + Vector2(i * 10, 0))
	ai._refresh_entity_lists()
	var vuln_with_enemies: float = ai._compute_tc_vulnerability(tc)
	assert_float(vuln_with_enemies).is_greater(vuln_no_enemies)


# --- Defense: vulnerability decreases with garrison ---


func test_vulnerability_decreases_with_defenders() -> void:
	var tm := _create_tech_manager()
	var ai := _create_ai_military(self, null, tm)
	var tc := _create_town_center()
	_give_ai_techs(tm, 10)
	# Place enemy near TC to create baseline vulnerability
	var tc_pos: Vector2 = tc.global_position
	_create_military_unit(0, "infantry", tc_pos + Vector2(50, 0))
	ai._refresh_entity_lists()
	var vuln_undefended: float = ai._compute_tc_vulnerability(tc)
	# Add AI defenders near TC
	for i in 5:
		_create_military_unit(1, "infantry", tc_pos + Vector2(i * 10, 10))
	ai._refresh_entity_lists()
	var vuln_defended: float = ai._compute_tc_vulnerability(tc)
	assert_float(vuln_defended).is_less(vuln_undefended)


# --- Defense: defender allocation proportional to techs ---


func test_defender_allocation_proportional_to_techs() -> void:
	var tm := _create_tech_manager()
	var ai := _create_ai_military(self, null, tm)
	var tc := _create_town_center()
	_give_ai_techs(tm, 10)
	# Create idle military units far from TC
	var tc_pos: Vector2 = tc.global_position
	var moved_count: int = 0
	for i in 8:
		var unit := _create_military_unit(1, "infantry", tc_pos + Vector2(5000, i * 10))
		unit._moving = false
	ai._refresh_entity_lists()
	ai._allocate_tc_defenders()
	# Some units should now be moving toward TC
	for child in get_children():
		if "unit_category" in child and child.unit_category == "military":
			if child.owner_id == 1 and child._moving:
				moved_count += 1
	assert_int(moved_count).is_greater(0)


# --- Defense: scales with age ---


func test_vulnerability_scales_with_age() -> void:
	var tm := _create_tech_manager()
	var ai := _create_ai_military(self, null, tm)
	var tc := _create_town_center()
	_give_ai_techs(tm, 10)
	GameManager.current_age = 1
	ai._refresh_entity_lists()
	var vuln_age1: float = ai._compute_tc_vulnerability(tc)
	GameManager.current_age = 4
	var vuln_age4: float = ai._compute_tc_vulnerability(tc)
	assert_float(vuln_age4).is_greater(vuln_age1)


# --- Defense: defends most vulnerable TC ---


func test_defends_most_vulnerable_tc() -> void:
	var tm := _create_tech_manager()
	var ai := _create_ai_military(self, null, tm)
	_give_ai_techs(tm, 10)
	# TC1 — safe, no enemies
	var tc1 := _create_town_center(1, Vector2i(50, 50))
	# TC2 — enemies nearby, more vulnerable
	var tc2 := _create_town_center(1, Vector2i(80, 80))
	var tc2_pos: Vector2 = tc2.global_position
	for i in 3:
		_create_military_unit(0, "infantry", tc2_pos + Vector2(i * 10, 0))
	# Create idle military near TC1
	var tc1_pos: Vector2 = tc1.global_position
	for i in 6:
		_create_military_unit(1, "infantry", tc1_pos + Vector2(5000, i * 10))
	ai._refresh_entity_lists()
	var vuln1: float = ai._compute_tc_vulnerability(tc1)
	var vuln2: float = ai._compute_tc_vulnerability(tc2)
	assert_float(vuln2).is_greater(vuln1)


# --- Offense: TC snipe with military advantage ---


func test_tc_snipe_with_military_advantage() -> void:
	var tm := _create_tech_manager()
	var ai := _create_ai_military(self, null, tm)
	_create_town_center(1, Vector2i(50, 50))
	# Create enemy TC
	_create_town_center(0, Vector2i(10, 10))
	# AI has clear military advantage (10 vs 3)
	for i in 10:
		_create_military_unit(1, "infantry", Vector2(i * 10, 0))
	for i in 3:
		_create_military_unit(0, "infantry", Vector2(200 + i * 10, 0))
	ai._refresh_entity_lists()
	assert_bool(ai._should_prioritize_tc_snipe()).is_true()


# --- Offense: no TC snipe without advantage ---


func test_no_tc_snipe_without_advantage() -> void:
	var tm := _create_tech_manager()
	var ai := _create_ai_military(self, null, tm)
	_create_town_center(1, Vector2i(50, 50))
	_create_town_center(0, Vector2i(10, 10))
	# Equal military (5 vs 5)
	for i in 5:
		_create_military_unit(1, "infantry", Vector2(i * 10, 0))
		_create_military_unit(0, "infantry", Vector2(200 + i * 10, 0))
	ai._refresh_entity_lists()
	assert_bool(ai._should_prioritize_tc_snipe()).is_false()


# --- Offense: TC priority on tech lead ---


func test_tc_priority_on_enemy_tech_lead() -> void:
	var tm := _create_tech_manager()
	var ai := _create_ai_military(self, null, tm)
	_create_town_center(1, Vector2i(50, 50))
	_create_town_center(0, Vector2i(10, 10))
	# Even military, but enemy has big tech lead
	for i in 5:
		_create_military_unit(1, "infantry", Vector2(i * 10, 0))
		_create_military_unit(0, "infantry", Vector2(200 + i * 10, 0))
	_give_ai_techs(tm, 2)
	_give_player_techs(tm, 6)  # Enemy leads by 4 (>= threshold 3)
	ai._refresh_entity_lists()
	assert_bool(ai._should_prioritize_tc_snipe()).is_true()


# --- Offense: rusher has lower snipe threshold ---


func test_rusher_lower_snipe_threshold() -> void:
	var tm := _create_tech_manager()
	var ai := _create_ai_military(self, null, tm)
	ai.personality = AIPersonality.get_personality("rusher")
	ai._load_tr_config()
	_create_town_center(1, Vector2i(50, 50))
	_create_town_center(0, Vector2i(10, 10))
	# Rusher has tc_snipe_military_advantage_ratio = 1.2
	# 7 vs 5 = 1.4 ratio — enough for rusher but not default (1.5)
	for i in 7:
		_create_military_unit(1, "infantry", Vector2(i * 10, 0))
	for i in 5:
		_create_military_unit(0, "infantry", Vector2(200 + i * 10, 0))
	ai._refresh_entity_lists()
	assert_bool(ai._should_prioritize_tc_snipe()).is_true()


# --- Forward TC: builder avoids without big advantage ---


func test_builder_avoids_forward_tc_without_advantage() -> void:
	var ai_econ := Node.new()
	ai_econ.name = "AIEcon_%d" % get_child_count()
	ai_econ.set_script(AIEconomyScript)
	ai_econ.personality = AIPersonality.get_personality("builder")
	add_child(ai_econ)
	auto_free(ai_econ)
	var tm := _create_tech_manager()
	ai_econ.setup(self, _create_pop_manager(), null, null, null, tm)
	# Builder needs 2.5 ratio — with 5 vs 3 (1.67) should fail
	for i in 5:
		_create_military_unit(1, "infantry", Vector2(i * 10, 0))
	for i in 3:
		_create_military_unit(0, "infantry", Vector2(200 + i * 10, 0))
	assert_bool(ai_econ._should_build_forward_tc()).is_false()


# --- Forward TC: rusher builds with small advantage ---


func test_rusher_builds_forward_tc_with_small_advantage() -> void:
	var ai_econ := Node.new()
	ai_econ.name = "AIEcon_%d" % get_child_count()
	ai_econ.set_script(AIEconomyScript)
	ai_econ.personality = AIPersonality.get_personality("rusher")
	add_child(ai_econ)
	auto_free(ai_econ)
	var tm := _create_tech_manager()
	ai_econ.setup(self, _create_pop_manager(), null, null, null, tm)
	# Rusher needs 1.3 ratio — with 5 vs 3 (1.67) should pass
	for i in 5:
		_create_military_unit(1, "infantry", Vector2(i * 10, 0))
	for i in 3:
		_create_military_unit(0, "infantry", Vector2(200 + i * 10, 0))
	assert_bool(ai_econ._should_build_forward_tc()).is_true()


# --- Forward TC: no rebuild at destroyed position ---


func test_no_rebuild_at_destroyed_position() -> void:
	var ai_econ := Node.new()
	ai_econ.name = "AIEcon_%d" % get_child_count()
	ai_econ.set_script(AIEconomyScript)
	add_child(ai_econ)
	auto_free(ai_econ)
	var tm := _create_tech_manager()
	ai_econ.setup(self, _create_pop_manager(), null, null, null, tm)
	# Record a destroyed TC position
	var destroyed_pos := Vector2i(20, 20)
	ai_econ._destroyed_tc_positions.append(destroyed_pos)
	# Test avoidance
	assert_bool(ai_econ._is_near_destroyed_tc(Vector2i(22, 22), 10)).is_true()
	assert_bool(ai_econ._is_near_destroyed_tc(Vector2i(50, 50), 10)).is_false()


# --- Tech loss: signal triggers boost timer ---


func test_tech_loss_triggers_boost_timer() -> void:
	var tm := _create_tech_manager()
	var ai := _create_ai_military(self, null, tm)
	assert_float(ai._tech_loss_boost_timer).is_equal(0.0)
	ai.on_tech_regressed(1, "fake_tech", {})
	assert_float(ai._tech_loss_boost_timer).is_greater(0.0)


# --- Tech loss: pop ratio boost active ---


func test_pop_ratio_boost_active_during_timer() -> void:
	var tm := _create_tech_manager()
	_init_ai_resources()
	var pop_mgr := _create_pop_manager()
	var ai := _create_ai_military(self, pop_mgr, tm)
	_create_town_center(1, Vector2i(50, 50))
	_create_barracks(1, Vector2i(45, 50), pop_mgr)
	ai.on_tech_regressed(1, "fake_tech", {})
	# max_military_pop_ratio should be boosted
	# Normal is 0.50, boost is 0.15, so effective = 0.65
	# With pop_cap = 200, at 0.50 ratio = 100 military blocks, but 0.65 = 130
	# Create exactly at the normal limit
	for i in 101:
		var unit := _create_military_unit(1, "infantry", Vector2(i * 10, 0))
		pop_mgr.register_unit(unit, 1)
	ai._refresh_entity_lists()
	# At normal 0.50 ratio: 101/200 = 0.505 > 0.50 -> would block
	# At boosted 0.65 ratio: 101/200 = 0.505 < 0.65 -> should allow
	assert_bool(ai._can_train_military()).is_true()


# --- Tech loss: boost expires ---


func test_boost_timer_expires() -> void:
	var tm := _create_tech_manager()
	var ai := _create_ai_military(self, null, tm)
	ai.on_tech_regressed(1, "fake_tech", {})
	assert_float(ai._tech_loss_boost_timer).is_greater(0.0)
	# Simulate time passing beyond boost duration
	ai._tech_loss_boost_timer = 0.5
	ai._process(1.0)  # game_delta = 1.0 with speed 1.0
	assert_float(ai._tech_loss_boost_timer).is_equal(0.0)


# --- Tech loss: AITech requeues regressed tech ---


func test_ai_tech_requeues_regressed_tech() -> void:
	var tm := _create_tech_manager()
	var ai := _create_ai_tech(tm)
	# Simulate regression
	ai.on_tech_regressed(1, "stone_tools", {})
	assert_bool("stone_tools" in ai._regressed_requeue).is_true()


# --- Save/Load: military preserves regression state ---


func test_military_save_load_preserves_regression_state() -> void:
	var tm := _create_tech_manager()
	var ai := _create_ai_military(self, null, tm)
	ai.on_tech_regressed(1, "fake_tech", {})
	ai._destroyed_tc_positions.append(Vector2i(10, 20))
	ai._destroyed_tc_positions.append(Vector2i(30, 40))
	var state: Dictionary = ai.save_state()
	assert_float(float(state.get("tech_loss_boost_timer", 0))).is_greater(0.0)
	var dtc: Array = state.get("destroyed_tc_positions", [])
	assert_int(dtc.size()).is_equal(2)
	# Load into fresh instance
	var ai2 := _create_ai_military(self, null, tm)
	ai2.load_state(state)
	assert_float(ai2._tech_loss_boost_timer).is_greater(0.0)
	assert_int(ai2._destroyed_tc_positions.size()).is_equal(2)
	assert_bool(ai2._destroyed_tc_positions[0] == Vector2i(10, 20)).is_true()


# --- Save/Load: tech preserves requeue ---


func test_tech_save_load_preserves_requeue() -> void:
	var tm := _create_tech_manager()
	var ai := _create_ai_tech(tm)
	ai.on_tech_regressed(1, "bronze_working", {})
	ai.on_tech_regressed(1, "writing", {})
	var state: Dictionary = ai.save_state()
	var rq: Array = state.get("regressed_requeue", [])
	assert_int(rq.size()).is_equal(2)
	# Load into fresh instance
	var ai2 := _create_ai_tech(tm)
	ai2.load_state(state)
	assert_int(ai2._regressed_requeue.size()).is_equal(2)
	assert_bool("bronze_working" in ai2._regressed_requeue).is_true()
	assert_bool("writing" in ai2._regressed_requeue).is_true()
