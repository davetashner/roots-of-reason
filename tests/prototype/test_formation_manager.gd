extends GdUnitTestSuite
## Tests for formation_manager.gd — formation offsets and speed synchronization.

const FormationManagerScript := preload("res://scripts/prototype/formation_manager.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")


func _create_fm(sp: float = 40.0) -> RefCounted:
	var fm := FormationManagerScript.new()
	fm.spacing = sp
	return fm


func _create_unit(pos: Vector2 = Vector2.ZERO, _speed_stat: float = 0.0) -> Node2D:
	var u := Node2D.new()
	u.set_script(UnitScript)
	u.unit_type = "land"
	u.position = pos
	add_child(u)
	auto_free(u)
	return u


# -- get_offsets: count --


func test_offsets_returns_empty_for_zero() -> void:
	var fm: RefCounted = _create_fm()
	var offsets: Array = fm.get_offsets(fm.FormationType.LINE, 0)
	assert_int(offsets.size()).is_equal(0)


func test_offsets_single_unit_returns_zero_vector() -> void:
	var fm: RefCounted = _create_fm()
	var offsets: Array = fm.get_offsets(fm.FormationType.STAGGERED, 1)
	assert_int(offsets.size()).is_equal(1)
	assert_float(offsets[0].length()).is_less(0.01)


func test_line_returns_correct_count() -> void:
	var fm: RefCounted = _create_fm()
	var offsets: Array = fm.get_offsets(fm.FormationType.LINE, 5)
	assert_int(offsets.size()).is_equal(5)


func test_box_returns_correct_count() -> void:
	var fm: RefCounted = _create_fm()
	var offsets: Array = fm.get_offsets(fm.FormationType.BOX, 9)
	assert_int(offsets.size()).is_equal(9)


func test_staggered_returns_correct_count() -> void:
	var fm: RefCounted = _create_fm()
	var offsets: Array = fm.get_offsets(fm.FormationType.STAGGERED, 7)
	assert_int(offsets.size()).is_equal(7)


# -- Line formation --


func test_line_perpendicular_to_facing() -> void:
	var fm: RefCounted = _create_fm()
	var facing := Vector2.RIGHT
	var offsets: Array = fm.get_offsets(fm.FormationType.LINE, 3, facing)
	# All offsets should have x ≈ 0 (perpendicular to RIGHT means along Y axis)
	for offset in offsets:
		assert_float(absf(offset.x)).is_less(0.01)


func test_line_centered_on_origin() -> void:
	var fm: RefCounted = _create_fm(40.0)
	var offsets: Array = fm.get_offsets(fm.FormationType.LINE, 3, Vector2.RIGHT)
	# Middle unit at origin, others ±spacing along Y
	var sum := Vector2.ZERO
	for offset in offsets:
		sum += offset
	assert_float(sum.length()).is_less(0.01)


func test_line_spacing_between_units() -> void:
	var fm: RefCounted = _create_fm(40.0)
	var offsets: Array = fm.get_offsets(fm.FormationType.LINE, 2, Vector2.RIGHT)
	var dist: float = offsets[0].distance_to(offsets[1])
	assert_float(dist).is_equal_approx(40.0, 0.01)


# -- Box formation --


func test_box_forms_grid() -> void:
	var fm: RefCounted = _create_fm(40.0)
	var offsets: Array = fm.get_offsets(fm.FormationType.BOX, 4, Vector2.RIGHT)
	# 4 units → 2x2 grid
	assert_int(offsets.size()).is_equal(4)
	# All offsets should be distinct
	for i in offsets.size():
		for j in range(i + 1, offsets.size()):
			assert_float(offsets[i].distance_to(offsets[j])).is_greater(1.0)


func test_box_9_units_3x3() -> void:
	var fm: RefCounted = _create_fm(40.0)
	var offsets: Array = fm.get_offsets(fm.FormationType.BOX, 9, Vector2.RIGHT)
	assert_int(offsets.size()).is_equal(9)


# -- Staggered formation --


