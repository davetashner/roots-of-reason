extends GdUnitTestSuite
## Integration tests for Wonder victory countdown with defense mechanics.
## Verifies countdown start, pause on damage, resume on repair, reset on
## destruction, and victory trigger on completion.

const VictoryManagerScript := preload("res://scripts/prototype/victory_manager.gd")

var _victory_ids: Array = []
var _victory_conditions: Array = []
var _wonder_started_ids: Array = []
var _wonder_cancelled_ids: Array = []
var _wonder_paused_ids: Array = []
var _wonder_resumed_ids: Array = []


func _reset_signals() -> void:
	_victory_ids.clear()
	_victory_conditions.clear()
	_wonder_started_ids.clear()
	_wonder_cancelled_ids.clear()
	_wonder_paused_ids.clear()
	_wonder_resumed_ids.clear()


func _on_player_victorious(pid: int, condition: String) -> void:
	_victory_ids.append(pid)
	_victory_conditions.append(condition)


func _on_wonder_started(pid: int, _duration: float) -> void:
	_wonder_started_ids.append(pid)


func _on_wonder_cancelled(pid: int) -> void:
	_wonder_cancelled_ids.append(pid)


func _on_wonder_paused(pid: int) -> void:
	_wonder_paused_ids.append(pid)


func _on_wonder_resumed(pid: int) -> void:
	_wonder_resumed_ids.append(pid)


class MockBuilding:
	extends Node2D
	signal construction_complete(building: Node2D)
	signal building_destroyed(building: Node2D)
	var building_name: String = ""
	var grid_pos: Vector2i = Vector2i.ZERO
	var owner_id: int = 0
	var under_construction: bool = false
	var hp: int = 5000
	var max_hp: int = 5000
	var last_attacker_id: int = -1


func _create_manager() -> Node:
	var mgr := Node.new()
	mgr.name = "VictoryManager"
	mgr.set_script(VictoryManagerScript)
	add_child(mgr)
	auto_free(mgr)
	# Use short durations for deterministic tests
	mgr._wonder_countdown_duration = 600.0
	mgr._wonder_hp_pause_threshold = 0.5
	mgr._defeat_delay = 0.0
	_reset_signals()
	mgr.player_victorious.connect(_on_player_victorious)
	mgr.wonder_countdown_started.connect(_on_wonder_started)
	mgr.wonder_countdown_cancelled.connect(_on_wonder_cancelled)
	mgr.wonder_countdown_paused.connect(_on_wonder_paused)
	mgr.wonder_countdown_resumed.connect(_on_wonder_resumed)
	return mgr


func _create_tc(pid: int) -> Node2D:
	var b := MockBuilding.new()
	b.building_name = "town_center"
	b.owner_id = pid
	add_child(b)
	auto_free(b)
	return b


func _create_wonder(pid: int, hp_val: int = 5000, max_hp_val: int = 5000) -> Node2D:
	var b := MockBuilding.new()
	b.building_name = "wonder"
	b.owner_id = pid
	b.hp = hp_val
	b.max_hp = max_hp_val
	add_child(b)
	auto_free(b)
	return b


# --- Test 1: Wonder build starts countdown ---


func test_wonder_build_starts_countdown() -> void:
	var mgr := _create_manager()
	var tc := _create_tc(0)
	mgr.register_town_center(0, tc)
	var wonder := _create_wonder(0)

	mgr.start_wonder_countdown(0, wonder)

	assert_array(_wonder_started_ids).contains([0])
	assert_float(mgr.get_wonder_countdown_remaining(0)).is_equal_approx(600.0, 0.1)
	assert_bool(mgr.is_wonder_countdown_paused(0)).is_false()


# --- Test 2: Wonder damage pauses countdown ---


