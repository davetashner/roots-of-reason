extends GdUnitTestSuite
## Tests for WarSurvival — medical tech chain lethal-damage survival mechanic.

var _war_survival: WarSurvival
var _tech_manager_mock: Node
var _original_game_time: float
var _unit_script: GDScript


func before() -> void:
	_original_game_time = GameManager.game_time
	GameManager.game_time = 0.0
	_unit_script = GDScript.new()
	_unit_script.source_code = (
		"extends Node2D\n" + "var hp: int = 0\n" + "var max_hp: int = 0\n" + "var owner_id: int = 0\n"
	)
	_unit_script.reload()


func after() -> void:
	GameManager.game_time = _original_game_time


func before_test() -> void:
	# Create mock TechManager with is_tech_researched method
	var mock: Node = auto_free(_MockTechManager.new())
	_tech_manager_mock = mock
	# Create WarSurvival and configure directly (bypass DataLoader)
	_war_survival = WarSurvival.new()
	add_child(_war_survival)
	_war_survival._survival_cooldown = 30.0
	_war_survival._tiers = [
		{"tech_id": "herbal_medicine", "chance": 0.10, "hp_percent": 0.0, "hp_flat": 1},
		{"tech_id": "surgery", "chance": 0.20, "hp_percent": 0.05, "hp_flat": 0},
		{"tech_id": "modern_medicine", "chance": 0.30, "hp_percent": 0.10, "hp_flat": 0},
	]
	_war_survival._flash_color = Color(0.2, 1.0, 0.2, 0.8)
	_war_survival._flash_duration = 0.5
	_war_survival.setup(_tech_manager_mock)


func after_test() -> void:
	if _war_survival != null and is_instance_valid(_war_survival):
		_war_survival.queue_free()
		_war_survival = null


func _make_unit(hp_val: int, max_hp_val: int, owner: int = 0) -> Node2D:
	var unit := Node2D.new()
	unit.set_script(_unit_script)
	unit.hp = hp_val
	unit.max_hp = max_hp_val
	unit.owner_id = owner
	add_child(unit)
	return unit


# -- No survival with no tech --


func test_no_survival_without_tech() -> void:
	_tech_manager_mock.researched = []
	var unit := _make_unit(5, 100)
	# Try 100 times — should never survive
	var survived := false
	for i in 100:
		unit.hp = 5
		if _war_survival.roll_survival(unit, 10):
			survived = true
			break
		_war_survival.clear_cooldown(unit)
	assert_bool(survived).is_false()
	unit.queue_free()


# -- Survival possible with herbal_medicine --


func test_survival_possible_with_herbal_medicine() -> void:
	_tech_manager_mock.researched = ["herbal_medicine"]
	# 10% chance — run 200 trials, expect at least 1 survival
	var survivals := 0
	var units: Array[Node2D] = []
	for i in 200:
		var unit := _make_unit(5, 100)
		units.append(unit)
		if _war_survival.roll_survival(unit, 10):
			survivals += 1
		_war_survival.clear_cooldown(unit)
	for u in units:
		u.queue_free()
	assert_int(survivals).is_greater(0)


# -- Higher chance with surgery --


func test_surgery_higher_chance() -> void:
	_tech_manager_mock.researched = ["herbal_medicine", "surgery"]
	var survivals := 0
	var units: Array[Node2D] = []
	for i in 500:
		var unit := _make_unit(5, 100)
		units.append(unit)
		if _war_survival.roll_survival(unit, 10):
			survivals += 1
		_war_survival.clear_cooldown(unit)
	for u in units:
		u.queue_free()
	# 20% chance: expect ~100 out of 500, at least 50
	assert_int(survivals).is_greater(50)


# -- Highest chance with modern_medicine --


func test_modern_medicine_highest_chance() -> void:
	_tech_manager_mock.researched = ["herbal_medicine", "surgery", "modern_medicine"]
	var survivals := 0
	var units: Array[Node2D] = []
	for i in 500:
		var unit := _make_unit(5, 100)
		units.append(unit)
		if _war_survival.roll_survival(unit, 10):
			survivals += 1
		_war_survival.clear_cooldown(unit)
	for u in units:
		u.queue_free()
	# 30% chance: expect ~150 out of 500, at least 100
	assert_int(survivals).is_greater(100)


# -- Cooldown prevents double survival --


