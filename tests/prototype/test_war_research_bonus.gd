extends GdUnitTestSuite
## Tests for war_research_bonus.gd — combat-based research speed bonus.

const WarResearchBonusScript := preload("res://scripts/prototype/war_research_bonus.gd")

var _original_age: int
var _original_game_time: float


func before_test() -> void:
	_original_age = GameManager.current_age
	_original_game_time = GameManager.game_time
	GameManager.current_age = 0
	GameManager.is_paused = false
	GameManager.game_speed = 1.0
	GameManager.game_time = 0.0


func after_test() -> void:
	GameManager.current_age = _original_age
	GameManager.is_paused = false
	GameManager.game_speed = 1.0
	GameManager.game_time = _original_game_time


func _create_war_bonus() -> Node:
	var node := Node.new()
	node.set_script(WarResearchBonusScript)
	add_child(node)
	auto_free(node)
	return node


# -- Initial state --


func test_initial_bonus_is_zero() -> void:
	var wb := _create_war_bonus()
	assert_float(wb.get_war_bonus(0)).is_equal(0.0)
	assert_bool(wb.is_bonus_active(0)).is_false()


# -- Combat activation --


func test_combat_activates_bonus() -> void:
	var wb := _create_war_bonus()
	GameManager.current_age = 0
	wb.notify_combat_started(0)
	assert_bool(wb.is_bonus_active(0)).is_true()
	assert_float(wb.get_war_bonus(0)).is_equal_approx(0.05, 0.001)


func test_bonus_scales_by_age() -> void:
	var wb := _create_war_bonus()
	# Age 0 = 0.05
	GameManager.current_age = 0
	wb.notify_combat_started(0)
	assert_float(wb.get_war_bonus(0)).is_equal_approx(0.05, 0.001)
	# Age 4 = 0.30
	GameManager.current_age = 4
	assert_float(wb.get_war_bonus(0)).is_equal_approx(0.30, 0.001)
	# Age 5 = 0.40
	GameManager.current_age = 5
	assert_float(wb.get_war_bonus(0)).is_equal_approx(0.40, 0.001)


# -- Linger timer --


func test_combat_ended_starts_linger() -> void:
	var wb := _create_war_bonus()
	GameManager.current_age = 0
	GameManager.game_time = 100.0
	wb.notify_combat_started(0)
	wb.notify_combat_ended(0)
	# Bonus should still be active (linger period)
	assert_bool(wb.is_bonus_active(0)).is_true()
	assert_float(wb.get_war_bonus(0)).is_equal_approx(0.05, 0.001)


func test_linger_expires_after_timeout() -> void:
	var wb := _create_war_bonus()
	GameManager.current_age = 0
	GameManager.game_time = 100.0
	wb.notify_combat_started(0)
	wb.notify_combat_ended(0)
	# Advance game_time past linger (30s default)
	GameManager.game_time = 131.0
	wb._process(1.0)
	assert_bool(wb.is_bonus_active(0)).is_false()
	assert_float(wb.get_war_bonus(0)).is_equal(0.0)


func test_linger_does_not_expire_before_timeout() -> void:
	var wb := _create_war_bonus()
	GameManager.current_age = 0
	GameManager.game_time = 100.0
	wb.notify_combat_started(0)
	wb.notify_combat_ended(0)
	# Only 20s elapsed — should still be active
	GameManager.game_time = 120.0
	wb._process(1.0)
	assert_bool(wb.is_bonus_active(0)).is_true()


# -- Re-activation --


func test_bonus_reactivates_on_new_combat() -> void:
	var wb := _create_war_bonus()
	GameManager.current_age = 0
	GameManager.game_time = 100.0
	wb.notify_combat_started(0)
	wb.notify_combat_ended(0)
	# Expire the linger
	GameManager.game_time = 131.0
	wb._process(1.0)
	assert_bool(wb.is_bonus_active(0)).is_false()
	# New combat should re-activate
	wb.notify_combat_started(0)
	assert_bool(wb.is_bonus_active(0)).is_true()
	assert_float(wb.get_war_bonus(0)).is_equal_approx(0.05, 0.001)


