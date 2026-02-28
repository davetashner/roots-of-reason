extends GdUnitTestSuite
## Tests for scripts/prototype/pandemic_manager.gd — pandemic event system.

const PandemicScript := preload("res://scripts/prototype/pandemic_manager.gd")
const PopManagerScript := preload("res://scripts/prototype/population_manager.gd")
const TechManagerScript := preload("res://scripts/prototype/tech_manager.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")

var _original_age: int


func before_test() -> void:
	_original_age = GameManager.current_age


func after_test() -> void:
	GameManager.current_age = _original_age
	GameUtils.clear_autoload_cache()


func _base_config(overrides: Dictionary = {}) -> Dictionary:
	var cfg := {
		"enabled": true,
		"active_ages": [0, 1, 2, 3],
		"check_interval_seconds": 120,
		"base_probability": 0.05,
		"density_threshold": 15,
		"density_scaling": 0.02,
		"effects":
		{
			"villager_work_rate_penalty": -0.30,
			"villager_death_chance": 0.05,
			"duration_seconds": 45,
		},
		"tech_mitigations":
		{
			"herbalism":
			{
				"severity_reduction": 0.25,
				"probability_reduction": 0.15,
			},
			"sanitation":
			{
				"severity_reduction": 0.50,
				"probability_reduction": 0.30,
			},
			"vaccines": {"immune": true},
		},
	}
	cfg.merge(overrides, true)
	return cfg


func _create_pandemic_manager() -> Node:
	var mgr := Node.new()
	mgr.set_script(PandemicScript)
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


func _mark_researched(tech: Node, tech_id: String, player_id: int = 0) -> void:
	if player_id not in tech._researched_techs:
		tech._researched_techs[player_id] = []
	tech._researched_techs[player_id].append(tech_id)


func _create_mock_villager(pid: int = 0, gather_rate: float = 1.0) -> Node2D:
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.owner_id = pid
	unit.unit_type = "villager"
	unit.hp = 25
	unit.max_hp = 25
	unit._gather_rate_multiplier = gather_rate
	add_child(unit)
	return auto_free(unit)


func _set_age(age: int) -> void:
	GameManager.current_age = age


# --- Config / Gating ---


func test_no_outbreak_when_disabled() -> void:
	_set_age(1)
	var pm := _create_pandemic_manager()
	pm._config = _base_config({"enabled": false})
	pm._scene_root = self
	# Force a high probability to confirm it's blocked
	pm._config.base_probability = 1.0
	pm._check_timer = 120.0
	pm._process(0.016)
	assert_bool(pm.is_outbreak_active(0)).is_false()


func test_no_outbreak_in_wrong_age() -> void:
	_set_age(4)  # Not in active_ages [0,1,2,3]
	var pm := _create_pandemic_manager()
	pm._config = _base_config({"base_probability": 1.0})
	pm._scene_root = self
	pm._roll_pandemics()
	assert_bool(pm.is_outbreak_active(0)).is_false()


func test_outbreak_possible_in_correct_age() -> void:
	_set_age(1)
	var pm := _create_pandemic_manager()
	pm._config = _base_config({"base_probability": 1.0})
	pm._scene_root = self
	pm._pop_manager = _create_pop_manager()
	pm._roll_pandemics()
	assert_bool(pm.is_outbreak_active(0)).is_true()


# --- Probability ---


func test_probability_below_threshold_base_only() -> void:
	_set_age(1)
	var pm := _create_pandemic_manager()
	var pop := _create_pop_manager()
	pm._config = _base_config()
	pm._pop_manager = pop
	# Population 10 is below density_threshold 15 -> only base 0.05
	var prob: float = pm._calculate_probability(0)
	assert_float(prob).is_equal_approx(0.05, 0.001)


func test_probability_increases_with_density() -> void:
	_set_age(1)
	var pm := _create_pandemic_manager()
	var pop := _create_pop_manager()
	pm._config = _base_config()
	pm._pop_manager = pop
	# Manually set population above threshold
	pop._current_population[0] = 20
	# 0.05 + max(0, (20-15)*0.02) = 0.05 + 0.10 = 0.15
	var prob: float = pm._calculate_probability(0)
	assert_float(prob).is_equal_approx(0.15, 0.001)


