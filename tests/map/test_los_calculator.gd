extends GdUnitTestSuite
## Tests for los_calculator.gd — symmetric shadowcasting FOV.

const LOSCalculator := preload("res://scripts/map/los_calculator.gd")

const MAP_W := 32
const MAP_H := 32


func _no_blocks(_pos: Vector2i) -> bool:
	return false


func _blocks_at(blocking_set: Dictionary) -> Callable:
	return func(pos: Vector2i) -> bool: return blocking_set.has(pos)


# -- Basic visibility tests --


func test_origin_always_visible() -> void:
	var origin := Vector2i(16, 16)
	var result := LOSCalculator.compute_visible_tiles(origin, 6, MAP_W, MAP_H, _no_blocks)
	assert_bool(result.has(origin)).is_true()


func test_open_terrain_full_circle() -> void:
	var origin := Vector2i(16, 16)
	var result := LOSCalculator.compute_visible_tiles(origin, 3, MAP_W, MAP_H, _no_blocks)
	# Should see tiles in all 4 cardinal directions
	assert_bool(result.has(Vector2i(16, 13))).is_true()  # north
	assert_bool(result.has(Vector2i(19, 16))).is_true()  # east
	assert_bool(result.has(Vector2i(16, 19))).is_true()  # south
	assert_bool(result.has(Vector2i(13, 16))).is_true()  # west
	# Should see diagonals too
	assert_bool(result.has(Vector2i(18, 14))).is_true()
	assert_bool(result.has(Vector2i(14, 18))).is_true()


func test_blocking_terrain_hides_tiles_behind() -> void:
	var origin := Vector2i(16, 16)
	# Place a wall directly east at (18, 16)
	var blockers := {Vector2i(18, 16): true}
	var result := LOSCalculator.compute_visible_tiles(origin, 6, MAP_W, MAP_H, _blocks_at(blockers))
	# The blocking tile itself should be visible
	assert_bool(result.has(Vector2i(18, 16))).is_true()
	# Tiles directly behind the wall should NOT be visible
	assert_bool(result.has(Vector2i(20, 16))).is_false()


func test_diagonal_blocking() -> void:
	var origin := Vector2i(16, 16)
	# Place blockers in a diagonal line NE
	var blockers := {Vector2i(17, 15): true, Vector2i(18, 14): true}
	var result := LOSCalculator.compute_visible_tiles(origin, 6, MAP_W, MAP_H, _blocks_at(blockers))
	# Blocking tiles visible
	assert_bool(result.has(Vector2i(17, 15))).is_true()
	# Tiles well behind the diagonal should be blocked
	assert_bool(result.has(Vector2i(20, 12))).is_false()


func test_radius_respected() -> void:
	var origin := Vector2i(16, 16)
	var result := LOSCalculator.compute_visible_tiles(origin, 3, MAP_W, MAP_H, _no_blocks)
	# Tile at distance 5 should NOT be visible with radius 3
	assert_bool(result.has(Vector2i(21, 16))).is_false()
	assert_bool(result.has(Vector2i(16, 21))).is_false()


func test_zero_los_only_origin() -> void:
	var origin := Vector2i(16, 16)
	var result := LOSCalculator.compute_visible_tiles(origin, 0, MAP_W, MAP_H, _no_blocks)
	assert_int(result.size()).is_equal(1)
	assert_bool(result.has(origin)).is_true()


func test_map_bounds_respected() -> void:
	# Origin near corner
	var origin := Vector2i(1, 1)
	var result := LOSCalculator.compute_visible_tiles(origin, 5, MAP_W, MAP_H, _no_blocks)
	# No tile should be out of bounds
	for tile: Vector2i in result:
		assert_bool(tile.x >= 0 and tile.x < MAP_W).is_true()
		assert_bool(tile.y >= 0 and tile.y < MAP_H).is_true()


func test_callable_receives_correct_positions() -> void:
	var checked_positions: Dictionary = {}
	var checker := func(pos: Vector2i) -> bool:
		checked_positions[pos] = true
		return false

	LOSCalculator.compute_visible_tiles(Vector2i(5, 5), 2, MAP_W, MAP_H, checker)
	# Should have checked some positions around origin
	assert_bool(checked_positions.size() > 0).is_true()


func test_symmetric_visibility() -> void:
	# If A can see B, B should be able to see A (given same LOS and no blockers)
	var a := Vector2i(16, 16)
	var b := Vector2i(18, 14)
	var result_a := LOSCalculator.compute_visible_tiles(a, 6, MAP_W, MAP_H, _no_blocks)
	var result_b := LOSCalculator.compute_visible_tiles(b, 6, MAP_W, MAP_H, _no_blocks)
	# A sees B => B sees A
	if result_a.has(b):
		assert_bool(result_b.has(a)).is_true()


func test_large_radius_reasonable_count() -> void:
	var origin := Vector2i(16, 16)
	var result := LOSCalculator.compute_visible_tiles(origin, 6, MAP_W, MAP_H, _no_blocks)
	# Circle area ~ pi*r^2 ~ 113 tiles for r=6, should be roughly that range
	assert_int(result.size()).is_greater(50)
	assert_int(result.size()).is_less(200)
