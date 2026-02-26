extends GdUnitTestSuite
## Tests for scripts/prototype/corruption_manager.gd — corruption calculation engine.

const CorruptionScript := preload("res://scripts/prototype/corruption_manager.gd")
const PopManagerScript := preload("res://scripts/prototype/population_manager.gd")
const TechManagerScript := preload("res://scripts/prototype/tech_manager.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")

var _original_age: int
var _original_corruption_rate: float


func before_test() -> void:
	_original_age = GameManager.current_age
	_original_corruption_rate = ResourceManager.get_corruption_rate(0)


func after_test() -> void:
	GameManager.current_age = _original_age
	ResourceManager.set_corruption_rate(0, _original_corruption_rate)
	ResourceManager.set_corruption_rate(1, 0.0)


func _base_config(overrides: Dictionary = {}) -> Dictionary:
	var cfg := {
		"enabled": true,
		"active_ages": [1, 2, 3, 4],
		"building_threshold": 8,
		"base_rate_per_building": 0.015,
		"max_corruption": 0.30,
		"tech_reductions": {},
	}
	cfg.merge(overrides, true)
	return cfg


func _create_corruption_manager() -> Node:
	var mgr := Node.new()
	mgr.set_script(CorruptionScript)
	add_child(mgr)
	return auto_free(mgr)


func _create_pop_manager() -> Node:
	var mgr := Node.new()
	mgr.set_script(PopManagerScript)
	add_child(mgr)
	mgr._starting_cap = 5
	mgr._hard_cap = 200
	return auto_free(mgr)


func _create_tech_manager() -> Node:
	var mgr := Node.new()
	mgr.set_script(TechManagerScript)
	add_child(mgr)
	return auto_free(mgr)


func _create_mock_building(bname: String = "barracks") -> Node2D:
	var b := Node2D.new()
	b.set_script(BuildingScript)
	b.building_name = bname
	b.max_hp = 550
	b.hp = 550
	b.under_construction = false
	b.build_progress = 1.0
	b.footprint = Vector2i(2, 2)
	b.grid_pos = Vector2i(0, 0)
	add_child(b)
	return auto_free(b)


func _set_age(age: int) -> void:
	GameManager.current_age = age


func _add_buildings(pop: Node, count: int) -> void:
	for i in count:
		var b := _create_mock_building("barracks")
		pop.register_building(b, 0)


func _mark_researched(tech: Node, tech_id: String, player_id: int = 0) -> void:
	if player_id not in tech._researched_techs:
		tech._researched_techs[player_id] = []
	tech._researched_techs[player_id].append(tech_id)


# --- Zero corruption cases ---


func test_corruption_zero_when_disabled() -> void:
	var cm := _create_corruption_manager()
	cm._config = _base_config({"enabled": false})
	assert_float(cm.calculate_corruption(0)).is_equal_approx(0.0, 0.001)


func test_corruption_zero_in_stone_age() -> void:
	_set_age(0)
	var cm := _create_corruption_manager()
	cm._config = _base_config()
	assert_float(cm.calculate_corruption(0)).is_equal_approx(0.0, 0.001)


func test_corruption_zero_in_information_age() -> void:
	_set_age(5)
	var cm := _create_corruption_manager()
	cm._config = _base_config()
	assert_float(cm.calculate_corruption(0)).is_equal_approx(0.0, 0.001)


func test_corruption_zero_below_threshold() -> void:
	_set_age(1)
	var pop := _create_pop_manager()
	var cm := _create_corruption_manager()
	cm._config = _base_config()
	cm._pop_manager = pop
	_add_buildings(pop, 8)
	assert_float(cm.calculate_corruption(0)).is_equal_approx(0.0, 0.001)


# --- Rate calculation ---


func test_corruption_rate_above_threshold() -> void:
	_set_age(1)
	var pop := _create_pop_manager()
	var cm := _create_corruption_manager()
	cm._config = _base_config()
	cm._pop_manager = pop
	# 10 buildings -> 2 above threshold -> 2 * 0.015 = 0.03
	_add_buildings(pop, 10)
	assert_float(cm.calculate_corruption(0)).is_equal_approx(0.03, 0.001)


func test_corruption_capped_at_max() -> void:
	_set_age(1)
	var pop := _create_pop_manager()
	var cm := _create_corruption_manager()
	cm._config = _base_config()
	cm._pop_manager = pop
	# 30 buildings -> 22 above -> 22 * 0.015 = 0.33 -> capped at 0.30
	_add_buildings(pop, 30)
	assert_float(cm.calculate_corruption(0)).is_equal_approx(0.30, 0.001)


# --- Tech reductions ---


