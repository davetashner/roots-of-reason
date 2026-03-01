extends GdUnitTestSuite
## Tests for base_fauna_ai.gd — shared save/load logic for all fauna AI.

const BaseFaunaAIScript := preload("res://scripts/fauna/base_fauna_ai.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")


func _create_unit_with_base_ai(pos: Vector2 = Vector2.ZERO) -> Node2D:
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.unit_type = "wolf"
	unit.owner_id = -1
	unit.unit_color = Color(0.5, 0.5, 0.5)
	unit.position = pos
	add_child(unit)
	unit._scene_root = self
	auto_free(unit)
	var ai := Node.new()
	ai.name = "FaunaAI"
	ai.set_script(BaseFaunaAIScript)
	unit.add_child(ai)
	ai._scene_root = self
	return unit


func _get_ai(unit: Node2D) -> Node:
	return unit.get_node("FaunaAI")


# -- Round-trip: all base fields survive save/load --


func test_save_load_round_trip() -> void:
	var unit := _create_unit_with_base_ai(Vector2(150, 250))
	var ai := _get_ai(unit)
	ai.spawn_origin = Vector2(150, 250)
	ai._patrol_idle_timer = 2.5
	ai._flee_timer = 1.3
	ai._scan_timer = 0.7
	ai._is_moving = true
	ai._move_target = Vector2(400, 600)

	var data: Dictionary = ai.save_state()

	var unit2 := _create_unit_with_base_ai()
	var ai2 := _get_ai(unit2)
	ai2.load_state(data)

	assert_float(ai2.spawn_origin.x).is_equal_approx(150.0, 0.001)
	assert_float(ai2.spawn_origin.y).is_equal_approx(250.0, 0.001)
	assert_float(ai2._patrol_idle_timer).is_equal_approx(2.5, 0.001)
	assert_float(ai2._flee_timer).is_equal_approx(1.3, 0.001)
	assert_float(ai2._scan_timer).is_equal_approx(0.7, 0.001)
	assert_bool(ai2._is_moving).is_true()
	assert_float(ai2._move_target.x).is_equal_approx(400.0, 0.001)
	assert_float(ai2._move_target.y).is_equal_approx(600.0, 0.001)


# -- Edge case: all-zero / default values --


func test_save_load_zero_values() -> void:
	var unit := _create_unit_with_base_ai()
	var ai := _get_ai(unit)
	# Leave everything at defaults (zero)
	ai.spawn_origin = Vector2.ZERO
	ai._patrol_idle_timer = 0.0
	ai._flee_timer = 0.0
	ai._scan_timer = 0.0
	ai._is_moving = false
	ai._move_target = Vector2.ZERO

	var data: Dictionary = ai.save_state()

	var unit2 := _create_unit_with_base_ai(Vector2(999, 999))
	var ai2 := _get_ai(unit2)
	ai2.spawn_origin = Vector2(999, 999)
	ai2._patrol_idle_timer = 99.0
	ai2._scan_timer = 99.0
	ai2._is_moving = true
	ai2.load_state(data)

	assert_float(ai2.spawn_origin.x).is_equal_approx(0.0, 0.001)
	assert_float(ai2.spawn_origin.y).is_equal_approx(0.0, 0.001)
	assert_float(ai2._patrol_idle_timer).is_equal_approx(0.0, 0.001)
	assert_float(ai2._flee_timer).is_equal_approx(0.0, 0.001)
	assert_float(ai2._scan_timer).is_equal_approx(0.0, 0.001)
	assert_bool(ai2._is_moving).is_false()
	assert_float(ai2._move_target.x).is_equal_approx(0.0, 0.001)
	assert_float(ai2._move_target.y).is_equal_approx(0.0, 0.001)


# -- Edge case: negative coordinates --


func test_save_load_negative_coordinates() -> void:
	var unit := _create_unit_with_base_ai()
	var ai := _get_ai(unit)
	ai.spawn_origin = Vector2(-300, -500)
	ai._move_target = Vector2(-100, -200)
	ai._is_moving = true

	var data: Dictionary = ai.save_state()

	var unit2 := _create_unit_with_base_ai()
	var ai2 := _get_ai(unit2)
	ai2.load_state(data)

	assert_float(ai2.spawn_origin.x).is_equal_approx(-300.0, 0.001)
	assert_float(ai2.spawn_origin.y).is_equal_approx(-500.0, 0.001)
	assert_float(ai2._move_target.x).is_equal_approx(-100.0, 0.001)
	assert_float(ai2._move_target.y).is_equal_approx(-200.0, 0.001)


