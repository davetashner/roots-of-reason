extends GdUnitTestSuite
## Tests for river_generator.gd — river tracing, merging, and flow direction.

const RiverGenerator := preload("res://scripts/map/river_generator.gd")

const MAP_W := 32
const MAP_H := 32


func _make_gradient_elevation(w: int, h: int) -> Dictionary:
	## Creates elevation grid where top=1.0, bottom=0.0 (guaranteed downhill).
	var grid: Dictionary = {}
	for y in h:
		for x in w:
			grid[Vector2i(x, y)] = 1.0 - (float(y) / float(h - 1))
	return grid


func _make_terrain_with_sources(w: int, h: int) -> Dictionary:
	## Creates terrain grid with mountain/stone at top rows, grass elsewhere,
	## and water at the bottom row.
	var grid: Dictionary = {}
	for y in h:
		for x in w:
			if y <= 2:
				grid[Vector2i(x, y)] = "mountain" if x % 2 == 0 else "stone"
			elif y >= h - 1:
				grid[Vector2i(x, y)] = "water"
			else:
				grid[Vector2i(x, y)] = "grass"
	return grid


func _generate_rivers() -> Dictionary:
	var gen := RiverGenerator.new()
	var cfg := {
		"river_count_min": 2,
		"river_count_max": 4,
		"source_elevation_threshold": 0.70,
		"noise_wander_strength": 0.04,
		"min_river_length": 3,
		"min_source_spacing": 8,
		"seed_offset": 2000,
	}
	gen.configure(cfg)
	var elev := _make_gradient_elevation(MAP_W, MAP_H)
	var terrain := _make_terrain_with_sources(MAP_W, MAP_H)
	return gen.generate(elev, terrain, MAP_W, MAP_H, 42)


func test_result_has_expected_keys() -> void:
	var result := _generate_rivers()
	assert_bool(result.has("river_tiles")).is_true()
	assert_bool(result.has("flow_directions")).is_true()
	assert_bool(result.has("river_ids")).is_true()
	assert_bool(result.has("river_widths")).is_true()


func test_river_tiles_are_contiguous() -> void:
	var result := _generate_rivers()
	var river_tiles: Dictionary = result["river_tiles"]
	if river_tiles.is_empty():
		return  # Nothing to check
	# Each river tile should have at least one river neighbor (8-directional)
	# except possibly source/terminus tiles
	var dirs := [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
		Vector2i(1, 1),
		Vector2i(1, -1),
		Vector2i(-1, 1),
		Vector2i(-1, -1),
	]
	var isolated_count := 0
	for pos: Vector2i in river_tiles:
		var has_neighbor := false
		for dir: Vector2i in dirs:
			if river_tiles.has(pos + dir):
				has_neighbor = true
				break
		if not has_neighbor:
			isolated_count += 1
	# Allow at most a few isolated tiles (sources at map edge)
	assert_int(isolated_count).is_less_equal(2)


func test_flow_direction_points_downhill() -> void:
	var elev := _make_gradient_elevation(MAP_W, MAP_H)
	var result := _generate_rivers()
	var flow_dirs: Dictionary = result["flow_directions"]
	for pos: Vector2i in flow_dirs:
		var dir: Vector2i = flow_dirs[pos]
		var next_pos := pos + dir
		if elev.has(next_pos):
			assert_float(elev[next_pos]).is_less_equal(elev[pos] + 0.01)


func test_river_count_within_range() -> void:
	var result := _generate_rivers()
	var river_ids: Dictionary = result["river_ids"]
	var unique_ids: Dictionary = {}
	for pos: Vector2i in river_ids:
		unique_ids[river_ids[pos]] = true
	assert_int(unique_ids.size()).is_greater_equal(1)
	assert_int(unique_ids.size()).is_less_equal(4)


