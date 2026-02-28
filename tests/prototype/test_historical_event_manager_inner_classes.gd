extends GdUnitTestSuite
## Round-trip save/load tests for HistoricalEventManager inner classes:
## PlaguePlayerState, AftermathState, RenaissanceState.

const HistoricalEventScript := preload("res://scripts/prototype/historical_event_manager.gd")

# =====================================================
# PlaguePlayerState
# =====================================================


func test_plague_player_state_roundtrip_populated() -> void:
	var state := HistoricalEventManager.PlaguePlayerState.new()
	state.death_chance_reduction = 0.30
	state.duration_remaining = 45.7
	state.original_rates[101] = 1.0
	state.original_rates[202] = 0.75
	state.original_rates[303] = 1.25

	var saved: Dictionary = state.save_data()
	var loaded := HistoricalEventManager.PlaguePlayerState.from_data(saved)

	assert_float(loaded.death_chance_reduction).is_equal_approx(0.30, 0.001)
	assert_float(loaded.duration_remaining).is_equal_approx(45.7, 0.001)
	assert_int(loaded.original_rates.size()).is_equal(3)
	assert_float(loaded.original_rates[101]).is_equal_approx(1.0, 0.001)
	assert_float(loaded.original_rates[202]).is_equal_approx(0.75, 0.001)
	assert_float(loaded.original_rates[303]).is_equal_approx(1.25, 0.001)


func test_plague_player_state_roundtrip_empty_rates() -> void:
	var state := HistoricalEventManager.PlaguePlayerState.new()
	state.death_chance_reduction = 0.50
	state.duration_remaining = 10.0

	var saved: Dictionary = state.save_data()
	var loaded := HistoricalEventManager.PlaguePlayerState.from_data(saved)

	assert_float(loaded.death_chance_reduction).is_equal_approx(0.50, 0.001)
	assert_float(loaded.duration_remaining).is_equal_approx(10.0, 0.001)
	assert_int(loaded.original_rates.size()).is_equal(0)


func test_plague_player_state_rates_keys_survive_string_conversion() -> void:
	## original_rates keys are instance IDs (ints). save_data() converts them to
	## strings for JSON compatibility. from_data() must convert them back to ints.
	var state := HistoricalEventManager.PlaguePlayerState.new()
	state.original_rates[999] = 0.5

	var saved: Dictionary = state.save_data()
	# Verify the saved dict uses string keys
	assert_bool(saved.original_rates.has("999")).is_true()

	var loaded := HistoricalEventManager.PlaguePlayerState.from_data(saved)
	# Verify the loaded dict uses int keys
	assert_bool(loaded.original_rates.has(999)).is_true()
	assert_float(loaded.original_rates[999]).is_equal_approx(0.5, 0.001)


func test_plague_player_state_json_roundtrip() -> void:
	## Verify the state survives a full JSON serialize/deserialize cycle,
	## which converts all numbers to floats.
	var state := HistoricalEventManager.PlaguePlayerState.new()
	state.death_chance_reduction = 0.30
	state.duration_remaining = 45.7
	state.original_rates[101] = 1.0
	state.original_rates[202] = 0.75

	var saved: Dictionary = state.save_data()
	var json_str: String = JSON.stringify(saved)
	var parsed: Dictionary = JSON.parse_string(json_str)
	var loaded := HistoricalEventManager.PlaguePlayerState.from_data(parsed)

	assert_float(loaded.death_chance_reduction).is_equal_approx(0.30, 0.001)
	assert_float(loaded.duration_remaining).is_equal_approx(45.7, 0.001)
	assert_int(loaded.original_rates.size()).is_equal(2)
	assert_float(loaded.original_rates[101]).is_equal_approx(1.0, 0.001)
	assert_float(loaded.original_rates[202]).is_equal_approx(0.75, 0.001)


# =====================================================
# AftermathState
# =====================================================


func test_aftermath_state_roundtrip_populated() -> void:
	var state := HistoricalEventManager.AftermathState.new()
	state.timer = 87.3

	var saved: Dictionary = state.save_data()
	var loaded := HistoricalEventManager.AftermathState.from_data(saved)

	assert_float(loaded.timer).is_equal_approx(87.3, 0.001)


func test_aftermath_state_roundtrip_zero_timer() -> void:
	var state := HistoricalEventManager.AftermathState.new()
	state.timer = 0.0

	var saved: Dictionary = state.save_data()
	var loaded := HistoricalEventManager.AftermathState.from_data(saved)

	assert_float(loaded.timer).is_equal_approx(0.0, 0.001)


func test_aftermath_state_json_roundtrip() -> void:
	## Verify the state survives a full JSON serialize/deserialize cycle.
	var state := HistoricalEventManager.AftermathState.new()
	state.timer = 119.5

	var saved: Dictionary = state.save_data()
	var json_str: String = JSON.stringify(saved)
	var parsed: Dictionary = JSON.parse_string(json_str)
	var loaded := HistoricalEventManager.AftermathState.from_data(parsed)

	assert_float(loaded.timer).is_equal_approx(119.5, 0.001)


# =====================================================
# RenaissanceState
# =====================================================


func test_renaissance_state_roundtrip_populated() -> void:
	var state := HistoricalEventManager.RenaissanceState.new()
	state.triggered = true
	state.active = true
	state.timer = 155.2
	state.phoenix = true

	var saved: Dictionary = state.save_data()
	var loaded := HistoricalEventManager.RenaissanceState.from_data(saved)

	assert_bool(loaded.triggered).is_true()
	assert_bool(loaded.active).is_true()
	assert_float(loaded.timer).is_equal_approx(155.2, 0.001)
	assert_bool(loaded.phoenix).is_true()


func test_renaissance_state_roundtrip_inactive() -> void:
	var state := HistoricalEventManager.RenaissanceState.new()
	state.triggered = true
	state.active = false
	state.timer = 0.0
	state.phoenix = false

	var saved: Dictionary = state.save_data()
	var loaded := HistoricalEventManager.RenaissanceState.from_data(saved)

	assert_bool(loaded.triggered).is_true()
	assert_bool(loaded.active).is_false()
	assert_float(loaded.timer).is_equal_approx(0.0, 0.001)
	assert_bool(loaded.phoenix).is_false()


func test_renaissance_state_roundtrip_all_false() -> void:
	## All booleans false — verify defaults don't mask real values.
	var state := HistoricalEventManager.RenaissanceState.new()
	state.triggered = false
	state.active = false
	state.timer = 42.0
	state.phoenix = false

	var saved: Dictionary = state.save_data()
	var loaded := HistoricalEventManager.RenaissanceState.from_data(saved)

	assert_bool(loaded.triggered).is_false()
	assert_bool(loaded.active).is_false()
	assert_float(loaded.timer).is_equal_approx(42.0, 0.001)
	assert_bool(loaded.phoenix).is_false()


func test_renaissance_state_json_roundtrip() -> void:
	## Verify the state survives a full JSON serialize/deserialize cycle.
	var state := HistoricalEventManager.RenaissanceState.new()
	state.triggered = true
	state.active = true
	state.timer = 155.2
	state.phoenix = true

	var saved: Dictionary = state.save_data()
	var json_str: String = JSON.stringify(saved)
	var parsed: Dictionary = JSON.parse_string(json_str)
	var loaded := HistoricalEventManager.RenaissanceState.from_data(parsed)

	assert_bool(loaded.triggered).is_true()
	assert_bool(loaded.active).is_true()
	assert_float(loaded.timer).is_equal_approx(155.2, 0.001)
	assert_bool(loaded.phoenix).is_true()
