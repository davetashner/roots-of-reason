extends GdUnitTestSuite
## Tests for prototype_building.gd — construction, damage states, and ruins.

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


# -- take_damage / damage states --


func test_take_damage_reduces_hp() -> void:
	var b := _create_building(false)
	b.take_damage(100, null)
	assert_int(b.hp).is_equal(450)


func test_take_damage_clamps_to_zero() -> void:
	var b := _create_building(false)
	b.take_damage(9999, null)
	assert_int(b.hp).is_equal(0)


func test_take_damage_emits_building_destroyed_at_zero() -> void:
	var b := _create_building(false)
	var monitor := monitor_signals(b)
	b.take_damage(550, null)
	await assert_signal(monitor).is_emitted("building_destroyed", [b])


func test_get_damage_state_intact() -> void:
	var b := _create_building(false)
	# Full HP — above 66%
	assert_str(b.get_damage_state()).is_equal("intact")


func test_get_damage_state_damaged() -> void:
	var b := _create_building(false)
	# Set to 50% HP — between 33% and 66%
	b.hp = 275
	assert_str(b.get_damage_state()).is_equal("damaged")


func test_get_damage_state_critical() -> void:
	var b := _create_building(false)
	# Set to 10% HP — below 33%
	b.hp = 55
	assert_str(b.get_damage_state()).is_equal("critical")


# -- Ruins --


func test_destroyed_becomes_ruins() -> void:
	var b := _create_building(false)
	b.take_damage(550, null)
	assert_bool(b._is_ruins).is_true()


func test_ruins_category_is_ruins() -> void:
	var b := _create_building(false)
	b.take_damage(550, null)
	assert_str(b.get_entity_category()).is_equal("ruins")


# -- save_state / load_state with ruins --


func test_save_state_includes_ruins_fields() -> void:
	var b := _create_building(false)
	b.take_damage(550, null)
	var state: Dictionary = b.save_state()
	assert_bool(state["is_ruins"]).is_true()
	assert_float(float(state["ruins_timer"])).is_equal_approx(0.0, 0.001)


# -- get_garrison_attack --


class StubStats:
	func get_stat(stat_name: String) -> float:
		if stat_name == "attack":
			return 5.0
		return 0.0


class StubGarrisonUnit:
	extends Node2D
	var stats: StubStats = null
	var owner_id: int = 0

	func _init() -> void:
		stats = StubStats.new()


func test_get_garrison_attack_empty_returns_zero() -> void:
	var b := _create_building(false)
	assert_int(b.get_garrison_attack()).is_equal(0)


func test_get_garrison_attack_sums_garrisoned_attack() -> void:
	var b := _create_building(false)
	b.building_name = "town_center"
	b.garrison_capacity = 15
	# Directly add units to garrisoned array for testing
	var u1 := StubGarrisonUnit.new()
	add_child(u1)
	auto_free(u1)
	var u2 := StubGarrisonUnit.new()
	add_child(u2)
	auto_free(u2)
	b._garrisoned_units.append(u1)
	b._garrisoned_units.append(u2)
	assert_int(b.get_garrison_attack()).is_equal(10)


func test_get_garrison_attack_skips_null_stats() -> void:
	var b := _create_building(false)
	b.garrison_capacity = 15
	var u := StubGarrisonUnit.new()
	u.stats = null
	add_child(u)
	auto_free(u)
	b._garrisoned_units.append(u)
	assert_int(b.get_garrison_attack()).is_equal(0)


func test_backward_compat_load_no_ruins_fields() -> void:
	var b := _create_building(false)
	# Old save data without ruins fields
	var old_state := {
		"building_name": "house",
		"grid_pos": [5, 5],
		"owner_id": 0,
		"hp": 550,
		"max_hp": 550,
		"under_construction": false,
		"build_progress": 1.0,
		"build_time": 25.0,
		"is_drop_off": false,
		"drop_off_types": [],
	}
	b.load_state(old_state)
	assert_bool(b._is_ruins).is_false()
	assert_float(b._ruins_timer).is_equal_approx(0.0, 0.001)