# -- Signals --


func test_war_bonus_activated_signal() -> void:
	var wb := _create_war_bonus()
	GameManager.current_age = 0
	var monitor := monitor_signals(wb)
	wb.notify_combat_started(0)
	await assert_signal(monitor).is_emitted("war_bonus_activated", [0, 0.05])


func test_war_bonus_expired_signal() -> void:
	var wb := _create_war_bonus()
	GameManager.current_age = 0
	GameManager.game_time = 100.0
	var monitor := monitor_signals(wb)
	wb.notify_combat_started(0)
	wb.notify_combat_ended(0)
	GameManager.game_time = 131.0
	wb._process(1.0)
	await assert_signal(monitor).is_emitted("war_bonus_expired", [0])


# -- Save/load --


func test_save_load_preserves_state() -> void:
	var wb := _create_war_bonus()
	GameManager.current_age = 2
	GameManager.game_time = 50.0
	wb.notify_combat_started(0)
	wb.notify_combat_ended(0)
	var state: Dictionary = wb.save_state()
	assert_bool(state.has("in_combat")).is_true()
	assert_bool(state.has("last_combat_time")).is_true()
	assert_bool(state.has("bonus_active")).is_true()
	assert_bool(state.has("applied_spillovers")).is_true()
	# Load into new instance
	var wb2 := _create_war_bonus()
	wb2.load_state(state)
	assert_bool(wb2.is_bonus_active(0)).is_true()
	assert_float(wb2.get_war_bonus(0)).is_equal_approx(0.10, 0.001)


# -- Spillover --


func test_spillover_applied_on_tech_completion() -> void:
	var wb := _create_war_bonus()
	var tech_data: Dictionary = {"id": "gunpowder", "war_spillover": {"mining_efficiency": 0.10}}
	wb.apply_spillover(0, "gunpowder", tech_data)
	var spillovers: Dictionary = wb.get_applied_spillovers(0)
	assert_float(spillovers.get("mining_efficiency", 0.0)).is_equal_approx(0.10, 0.001)


func test_spillover_signal_emitted() -> void:
	var wb := _create_war_bonus()
	var received: Array = []
	wb.spillover_applied.connect(
		func(pid: int, tid: String, bonuses: Dictionary) -> void:
			received.append({"player_id": pid, "tech_id": tid, "bonuses": bonuses})
	)
	var tech_data: Dictionary = {"id": "rifling", "war_spillover": {"mining_efficiency": 0.15}}
	wb.apply_spillover(0, "rifling", tech_data)
	assert_int(received.size()).is_equal(1)
	assert_int(received[0]["player_id"]).is_equal(0)
	assert_str(received[0]["tech_id"]).is_equal("rifling")


func test_spillover_accumulates() -> void:
	var wb := _create_war_bonus()
	var tech_data1: Dictionary = {"id": "gunpowder", "war_spillover": {"mining_efficiency": 0.10}}
	var tech_data2: Dictionary = {"id": "rifling", "war_spillover": {"mining_efficiency": 0.15}}
	wb.apply_spillover(0, "gunpowder", tech_data1)
	wb.apply_spillover(0, "rifling", tech_data2)
	var spillovers: Dictionary = wb.get_applied_spillovers(0)
	assert_float(spillovers.get("mining_efficiency", 0.0)).is_equal_approx(0.25, 0.001)


# -- Multiple players --


func test_multiple_players_independent() -> void:
	var wb := _create_war_bonus()
	GameManager.current_age = 0
	wb.notify_combat_started(0)
	assert_bool(wb.is_bonus_active(0)).is_true()
	assert_bool(wb.is_bonus_active(1)).is_false()
	wb.notify_combat_started(1)
	assert_bool(wb.is_bonus_active(1)).is_true()
