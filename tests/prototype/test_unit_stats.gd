extends GdUnitTestSuite
## Tests for UnitStats — stat loading, modifier stacking, save/load.

const UnitStatsScript := preload("res://scripts/prototype/unit_stats.gd")


func _create_stats(id: String = "test_unit", base: Dictionary = {}) -> UnitStats:
	if base.is_empty():
		base = {"hp": 40.0, "attack": 6.0, "defense": 1.0, "speed": 1.2}
	return UnitStats.new(id, base)


# -- from_data --


func test_from_data_loads_villager_stats() -> void:
	var s := UnitStats.from_data("villager")
	assert_str(s.unit_id).is_equal("villager")
	assert_float(s.get_base_stat("hp")).is_equal(25.0)
	assert_float(s.get_base_stat("attack")).is_equal(5.0)
	assert_float(s.get_base_stat("defense")).is_equal(0.0)
	assert_float(s.get_base_stat("speed")).is_equal(1.5)
	assert_float(s.get_base_stat("los")).is_equal(4.0)


func test_from_data_loads_infantry_stats() -> void:
	var s := UnitStats.from_data("infantry")
	assert_str(s.unit_id).is_equal("infantry")
	assert_float(s.get_base_stat("hp")).is_equal(40.0)
	assert_float(s.get_base_stat("attack")).is_equal(6.0)
	assert_float(s.get_base_stat("defense")).is_equal(1.0)
	assert_float(s.get_base_stat("speed")).is_equal(1.2)


func test_from_data_nonexistent_returns_empty() -> void:
	var s := UnitStats.from_data("nonexistent_unit")
	assert_str(s.unit_id).is_equal("nonexistent_unit")
	assert_float(s.get_stat("hp")).is_equal(0.0)


# -- get_stat / get_base_stat --


func test_get_stat_returns_base_value() -> void:
	var s := _create_stats()
	assert_float(s.get_stat("hp")).is_equal(40.0)
	assert_float(s.get_stat("attack")).is_equal(6.0)


func test_get_base_stat_returns_unmodified() -> void:
	var s := _create_stats()
	s.add_modifier("attack", "tech:bronze", 2.0, "flat")
	# get_base_stat ignores modifiers
	assert_float(s.get_base_stat("attack")).is_equal(6.0)
	# get_stat includes modifier
	assert_float(s.get_stat("attack")).is_equal(8.0)


func test_get_stat_missing_returns_zero() -> void:
	var s := _create_stats()
	assert_float(s.get_stat("nonexistent")).is_equal(0.0)


# -- Modifiers --


func test_flat_modifier_adds_to_stat() -> void:
	var s := _create_stats()
	s.add_modifier("attack", "tech:bronze", 2.0, "flat")
	assert_float(s.get_stat("attack")).is_equal(8.0)


func test_percent_modifier_multiplies_stat() -> void:
	var s := _create_stats()
	s.add_modifier("hp", "civ:bonus", 0.5, "percent")
	# 40 * (1 + 0.5) = 60
	assert_float(s.get_stat("hp")).is_equal(60.0)


func test_multiple_modifiers_stack() -> void:
	var s := _create_stats()
	s.add_modifier("attack", "tech:bronze", 2.0, "flat")
	s.add_modifier("attack", "tech:iron", 3.0, "flat")
	s.add_modifier("attack", "civ:bonus", 0.25, "percent")
	# (6 + 2 + 3) * (1 + 0.25) = 11 * 1.25 = 13.75
	assert_float(s.get_stat("attack")).is_equal_approx(13.75, 0.001)


func test_modifier_type_flat_and_percent_combined() -> void:
	var s := _create_stats()
	s.add_modifier("defense", "tech:shields", 4.0, "flat")
	s.add_modifier("defense", "civ:bonus", 0.5, "percent")
	# (1 + 4) * (1 + 0.5) = 5 * 1.5 = 7.5
	assert_float(s.get_stat("defense")).is_equal_approx(7.5, 0.001)


# -- remove_modifier --


func test_remove_modifier_by_source() -> void:
	var s := _create_stats()
	s.add_modifier("attack", "tech:bronze", 2.0, "flat")
	s.add_modifier("attack", "tech:iron", 3.0, "flat")
	s.remove_modifier("attack", "tech:bronze")
	assert_float(s.get_stat("attack")).is_equal(9.0)


func test_remove_all_from_source() -> void:
	var s := _create_stats()
	s.add_modifier("attack", "tech:bronze", 2.0, "flat")
	s.add_modifier("defense", "tech:bronze", 1.0, "flat")
	s.add_modifier("hp", "tech:bronze", 10.0, "flat")
	s.remove_all_from_source("tech:bronze")
	assert_float(s.get_stat("attack")).is_equal(6.0)
	assert_float(s.get_stat("defense")).is_equal(1.0)
	assert_float(s.get_stat("hp")).is_equal(40.0)


func test_has_modifier() -> void:
	var s := _create_stats()
	assert_bool(s.has_modifier("attack", "tech:bronze")).is_false()
	s.add_modifier("attack", "tech:bronze", 2.0, "flat")
	assert_bool(s.has_modifier("attack", "tech:bronze")).is_true()
	assert_bool(s.has_modifier("attack", "tech:iron")).is_false()


# -- get_all_stats --


func test_get_all_stats_returns_computed() -> void:
	var s := _create_stats()
	s.add_modifier("attack", "tech:bronze", 2.0, "flat")
	var all := s.get_all_stats()
	assert_float(all["attack"]).is_equal(8.0)
	assert_float(all["hp"]).is_equal(40.0)


# -- set_base_stat --


func test_set_base_stat_updates_value() -> void:
	var s := _create_stats()
	s.set_base_stat("hp", 100.0)
	assert_float(s.get_base_stat("hp")).is_equal(100.0)
	assert_float(s.get_stat("hp")).is_equal(100.0)


# -- save / load --


func test_save_load_preserves_base_and_modifiers() -> void:
	var s := _create_stats()
	s.add_modifier("attack", "tech:bronze", 2.0, "flat")
	s.add_modifier("hp", "civ:bonus", 0.5, "percent")
	var saved := s.save_state()

	var s2 := UnitStats.new()
	s2.load_state(saved)
	assert_str(s2.unit_id).is_equal("test_unit")
	assert_float(s2.get_stat("attack")).is_equal(8.0)
	assert_float(s2.get_stat("hp")).is_equal(60.0)
	assert_float(s2.get_base_stat("attack")).is_equal(6.0)


# -- signal --


func test_stats_changed_signal_on_add_modifier() -> void:
	var s := _create_stats()
	var monitor := monitor_signals(s)
	s.add_modifier("attack", "tech:bronze", 2.0, "flat")
	await assert_signal(monitor).is_emitted("stats_changed")


func test_stats_changed_signal_on_remove_modifier() -> void:
	var s := _create_stats()
	s.add_modifier("attack", "tech:bronze", 2.0, "flat")
	var monitor := monitor_signals(s)
	s.remove_modifier("attack", "tech:bronze")
	await assert_signal(monitor).is_emitted("stats_changed")


func test_stats_changed_signal_on_set_base_stat() -> void:
	var s := _create_stats()
	var monitor := monitor_signals(s)
	s.set_base_stat("hp", 100.0)
	await assert_signal(monitor).is_emitted("stats_changed")
