extends GdUnitTestSuite
## Tests for scripts/prototype/historical_event_manager.gd — historical events system.

const HistoricalEventScript := preload("res://scripts/prototype/historical_event_manager.gd")
const TechManagerScript := preload("res://scripts/prototype/tech_manager.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")


class MockBuildingPlacer:
	extends Node
	var _placed_buildings: Array[Dictionary] = []


class MockBuilding:
	extends Node2D
	var owner_id: int = 0
	var grid_pos: Vector2i = Vector2i.ZERO


var _original_age: int
var _original_game_time: float


func before_test() -> void:
	_original_age = GameManager.current_age
	_original_game_time = GameManager.game_time


func after_test() -> void:
	GameManager.current_age = _original_age
	GameManager.game_time = _original_game_time


func _create_manager() -> Node:
	var mgr := Node.new()
	mgr.set_script(HistoricalEventScript)
	add_child(mgr)
	return auto_free(mgr)


func _create_tech_manager() -> Node:
	var mgr := Node.new()
	mgr.set_script(TechManagerScript)
	add_child(mgr)
	return auto_free(mgr)


func _create_mock_trade_manager() -> Node:
	## Minimal mock with set/clear methods and tracking.
	var mgr := Node.new()
	mgr.set_meta("_multipliers", {})
	mgr.set_script(load("res://scripts/prototype/trade_manager.gd"))
	add_child(mgr)
	return auto_free(mgr)


func _create_mock_building_placer() -> Node:
	var bp := MockBuildingPlacer.new()
	add_child(bp)
	return auto_free(bp)


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


func _create_mock_military(pid: int = 0) -> Node2D:
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.owner_id = pid
	unit.unit_type = "swordsman"
	unit.hp = 100
	unit.max_hp = 100
	unit._gather_rate_multiplier = 1.0
	add_child(unit)
	return auto_free(unit)


func _plague_config() -> Dictionary:
	return {
		"enabled": true,
		"events":
		{
			"black_plague":
			{
				"trigger":
				{
					"method": "guaranteed_by_age",
					"trigger_age": 3,
					"trigger_delay_seconds": [0, 0],
					"once_per_game": true,
				},
				"effects":
				{
					"villager_work_rate_penalty": -0.50,
					"villager_death_chance": 0.15,
					"duration_seconds": 90,
					"military_hp_drain_per_second": 2,
					"trade_income_penalty": -0.75,
				},
				"tech_mitigations":
				{
					"herbalism":
					{
						"death_chance_reduction": 0.30,
						"duration_reduction": 0.20,
					},
					"sanitation":
					{
						"death_chance_reduction": 0.50,
						"work_rate_penalty_reduction": 0.40,
					},
					"vaccines": {"immune": true},
				},
				"aftermath":
				{
					"labor_scarcity_bonus":
					{
						"villager_work_rate_bonus": 0.15,
						"duration_seconds": 120,
					},
					"innovation_pressure":
					{
						"research_speed_bonus": 0.20,
						"duration_seconds": 120,
					},
				},
				"affects_all_players": true,
			},
		},
		"plague_renaissance_interaction":
		{
			"phoenix_bonus":
			{
				"all_effects_multiplied": 1.5,
			},
		},
	}


func _renaissance_config() -> Dictionary:
	var cfg := _plague_config()
	cfg.events["renaissance"] = {
		"trigger":
		{
			"method": "tech_milestone",
			"required_techs": ["printing_press", "banking", "guilds"],
			"trigger_age_minimum": 3,
			"per_player": true,
			"once_per_player": true,
		},
		"effects":
		{
			"research_speed_bonus": 0.35,
			"gold_income_bonus": 0.20,
			"duration_seconds": 180,
		},
		"bonus_triggers":
		{
			"has_library_count_3_plus":
			{
				"extra_knowledge_bonus": 0.25,
			},
			"has_market_count_2_plus":
			{
				"extra_gold_bonus": 0.15,
			},
		},
	}
	return cfg


