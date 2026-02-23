extends GdUnitTestSuite
## Tests for prototype_building.gd — construction state and build progress.

const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")


func _create_building(under_construction: bool = true, build_time: float = 25.0) -> Node2D:
	var b := Node2D.new()
	b.set_script(BuildingScript)
	b.building_name = "house"
	b.max_hp = 550
	b.hp = 0 if under_construction else 550
	b.under_construction = under_construction
	b.build_progress = 0.0 if under_construction else 1.0
	b._build_time = build_time
	b.footprint = Vector2i(2, 2)
	b.grid_pos = Vector2i(5, 5)
	add_child(b)
	auto_free(b)
	return b


# -- apply_build_work --


func test_apply_build_work_increments_progress() -> void:
	var b := _create_building()
	b.apply_build_work(0.1)
	assert_float(b.build_progress).is_equal_approx(0.1, 0.001)


func test_apply_build_work_scales_hp() -> void:
	var b := _create_building()
	b.apply_build_work(0.5)
	assert_int(b.hp).is_equal(int(0.5 * 550))


func test_apply_build_work_clamps_at_one() -> void:
	var b := _create_building()
	b.apply_build_work(1.5)
	assert_float(b.build_progress).is_equal_approx(1.0, 0.001)


func test_apply_build_work_emits_construction_complete() -> void:
	var b := _create_building()
	var monitor := monitor_signals(b)
	b.apply_build_work(1.0)
	await assert_signal(monitor).is_emitted("construction_complete", [b])


func test_apply_build_work_completes_construction() -> void:
	var b := _create_building()
	b.apply_build_work(1.0)
	assert_bool(b.under_construction).is_false()
	assert_int(b.hp).is_equal(550)


func test_apply_build_work_noop_when_complete() -> void:
	var b := _create_building(false)
	b.apply_build_work(0.5)
	# Should remain at full HP, not change
	assert_int(b.hp).is_equal(550)
	assert_float(b.build_progress).is_equal_approx(1.0, 0.001)


# -- get_entity_category --


func test_entity_category_construction_site() -> void:
	var b := _create_building()
	assert_str(b.get_entity_category()).is_equal("construction_site")


func test_entity_category_after_complete() -> void:
	var b := _create_building()
	b.apply_build_work(1.0)
	assert_str(b.get_entity_category()).is_equal("own_building")


# -- save_state / load_state --


func test_save_state_includes_construction_fields() -> void:
	var b := _create_building()
	b.apply_build_work(0.4)
	var state: Dictionary = b.save_state()
	assert_bool(state["under_construction"]).is_true()
	assert_float(float(state["build_progress"])).is_equal_approx(0.4, 0.001)
	assert_float(float(state["build_time"])).is_equal_approx(25.0, 0.001)


func test_save_load_round_trip() -> void:
	var b := _create_building()
	b.apply_build_work(0.6)
	var state: Dictionary = b.save_state()
	var b2 := _create_building()
	b2.load_state(state)
	assert_float(b2.build_progress).is_equal_approx(0.6, 0.001)
	assert_bool(b2.under_construction).is_true()
	assert_int(b2.hp).is_equal(b.hp)
	assert_float(b2._build_time).is_equal_approx(25.0, 0.001)


# -- Incremental build --


func test_multiple_increments_accumulate() -> void:
	var b := _create_building()
	b.apply_build_work(0.3)
	b.apply_build_work(0.3)
	b.apply_build_work(0.3)
	assert_float(b.build_progress).is_equal_approx(0.9, 0.001)
	assert_bool(b.under_construction).is_true()
	b.apply_build_work(0.1)
	assert_bool(b.under_construction).is_false()
