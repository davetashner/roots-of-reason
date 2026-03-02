extends GdUnitTestSuite
## Tests for debug unit control commands (move, attack, gather, set-hp, kill, teleport).

const UnitFactory := preload("res://tests/helpers/unit_factory.gd")
const GMGuard := preload("res://tests/helpers/game_manager_guard.gd")
const RMGuard := preload("res://tests/helpers/resource_manager_guard.gd")
const DebugConsoleScript := preload("res://scripts/debug/debug_console.gd")

var _root: Node2D
var _gm_guard: RefCounted
var _rm_guard: RefCounted


func before_test() -> void:
	_gm_guard = GMGuard.new()
	_rm_guard = RMGuard.new()
	_root = auto_free(Node2D.new())
	add_child(_root)


func after_test() -> void:
	_gm_guard.dispose()
	_rm_guard.dispose()


# -- find_entity --


func test_find_entity_returns_node() -> void:
	var u := UnitFactory.create_villager({"name": "TestUnit1"})
	_root.add_child(u)
	auto_free(u)
	var found: Node = DebugAPI.find_entity("TestUnit1", _root)
	assert_object(found).is_not_null()
	assert_object(found).is_same(u)


func test_find_entity_returns_null_for_missing() -> void:
	var found: Node = DebugAPI.find_entity("NonExistent", _root)
	assert_object(found).is_null()


# -- move --


func test_move_sets_unit_moving() -> void:
	var u := UnitFactory.create_villager({"name": "MoveUnit"})
	_root.add_child(u)
	auto_free(u)
	var result: String = DebugAPI.move_unit("MoveUnit", 200.0, 300.0, _root)
	assert_str(result).contains("Moved")
	assert_bool(u._moving).is_true()


func test_move_invalid_unit_returns_error() -> void:
	var result: String = DebugAPI.move_unit("FakeUnit", 0.0, 0.0, _root)
	assert_str(result).contains("Error")
	assert_str(result).contains("not found")


# -- attack --


func test_attack_engages_target() -> void:
	var attacker := UnitFactory.create_combat_unit({"name": "Attacker", "owner_id": 0})
	var target := UnitFactory.create_combat_unit({"name": "Target", "owner_id": 1, "position": Vector2(100, 100)})
	_root.add_child(attacker)
	_root.add_child(target)
	auto_free(attacker)
	auto_free(target)
	var result: String = DebugAPI.attack_unit("Attacker", "Target", _root)
	assert_str(result).contains("attacking")
	assert_object(attacker._combat_target).is_same(target)


func test_attack_invalid_unit_returns_error() -> void:
	var result: String = DebugAPI.attack_unit("FakeAttacker", "FakeTarget", _root)
	assert_str(result).contains("Error")
	assert_str(result).contains("not found")


func test_attack_invalid_target_returns_error() -> void:
	var u := UnitFactory.create_combat_unit({"name": "Attacker2"})
	_root.add_child(u)
	auto_free(u)
	var result: String = DebugAPI.attack_unit("Attacker2", "FakeTarget", _root)
	assert_str(result).contains("Error")
	assert_str(result).contains("target")


# -- gather --


func test_gather_invalid_unit_returns_error() -> void:
	var result: String = DebugAPI.gather_unit("FakeGatherer", "FakeResource", _root)
	assert_str(result).contains("Error")
	assert_str(result).contains("not found")


func test_gather_invalid_resource_returns_error() -> void:
	var u := UnitFactory.create_villager({"name": "Gatherer1"})
	_root.add_child(u)
	auto_free(u)
	var result: String = DebugAPI.gather_unit("Gatherer1", "FakeResource", _root)
	assert_str(result).contains("Error")
	assert_str(result).contains("resource")


# -- set-hp --