func _setup_full(cfg: Dictionary) -> Dictionary:
	var mgr := _create_manager()
	var tech := _create_tech_manager()
	var trade := _create_mock_trade_manager()
	var bp := _create_mock_building_placer()
	mgr._config = cfg
	mgr._tech_manager = tech
	mgr._trade_manager = trade
	mgr._building_placer = bp
	mgr._scene_root = self
	return {"mgr": mgr, "tech": tech, "trade": trade, "bp": bp}


# =====================================================
# Black Plague — Gating
# =====================================================


func test_plague_does_not_fire_in_wrong_age() -> void:
	GameManager.current_age = 2
	var parts := _setup_full(_plague_config())
	var mgr: Node = parts.mgr
	mgr._on_age_advanced(2)
	assert_bool(mgr._plague_fired).is_false()
	assert_bool(mgr.is_plague_active()).is_false()


func test_plague_fires_on_correct_age() -> void:
	GameManager.current_age = 3
	var parts := _setup_full(_plague_config())
	var mgr: Node = parts.mgr
	# With delay [0,0], plague fires immediately on next tick
	mgr._on_age_advanced(3)
	assert_bool(mgr._plague_fired).is_true()
	# Tick to trigger delay timer → should start plague
	mgr._tick_plague_delay(1.0)
	assert_bool(mgr.is_plague_active()).is_true()


func test_plague_fires_only_once() -> void:
	GameManager.current_age = 3
	var parts := _setup_full(_plague_config())
	var mgr: Node = parts.mgr
	mgr._on_age_advanced(3)
	mgr._tick_plague_delay(1.0)
	assert_bool(mgr.is_plague_active()).is_true()
	# End plague
	mgr._end_black_plague()
	assert_bool(mgr.is_plague_active()).is_false()
	# Advancing age again should not re-fire
	mgr._on_age_advanced(4)
	mgr._tick_plague_delay(1.0)
	assert_bool(mgr.is_plague_active()).is_false()


func test_plague_affects_all_players() -> void:
	GameManager.current_age = 3
	var parts := _setup_full(_plague_config())
	var mgr: Node = parts.mgr
	_create_mock_villager(0)
	_create_mock_villager(1)
	var signals_received: Array = []
	mgr.event_started.connect(func(eid: String, pid: int) -> void: signals_received.append([eid, pid]))
	mgr._on_age_advanced(3)
	mgr._tick_plague_delay(1.0)
	# Both players should have received the event
	var pids: Array = []
	for sig: Array in signals_received:
		if sig[0] == "black_plague":
			pids.append(sig[1])
	assert_bool(0 in pids).is_true()
	assert_bool(1 in pids).is_true()


# =====================================================
# Black Plague — Effects
# =====================================================


func test_plague_work_rate_penalty() -> void:
	GameManager.current_age = 3
	var parts := _setup_full(_plague_config())
	var mgr: Node = parts.mgr
	var v := _create_mock_villager(0, 1.0)
	mgr._on_age_advanced(3)
	mgr._tick_plague_delay(1.0)
	# penalty = -0.50 → gather rate = 1.0 + (-0.50) = 0.50
	assert_float(v._gather_rate_multiplier).is_equal_approx(0.50, 0.01)


func test_plague_death_rolls() -> void:
	GameManager.current_age = 3
	var cfg := _plague_config()
	cfg.events.black_plague.effects.villager_death_chance = 1.0
	var parts := _setup_full(cfg)
	var mgr: Node = parts.mgr
	var v := _create_mock_villager(0)
	mgr._on_age_advanced(3)
	mgr._tick_plague_delay(1.0)
	# Force death roll
	mgr._roll_plague_deaths(cfg.events.black_plague.effects)
	assert_int(v.hp).is_less_equal(0)