func test_code_of_laws_reduces_corruption() -> void:
	_set_age(1)
	var pop := _create_pop_manager()
	var tech := _create_tech_manager()
	var cm := _create_corruption_manager()
	cm._config = _base_config({"tech_reductions": {"code_of_laws": -0.30}})
	cm._pop_manager = pop
	cm._tech_manager = tech
	# 28 buildings -> 20 above -> 20 * 0.015 = 0.30
	_add_buildings(pop, 28)
	assert_float(cm.calculate_corruption(0)).is_equal_approx(0.30, 0.001)
	_mark_researched(tech, "code_of_laws", 0)
	# 0.30 + (-0.30) = 0.0
	assert_float(cm.calculate_corruption(0)).is_equal_approx(0.0, 0.001)


func test_banking_reduces_corruption() -> void:
	_set_age(1)
	var pop := _create_pop_manager()
	var tech := _create_tech_manager()
	var cm := _create_corruption_manager()
	cm._config = _base_config({"tech_reductions": {"banking": -0.25}})
	cm._pop_manager = pop
	cm._tech_manager = tech
	_add_buildings(pop, 28)
	_mark_researched(tech, "banking", 0)
	# 0.30 - 0.25 = 0.05
	assert_float(cm.calculate_corruption(0)).is_equal_approx(0.05, 0.001)


func test_civil_service_eliminates_corruption() -> void:
	_set_age(1)
	var pop := _create_pop_manager()
	var tech := _create_tech_manager()
	var cm := _create_corruption_manager()
	cm._config = _base_config({"tech_reductions": {"civil_service": -1.0}})
	cm._pop_manager = pop
	cm._tech_manager = tech
	_add_buildings(pop, 28)
	_mark_researched(tech, "civil_service", 0)
	assert_float(cm.calculate_corruption(0)).is_equal_approx(0.0, 0.001)


func test_stacked_tech_reductions() -> void:
	_set_age(1)
	var pop := _create_pop_manager()
	var tech := _create_tech_manager()
	var cm := _create_corruption_manager()
	var reductions := {"code_of_laws": -0.30, "banking": -0.25}
	cm._config = _base_config({"tech_reductions": reductions})
	cm._pop_manager = pop
	cm._tech_manager = tech
	_add_buildings(pop, 28)
	_mark_researched(tech, "code_of_laws", 0)
	_mark_researched(tech, "banking", 0)
	# 0.30 - 0.30 - 0.25 = -0.25 -> clamped to 0.0
	assert_float(cm.calculate_corruption(0)).is_equal_approx(0.0, 0.001)


# --- Knowledge immunity ---


func test_knowledge_immune() -> void:
	var cm := _create_corruption_manager()
	cm._config = {
		"knowledge_immune": true,
		"affected_resources": ["food", "wood", "stone", "gold"],
	}
	assert_bool(cm.is_resource_affected("knowledge")).is_false()
	assert_bool(cm.is_resource_affected("food")).is_true()
	assert_bool(cm.is_resource_affected("gold")).is_true()


# --- Signal emission ---


func test_corruption_changed_signal_emitted() -> void:
	_set_age(1)
	var pop := _create_pop_manager()
	var cm := _create_corruption_manager()
	cm._config = _base_config()
	cm._pop_manager = pop
	_add_buildings(pop, 10)
	var result: Array = []
	cm.corruption_changed.connect(func(pid: int, rate: float) -> void: result.append([pid, rate]))
	cm.recalculate(0)
	assert_int(result.size()).is_equal(1)
	assert_float(result[0][1]).is_equal_approx(0.03, 0.001)


func test_no_signal_when_rate_unchanged() -> void:
	_set_age(1)
	var pop := _create_pop_manager()
	var cm := _create_corruption_manager()
	cm._config = _base_config()
	cm._pop_manager = pop
	cm.recalculate(0)
	var result: Array = []
	cm.corruption_changed.connect(func(pid: int, rate: float) -> void: result.append([pid, rate]))
	cm.recalculate(0)
	assert_int(result.size()).is_equal(0)


# --- Save/Load ---


func test_save_load_roundtrip() -> void:
	var cm := _create_corruption_manager()
	cm._current_rates[0] = 0.15
	cm._current_rates[1] = 0.05
	ResourceManager.set_corruption_rate(0, 0.15)
	ResourceManager.set_corruption_rate(1, 0.05)
	var state: Dictionary = cm.save_state()
	var cm2 := _create_corruption_manager()
	cm2.load_state(state)
	assert_float(cm2._current_rates.get(0, 0.0)).is_equal_approx(0.15, 0.001)
	assert_float(cm2._current_rates.get(1, 0.0)).is_equal_approx(0.05, 0.001)
	assert_float(ResourceManager.get_corruption_rate(0)).is_equal_approx(0.15, 0.001)
