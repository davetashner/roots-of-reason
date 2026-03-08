extends GdUnitTestSuite
## Tests for DropOffCommandHandler.

const HandlerScript := preload("res://scripts/prototype/drop_off_command_handler.gd")

var _handler: RefCounted


func before_test() -> void:
	_handler = HandlerScript.new()


# ---------------------------------------------------------------------------
# Mock helpers
# ---------------------------------------------------------------------------


class MockBuilding:
	extends Node2D

	var is_drop_off: bool = true
	var drop_off_types: Array[String] = ["food", "wood", "stone", "gold"]
	var garrisoned: Array[Node] = []

	func garrison_unit(unit: Node) -> void:
		garrisoned.append(unit)


class MockUnit:
	extends Node2D

	var _carried_amount: int = 0
	var _gather_type: String = ""
	var _drop_off_building: Node2D = null
	var _move_target: Vector2 = Vector2.ZERO

	func send_to_drop_off(building: Node2D) -> void:
		_drop_off_building = building

	func move_to(pos: Vector2) -> void:
		_move_target = pos


# ---------------------------------------------------------------------------
# can_handle tests
# ---------------------------------------------------------------------------


func test_can_handle_returns_false_for_non_garrison_cmd() -> void:
	var building := auto_free(MockBuilding.new())
	var unit := auto_free(MockUnit.new())
	unit._carried_amount = 5
	unit._gather_type = "food"
	var selected: Array[Node] = [unit]
	assert_bool(_handler.can_handle("move", building, selected, Vector2.ZERO)).is_false()


func test_can_handle_returns_false_for_null_target() -> void:
	var unit := auto_free(MockUnit.new())
	unit._carried_amount = 5
	unit._gather_type = "food"
	var selected: Array[Node] = [unit]
	assert_bool(_handler.can_handle("garrison", null, selected, Vector2.ZERO)).is_false()


func test_can_handle_returns_false_for_non_drop_off_building() -> void:
	var building := auto_free(MockBuilding.new())
	building.is_drop_off = false
	var unit := auto_free(MockUnit.new())
	unit._carried_amount = 5
	unit._gather_type = "food"
	var selected: Array[Node] = [unit]
	assert_bool(_handler.can_handle("garrison", building, selected, Vector2.ZERO)).is_false()


func test_can_handle_returns_false_when_no_units_carrying() -> void:
	var building := auto_free(MockBuilding.new())
	var unit := auto_free(MockUnit.new())
	unit._carried_amount = 0
	unit._gather_type = "food"
	var selected: Array[Node] = [unit]
	assert_bool(_handler.can_handle("garrison", building, selected, Vector2.ZERO)).is_false()


func test_can_handle_returns_false_for_wrong_resource_type() -> void:
	var building := auto_free(MockBuilding.new())
	building.drop_off_types = ["wood"]
	var unit := auto_free(MockUnit.new())
	unit._carried_amount = 5
	unit._gather_type = "food"
	var selected: Array[Node] = [unit]
	assert_bool(_handler.can_handle("garrison", building, selected, Vector2.ZERO)).is_false()


func test_can_handle_returns_true_for_carrying_villager_matching_type() -> void:
	var building := auto_free(MockBuilding.new())
	var unit := auto_free(MockUnit.new())
	unit._carried_amount = 5
	unit._gather_type = "food"
	var selected: Array[Node] = [unit]
	assert_bool(_handler.can_handle("garrison", building, selected, Vector2.ZERO)).is_true()


func test_can_handle_true_if_any_unit_carrying() -> void:
	var building := auto_free(MockBuilding.new())
	var u1 := auto_free(MockUnit.new())
	u1._carried_amount = 0
	u1._gather_type = ""
	var u2 := auto_free(MockUnit.new())
	u2._carried_amount = 3
	u2._gather_type = "wood"
	var selected: Array[Node] = [u1, u2]
	assert_bool(_handler.can_handle("garrison", building, selected, Vector2.ZERO)).is_true()


# ---------------------------------------------------------------------------
# execute tests
# ---------------------------------------------------------------------------


func test_execute_sends_carrying_unit_to_drop_off() -> void:
	var building := auto_free(MockBuilding.new())
	var unit := auto_free(MockUnit.new())
	unit._carried_amount = 7
	unit._gather_type = "food"
	var selected: Array[Node] = [unit]
	var result := _handler.execute("garrison", building, selected, Vector2.ZERO)
	assert_bool(result).is_true()
	assert_object(unit._drop_off_building).is_same(building)


func test_execute_garrisons_non_carrying_unit() -> void:
	var building := auto_free(MockBuilding.new())
	building.global_position = Vector2(100, 200)
	var unit := auto_free(MockUnit.new())
	unit._carried_amount = 0
	unit._gather_type = ""
	var selected: Array[Node] = [unit]
	var result := _handler.execute("garrison", building, selected, Vector2.ZERO)
	assert_bool(result).is_true()
	assert_object(unit._drop_off_building).is_null()
	assert_vector(unit._move_target).is_equal(Vector2(100, 200))
	assert_int(building.garrisoned.size()).is_equal(1)


func test_execute_mixed_units_drop_off_and_garrison() -> void:
	var building := auto_free(MockBuilding.new())
	building.global_position = Vector2(50, 50)
	var carrier := auto_free(MockUnit.new())
	carrier._carried_amount = 5
	carrier._gather_type = "wood"
	var idle := auto_free(MockUnit.new())
	idle._carried_amount = 0
	idle._gather_type = ""
	var selected: Array[Node] = [carrier, idle]
	_handler.execute("garrison", building, selected, Vector2.ZERO)
	assert_object(carrier._drop_off_building).is_same(building)
	assert_vector(idle._move_target).is_equal(Vector2(50, 50))
	assert_int(building.garrisoned.size()).is_equal(1)


func test_execute_returns_false_for_wrong_cmd() -> void:
	var building := auto_free(MockBuilding.new())
	var unit := auto_free(MockUnit.new())
	unit._carried_amount = 5
	unit._gather_type = "food"
	var selected: Array[Node] = [unit]
	assert_bool(_handler.execute("move", building, selected, Vector2.ZERO)).is_false()


func test_execute_returns_false_for_null_target() -> void:
	var unit := auto_free(MockUnit.new())
	unit._carried_amount = 5
	unit._gather_type = "food"
	var selected: Array[Node] = [unit]
	assert_bool(_handler.execute("garrison", null, selected, Vector2.ZERO)).is_false()
