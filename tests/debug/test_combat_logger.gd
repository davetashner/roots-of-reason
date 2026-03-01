extends GdUnitTestSuite
## Tests for combat_logger.gd — static ring buffer for combat damage events.

const CombatLoggerScript := preload("res://scripts/debug/combat_logger.gd")


class MockCombatUnit:
	extends Node2D
	var owner_id: int = 0
	var unit_type: String = "infantry"


func before_test() -> void:
	CombatLoggerScript.clear()


func _make_unit(unit_name: String, oid: int) -> MockCombatUnit:
	var u := MockCombatUnit.new()
	u.name = unit_name
	u.owner_id = oid
	u.global_position = Vector2(100, 200)
	return auto_free(u)


func _log_one(attacker_name: String = "Attacker", defender_name: String = "Defender", damage: int = 10) -> void:
	var atk := _make_unit(attacker_name, 0)
	var dfn := _make_unit(defender_name, 1)
	var atk_stats := {"attack": 15.0, "attack_type": "melee", "unit_type": "infantry"}
	var def_stats := {"defense": 5.0, "armor_type": "light", "unit_type": "infantry"}
	var extras := {"hp_before": 50, "hp_after": 40, "max_hp": 50}
	CombatLoggerScript.log_damage(atk, dfn, damage, atk_stats, def_stats, extras)


func test_log_damage_records_event() -> void:
	_log_one()
	var events := CombatLoggerScript.get_events()
	assert_int(events.size()).is_equal(1)
	var ev: Dictionary = events[0]
	assert_str(ev["attacker"]["name"]).is_equal("Attacker")
	assert_str(ev["defender"]["name"]).is_equal("Defender")
	assert_int(ev["damage"]["final"]).is_equal(10)
	assert_str(ev["outcome"]).is_equal("hit")


func test_event_fields_complete() -> void:
	_log_one()
	var ev: Dictionary = CombatLoggerScript.get_events()[0]
	# Attacker fields
	assert_bool(ev["attacker"].has("name")).is_true()
	assert_bool(ev["attacker"].has("owner_id")).is_true()
	assert_bool(ev["attacker"].has("unit_type")).is_true()
	assert_bool(ev["attacker"].has("attack")).is_true()
	assert_bool(ev["attacker"].has("attack_type")).is_true()
	assert_bool(ev["attacker"].has("position")).is_true()
	# Defender fields
	assert_bool(ev["defender"].has("hp_before")).is_true()
	assert_bool(ev["defender"].has("hp_after")).is_true()
	assert_bool(ev["defender"].has("max_hp")).is_true()
	assert_bool(ev["defender"].has("armor_type")).is_true()
	# Damage fields
	assert_bool(ev["damage"].has("final")).is_true()
	assert_bool(ev["damage"].has("raw_attack")).is_true()
	assert_bool(ev["damage"].has("raw_defense")).is_true()
	assert_bool(ev["damage"].has("overkill")).is_true()


func test_lethal_outcome() -> void:
	var atk := _make_unit("Atk", 0)
	var dfn := _make_unit("Dfn", 1)
	var atk_stats := {"attack": 20.0, "attack_type": "melee", "unit_type": "infantry"}
	var def_stats := {"defense": 5.0, "unit_type": "infantry"}
	var extras := {"hp_before": 10, "hp_after": 0, "max_hp": 50}
	CombatLoggerScript.log_damage(atk, dfn, 15, atk_stats, def_stats, extras)
	var ev: Dictionary = CombatLoggerScript.get_events()[0]
	assert_str(ev["outcome"]).is_equal("lethal")
	assert_int(ev["damage"]["overkill"]).is_equal(5)


func test_war_survival_outcome() -> void:
	var atk := _make_unit("Atk", 0)
	var dfn := _make_unit("Dfn", 1)
	var atk_stats := {"attack": 20.0, "attack_type": "melee", "unit_type": "infantry"}
	var def_stats := {"defense": 5.0, "unit_type": "infantry"}
	var extras := {"hp_before": 10, "hp_after": 1, "max_hp": 50, "war_survived": true}
	CombatLoggerScript.log_damage(atk, dfn, 15, atk_stats, def_stats, extras)
	assert_str(CombatLoggerScript.get_events()[0]["outcome"]).is_equal("survived")


func test_ring_buffer_capacity() -> void:
	for i in 250:
		_log_one("Atk_%d" % i, "Dfn_%d" % i)
	var events := CombatLoggerScript.get_events(0)
	assert_int(events.size()).is_equal(CombatLoggerScript.DEFAULT_CAPACITY)
	# First event should be the one logged at index 50 (250 - 200)
	assert_str(events[0]["attacker"]["name"]).is_equal("Atk_50")
	assert_int(CombatLoggerScript.get_total_logged()).is_equal(250)


func test_get_events_with_limit() -> void:
	for i in 10:
		_log_one("Atk_%d" % i)
	var events := CombatLoggerScript.get_events(3)
	assert_int(events.size()).is_equal(3)
	# Should be the 3 most recent
	assert_str(events[0]["attacker"]["name"]).is_equal("Atk_7")
	assert_str(events[2]["attacker"]["name"]).is_equal("Atk_9")


func test_get_events_limit_zero_returns_all() -> void:
	for i in 5:
		_log_one("Atk_%d" % i)
	assert_int(CombatLoggerScript.get_events(0).size()).is_equal(5)


func test_get_events_limit_exceeds_size() -> void:
	_log_one()
	assert_int(CombatLoggerScript.get_events(100).size()).is_equal(1)


func test_clear_resets_buffer() -> void:
	_log_one()
	assert_int(CombatLoggerScript.get_events().size()).is_equal(1)
	CombatLoggerScript.clear()
	assert_int(CombatLoggerScript.get_events().size()).is_equal(0)
	assert_int(CombatLoggerScript.get_total_logged()).is_equal(0)


func test_event_ordering() -> void:
	for i in 5:
		_log_one("Atk_%d" % i)
	var events := CombatLoggerScript.get_events()
	for i in events.size() - 1:
		# Each event should have a timestamp >= the previous
		assert_bool(events[i + 1]["timestamp"] >= events[i]["timestamp"]).is_true()


func test_overkill_zero_when_no_excess() -> void:
	var atk := _make_unit("Atk", 0)
	var dfn := _make_unit("Dfn", 1)
	var atk_stats := {"attack": 10.0, "attack_type": "melee", "unit_type": "infantry"}
	var def_stats := {"defense": 5.0, "unit_type": "infantry"}
	var extras := {"hp_before": 50, "hp_after": 45, "max_hp": 50}
	CombatLoggerScript.log_damage(atk, dfn, 5, atk_stats, def_stats, extras)
	assert_int(CombatLoggerScript.get_events()[0]["damage"]["overkill"]).is_equal(0)
