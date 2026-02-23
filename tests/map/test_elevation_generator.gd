extends GdUnitTestSuite
## Tests for elevation_generator.gd — FastNoiseLite elevation grid generation.

const ElevationGenerator := preload("res://scripts/map/elevation_generator.gd")


func _create_generator() -> RefCounted:
	var gen := ElevationGenerator.new()
	var cfg := {
		"frequency": 0.015,
		"octaves": 4,
		"lacunarity": 2.0,
		"gain": 0.5,
		"seed_offset": 1000,
	}
	gen.configure(cfg)
	return gen


func test_returns_correct_grid_size() -> void:
	var gen := _create_generator()
	var grid: Dictionary = gen.generate(16, 16, 42)
	assert_int(grid.size()).is_equal(256)  # 16x16


func test_all_values_normalized_zero_to_one() -> void:
	var gen := _create_generator()
	var grid: Dictionary = gen.generate(32, 32, 42)
	for pos: Vector2i in grid:
		var val: float = grid[pos]
		assert_float(val).is_greater_equal(0.0)
		assert_float(val).is_less_equal(1.0)


func test_same_seed_produces_same_output() -> void:
	var gen1 := _create_generator()
	var gen2 := _create_generator()
	var grid1: Dictionary = gen1.generate(16, 16, 42)
	var grid2: Dictionary = gen2.generate(16, 16, 42)
	for pos: Vector2i in grid1:
		assert_float(grid2[pos]).is_equal(grid1[pos])


func test_different_seeds_produce_different_output() -> void:
	var gen := _create_generator()
	var grid1: Dictionary = gen.generate(16, 16, 42)
	var grid2: Dictionary = gen.generate(16, 16, 99)
	var differences := 0
	for pos: Vector2i in grid1:
		if not is_equal_approx(grid1[pos], grid2[pos]):
			differences += 1
	assert_int(differences).is_greater(0)


func test_empty_config_uses_defaults() -> void:
	var gen := ElevationGenerator.new()
	gen.configure({})
	var grid: Dictionary = gen.generate(8, 8, 42)
	assert_int(grid.size()).is_equal(64)
	for pos: Vector2i in grid:
		assert_float(grid[pos]).is_greater_equal(0.0)
		assert_float(grid[pos]).is_less_equal(1.0)


func test_single_tile_grid() -> void:
	var gen := _create_generator()
	var grid: Dictionary = gen.generate(1, 1, 42)
	assert_int(grid.size()).is_equal(1)
	assert_bool(grid.has(Vector2i(0, 0))).is_true()
	# Single tile normalizes to 0.5 (flat map)
	assert_float(grid[Vector2i(0, 0)]).is_equal(0.5)