func test_probability_zero_guaranteed_no_outbreak() -> void:
	_set_age(1)
	var pm := _create_pandemic_manager()
	pm._config = _base_config({"base_probability": 0.0, "density_scaling": 0.0})
	pm._scene_root = self
	pm._pop_manager = _create_pop_manager()
	# Run many rolls — should never trigger
	for i in 100:
		pm._roll_pandemics()
	assert_bool(pm.is_outbreak_active(0)).is_false()


func test_probability_one_guarantees_outbreak() -> void:
	_set_age(1)
	var pm := _create_pandemic_manager()
	pm._config = _base_config({"base_probability": 1.0})
	pm._scene_root = self
	pm._pop_manager = _create_pop_manager()
	pm._roll_pandemics()
	assert_bool(pm.is_outbreak_active(0)).is_true()


# --- Tech Mitigation ---


func test_herbalism_reduces_probability() -> void:
	_set_age(1)
	var pm := _create_pandemic_manager()
	var tech := _create_tech_manager()
	pm._config = _base_config()
	pm._tech_manager = tech
	pm._pop_manager = _create_pop_manager()
	_mark_researched(tech, "herbalism", 0)
	# 0.05 - 0.15 = -0.10, clamped to 0.0
	var prob: float = pm._calculate_probability(0)
	assert_float(prob).is_equal_approx(0.0, 0.001)


func test_herbalism_reduces_severity() -> void:
	var pm := _create_pandemic_manager()
	var tech := _create_tech_manager()
	pm._config = _base_config()
	pm._tech_manager = tech
	_mark_researched(tech, "herbalism", 0)
	# 1.0 - 0.25 = 0.75
	var sev: float = pm._calculate_severity(0)
	assert_float(sev).is_equal_approx(0.75, 0.001)


func test_sanitation_stacks_with_herbalism() -> void:
	var pm := _create_pandemic_manager()
	var tech := _create_tech_manager()
	pm._config = _base_config()
	pm._tech_manager = tech
	_mark_researched(tech, "herbalism", 0)
	_mark_researched(tech, "sanitation", 0)
	# 1.0 - 0.25 - 0.50 = 0.25
	var sev: float = pm._calculate_severity(0)
	assert_float(sev).is_equal_approx(0.25, 0.001)


func test_vaccines_grant_immunity() -> void:
	_set_age(1)
	var pm := _create_pandemic_manager()
	var tech := _create_tech_manager()
	pm._config = _base_config({"base_probability": 1.0})
	pm._tech_manager = tech
	pm._scene_root = self
	pm._pop_manager = _create_pop_manager()
	_mark_researched(tech, "vaccines", 0)
	var prob: float = pm._calculate_probability(0)
	assert_float(prob).is_equal_approx(0.0, 0.001)
	pm._roll_pandemics()
	assert_bool(pm.is_outbreak_active(0)).is_false()


# --- Outbreak Effects ---


func test_work_rate_penalty_applied() -> void:
	_set_age(1)
	var pm := _create_pandemic_manager()
	pm._config = _base_config({"base_probability": 1.0})
	pm._scene_root = self
	pm._pop_manager = _create_pop_manager()
	var v := _create_mock_villager(0, 1.0)
	pm._roll_pandemics()
	# penalty = -0.30 * severity(1.0) = -0.30 -> multiplier = 1.0 - 0.30 = 0.70
	assert_float(v._gather_rate_multiplier).is_equal_approx(0.70, 0.001)


func test_penalty_scaled_by_severity() -> void:
	_set_age(1)
	var pm := _create_pandemic_manager()
	var tech := _create_tech_manager()
	pm._config = _base_config({"base_probability": 1.0})
	pm._tech_manager = tech
	pm._scene_root = self
	pm._pop_manager = _create_pop_manager()
	_mark_researched(tech, "herbalism", 0)
	var v := _create_mock_villager(0, 1.0)
	# Call _start_outbreak directly — _roll_pandemics uses randf() which makes
	# this test flaky because herbalism reduces probability from 1.0 to 0.85.
	pm._start_outbreak(0)
	# severity = 0.75, penalty = -0.30 * 0.75 = -0.225 -> multiplier = 0.775
	assert_float(v._gather_rate_multiplier).is_equal_approx(0.775, 0.001)


