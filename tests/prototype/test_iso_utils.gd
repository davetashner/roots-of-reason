extends GdUnitTestSuite
## Tests for IsoUtils coordinate conversion utilities.


func test_grid_to_screen_origin() -> void:
	var result := IsoUtils.grid_to_screen(Vector2.ZERO)
	assert_vector(result).is_equal(Vector2.ZERO)


func test_grid_to_screen_unit_x() -> void:
	var result := IsoUtils.grid_to_screen(Vector2(1, 0))
	assert_vector(result).is_equal(Vector2(64.0, 32.0))


func test_grid_to_screen_unit_y() -> void:
	var result := IsoUtils.grid_to_screen(Vector2(0, 1))
	assert_vector(result).is_equal(Vector2(-64.0, 32.0))


func test_screen_to_grid_origin() -> void:
	var result := IsoUtils.screen_to_grid(Vector2.ZERO)
	assert_vector(result).is_equal(Vector2.ZERO)


func test_roundtrip_grid_screen_grid() -> void:
	var original := Vector2(3, 5)
	var screen := IsoUtils.grid_to_screen(original)
	var back := IsoUtils.screen_to_grid(screen)
	assert_vector(back).is_equal_approx(original, Vector2(0.01, 0.01))


func test_snap_to_grid_exact() -> void:
	var screen := IsoUtils.grid_to_screen(Vector2(4, 7))
	var snap_result := IsoUtils.snap_to_grid(screen)
	assert_vector(snap_result).is_equal(Vector2i(4, 7))


func test_snap_to_grid_with_offset() -> void:
	var screen := IsoUtils.grid_to_screen(Vector2(4, 7))
	# Small offset should still snap to same cell
	var snap_result := IsoUtils.snap_to_grid(screen + Vector2(5, 5))
	assert_vector(snap_result).is_equal(Vector2i(4, 7))


func test_tile_dimensions() -> void:
	assert_int(IsoUtils.TILE_WIDTH).is_equal(128)
	assert_int(IsoUtils.TILE_HEIGHT).is_equal(64)