func test_set_hp_sets_value() -> void:
	var u := UnitFactory.create_combat_unit({"name": "HPUnit", "hp": 40, "max_hp": 40})
	_root.add_child(u)
	auto_free(u)
	var result: String = DebugAPI.set_unit_hp("HPUnit", 20, _root)
	assert_str(result).contains("Set")
	assert_int(u.hp).is_equal(20)


func test_set_hp_clamps_to_max() -> void:
	var u := UnitFactory.create_combat_unit({"name": "HPClampMax", "hp": 40, "max_hp": 40})
	_root.add_child(u)
	auto_free(u)
	DebugAPI.set_unit_hp("HPClampMax", 999, _root)
	assert_int(u.hp).is_equal(40)


func test_set_hp_clamps_to_zero() -> void:
	var u := UnitFactory.create_combat_unit({"name": "HPClampZero", "hp": 40, "max_hp": 40})
	_root.add_child(u)
	auto_free(u)
	DebugAPI.set_unit_hp("HPClampZero", -50, _root)
	assert_int(u.hp).is_equal(0)


func test_set_hp_invalid_unit_returns_error() -> void:
	var result: String = DebugAPI.set_unit_hp("FakeUnit", 10, _root)
	assert_str(result).contains("Error")
	assert_str(result).contains("not found")


# -- kill --


func test_kill_triggers_death() -> void:
	var u := UnitFactory.create_combat_unit({"name": "KillTarget", "hp": 40, "max_hp": 40})
	_root.add_child(u)
	auto_free(u)
	var died := [false]
	u.unit_died.connect(func(_unit: Node2D, _killer: Node2D) -> void: died[0] = true)
	var result: String = DebugAPI.kill_unit("KillTarget", _root)
	assert_str(result).contains("Killed")
	assert_bool(died[0]).is_true()
	assert_int(u.hp).is_equal(0)


func test_kill_invalid_unit_returns_error() -> void:
	var result: String = DebugAPI.kill_unit("FakeUnit", _root)
	assert_str(result).contains("Error")
	assert_str(result).contains("not found")


# -- teleport --


func test_teleport_sets_position() -> void:
	var u := UnitFactory.create_villager({"name": "TeleportUnit", "position": Vector2.ZERO})
	_root.add_child(u)
	auto_free(u)
	var result: String = DebugAPI.teleport_unit("TeleportUnit", 500.0, 600.0, _root)
	assert_str(result).contains("Teleported")
	assert_float(u.position.x).is_equal_approx(500.0, 0.1)
	assert_float(u.position.y).is_equal_approx(600.0, 0.1)


func test_teleport_invalid_unit_returns_error() -> void:
	var result: String = DebugAPI.teleport_unit("FakeUnit", 0.0, 0.0, _root)
	assert_str(result).contains("Error")
	assert_str(result).contains("not found")


# -- Console command registration --


func test_console_registers_move_command() -> void:
	var console: Node = auto_free(DebugConsoleScript.new())
	add_child(console)
	assert_bool(console.get_registry().has_command("move")).is_true()


func test_console_registers_attack_command() -> void:
	var console: Node = auto_free(DebugConsoleScript.new())
	add_child(console)
	assert_bool(console.get_registry().has_command("attack")).is_true()


func test_console_registers_gather_command() -> void:
	var console: Node = auto_free(DebugConsoleScript.new())
	add_child(console)
	assert_bool(console.get_registry().has_command("gather")).is_true()


func test_console_registers_set_hp_command() -> void:
	var console: Node = auto_free(DebugConsoleScript.new())
	add_child(console)
	assert_bool(console.get_registry().has_command("set-hp")).is_true()


func test_console_registers_kill_command() -> void:
	var console: Node = auto_free(DebugConsoleScript.new())
	add_child(console)
	assert_bool(console.get_registry().has_command("kill")).is_true()


func test_console_registers_teleport_command() -> void:
	var console: Node = auto_free(DebugConsoleScript.new())
	add_child(console)
	assert_bool(console.get_registry().has_command("teleport")).is_true()
