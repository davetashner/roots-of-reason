extends GdUnitTestSuite
## Tests for visibility_manager.gd — explored/visible tile tracking.

const VisibilityManagerScript := preload("res://scripts/prototype/visibility_manager.gd")

const MAP_W := 32
const MAP_H := 32

var _mock_script: GDScript


func before() -> void:
	_mock_script = GDScript.new()
	_mock_script.source_code = (
		"extends Node2D\nvar los: int = 4\n"
		+ "func get_stat(s: String) -> float:\n"
		+ '\tif s == "los": return float(los)\n'
		+ "\treturn 0.0\n"
	)
	_mock_script.reload()


func _no_blocks(_pos: Vector2i) -> bool:
	return false


func _make_mock_unit(grid_x: int, grid_y: int, los_val: int = 4) -> Node2D:
	var unit := Node2D.new()
	unit.set_script(_mock_script)
	unit.los = los_val
	# Position in screen coords (128x64 isometric)
	unit.position = Vector2(
		float(grid_x - grid_y) * 64.0,
		float(grid_x + grid_y) * 32.0,
	)
	return auto_free(unit)


func _make_manager() -> Node:
	var mgr := Node.new()
	mgr.set_script(VisibilityManagerScript)
	mgr.setup(MAP_W, MAP_H, _no_blocks)
	return auto_free(mgr)


# -- Basic tests --


func test_initial_all_unexplored() -> void:
	var mgr := _make_manager()
	assert_bool(mgr.is_explored(0, Vector2i(16, 16))).is_false()
	assert_bool(mgr.is_visible(0, Vector2i(16, 16))).is_false()


func test_update_marks_visible() -> void:
	var mgr := _make_manager()
	var unit := _make_mock_unit(16, 16, 3)
	mgr.update_visibility(0, [unit])
	# Origin tile should be visible
	assert_bool(mgr.is_visible(0, Vector2i(16, 16))).is_true()
	assert_bool(mgr.is_explored(0, Vector2i(16, 16))).is_true()


func test_explored_persists_after_unit_moves() -> void:
	var mgr := _make_manager()
	var unit := _make_mock_unit(16, 16, 3)
	mgr.update_visibility(0, [unit])

	var explored_tile := Vector2i(16, 16)
	assert_bool(mgr.is_explored(0, explored_tile)).is_true()

	# Move unit away
	unit.position = Vector2(0.0, 640.0)  # ~grid (10, 10)
	mgr.update_visibility(0, [unit])

	# Old position should still be explored but no longer visible
	assert_bool(mgr.is_explored(0, explored_tile)).is_true()
	assert_bool(mgr.is_visible(0, explored_tile)).is_false()


func test_multiple_units_union() -> void:
	var mgr := _make_manager()
	var unit_a := _make_mock_unit(10, 10, 2)
	var unit_b := _make_mock_unit(20, 20, 2)
	mgr.update_visibility(0, [unit_a, unit_b])

	# Both unit positions should be visible
	assert_bool(mgr.is_visible(0, Vector2i(10, 10))).is_true()
	assert_bool(mgr.is_visible(0, Vector2i(20, 20))).is_true()


func test_enemy_not_tracked_for_player() -> void:
	var mgr := _make_manager()
	var unit := _make_mock_unit(16, 16, 4)
	# Update for player 1 only
	mgr.update_visibility(1, [unit])

	# Player 0 should not see it
	assert_bool(mgr.is_visible(0, Vector2i(16, 16))).is_false()
	# Player 1 should see it
	assert_bool(mgr.is_visible(1, Vector2i(16, 16))).is_true()


func test_save_preserves_explored() -> void:
	var mgr := _make_manager()
	var unit := _make_mock_unit(16, 16, 3)
	mgr.update_visibility(0, [unit])

	var state: Dictionary = mgr.save_state()
	assert_bool(state.has("explored")).is_true()

	# Load into a new manager
	var mgr2 := _make_manager()
	mgr2.load_state(state)
	assert_bool(mgr2.is_explored(0, Vector2i(16, 16))).is_true()


func test_save_excludes_visible() -> void:
	var mgr := _make_manager()
	var unit := _make_mock_unit(16, 16, 3)
	mgr.update_visibility(0, [unit])

	var state: Dictionary = mgr.save_state()
	# Save should only contain "explored", not "visible"
	assert_bool(state.has("explored")).is_true()
	assert_bool(not state.has("visible")).is_true()


func test_load_backward_compatible() -> void:
	var mgr := _make_manager()
	# Load empty state — should not crash
	mgr.load_state({})
	assert_bool(mgr.is_explored(0, Vector2i(0, 0))).is_false()


# -- Dirty flag tests --


func test_dirty_flag_set_on_first_update() -> void:
	var mgr := _make_manager()
	var unit := _make_mock_unit(16, 16, 3)
	mgr.update_visibility(0, [unit])
	assert_bool(mgr.has_changes(0)).is_true()