func test_plague_military_hp_drain() -> void:
	GameManager.current_age = 3
	var parts := _setup_full(_plague_config())
	var mgr: Node = parts.mgr
	var mil := _create_mock_military(0)
	mgr._on_age_advanced(3)
	mgr._tick_plague_delay(1.0)
	var original_hp: int = mil.hp
	# Drain for 5 seconds at 2 hp/s = 10 hp
	mgr._drain_military_hp(5.0, 2.0)
	assert_int(mil.hp).is_less(original_hp)


func test_plague_trade_penalty() -> void:
	GameManager.current_age = 3
	var parts := _setup_full(_plague_config())
	var mgr: Node = parts.mgr
	var trade: Node = parts.trade
	mgr._on_age_advanced(3)
	mgr._tick_plague_delay(1.0)
	# Trade multiplier should be 0.25 (1.0 + (-0.75))
	var mult: float = trade._trade_income_multiplier.get(0, 1.0)
	assert_float(mult).is_equal_approx(0.25, 0.01)


# =====================================================
# Black Plague — Tech Mitigations
# =====================================================


func test_herbalism_reduces_death_chance() -> void:
	GameManager.current_age = 3
	var cfg := _plague_config()
	cfg.events.black_plague.effects.villager_death_chance = 1.0
	var parts := _setup_full(cfg)
	var mgr: Node = parts.mgr
	var tech: Node = parts.tech
	_mark_researched(tech, "herbalism", 0)
	mgr._on_age_advanced(3)
	mgr._tick_plague_delay(1.0)
	# Herbalism: death -30% → effective = 0.70
	var pstate: RefCounted = mgr._plague_states.get(0)
	assert_object(pstate).is_not_null()
	assert_float(pstate.death_chance_reduction).is_equal_approx(0.30, 0.01)


func test_sanitation_reduces_work_penalty() -> void:
	GameManager.current_age = 3
	var parts := _setup_full(_plague_config())
	var mgr: Node = parts.mgr
	var tech: Node = parts.tech
	_mark_researched(tech, "sanitation", 0)
	var v := _create_mock_villager(0, 1.0)
	mgr._on_age_advanced(3)
	mgr._tick_plague_delay(1.0)
	# Sanitation: work penalty reduced 40% → effective penalty = -0.50 * (1 - 0.40) = -0.30
	# gather rate = 1.0 + (-0.30) = 0.70
	assert_float(v._gather_rate_multiplier).is_equal_approx(0.70, 0.01)


func test_vaccines_grant_immunity() -> void:
	GameManager.current_age = 3
	var parts := _setup_full(_plague_config())
	var mgr: Node = parts.mgr
	var tech: Node = parts.tech
	_mark_researched(tech, "vaccines", 0)
	var v := _create_mock_villager(0, 1.0)
	var end_signals: Array = []
	mgr.event_ended.connect(func(eid: String, pid: int) -> void: end_signals.append([eid, pid]))
	mgr._on_age_advanced(3)
	mgr._tick_plague_delay(1.0)
	# Villager should be unaffected
	assert_float(v._gather_rate_multiplier).is_equal_approx(1.0, 0.01)
	# Player 0 should get immediate start+end (immune)
	var p0_end: bool = false
	for sig: Array in end_signals:
		if sig[0] == "black_plague" and sig[1] == 0:
			p0_end = true
	assert_bool(p0_end).is_true()


# =====================================================
# Plague Aftermath
# =====================================================


func test_aftermath_bonuses_applied() -> void:
	GameManager.current_age = 3
	var parts := _setup_full(_plague_config())
	var mgr: Node = parts.mgr
	var tech: Node = parts.tech
	var v := _create_mock_villager(0, 1.0)
	mgr._on_age_advanced(3)
	mgr._tick_plague_delay(1.0)
	# End plague for player 0
	mgr._end_plague_for_player(0)
	# Aftermath: work rate +0.15 → 1.0 + 0.15 = 1.15
	assert_float(v._gather_rate_multiplier).is_equal_approx(1.15, 0.01)
	assert_bool(mgr.is_aftermath_active(0)).is_true()
	# Research bonus should be set
	var event_bonus: float = tech._event_research_bonus.get(0, 0.0)
	assert_float(event_bonus).is_equal_approx(0.20, 0.01)