func test_wonder_damage_pauses_countdown() -> void:
	var mgr := _create_manager()
	var tc := _create_tc(0)
	mgr.register_town_center(0, tc)
	var wonder := _create_wonder(0)
	mgr.start_wonder_countdown(0, wonder)

	# Tick a bit so countdown is running
	mgr._tick_wonder_countdowns(10.0)
	assert_float(mgr.get_wonder_countdown_remaining(0)).is_equal_approx(590.0, 0.1)

	# Damage below 50% HP (2499/5000 = 49.98%)
	wonder.hp = 2499
	mgr.on_wonder_hp_changed(0, wonder.hp, wonder.max_hp)

	assert_bool(mgr.is_wonder_countdown_paused(0)).is_true()
	assert_array(_wonder_paused_ids).contains([0])

	# Tick while paused — remaining should not change
	var remaining_before: float = mgr.get_wonder_countdown_remaining(0)
	mgr._tick_wonder_countdowns(100.0)
	assert_float(mgr.get_wonder_countdown_remaining(0)).is_equal_approx(remaining_before, 0.01)


# --- Test 3: Wonder repair resumes countdown ---


func test_wonder_repair_resumes_countdown() -> void:
	var mgr := _create_manager()
	var tc := _create_tc(0)
	mgr.register_town_center(0, tc)
	var wonder := _create_wonder(0)
	mgr.start_wonder_countdown(0, wonder)

	# Damage to pause
	wonder.hp = 2000
	mgr.on_wonder_hp_changed(0, wonder.hp, wonder.max_hp)
	assert_bool(mgr.is_wonder_countdown_paused(0)).is_true()

	# Repair above 50% (2500/5000 = exactly 50% — still below threshold)
	wonder.hp = 2500
	mgr.on_wonder_hp_changed(0, wonder.hp, wonder.max_hp)
	# 2500/5000 = 0.5 which is NOT < 0.5, so it should resume
	assert_bool(mgr.is_wonder_countdown_paused(0)).is_false()
	assert_array(_wonder_resumed_ids).contains([0])

	# Tick should now reduce remaining
	var remaining_before: float = mgr.get_wonder_countdown_remaining(0)
	mgr._tick_wonder_countdowns(5.0)
	assert_float(mgr.get_wonder_countdown_remaining(0)).is_less(remaining_before)


# --- Test 4: Wonder destroyed resets countdown ---


func test_wonder_destroyed_resets_countdown() -> void:
	var mgr := _create_manager()
	var tc := _create_tc(0)
	mgr.register_town_center(0, tc)
	var wonder := _create_wonder(0)
	mgr.start_wonder_countdown(0, wonder)

	assert_float(mgr.get_wonder_countdown_remaining(0)).is_greater(0.0)

	# Destroy the wonder
	mgr.cancel_wonder_countdown(0)

	assert_array(_wonder_cancelled_ids).contains([0])
	assert_float(mgr.get_wonder_countdown_remaining(0)).is_equal(-1.0)

	# Ticking should not trigger victory
	mgr._tick_wonder_countdowns(700.0)
	assert_array(_victory_ids).is_empty()


# --- Test 5: Countdown completes triggers victory ---


func test_wonder_countdown_completes_victory() -> void:
	var mgr := _create_manager()
	var tc := _create_tc(0)
	mgr.register_town_center(0, tc)
	var wonder := _create_wonder(0)
	mgr.start_wonder_countdown(0, wonder)

	# Tick the full duration
	mgr._tick_wonder_countdowns(600.1)

	assert_array(_victory_ids).contains([0])
	assert_array(_victory_conditions).contains(["wonder"])
	assert_bool(mgr.is_game_over()).is_true()
	var result: Dictionary = mgr.get_game_result()
	assert_int(result.get("winner", -1)).is_equal(0)
	assert_str(result.get("condition", "")).is_equal("wonder")


# --- Additional edge case tests ---