func test_dirty_flag_false_when_unchanged() -> void:
	var mgr := _make_manager()
	var unit := _make_mock_unit(16, 16, 3)
	mgr.update_visibility(0, [unit])
	# Update again with same unit at same position — no change
	mgr.update_visibility(0, [unit])
	assert_bool(mgr.has_changes(0)).is_false()


func test_dirty_flag_true_when_unit_moves() -> void:
	var mgr := _make_manager()
	var unit := _make_mock_unit(16, 16, 3)
	mgr.update_visibility(0, [unit])
	# Move unit to a different position
	unit.position = Vector2(0.0, 640.0)
	mgr.update_visibility(0, [unit])
	assert_bool(mgr.has_changes(0)).is_true()


func test_clear_dirty() -> void:
	var mgr := _make_manager()
	var unit := _make_mock_unit(16, 16, 3)
	mgr.update_visibility(0, [unit])
	assert_bool(mgr.has_changes(0)).is_true()
	mgr.clear_dirty(0)
	assert_bool(mgr.has_changes(0)).is_false()


func test_has_changes_false_for_unknown_player() -> void:
	var mgr := _make_manager()
	assert_bool(mgr.has_changes(99)).is_false()


func test_signal_not_emitted_when_unchanged() -> void:
	var mgr := _make_manager()
	add_child(mgr)
	var unit := _make_mock_unit(16, 16, 3)
	mgr.update_visibility(0, [unit])

	var signal_fired: Array = [false]
	mgr.visibility_changed.connect(func(_pid: int) -> void: signal_fired[0] = true)

	# Update with same position — should NOT fire signal
	signal_fired[0] = false
	mgr.update_visibility(0, [unit])
	assert_bool(signal_fired[0]).is_false()


# -- FOV cache tests --


func test_cache_populated_after_update() -> void:
	var mgr := _make_manager()
	var unit := _make_mock_unit(16, 16, 3)
	mgr.update_visibility(0, [unit])
	assert_int(mgr.get_fov_cache_size()).is_equal(1)


func test_cache_reused_when_unit_stationary() -> void:
	var mgr := _make_manager()
	var unit := _make_mock_unit(16, 16, 3)
	mgr.update_visibility(0, [unit])

	var visible_first: Dictionary = mgr.get_visible_tiles(0).duplicate()

	# Update again without moving — result should be identical
	mgr.update_visibility(0, [unit])

	var visible_second: Dictionary = mgr.get_visible_tiles(0)
	assert_int(visible_second.size()).is_equal(visible_first.size())
	for tile: Vector2i in visible_first:
		assert_bool(visible_second.has(tile)).is_true()


func test_cache_invalidated_when_unit_moves() -> void:
	var mgr := _make_manager()
	var unit := _make_mock_unit(16, 16, 3)
	mgr.update_visibility(0, [unit])

	# Should see origin
	assert_bool(mgr.is_visible(0, Vector2i(16, 16))).is_true()

	# Move unit to a different grid cell
	unit.position = Vector2(0.0, 640.0)  # ~grid (10, 10)
	mgr.update_visibility(0, [unit])

	# Old origin should no longer be visible; new position should be
	assert_bool(mgr.is_visible(0, Vector2i(16, 16))).is_false()
	assert_bool(mgr.is_visible(0, Vector2i(10, 10))).is_true()
	# Cache should still have exactly 1 entry (updated, not duplicated)
	assert_int(mgr.get_fov_cache_size()).is_equal(1)


func test_cache_evicts_removed_units() -> void:
	var mgr := _make_manager()
	var unit_a := _make_mock_unit(10, 10, 2)
	var unit_b := _make_mock_unit(20, 20, 2)
	mgr.update_visibility(0, [unit_a, unit_b])
	assert_int(mgr.get_fov_cache_size()).is_equal(2)

	# Remove unit_b from the list
	mgr.update_visibility(0, [unit_a])
	assert_int(mgr.get_fov_cache_size()).is_equal(1)


func test_invalidate_fov_cache_clears_all() -> void:
	var mgr := _make_manager()
	var unit := _make_mock_unit(16, 16, 3)
	mgr.update_visibility(0, [unit])
	assert_int(mgr.get_fov_cache_size()).is_equal(1)

	mgr.invalidate_fov_cache()
	assert_int(mgr.get_fov_cache_size()).is_equal(0)


func test_load_state_clears_cache() -> void:
	var mgr := _make_manager()
	var unit := _make_mock_unit(16, 16, 3)
	mgr.update_visibility(0, [unit])
	assert_int(mgr.get_fov_cache_size()).is_equal(1)

	mgr.load_state({})
	assert_int(mgr.get_fov_cache_size()).is_equal(0)