func test_aftermath_expires_after_duration() -> void:
	GameManager.current_age = 3
	var parts := _setup_full(_plague_config())
	var mgr: Node = parts.mgr
	var tech: Node = parts.tech
	var v := _create_mock_villager(0, 1.0)
	mgr._on_age_advanced(3)
	mgr._tick_plague_delay(1.0)
	mgr._end_plague_for_player(0)
	assert_bool(mgr.is_aftermath_active(0)).is_true()
	# Tick past aftermath duration (120s)
	mgr._tick_aftermath(121.0)
	assert_bool(mgr.is_aftermath_active(0)).is_false()
	# Work rate bonus removed: 1.15 - 0.15 = 1.0
	assert_float(v._gather_rate_multiplier).is_equal_approx(1.0, 0.01)
	# Research bonus cleared
	assert_bool(tech._event_research_bonus.has(0)).is_false()


# =====================================================
# Renaissance — Triggers
# =====================================================


func test_renaissance_requires_all_techs() -> void:
	GameManager.current_age = 3
	var parts := _setup_full(_renaissance_config())
	var mgr: Node = parts.mgr
	var tech: Node = parts.tech
	# Only 2 of 3 techs
	_mark_researched(tech, "printing_press", 0)
	_mark_researched(tech, "banking", 0)
	mgr._check_renaissance(0)
	assert_bool(mgr.is_renaissance_active(0)).is_false()


func test_renaissance_requires_minimum_age() -> void:
	GameManager.current_age = 2
	var parts := _setup_full(_renaissance_config())
	var mgr: Node = parts.mgr
	var tech: Node = parts.tech
	_mark_researched(tech, "printing_press", 0)
	_mark_researched(tech, "banking", 0)
	_mark_researched(tech, "guilds", 0)
	mgr._check_renaissance(0)
	assert_bool(mgr.is_renaissance_active(0)).is_false()


func test_renaissance_triggers_with_all_conditions() -> void:
	GameManager.current_age = 3
	var parts := _setup_full(_renaissance_config())
	var mgr: Node = parts.mgr
	var tech: Node = parts.tech
	_mark_researched(tech, "printing_press", 0)
	_mark_researched(tech, "banking", 0)
	_mark_researched(tech, "guilds", 0)
	var signals_received: Array = []
	mgr.event_started.connect(func(eid: String, pid: int) -> void: signals_received.append([eid, pid]))
	mgr._check_renaissance(0)
	assert_bool(mgr.is_renaissance_active(0)).is_true()
	var found: bool = false
	for sig: Array in signals_received:
		if sig[0] == "renaissance" and sig[1] == 0:
			found = true
	assert_bool(found).is_true()


func test_renaissance_once_per_player() -> void:
	GameManager.current_age = 3
	var parts := _setup_full(_renaissance_config())
	var mgr: Node = parts.mgr
	var tech: Node = parts.tech
	_mark_researched(tech, "printing_press", 0)
	_mark_researched(tech, "banking", 0)
	_mark_researched(tech, "guilds", 0)
	mgr._check_renaissance(0)
	assert_bool(mgr.is_renaissance_active(0)).is_true()
	# End it
	mgr._end_renaissance(0)
	assert_bool(mgr.is_renaissance_active(0)).is_false()
	# Try to trigger again — should not fire
	mgr._check_renaissance(0)
	assert_bool(mgr.is_renaissance_active(0)).is_false()


# =====================================================
# Renaissance — Effects
# =====================================================


func test_renaissance_research_speed_bonus() -> void:
	GameManager.current_age = 3
	var parts := _setup_full(_renaissance_config())
	var mgr: Node = parts.mgr
	var tech: Node = parts.tech
	_mark_researched(tech, "printing_press", 0)
	_mark_researched(tech, "banking", 0)
	_mark_researched(tech, "guilds", 0)
	mgr._check_renaissance(0)
	var event_bonus: float = tech._event_research_bonus.get(0, 0.0)
	assert_float(event_bonus).is_equal_approx(0.35, 0.01)