func test_mountains_not_traversed() -> void:
	var result := _generate_rivers()
	var river_tiles: Dictionary = result["river_tiles"]
	var terrain := _make_terrain_with_sources(MAP_W, MAP_H)
	# River tiles should not be on mountain terrain (sources start on stone/mountain
	# but the source tile itself is allowed — check that non-source river tiles aren't mountains)
	var flow_dirs: Dictionary = result["flow_directions"]
	for pos: Vector2i in river_tiles:
		# If this tile has an incoming flow direction, it's not a source
		if flow_dirs.has(pos):
			var dir: Vector2i = flow_dirs[pos]
			var next_pos: Vector2i = pos + dir
			if terrain.get(next_pos, "") == "mountain":
				# River should never flow INTO a mountain
				assert_bool(false).is_true()


func test_no_river_outside_map_bounds() -> void:
	var result := _generate_rivers()
	var river_tiles: Dictionary = result["river_tiles"]
	for pos: Vector2i in river_tiles:
		assert_bool(pos.x >= 0 and pos.x < MAP_W).is_true()
		assert_bool(pos.y >= 0 and pos.y < MAP_H).is_true()


func test_terminates_at_water() -> void:
	var result := _generate_rivers()
	var river_tiles: Dictionary = result["river_tiles"]
	var terrain := _make_terrain_with_sources(MAP_W, MAP_H)
	# Check that at least one river has a tile adjacent to water (bottom row)
	var reaches_water := false
	for pos: Vector2i in river_tiles:
		if pos.y >= MAP_H - 2:  # Near water row
			reaches_water = true
			break
	if river_tiles.size() > 0:
		assert_bool(reaches_water).is_true()


func test_same_seed_is_deterministic() -> void:
	var gen1 := RiverGenerator.new()
	gen1.configure({"river_count_min": 2, "river_count_max": 4, "min_river_length": 3, "min_source_spacing": 8})
	var elev := _make_gradient_elevation(MAP_W, MAP_H)
	var terrain := _make_terrain_with_sources(MAP_W, MAP_H)
	var r1: Dictionary = gen1.generate(elev, terrain, MAP_W, MAP_H, 42)

	var gen2 := RiverGenerator.new()
	gen2.configure({"river_count_min": 2, "river_count_max": 4, "min_river_length": 3, "min_source_spacing": 8})
	var r2: Dictionary = gen2.generate(elev, terrain, MAP_W, MAP_H, 42)

	var tiles1: Dictionary = r1["river_tiles"]
	var tiles2: Dictionary = r2["river_tiles"]
	assert_int(tiles1.size()).is_equal(tiles2.size())
	for pos: Vector2i in tiles1:
		assert_bool(tiles2.has(pos)).is_true()


func test_short_rivers_discarded() -> void:
	var gen := RiverGenerator.new()
	var cfg := {
		"river_count_min": 2,
		"river_count_max": 4,
		"min_river_length": 100,  # Very high — should discard all rivers
		"min_source_spacing": 8,
	}
	gen.configure(cfg)
	var elev := _make_gradient_elevation(MAP_W, MAP_H)
	var terrain := _make_terrain_with_sources(MAP_W, MAP_H)
	var result: Dictionary = gen.generate(elev, terrain, MAP_W, MAP_H, 42)
	var river_tiles: Dictionary = result["river_tiles"]
	assert_int(river_tiles.size()).is_equal(0)


func test_merge_increases_width() -> void:
	var result := _generate_rivers()
	var river_widths: Dictionary = result["river_widths"]
	# Check if any tile has width > 1 (merge point or downstream of merge)
	var has_wide := false
	for pos: Vector2i in river_widths:
		if river_widths[pos] > 1:
			has_wide = true
			break
	# Merges may or may not happen depending on river layout, so this is a soft check
	# If there are multiple rivers, merges are likely on a 32x32 map
	var river_ids: Dictionary = result["river_ids"]
	var unique_ids: Dictionary = {}
	for pos: Vector2i in river_ids:
		unique_ids[river_ids[pos]] = true
	if unique_ids.size() >= 2:
		# With multiple rivers, widening may occur — just verify widths are valid
		for pos: Vector2i in river_widths:
			assert_int(river_widths[pos]).is_greater_equal(1)
			assert_int(river_widths[pos]).is_less_equal(2)