func test_death_chance_can_kill_villager() -> void:
	_set_age(1)
	var pm := _create_pandemic_manager()
	pm._config = _base_config(
		{
			"base_probability": 1.0,
			"effects":
			{
				"villager_work_rate_penalty": -0.30,
				"villager_death_chance": 1.0,  # Guaranteed kill
				"duration_seconds": 45,
			},
		}
	)
	pm._scene_root = self
	pm._pop_manager = _create_pop_manager()
	var v := _create_mock_villager(0)
	pm._roll_pandemics()
	# Force death roll
	pm._roll_deaths(0, 1.0)
	assert_int(v.hp).is_less_equal(0)


func test_death_roll_zero_chance_no_kills() -> void:
	_set_age(1)
	var pm := _create_pandemic_manager()
	pm._config = _base_config(
		{
			"base_probability": 1.0,
			"effects":
			{
				"villager_work_rate_penalty": -0.30,
				"villager_death_chance": 0.0,
				"duration_seconds": 45,
			},
		}
	)
	pm._scene_root = self
	pm._pop_manager = _create_pop_manager()
	var v := _create_mock_villager(0)
	pm._roll_pandemics()
	for i in 50:
		pm._roll_deaths(0, 1.0)
	assert_int(v.hp).is_greater(0)


# --- Outbreak Lifecycle ---


func test_outbreak_starts_on_roll_success() -> void:
	_set_age(1)
	var pm := _create_pandemic_manager()
	pm._config = _base_config({"base_probability": 1.0})
	pm._scene_root = self
	pm._pop_manager = _create_pop_manager()
	var signals_received: Array = []
	pm.pandemic_started.connect(func(pid: int, sev: float) -> void: signals_received.append([pid, sev]))
	pm._roll_pandemics()
	assert_bool(pm.is_outbreak_active(0)).is_true()
	assert_int(signals_received.size()).is_greater(0)


func test_outbreak_ends_after_duration() -> void:
	_set_age(1)
	var pm := _create_pandemic_manager()
	pm._config = _base_config(
		{
			"base_probability": 1.0,
			"effects":
			{
				"villager_work_rate_penalty": -0.30,
				"villager_death_chance": 0.0,
				"duration_seconds": 10,
			},
		}
	)
	pm._scene_root = self
	pm._pop_manager = _create_pop_manager()
	var end_signals: Array = []
	pm.pandemic_ended.connect(func(pid: int) -> void: end_signals.append(pid))
	pm._roll_pandemics()
	assert_bool(pm.is_outbreak_active(0)).is_true()
	# Tick past duration
	pm._tick_outbreaks(11.0)
	assert_bool(pm.is_outbreak_active(0)).is_false()
	assert_int(end_signals.size()).is_greater(0)


func test_work_rate_restored_after_outbreak() -> void:
	_set_age(1)
	var pm := _create_pandemic_manager()
	pm._config = _base_config(
		{
			"base_probability": 1.0,
			"effects":
			{
				"villager_work_rate_penalty": -0.30,
				"villager_death_chance": 0.0,
				"duration_seconds": 10,
			},
		}
	)
	pm._scene_root = self
	pm._pop_manager = _create_pop_manager()
	var v := _create_mock_villager(0, 1.0)
	pm._roll_pandemics()
	assert_float(v._gather_rate_multiplier).is_equal_approx(0.70, 0.001)
	# End outbreak
	pm._tick_outbreaks(11.0)
	assert_float(v._gather_rate_multiplier).is_equal_approx(1.0, 0.001)


# --- Save / Load ---


func test_save_load_roundtrip_timer() -> void:
	var pm := _create_pandemic_manager()
	pm._config = _base_config()
	pm._check_timer = 55.5
	var state: Dictionary = pm.save_state()
	var pm2 := _create_pandemic_manager()
	pm2._config = _base_config()
	pm2.load_state(state)
	assert_float(pm2._check_timer).is_equal_approx(55.5, 0.01)