func test_renaissance_gold_income_bonus() -> void:
	GameManager.current_age = 3
	var parts := _setup_full(_renaissance_config())
	var mgr: Node = parts.mgr
	var tech: Node = parts.tech
	var trade: Node = parts.trade
	_mark_researched(tech, "printing_press", 0)
	_mark_researched(tech, "banking", 0)
	_mark_researched(tech, "guilds", 0)
	mgr._check_renaissance(0)
	# Trade multiplier should be 1.0 + 0.20 = 1.20
	var mult: float = trade._trade_income_multiplier.get(0, 1.0)
	assert_float(mult).is_equal_approx(1.20, 0.01)


func test_renaissance_library_bonus() -> void:
	GameManager.current_age = 3
	var parts := _setup_full(_renaissance_config())
	var mgr: Node = parts.mgr
	var tech: Node = parts.tech
	var bp: Node = parts.bp
	_mark_researched(tech, "printing_press", 0)
	_mark_researched(tech, "banking", 0)
	_mark_researched(tech, "guilds", 0)
	for i in 3:
		var bld := MockBuilding.new()
		bld.owner_id = 0
		bld.grid_pos = Vector2i(i, 0)
		add_child(bld)
		auto_free(bld)
		bp._placed_buildings.append({"node": bld, "building_name": "library"})
	mgr._check_renaissance(0)
	# Research bonus should be 0.35 + 0.25 = 0.60
	var event_bonus: float = tech._event_research_bonus.get(0, 0.0)
	assert_float(event_bonus).is_equal_approx(0.60, 0.01)


func test_renaissance_market_bonus() -> void:
	GameManager.current_age = 3
	var parts := _setup_full(_renaissance_config())
	var mgr: Node = parts.mgr
	var tech: Node = parts.tech
	var trade: Node = parts.trade
	var bp: Node = parts.bp
	_mark_researched(tech, "printing_press", 0)
	_mark_researched(tech, "banking", 0)
	_mark_researched(tech, "guilds", 0)
	for i in 2:
		var bld := MockBuilding.new()
		bld.owner_id = 0
		bld.grid_pos = Vector2i(i, 0)
		add_child(bld)
		auto_free(bld)
		bp._placed_buildings.append({"node": bld, "building_name": "market"})
	mgr._check_renaissance(0)
	# Trade multiplier should be 1.0 + 0.20 + 0.15 = 1.35
	var mult: float = trade._trade_income_multiplier.get(0, 1.0)
	assert_float(mult).is_equal_approx(1.35, 0.01)


func test_renaissance_ends_after_duration() -> void:
	GameManager.current_age = 3
	var parts := _setup_full(_renaissance_config())
	var mgr: Node = parts.mgr
	var tech: Node = parts.tech
	var trade: Node = parts.trade
	_mark_researched(tech, "printing_press", 0)
	_mark_researched(tech, "banking", 0)
	_mark_researched(tech, "guilds", 0)
	mgr._check_renaissance(0)
	assert_bool(mgr.is_renaissance_active(0)).is_true()
	# Tick past duration (180s)
	mgr._tick_renaissance(181.0)
	assert_bool(mgr.is_renaissance_active(0)).is_false()
	# Research bonus cleared
	assert_bool(tech._event_research_bonus.has(0)).is_false()
	# Trade multiplier cleared
	assert_bool(trade._trade_income_multiplier.has(0)).is_false()


# =====================================================
# Phoenix Interaction
# =====================================================