# -- save_state returns expected keys --


func test_save_state_contains_all_keys() -> void:
	var unit := _create_unit_with_base_ai()
	var ai := _get_ai(unit)
	var data: Dictionary = ai.save_state()

	var expected_keys := [
		"spawn_origin_x",
		"spawn_origin_y",
		"patrol_idle_timer",
		"flee_timer",
		"scan_timer",
		"is_moving",
		"move_target_x",
		"move_target_y",
	]
	for key in expected_keys:
		assert_bool(data.has(key)).is_true()


# -- load_state tolerates missing keys (uses defaults) --


func test_load_state_with_empty_dict() -> void:
	var unit := _create_unit_with_base_ai(Vector2(500, 500))
	var ai := _get_ai(unit)
	ai.spawn_origin = Vector2(500, 500)
	ai._patrol_idle_timer = 10.0
	ai._scan_timer = 5.0
	ai._is_moving = true

	ai.load_state({})

	# All fields should reset to defaults
	assert_float(ai.spawn_origin.x).is_equal_approx(0.0, 0.001)
	assert_float(ai.spawn_origin.y).is_equal_approx(0.0, 0.001)
	assert_float(ai._patrol_idle_timer).is_equal_approx(0.0, 0.001)
	assert_float(ai._flee_timer).is_equal_approx(0.0, 0.001)
	assert_float(ai._scan_timer).is_equal_approx(0.0, 0.001)
	assert_bool(ai._is_moving).is_false()
	assert_float(ai._move_target.x).is_equal_approx(0.0, 0.001)
	assert_float(ai._move_target.y).is_equal_approx(0.0, 0.001)


# -- Subclass extra keys survive base class load --


func test_subclass_keys_preserved_through_base_load() -> void:
	var unit := _create_unit_with_base_ai()
	var ai := _get_ai(unit)
	ai.spawn_origin = Vector2(100, 200)
	ai._scan_timer = 0.5

	var data: Dictionary = ai.save_state()
	# Simulate a subclass adding extra keys after super()
	data["state"] = 2
	data["pack_id"] = 7
	data["custom_field"] = "hello"

	var unit2 := _create_unit_with_base_ai()
	var ai2 := _get_ai(unit2)
	ai2.load_state(data)

	# Base fields restored
	assert_float(ai2.spawn_origin.x).is_equal_approx(100.0, 0.001)
	assert_float(ai2._scan_timer).is_equal_approx(0.5, 0.001)
	# Subclass keys still present in dict (not consumed/removed by base load)
	assert_int(int(data["state"])).is_equal(2)
	assert_int(int(data["pack_id"])).is_equal(7)
	assert_str(str(data["custom_field"])).is_equal("hello")


# -- JSON round-trip: numbers survive parse_string float coercion --


func test_json_round_trip() -> void:
	var unit := _create_unit_with_base_ai()
	var ai := _get_ai(unit)
	ai.spawn_origin = Vector2(123, 456)
	ai._patrol_idle_timer = 3.14
	ai._flee_timer = 2.71
	ai._scan_timer = 0.42
	ai._is_moving = true
	ai._move_target = Vector2(789, 101)

	var data: Dictionary = ai.save_state()
	var json_str: String = JSON.stringify(data)
	var parsed: Dictionary = JSON.parse_string(json_str)

	var unit2 := _create_unit_with_base_ai()
	var ai2 := _get_ai(unit2)
	ai2.load_state(parsed)

	assert_float(ai2.spawn_origin.x).is_equal_approx(123.0, 0.01)
	assert_float(ai2.spawn_origin.y).is_equal_approx(456.0, 0.01)
	assert_float(ai2._patrol_idle_timer).is_equal_approx(3.14, 0.01)
	assert_float(ai2._flee_timer).is_equal_approx(2.71, 0.01)
	assert_float(ai2._scan_timer).is_equal_approx(0.42, 0.01)
	assert_bool(ai2._is_moving).is_true()
	assert_float(ai2._move_target.x).is_equal_approx(789.0, 0.01)
	assert_float(ai2._move_target.y).is_equal_approx(101.0, 0.01)