func test_staggered_odd_rows_offset() -> void:
	var fm: RefCounted = _create_fm(40.0)
	var offsets: Array = fm.get_offsets(fm.FormationType.STAGGERED, 6, Vector2.RIGHT)
	# Get cols count: ceil(sqrt(6)) = 3, rows = 2
	# Row 0 units at cols 0,1,2; row 1 (odd) at cols 0,1,2 + 0.5 stagger
	# The first 3 offsets (row 0) and last 3 (row 1) should differ in perpendicular position
	var row0_perp: Array[float] = []
	var row1_perp: Array[float] = []
	for i in 3:
		row0_perp.append(offsets[i].y)
	for i in range(3, 6):
		row1_perp.append(offsets[i].y)
	# Row 1 should be shifted by half-spacing relative to row 0
	var shift: float = row1_perp[0] - row0_perp[0]
	assert_float(absf(shift)).is_greater(0.1)


# -- Facing direction --


func test_offsets_rotate_with_facing() -> void:
	var fm: RefCounted = _create_fm()
	var offsets_right: Array = fm.get_offsets(fm.FormationType.LINE, 3, Vector2.RIGHT)
	var offsets_up: Array = fm.get_offsets(fm.FormationType.LINE, 3, Vector2.UP)
	# With RIGHT facing, line goes along Y; with UP facing, line goes along X
	# The offset patterns should be rotated
	assert_float(absf(offsets_right[0].x)).is_less(0.01)
	assert_float(absf(offsets_up[0].y)).is_less(0.01)


# -- Large group --


func test_large_group_40_units() -> void:
	var fm: RefCounted = _create_fm()
	var offsets: Array = fm.get_offsets(fm.FormationType.STAGGERED, 40)
	assert_int(offsets.size()).is_equal(40)
	# All unique
	for i in offsets.size():
		for j in range(i + 1, offsets.size()):
			assert_float(offsets[i].distance_to(offsets[j])).is_greater(0.01)


# -- Speed sync --


func test_formation_speed_returns_minimum() -> void:
	var fm: RefCounted = _create_fm()
	var u1: Node2D = _create_unit()
	var u2: Node2D = _create_unit()
	# Default MOVE_SPEED is 150.0 for both since stats have no speed entry
	var speed: float = fm.get_formation_speed([u1, u2])
	assert_float(speed).is_equal_approx(150.0, 0.01)


func test_formation_speed_empty_returns_default() -> void:
	var fm: RefCounted = _create_fm()
	var speed: float = fm.get_formation_speed([])
	assert_float(speed).is_equal_approx(150.0, 0.01)


# -- Unit speed override --


func test_set_formation_speed_caps_movement() -> void:
	var u: Node2D = _create_unit()
	# Default speed is 150
	assert_float(u.get_move_speed()).is_equal_approx(150.0, 0.01)
	u.set_formation_speed(100.0)
	assert_float(u.get_move_speed()).is_equal_approx(100.0, 0.01)


func test_clear_formation_speed_restores() -> void:
	var u: Node2D = _create_unit()
	u.set_formation_speed(100.0)
	u.clear_formation_speed()
	assert_float(u.get_move_speed()).is_equal_approx(150.0, 0.01)


func test_formation_speed_override_saved() -> void:
	var u: Node2D = _create_unit()
	u.set_formation_speed(80.0)
	var state: Dictionary = u.save_state()
	assert_float(float(state["formation_speed_override"])).is_equal_approx(80.0, 0.01)


func test_formation_speed_override_loaded() -> void:
	var u: Node2D = _create_unit()
	u.load_state({"formation_speed_override": 90.0})
	assert_float(u._formation_speed_override).is_equal_approx(90.0, 0.01)


# -- Type conversion --


func test_type_from_string_line() -> void:
	assert_int(FormationManagerScript.type_from_string("line")).is_equal(FormationManagerScript.FormationType.LINE)


func test_type_from_string_box() -> void:
	assert_int(FormationManagerScript.type_from_string("box")).is_equal(FormationManagerScript.FormationType.BOX)


func test_type_from_string_staggered() -> void:
	assert_int(FormationManagerScript.type_from_string("staggered")).is_equal(
		FormationManagerScript.FormationType.STAGGERED
	)


func test_type_from_string_unknown_defaults_staggered() -> void:
	assert_int(FormationManagerScript.type_from_string("unknown")).is_equal(
		FormationManagerScript.FormationType.STAGGERED
	)


func test_type_to_string_roundtrip() -> void:
	for t in [
		FormationManagerScript.FormationType.LINE,
		FormationManagerScript.FormationType.BOX,
		FormationManagerScript.FormationType.STAGGERED,
	]:
		var s: String = FormationManagerScript.type_to_string(t)
		assert_int(FormationManagerScript.type_from_string(s)).is_equal(t)