func test_cooldown_prevents_double_survival() -> void:
	_tech_manager_mock.researched = ["modern_medicine"]
	GameManager.game_time = 100.0
	# Force a survival by using 100% chance temporarily
	_war_survival._tiers = [
		{"tech_id": "modern_medicine", "chance": 1.0, "hp_percent": 0.10, "hp_flat": 0},
	]
	var unit := _make_unit(5, 100)
	var first := _war_survival.roll_survival(unit, 10)
	assert_bool(first).is_true()
	# Try again immediately — should fail due to cooldown
	unit.hp = 5
	var second := _war_survival.roll_survival(unit, 10)
	assert_bool(second).is_false()
	# Advance time past cooldown
	GameManager.game_time = 131.0
	unit.hp = 5
	var third := _war_survival.roll_survival(unit, 10)
	assert_bool(third).is_true()
	unit.queue_free()


# -- Surviving unit has correct HP --


func test_herbal_medicine_leaves_1_hp() -> void:
	_tech_manager_mock.researched = ["herbal_medicine"]
	_war_survival._tiers = [
		{"tech_id": "herbal_medicine", "chance": 1.0, "hp_percent": 0.0, "hp_flat": 1},
	]
	var unit := _make_unit(5, 100)
	_war_survival.roll_survival(unit, 10)
	assert_int(unit.hp).is_equal(1)
	unit.queue_free()


func test_surgery_leaves_5_percent_hp() -> void:
	_tech_manager_mock.researched = ["herbal_medicine", "surgery"]
	_war_survival._tiers = [
		{"tech_id": "herbal_medicine", "chance": 1.0, "hp_percent": 0.0, "hp_flat": 1},
		{"tech_id": "surgery", "chance": 1.0, "hp_percent": 0.05, "hp_flat": 0},
	]
	var unit := _make_unit(5, 100)
	_war_survival.roll_survival(unit, 10)
	# 5% of 100 = 5, max(1, 5) = 5
	assert_int(unit.hp).is_equal(5)
	unit.queue_free()


func test_modern_medicine_leaves_10_percent_hp() -> void:
	_tech_manager_mock.researched = ["herbal_medicine", "surgery", "modern_medicine"]
	_war_survival._tiers = [
		{"tech_id": "herbal_medicine", "chance": 1.0, "hp_percent": 0.0, "hp_flat": 1},
		{"tech_id": "surgery", "chance": 1.0, "hp_percent": 0.05, "hp_flat": 0},
		{"tech_id": "modern_medicine", "chance": 1.0, "hp_percent": 0.10, "hp_flat": 0},
	]
	var unit := _make_unit(5, 200)
	_war_survival.roll_survival(unit, 10)
	# 10% of 200 = 20, max(1, 20) = 20
	assert_int(unit.hp).is_equal(20)
	unit.queue_free()


# -- Survival only on lethal damage --


func test_non_lethal_damage_does_not_trigger() -> void:
	_tech_manager_mock.researched = ["modern_medicine"]
	_war_survival._tiers = [
		{"tech_id": "modern_medicine", "chance": 1.0, "hp_percent": 0.10, "hp_flat": 0},
	]
	var unit := _make_unit(50, 100)
	# Damage of 10 when unit has 50 HP — not lethal
	var result := _war_survival.roll_survival(unit, 10)
	assert_bool(result).is_false()
	unit.queue_free()


# -- No tech manager --


func test_no_tech_manager_returns_false() -> void:
	var ws := WarSurvival.new()
	add_child(ws)
	ws._tiers = [
		{"tech_id": "herbal_medicine", "chance": 1.0, "hp_percent": 0.0, "hp_flat": 1},
	]
	# No setup call — _tech_manager is null
	var unit := _make_unit(5, 100)
	var result := ws.roll_survival(unit, 10)
	assert_bool(result).is_false()
	unit.queue_free()
	ws.queue_free()


# -- Signal emitted on survival --


func test_unit_survived_signal_emitted() -> void:
	_tech_manager_mock.researched = ["herbal_medicine"]
	_war_survival._tiers = [
		{"tech_id": "herbal_medicine", "chance": 1.0, "hp_percent": 0.0, "hp_flat": 1},
	]
	var received: Array = [false]
	_war_survival.unit_survived.connect(func(_unit: Node2D, _hp: int) -> void: received[0] = true)
	var unit := _make_unit(5, 100)
	_war_survival.roll_survival(unit, 10)
	assert_bool(received[0]).is_true()
	unit.queue_free()


# -- Higher tier replaces lower (not cumulative) --