func test_wonder_pause_resume_multiple_cycles() -> void:
	## Verify multiple damage/repair cycles correctly pause and resume.
	var mgr := _create_manager()
	var tc := _create_tc(0)
	mgr.register_town_center(0, tc)
	var wonder := _create_wonder(0)
	mgr.start_wonder_countdown(0, wonder)

	# Tick 100s
	mgr._tick_wonder_countdowns(100.0)
	assert_float(mgr.get_wonder_countdown_remaining(0)).is_equal_approx(500.0, 0.1)

	# First damage cycle — pause
	wonder.hp = 1000
	mgr.on_wonder_hp_changed(0, wonder.hp, wonder.max_hp)
	assert_bool(mgr.is_wonder_countdown_paused(0)).is_true()

	# Tick while paused (no change)
	mgr._tick_wonder_countdowns(50.0)
	assert_float(mgr.get_wonder_countdown_remaining(0)).is_equal_approx(500.0, 0.1)

	# Repair — resume
	wonder.hp = 4000
	mgr.on_wonder_hp_changed(0, wonder.hp, wonder.max_hp)
	assert_bool(mgr.is_wonder_countdown_paused(0)).is_false()

	# Second damage cycle — pause again
	wonder.hp = 2000
	mgr.on_wonder_hp_changed(0, wonder.hp, wonder.max_hp)
	assert_bool(mgr.is_wonder_countdown_paused(0)).is_true()

	# Repair — resume
	wonder.hp = 3000
	mgr.on_wonder_hp_changed(0, wonder.hp, wonder.max_hp)
	assert_bool(mgr.is_wonder_countdown_paused(0)).is_false()

	# Tick remaining 500s
	mgr._tick_wonder_countdowns(500.1)
	assert_array(_victory_ids).contains([0])
	assert_array(_victory_conditions).contains(["wonder"])


func test_wonder_destroyed_while_paused_cancels() -> void:
	## Destroying a wonder that is paused should cancel the countdown.
	var mgr := _create_manager()
	var tc := _create_tc(0)
	mgr.register_town_center(0, tc)
	var wonder := _create_wonder(0)
	mgr.start_wonder_countdown(0, wonder)

	# Pause via damage
	wonder.hp = 100
	mgr.on_wonder_hp_changed(0, wonder.hp, wonder.max_hp)
	assert_bool(mgr.is_wonder_countdown_paused(0)).is_true()

	# Destroy
	mgr.cancel_wonder_countdown(0)
	assert_float(mgr.get_wonder_countdown_remaining(0)).is_equal(-1.0)
	assert_bool(mgr.is_wonder_countdown_paused(0)).is_false()


func test_wonder_hp_at_exactly_threshold_not_paused() -> void:
	## HP at exactly 50% should NOT pause (only strictly below threshold).
	var mgr := _create_manager()
	var tc := _create_tc(0)
	mgr.register_town_center(0, tc)
	var wonder := _create_wonder(0)
	mgr.start_wonder_countdown(0, wonder)

	# Set HP to exactly 50%
	wonder.hp = 2500
	mgr.on_wonder_hp_changed(0, wonder.hp, wonder.max_hp)
	assert_bool(mgr.is_wonder_countdown_paused(0)).is_false()
	assert_array(_wonder_paused_ids).is_empty()


func test_wonder_pause_state_save_load_roundtrip() -> void:
	## Paused state should survive save/load.
	var mgr := _create_manager()
	var tc := _create_tc(0)
	mgr.register_town_center(0, tc)
	var wonder := _create_wonder(0)
	mgr.start_wonder_countdown(0, wonder)

	# Tick 200s then pause
	mgr._tick_wonder_countdowns(200.0)
	wonder.hp = 1000
	mgr.on_wonder_hp_changed(0, wonder.hp, wonder.max_hp)
	assert_bool(mgr.is_wonder_countdown_paused(0)).is_true()
	var remaining: float = mgr.get_wonder_countdown_remaining(0)

	# Save
	var state: Dictionary = mgr.save_state()

	# Load into fresh manager
	var mgr2 := _create_manager()
	mgr2.load_state(state)
	assert_bool(mgr2.is_wonder_countdown_paused(0)).is_true()
	assert_float(mgr2.get_wonder_countdown_remaining(0)).is_equal_approx(remaining, 0.1)