func test_phoenix_bonus_within_window() -> void:
	GameManager.current_age = 3
	GameManager.game_time = 1000.0
	var parts := _setup_full(_renaissance_config())
	var mgr: Node = parts.mgr
	var tech: Node = parts.tech
	# Simulate plague ending at game_time 1000
	mgr._plague_end_times[0] = 1000.0
	_mark_researched(tech, "printing_press", 0)
	_mark_researched(tech, "banking", 0)
	_mark_researched(tech, "guilds", 0)
	# Renaissance at game_time 1000 (0s after plague) — within 120s window
	mgr._check_renaissance(0)
	assert_bool(mgr.is_phoenix_active(0)).is_true()
	# Research bonus should be 0.35 * 1.5 = 0.525
	var event_bonus: float = tech._event_research_bonus.get(0, 0.0)
	assert_float(event_bonus).is_equal_approx(0.525, 0.01)


func test_phoenix_not_triggered_outside_window() -> void:
	GameManager.current_age = 3
	GameManager.game_time = 1200.0
	var parts := _setup_full(_renaissance_config())
	var mgr: Node = parts.mgr
	var tech: Node = parts.tech
	# Plague ended 200s ago — outside 120s window
	mgr._plague_end_times[0] = 1000.0
	_mark_researched(tech, "printing_press", 0)
	_mark_researched(tech, "banking", 0)
	_mark_researched(tech, "guilds", 0)
	mgr._check_renaissance(0)
	assert_bool(mgr.is_phoenix_active(0)).is_false()
	# Normal research bonus (no phoenix multiplier)
	var event_bonus: float = tech._event_research_bonus.get(0, 0.0)
	assert_float(event_bonus).is_equal_approx(0.35, 0.01)


# =====================================================
# Save / Load
# =====================================================


func test_save_load_roundtrip() -> void:
	GameManager.current_age = 3
	GameManager.game_time = 500.0
	var parts := _setup_full(_renaissance_config())
	var mgr: Node = parts.mgr
	# Set up some state
	mgr._plague_fired = true
	mgr._plague_end_times[0] = 450.0
	var astate := HistoricalEventManager.AftermathState.new()
	astate.timer = 60.0
	mgr._aftermath_states[0] = astate
	var rstate := HistoricalEventManager.RenaissanceState.new()
	rstate.triggered = true
	rstate.active = true
	rstate.timer = 120.0
	rstate.phoenix = true
	mgr._renaissance_states[0] = rstate
	var state: Dictionary = mgr.save_state()
	# Create fresh manager and load
	var mgr2 := _create_manager()
	mgr2._config = _renaissance_config()
	mgr2.load_state(state)
	assert_bool(mgr2._plague_fired).is_true()
	assert_float(mgr2._plague_end_times.get(0, 0.0)).is_equal_approx(450.0, 0.1)
	assert_bool(mgr2._aftermath_states.has(0)).is_true()
	assert_float(mgr2._aftermath_states[0].timer).is_equal_approx(60.0, 0.1)
	assert_bool(mgr2._renaissance_states.has(0)).is_true()
	assert_bool(mgr2._renaissance_states[0].triggered).is_true()
	assert_bool(mgr2._renaissance_states[0].active).is_true()
	assert_float(mgr2._renaissance_states[0].timer).is_equal_approx(120.0, 0.1)
	assert_bool(mgr2._renaissance_states[0].phoenix).is_true()


func test_save_load_plague_active_state() -> void:
	GameManager.current_age = 3
	var parts := _setup_full(_plague_config())
	var mgr: Node = parts.mgr
	_create_mock_villager(0)
	mgr._on_age_advanced(3)
	mgr._tick_plague_delay(1.0)
	assert_bool(mgr.is_plague_active()).is_true()
	var state: Dictionary = mgr.save_state()
	assert_bool(bool(state.get("plague_active", false))).is_true()
	assert_float(float(state.get("plague_timer", 0.0))).is_greater(0.0)
	# Load into fresh manager
	var mgr2 := _create_manager()
	mgr2._config = _plague_config()
	mgr2.load_state(state)
	assert_bool(mgr2._plague_active).is_true()
	assert_bool(mgr2._plague_fired).is_true()