func test_save_load_roundtrip_active_outbreak() -> void:
	_set_age(1)
	var pm := _create_pandemic_manager()
	pm._config = _base_config(
		{
			"base_probability": 1.0,
			"effects":
			{
				"villager_work_rate_penalty": -0.30,
				"villager_death_chance": 0.0,
				"duration_seconds": 45,
			},
		}
	)
	pm._scene_root = self
	pm._pop_manager = _create_pop_manager()
	_create_mock_villager(0, 1.0)
	pm._roll_pandemics()
	assert_bool(pm.is_outbreak_active(0)).is_true()
	var state: Dictionary = pm.save_state()
	# Verify state has outbreak data
	assert_bool(state.has("active_outbreaks")).is_true()
	var outbreaks: Dictionary = state.active_outbreaks
	assert_bool(outbreaks.has("0")).is_true()
	assert_float(float(outbreaks["0"].severity)).is_equal_approx(1.0, 0.001)


func test_load_state_reapplies_penalty() -> void:
	_set_age(1)
	var pm := _create_pandemic_manager()
	pm._config = _base_config(
		{
			"effects":
			{
				"villager_work_rate_penalty": -0.30,
				"villager_death_chance": 0.0,
				"duration_seconds": 45,
			},
		}
	)
	pm._scene_root = self
	# Create a villager with normal rate
	var v := _create_mock_villager(0, 1.0)
	# Load state with active outbreak
	var state := {
		"check_timer": 10.0,
		"active_outbreaks":
		{
			"0":
			{
				"timer": 30.0,
				"severity": 1.0,
				"death_timer": 0.0,
				"original_rates": {},
			},
		},
	}
	pm.load_state(state)
	# Villager should have penalty reapplied
	assert_float(v._gather_rate_multiplier).is_equal_approx(0.70, 0.001)


# --- Multi-player ---


func test_independent_outbreaks_per_player() -> void:
	_set_age(1)
	var pm := _create_pandemic_manager()
	pm._config = _base_config({"base_probability": 1.0})
	pm._scene_root = self
	pm._pop_manager = _create_pop_manager()
	var v0 := _create_mock_villager(0, 1.0)
	var v1 := _create_mock_villager(1, 1.0)
	pm._roll_pandemics()
	assert_bool(pm.is_outbreak_active(0)).is_true()
	assert_bool(pm.is_outbreak_active(1)).is_true()
	assert_float(v0._gather_rate_multiplier).is_equal_approx(0.70, 0.001)
	assert_float(v1._gather_rate_multiplier).is_equal_approx(0.70, 0.001)


func test_severity_query_methods() -> void:
	_set_age(1)
	var pm := _create_pandemic_manager()
	pm._config = _base_config({"base_probability": 1.0})
	pm._scene_root = self
	pm._pop_manager = _create_pop_manager()
	pm._roll_pandemics()
	assert_float(pm.get_outbreak_severity(0)).is_equal_approx(1.0, 0.001)
	assert_float(pm.get_outbreak_time_remaining(0)).is_greater(0.0)
	# No outbreak for query on non-outbreak state
	assert_float(pm.get_outbreak_severity(99)).is_equal_approx(0.0, 0.001)
	assert_float(pm.get_outbreak_time_remaining(99)).is_equal_approx(0.0, 0.001)


func test_check_timer_increments_via_process() -> void:
	var pm := _create_pandemic_manager()
	pm._config = _base_config({"check_interval_seconds": 120})
	pm._scene_root = self
	pm._pop_manager = _create_pop_manager()
	# Simulate ~60 seconds of game time at 60fps
	for i in 3600:
		pm._process(1.0 / 60.0)
	# Timer should be around 60 (not exact due to float precision)
	assert_float(pm._check_timer).is_between(59.0, 61.0)


func test_antibiotics_villager_death_immunity() -> void:
	_set_age(1)
	var pm := _create_pandemic_manager()
	var tech := _create_tech_manager()
	pm._config = _base_config(
		{
			"base_probability": 1.0,
			"effects":
			{
				"villager_work_rate_penalty": -0.30,
				"villager_death_chance": 1.0,
				"duration_seconds": 45,
			},
			"tech_mitigations":
			{
				"antibiotics": {"villager_death_immunity": true},
			},
		}
	)
	pm._tech_manager = tech
	pm._scene_root = self
	pm._pop_manager = _create_pop_manager()
	_mark_researched(tech, "antibiotics", 0)
	var v := _create_mock_villager(0)
	pm._roll_pandemics()
	# Death chance is 1.0 but antibiotics gives immunity
	pm._roll_deaths(0, 1.0)
	assert_int(v.hp).is_greater(0)
