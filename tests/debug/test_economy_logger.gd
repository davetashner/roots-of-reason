extends GdUnitTestSuite
## Tests for economy_logger.gd — static ring buffer for economy deposit events.

const EconomyLoggerScript := preload("res://scripts/debug/economy_logger.gd")


class MockVillager:
	extends Node2D
	var owner_id: int = 0
	var unit_category: String = "villager"


func before_test() -> void:
	EconomyLoggerScript.clear()


func _make_villager(vname: String, oid: int = 0) -> MockVillager:
	var v := MockVillager.new()
	v.name = vname
	v.owner_id = oid
	return auto_free(v)


func _log_deposit(
	vname: String = "Villager_0",
	res_type: String = "wood",
	amount: int = 10,
	player_id: int = 0,
) -> void:
	var v := _make_villager(vname, player_id)
	var extras := {
		"drop_off_building": "lumber_camp",
		"carry_capacity": 10,
		"gather_rate": 0.4,
		"gather_multiplier": 1.0,
	}
	EconomyLoggerScript.log_deposit(v, player_id, res_type, amount, extras)


func test_log_deposit_records_event() -> void:
	_log_deposit()
	var events := EconomyLoggerScript.get_events()
	assert_int(events.size()).is_equal(1)
	var ev: Dictionary = events[0]
	assert_str(ev["unit_name"]).is_equal("Villager_0")
	assert_str(ev["resource_type"]).is_equal("wood")
	assert_int(ev["amount"]).is_equal(10)
	assert_int(ev["player_id"]).is_equal(0)


func test_event_fields_complete() -> void:
	_log_deposit()
	var ev: Dictionary = EconomyLoggerScript.get_events()[0]
	assert_bool(ev.has("timestamp")).is_true()
	assert_bool(ev.has("player_id")).is_true()
	assert_bool(ev.has("resource_type")).is_true()
	assert_bool(ev.has("amount")).is_true()
	assert_bool(ev.has("unit_name")).is_true()
	assert_bool(ev.has("drop_off_building")).is_true()
	assert_bool(ev.has("carry_capacity")).is_true()
	assert_bool(ev.has("gather_rate")).is_true()
	assert_bool(ev.has("gather_multiplier")).is_true()


func test_ring_buffer_capacity() -> void:
	for i in 250:
		_log_deposit("V_%d" % i)
	var events := EconomyLoggerScript.get_events(0)
	assert_int(events.size()).is_equal(EconomyLoggerScript.DEFAULT_CAPACITY)
	assert_str(events[0]["unit_name"]).is_equal("V_50")
	assert_int(EconomyLoggerScript.get_total_logged()).is_equal(250)


func test_get_events_with_limit() -> void:
	for i in 10:
		_log_deposit("V_%d" % i)
	var events := EconomyLoggerScript.get_events(3)
	assert_int(events.size()).is_equal(3)
	assert_str(events[0]["unit_name"]).is_equal("V_7")
	assert_str(events[2]["unit_name"]).is_equal("V_9")


func test_get_events_limit_zero_returns_all() -> void:
	for i in 5:
		_log_deposit("V_%d" % i)
	assert_int(EconomyLoggerScript.get_events(0).size()).is_equal(5)


func test_clear_resets_buffer() -> void:
	_log_deposit()
	assert_int(EconomyLoggerScript.get_events().size()).is_equal(1)
	EconomyLoggerScript.clear()
	assert_int(EconomyLoggerScript.get_events().size()).is_equal(0)
	assert_int(EconomyLoggerScript.get_total_logged()).is_equal(0)


func test_multiple_resource_types() -> void:
	_log_deposit("V_0", "wood", 10)
	_log_deposit("V_1", "food", 8)
	_log_deposit("V_2", "gold", 5)
	var events := EconomyLoggerScript.get_events(0)
	assert_int(events.size()).is_equal(3)
	assert_str(events[0]["resource_type"]).is_equal("wood")
	assert_str(events[1]["resource_type"]).is_equal("food")
	assert_str(events[2]["resource_type"]).is_equal("gold")


func test_get_gather_rates_empty_when_no_events() -> void:
	var rates := EconomyLoggerScript.get_gather_rates(0)
	assert_dict(rates).is_empty()


func test_get_deposits_per_second_zero_when_no_events() -> void:
	var dps := EconomyLoggerScript.get_deposits_per_second(0)
	assert_float(dps).is_equal_approx(0.0, 0.001)


func test_different_players() -> void:
	_log_deposit("V_0", "wood", 10, 0)
	_log_deposit("V_1", "food", 8, 1)
	var events := EconomyLoggerScript.get_events(0)
	assert_int(events.size()).is_equal(2)
	assert_int(events[0]["player_id"]).is_equal(0)
	assert_int(events[1]["player_id"]).is_equal(1)