func test_only_highest_tier_applies() -> void:
	_tech_manager_mock.researched = ["herbal_medicine", "surgery"]
	_war_survival._tiers = [
		{"tech_id": "herbal_medicine", "chance": 1.0, "hp_percent": 0.0, "hp_flat": 1},
		{"tech_id": "surgery", "chance": 1.0, "hp_percent": 0.05, "hp_flat": 0},
	]
	var unit := _make_unit(5, 100)
	_war_survival.roll_survival(unit, 10)
	# Surgery: 5% of 100 = 5, not herbal_medicine's 1 HP
	assert_int(unit.hp).is_equal(5)
	unit.queue_free()


# -- Save/load round-trip --


func test_save_load_unit_cooldowns_round_trip() -> void:
	_tech_manager_mock.researched = ["modern_medicine"]
	_war_survival._tiers = [
		{"tech_id": "modern_medicine", "chance": 1.0, "hp_percent": 0.10, "hp_flat": 0},
	]
	GameManager.game_time = 50.0
	var unit := _make_unit(5, 100)
	_war_survival.roll_survival(unit, 10)
	# Cooldown should be recorded
	var uid: int = unit.get_instance_id()
	assert_float(_war_survival._unit_cooldowns.get(uid, -1.0)).is_equal(50.0)

	# Save state
	var state: Dictionary = _war_survival.save_state()
	# Simulate JSON round-trip (keys become strings, values become floats)
	var json_str: String = JSON.stringify(state)
	var parsed: Dictionary = JSON.parse_string(json_str)

	# Load into a fresh WarSurvival
	var ws2 := WarSurvival.new()
	add_child(ws2)
	ws2.load_state(parsed)

	# Verify int key survived the JSON round-trip
	assert_bool(ws2._unit_cooldowns.has(uid)).is_true()
	assert_float(ws2._unit_cooldowns[uid]).is_equal(50.0)

	# Verify the key is actually an int, not a string
	for key: Variant in ws2._unit_cooldowns:
		assert_int(typeof(key)).is_equal(TYPE_INT)

	ws2.queue_free()
	unit.queue_free()


func test_save_load_empty_cooldowns() -> void:
	# No cooldowns recorded
	var state: Dictionary = _war_survival.save_state()
	var json_str: String = JSON.stringify(state)
	var parsed: Dictionary = JSON.parse_string(json_str)

	var ws2 := WarSurvival.new()
	add_child(ws2)
	ws2.load_state(parsed)

	assert_int(ws2._unit_cooldowns.size()).is_equal(0)
	ws2.queue_free()


func test_save_load_multiple_cooldowns() -> void:
	_tech_manager_mock.researched = ["modern_medicine"]
	_war_survival._tiers = [
		{"tech_id": "modern_medicine", "chance": 1.0, "hp_percent": 0.10, "hp_flat": 0},
	]

	# Create multiple units and trigger survival at different game times
	GameManager.game_time = 10.0
	var unit_a := _make_unit(5, 100)
	_war_survival.roll_survival(unit_a, 10)
	var uid_a: int = unit_a.get_instance_id()

	GameManager.game_time = 20.0
	var unit_b := _make_unit(5, 100)
	_war_survival.roll_survival(unit_b, 10)
	var uid_b: int = unit_b.get_instance_id()

	GameManager.game_time = 30.0
	var unit_c := _make_unit(5, 100)
	_war_survival.roll_survival(unit_c, 10)
	var uid_c: int = unit_c.get_instance_id()

	# Save, JSON round-trip, load
	var state: Dictionary = _war_survival.save_state()
	var json_str: String = JSON.stringify(state)
	var parsed: Dictionary = JSON.parse_string(json_str)

	var ws2 := WarSurvival.new()
	add_child(ws2)
	ws2.load_state(parsed)

	# Verify all three entries survived
	assert_int(ws2._unit_cooldowns.size()).is_equal(3)
	assert_float(ws2._unit_cooldowns[uid_a]).is_equal(10.0)
	assert_float(ws2._unit_cooldowns[uid_b]).is_equal(20.0)
	assert_float(ws2._unit_cooldowns[uid_c]).is_equal(30.0)

	# Verify all keys are ints
	for key: Variant in ws2._unit_cooldowns:
		assert_int(typeof(key)).is_equal(TYPE_INT)

	ws2.queue_free()
	unit_a.queue_free()
	unit_b.queue_free()
	unit_c.queue_free()


# -- Mock TechManager --


class _MockTechManager:
	extends Node
	var researched: Array = []

	func is_tech_researched(tech_id: String, _player_id: int = 0) -> bool:
		return tech_id in researched
