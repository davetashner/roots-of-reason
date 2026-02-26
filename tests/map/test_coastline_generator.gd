extends GdUnitTestSuite
## Tests for coastline_generator.gd — adjacency-based terrain reclassification.

const CoastlineGenerator := preload("res://scripts/map/coastline_generator.gd")


func _make_gen(shore_enabled: bool = true) -> RefCounted:
	var gen := CoastlineGenerator.new()
	gen.configure({"shore_enabled": shore_enabled})
	return gen


func _grid_from_rows(rows: Array) -> Dictionary:
	## Build a tile_grid from an array of strings, one char per tile.
	## G=grass, W=water, M=mountain, R=river, S=sand, D=dirt
	var mapping := {"G": "grass", "W": "water", "M": "mountain", "R": "river", "S": "sand", "D": "dirt"}
	var grid: Dictionary = {}
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var ch := row[x]
			if mapping.has(ch):
				grid[Vector2i(x, y)] = mapping[ch]
	return grid


func test_water_next_to_land_becomes_shallows() -> void:
	# G W
	var grid := _grid_from_rows(["GW"])
	var gen := _make_gen()
	var result: Dictionary = gen.generate(grid, 2, 1)
	var changes: Dictionary = result.changes
	assert_str(changes.get(Vector2i(1, 0), "")).is_equal("shallows")


func test_water_surrounded_by_water_becomes_deep_water() -> void:
	# W W W
	# W W W
	# W W W
	var grid := _grid_from_rows(["WWW", "WWW", "WWW"])
	var gen := _make_gen()
	var result: Dictionary = gen.generate(grid, 3, 3)
	var changes: Dictionary = result.changes
	assert_str(changes.get(Vector2i(1, 1), "")).is_equal("deep_water")


func test_land_next_to_water_becomes_shore() -> void:
	# G W
	var grid := _grid_from_rows(["GW"])
	var gen := _make_gen()
	var result: Dictionary = gen.generate(grid, 2, 1)
	var changes: Dictionary = result.changes
	assert_str(changes.get(Vector2i(0, 0), "")).is_equal("shore")


func test_river_tiles_unchanged() -> void:
	# R W
	var grid := _grid_from_rows(["RW"])
	var gen := _make_gen()
	var result: Dictionary = gen.generate(grid, 2, 1)
	var changes: Dictionary = result.changes
	# River should not become shore even though it's next to water
	assert_bool(changes.has(Vector2i(0, 0))).is_false()


func test_mountain_tiles_unchanged() -> void:
	# M W
	var grid := _grid_from_rows(["MW"])
	var gen := _make_gen()
	var result: Dictionary = gen.generate(grid, 2, 1)
	var changes: Dictionary = result.changes
	# Mountain should not become shore
	assert_bool(changes.has(Vector2i(0, 0))).is_false()


func test_diagonal_adjacency_triggers_conversion() -> void:
	# G .
	# . W
	var grid: Dictionary = {Vector2i(0, 0): "grass", Vector2i(1, 1): "water"}
	var gen := _make_gen()
	var result: Dictionary = gen.generate(grid, 2, 2)
	var changes: Dictionary = result.changes
	assert_str(changes.get(Vector2i(0, 0), "")).is_equal("shore")
	assert_str(changes.get(Vector2i(1, 1), "")).is_equal("shallows")


func test_no_cascading() -> void:
	# Shore doesn't trigger more shore. Collect-then-apply means we read
	# original terrain, not intermediate results.
	# G G W W W
	var grid := _grid_from_rows(["GGWWW"])
	var gen := _make_gen()
	var result: Dictionary = gen.generate(grid, 5, 1)
	var changes: Dictionary = result.changes
	# G at (0,0) is NOT adjacent to water — should not become shore
	assert_bool(changes.has(Vector2i(0, 0))).is_false()
	# G at (1,0) IS adjacent to water — becomes shore
	assert_str(changes.get(Vector2i(1, 0), "")).is_equal("shore")


func test_empty_grid_no_changes() -> void:
	var gen := _make_gen()
	var result: Dictionary = gen.generate({}, 0, 0)
	var changes: Dictionary = result.changes
	assert_int(changes.size()).is_equal(0)


func test_shore_disabled_no_changes() -> void:
	var grid := _grid_from_rows(["GW"])
	var gen := _make_gen(false)
	var result: Dictionary = gen.generate(grid, 2, 1)
	var changes: Dictionary = result.changes
	assert_int(changes.size()).is_equal(0)


func test_full_water_grid_all_deep_water() -> void:
	var grid := _grid_from_rows(["WWW", "WWW", "WWW"])
	var gen := _make_gen()
	var result: Dictionary = gen.generate(grid, 3, 3)
	var changes: Dictionary = result.changes
	for pos: Vector2i in changes:
		assert_str(changes[pos]).is_equal("deep_water")


func test_single_land_in_water() -> void:
	# W W W
	# W G W
	# W W W
	var grid := _grid_from_rows(["WWW", "WGW", "WWW"])
	var gen := _make_gen()
	var result: Dictionary = gen.generate(grid, 3, 3)
	var changes: Dictionary = result.changes
	# Center land becomes shore
	assert_str(changes.get(Vector2i(1, 1), "")).is_equal("shore")
	# All 8 surrounding water tiles become shallows (adjacent to land)
	for dir: Vector2i in CoastlineGenerator.DIRECTIONS_8:
		var neighbor := Vector2i(1, 1) + dir
		assert_str(changes.get(neighbor, "")).is_equal("shallows")


func test_three_band_pattern() -> void:
	# G G G W W W W W
	var grid := _grid_from_rows(["GGGWWWWW"])
	var gen := _make_gen()
	var result: Dictionary = gen.generate(grid, 8, 1)
	var changes: Dictionary = result.changes
	# G at x=2 adjacent to water -> shore
	assert_str(changes.get(Vector2i(2, 0), "")).is_equal("shore")
	# W at x=3 adjacent to land -> shallows
	assert_str(changes.get(Vector2i(3, 0), "")).is_equal("shallows")
	# W at x=5 not adjacent to land -> deep_water
	assert_str(changes.get(Vector2i(5, 0), "")).is_equal("deep_water")
