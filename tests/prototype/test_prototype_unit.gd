extends GdUnitTestSuite
## Tests for prototype_unit.gd — build task and construction integration.

const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")


func _create_unit(pos: Vector2 = Vector2.ZERO) -> Node2D:
	var u := Node2D.new()
	u.set_script(UnitScript)
	u.unit_type = "villager"
	u.position = pos
	u._build_speed = 1.0
	u._build_reach = 80.0
	add_child(u)
	auto_free(u)
	return u


func _create_building(pos: Vector2 = Vector2.ZERO, build_time: float = 25.0) -> Node2D:
	var b := Node2D.new()
	b.set_script(BuildingScript)
	b.building_name = "house"
	b.max_hp = 550
	b.hp = 0
	b.under_construction = true
	b.build_progress = 0.0
	b._build_time = build_time
	b.footprint = Vector2i(2, 2)
	b.grid_pos = Vector2i(5, 5)
	b.position = pos
	add_child(b)
	auto_free(b)
	return b


# -- assign_build_target --


func test_assign_build_target_sets_target() -> void:
	var u := _create_unit()
	var b := _create_building(Vector2(50, 0))
	u.assign_build_target(b)
	assert_bool(u._build_target == b).is_true()


func test_assign_build_target_starts_moving() -> void:
	var u := _create_unit()
	var b := _create_building(Vector2(200, 0))
	u.assign_build_target(b)
	assert_bool(u._moving).is_true()


# -- _tick_build --


func test_tick_build_noop_when_no_target() -> void:
	var u := _create_unit()
	# Should not error when no target
	u._tick_build(1.0)
	assert_bool(u.is_idle()).is_true()


func test_tick_build_noop_when_out_of_range() -> void:
	var u := _create_unit(Vector2.ZERO)
	var b := _create_building(Vector2(500, 0))
	u._build_target = b
	u._moving = false
	u._tick_build(1.0)
	# Building progress should remain 0 (out of range)
	assert_float(b.build_progress).is_equal_approx(0.0, 0.001)


func test_tick_build_applies_work_in_range() -> void:
	var u := _create_unit(Vector2.ZERO)
	var b := _create_building(Vector2(30, 0), 25.0)
	u._build_target = b
	u._moving = false
	# 1 second of work: build_speed(1.0) / build_time(25.0) = 0.04
	u._tick_build(1.0)
	assert_float(b.build_progress).is_equal_approx(0.04, 0.001)


func test_tick_build_stops_movement_in_range() -> void:
	var u := _create_unit(Vector2.ZERO)
	var b := _create_building(Vector2(30, 0))
	u._build_target = b
	u._moving = true
	u._tick_build(1.0)
	assert_bool(u._moving).is_false()


func test_tick_build_clears_target_on_complete() -> void:
	var u := _create_unit(Vector2.ZERO)
	var b := _create_building(Vector2(30, 0), 1.0)
	u._build_target = b
	u._moving = false
	# build_speed(1.0) / build_time(1.0) * delta(1.0) = 1.0 => completes
	u._tick_build(1.0)
	assert_bool(u._build_target == null).is_true()
	assert_bool(b.under_construction).is_false()


func test_tick_build_clears_target_when_freed() -> void:
	var u := _create_unit(Vector2.ZERO)
	var b := Node2D.new()
	b.set_script(BuildingScript)
	b.under_construction = true
	b._build_time = 25.0
	b.max_hp = 100
	b.hp = 0
	add_child(b)
	u._build_target = b
	b.free()
	u._tick_build(1.0)
	assert_bool(u._build_target == null).is_true()


# -- is_idle --


func test_is_idle_when_stationary_no_target() -> void:
	var u := _create_unit()
	assert_bool(u.is_idle()).is_true()


func test_not_idle_when_moving() -> void:
	var u := _create_unit()
	u.move_to(Vector2(100, 100))
	assert_bool(u.is_idle()).is_false()


func test_not_idle_when_building() -> void:
	var u := _create_unit()
	var b := _create_building(Vector2(30, 0))
	u._build_target = b
	u._moving = false
	assert_bool(u.is_idle()).is_false()


# -- save_state --


func test_save_state_includes_build_target() -> void:
	var u := _create_unit()
	var b := _create_building()
	b.name = "Building_house_5_5"
	u._build_target = b
	var state: Dictionary = u.save_state()
	assert_str(state.get("build_target_name", "")).is_equal("Building_house_5_5")


func test_save_state_no_build_target() -> void:
	var u := _create_unit()
	var state: Dictionary = u.save_state()
	assert_bool(state.has("build_target_name")).is_false()


func test_load_state_stores_pending_target() -> void:
	var u := _create_unit()
	var state := {
		"position_x": 10.0,
		"position_y": 20.0,
		"unit_type": "villager",
		"build_target_name": "Building_house_5_5",
	}
	u.load_state(state)
	assert_str(u._pending_build_target_name).is_equal("Building_house_5_5")


# -- Multiple villagers additive --


func test_multiple_villagers_additive() -> void:
	var b := _create_building(Vector2.ZERO, 25.0)
	var u1 := _create_unit(Vector2(10, 0))
	var u2 := _create_unit(Vector2(-10, 0))
	var u3 := _create_unit(Vector2(0, 10))
	u1._build_target = b
	u2._build_target = b
	u3._build_target = b
	u1._moving = false
	u2._moving = false
	u3._moving = false
	# Each contributes 1.0/25.0 = 0.04 per second; 3 villagers = 0.12
	u1._tick_build(1.0)
	u2._tick_build(1.0)
	u3._tick_build(1.0)
	assert_float(b.build_progress).is_equal_approx(0.12, 0.001)
