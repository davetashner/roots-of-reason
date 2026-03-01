extends GdUnitTestSuite
## Tests for terrain_mapper.gd — elevation+moisture to terrain type mapping
## and island mask edge forcing.

const TerrainMapperScript := preload("res://scripts/map/terrain_mapper.gd")
const ElevationGenerator := preload("res://scripts/map/elevation_generator.gd")


func _create_mapper() -> RefCounted:
	var mapper := TerrainMapperScript.new()
	mapper.configure({})
	return mapper


# -- Threshold mapping tests --


func test_deep_water() -> void:
	var mapper := _create_mapper()
	assert_str(mapper.get_terrain(0.1, 0.5)).is_equal("water")


func test_water_at_zero() -> void:
	var mapper := _create_mapper()
	assert_str(mapper.get_terrain(0.0, 0.5)).is_equal("water")


func test_sand() -> void:
	var mapper := _create_mapper()
	assert_str(mapper.get_terrain(0.35, 0.5)).is_equal("sand")


func test_desert_low_moisture_in_sand_band() -> void:
	var mapper := _create_mapper()
	# Elevation in sand band (0.30-0.40), very low moisture -> desert
	assert_str(mapper.get_terrain(0.35, 0.1)).is_equal("desert")


func test_sand_not_desert_above_threshold() -> void:
	var mapper := _create_mapper()
	# Elevation in sand band, moisture above desert threshold -> sand
	assert_str(mapper.get_terrain(0.35, 0.3)).is_equal("sand")


func test_desert_boundary_at_threshold() -> void:
	var mapper := _create_mapper()
	# Exactly at desert threshold (0.25) -> sand (desert is < 0.25)
	assert_str(mapper.get_terrain(0.35, 0.25)).is_equal("sand")


func test_grass() -> void:
	var mapper := _create_mapper()
	assert_str(mapper.get_terrain(0.5, 0.4)).is_equal("grass")


func test_forest_high_moisture() -> void:
	var mapper := _create_mapper()
	assert_str(mapper.get_terrain(0.5, 0.7)).is_equal("forest")


func test_dirt_low_moisture() -> void:
	var mapper := _create_mapper()
	assert_str(mapper.get_terrain(0.5, 0.1)).is_equal("dirt")


func test_stone() -> void:
	var mapper := _create_mapper()
	assert_str(mapper.get_terrain(0.8, 0.5)).is_equal("stone")


func test_mountain() -> void:
	var mapper := _create_mapper()
	assert_str(mapper.get_terrain(0.9, 0.5)).is_equal("mountain")


func test_mountain_at_one() -> void:
	var mapper := _create_mapper()
	assert_str(mapper.get_terrain(1.0, 0.5)).is_equal("mountain")


# -- Boundary tests --


func test_boundary_water_sand() -> void:
	var mapper := _create_mapper()
	# Exactly at 0.3 should be sand (not water: water is < 0.3)
	assert_str(mapper.get_terrain(0.3, 0.5)).is_equal("sand")


func test_boundary_sand_grass() -> void:
	var mapper := _create_mapper()
	# Exactly at 0.4 should be grass range (not sand: sand is < 0.4)
	var terrain: String = mapper.get_terrain(0.4, 0.4)
	assert_bool(terrain in ["grass", "dirt", "forest"]).is_true()


func test_boundary_grass_stone() -> void:
	var mapper := _create_mapper()
	# Exactly at 0.7 should be stone (not grass: grass is < 0.7)
	assert_str(mapper.get_terrain(0.7, 0.5)).is_equal("stone")


func test_boundary_stone_mountain() -> void:
	var mapper := _create_mapper()
	# Exactly at 0.85 should be mountain (not stone: stone is < 0.85)
	assert_str(mapper.get_terrain(0.85, 0.5)).is_equal("mountain")


# -- Custom thresholds --


func test_configure_custom_thresholds() -> void:
	var mapper := TerrainMapperScript.new()
	var cfg := {
		"terrain_thresholds":
		{
			"water": 0.5,
			"sand": 0.6,
			"grass": 0.8,
			"stone": 0.9,
			"mountain": 1.0,
		},
	}
	mapper.configure(cfg)
	# With water threshold at 0.5, elevation 0.4 should be water
	assert_str(mapper.get_terrain(0.4, 0.5)).is_equal("water")
	# Elevation 0.55 should be sand (0.5 <= e < 0.6)
	assert_str(mapper.get_terrain(0.55, 0.5)).is_equal("sand")


func test_configure_custom_moisture_thresholds() -> void:
	var mapper := TerrainMapperScript.new()
	var cfg := {
		"forest_moisture_threshold": 0.3,
		"dirt_moisture_threshold": 0.1,
	}
	mapper.configure(cfg)
	# With forest threshold at 0.3, moisture 0.35 in grass range should be forest
	assert_str(mapper.get_terrain(0.5, 0.35)).is_equal("forest")
	# Moisture 0.05 should be dirt
	assert_str(mapper.get_terrain(0.5, 0.05)).is_equal("dirt")


# -- Island mask tests --


func test_island_mask_edges_are_zero() -> void:
	var grid: Dictionary = {}
	for y in 20:
		for x in 20:
			grid[Vector2i(x, y)] = 0.8  # High elevation everywhere
	TerrainMapperScript.apply_island_mask(grid, 20, 20, 3, 8)
	# Edge cells (distance < 3) should be 0.0
	assert_float(grid[Vector2i(0, 0)]).is_equal(0.0)
	assert_float(grid[Vector2i(1, 0)]).is_equal(0.0)
	assert_float(grid[Vector2i(0, 1)]).is_equal(0.0)
	assert_float(grid[Vector2i(19, 19)]).is_equal(0.0)
	assert_float(grid[Vector2i(2, 0)]).is_equal(0.0)


func test_island_mask_center_unaffected() -> void:
	var grid: Dictionary = {}
	for y in 30:
		for x in 30:
			grid[Vector2i(x, y)] = 0.75
	TerrainMapperScript.apply_island_mask(grid, 30, 30, 3, 8)
	# Center cell (15,15) has min_edge_distance = 14, well past edge+falloff (3+8=11)
	assert_float(grid[Vector2i(15, 15)]).is_equal(0.75)


func test_island_mask_falloff_gradual() -> void:
	var grid: Dictionary = {}
	for y in 30:
		for x in 30:
			grid[Vector2i(x, y)] = 1.0
	TerrainMapperScript.apply_island_mask(grid, 30, 30, 3, 8)
	# Cell at x=3 (dist_to_edge=3) is first falloff cell: t = 0/8 = 0.0
	assert_float(grid[Vector2i(3, 15)]).is_equal(0.0)
	# Cell at x=7 (dist_to_edge=7) is in falloff: t = 4/8 = 0.5
	assert_float(grid[Vector2i(7, 15)]).is_equal(0.5)
	# Cell at x=10 (dist_to_edge=10) is in falloff: t = 7/8 = 0.875
	assert_float(grid[Vector2i(10, 15)]).is_equal(0.875)
	# Cell at x=11 (dist_to_edge=11) is past falloff, should be 1.0
	assert_float(grid[Vector2i(11, 15)]).is_equal(1.0)


# -- Seed reproducibility integration test --


func test_seed_reproducibility() -> void:
	var elev_gen := ElevationGenerator.new()
	elev_gen.configure({"frequency": 0.015, "octaves": 4, "seed_offset": 1000})
	var moisture_gen := ElevationGenerator.new()
	moisture_gen.configure({"frequency": 0.02, "octaves": 3, "seed_offset": 3000})

	var mapper := _create_mapper()

	# Generate twice with same seed
	var elev1: Dictionary = elev_gen.generate(16, 16, 42)
	var moist1: Dictionary = moisture_gen.generate(16, 16, 42)
	var terrains1: Dictionary = {}
	for pos: Vector2i in elev1:
		terrains1[pos] = mapper.get_terrain(elev1[pos], moist1[pos])

	var elev2: Dictionary = elev_gen.generate(16, 16, 42)
	var moist2: Dictionary = moisture_gen.generate(16, 16, 42)
	var terrains2: Dictionary = {}
	for pos: Vector2i in elev2:
		terrains2[pos] = mapper.get_terrain(elev2[pos], moist2[pos])

	for pos: Vector2i in terrains1:
		assert_str(terrains2[pos]).is_equal(terrains1[pos])


func test_different_seeds_produce_different_terrain() -> void:
	var elev_gen := ElevationGenerator.new()
	elev_gen.configure({"frequency": 0.015, "octaves": 4, "seed_offset": 1000})
	var moisture_gen := ElevationGenerator.new()
	moisture_gen.configure({"frequency": 0.02, "octaves": 3, "seed_offset": 3000})

	var mapper := _create_mapper()

	var elev1: Dictionary = elev_gen.generate(16, 16, 42)
	var moist1: Dictionary = moisture_gen.generate(16, 16, 42)
	var terrains1: Dictionary = {}
	for pos: Vector2i in elev1:
		terrains1[pos] = mapper.get_terrain(elev1[pos], moist1[pos])

	var elev2: Dictionary = elev_gen.generate(16, 16, 99)
	var moist2: Dictionary = moisture_gen.generate(16, 16, 99)
	var terrains2: Dictionary = {}
	for pos: Vector2i in elev2:
		terrains2[pos] = mapper.get_terrain(elev2[pos], moist2[pos])

	var differences := 0
	for pos: Vector2i in terrains1:
		if terrains1[pos] != terrains2.get(pos, ""):
			differences += 1
	assert_int(differences).is_greater(0)


# -- Smooth terrain tests --


func _build_grid(rows: Array) -> Dictionary:
	## Helper: build tile_grid from 2D array of terrain strings.
	var grid: Dictionary = {}
	for y in rows.size():
		var row: Array = rows[y]
		for x in row.size():
			grid[Vector2i(x, y)] = row[x]
	return grid


func test_smooth_terrain_removes_isolated_tile() -> void:
	# 3x3 grid: center is "dirt" surrounded by 8 "grass" tiles
	var grid := _build_grid(
		[
			["grass", "grass", "grass"],
			["grass", "dirt", "grass"],
			["grass", "grass", "grass"],
		]
	)
	TerrainMapperScript.smooth_terrain(grid, 3, 3, 1)
	# All 8 neighbors are grass, so dirt should flip to grass
	assert_str(grid[Vector2i(1, 1)]).is_equal("grass")


func test_smooth_terrain_preserves_majority() -> void:
	# 3x3 grid: center is "grass" surrounded by 5 "grass" and 3 "dirt"
	var grid := _build_grid(
		[
			["grass", "grass", "grass"],
			["dirt", "grass", "dirt"],
			["dirt", "grass", "grass"],
		]
	)
	TerrainMapperScript.smooth_terrain(grid, 3, 3, 1)
	# Center has 5 grass neighbors, should stay grass
	assert_str(grid[Vector2i(1, 1)]).is_equal("grass")


func test_smooth_terrain_skips_water() -> void:
	# Water tiles should never be changed
	var grid := _build_grid(
		[
			["grass", "grass", "grass"],
			["grass", "water", "grass"],
			["grass", "grass", "grass"],
		]
	)
	TerrainMapperScript.smooth_terrain(grid, 3, 3, 1)
	assert_str(grid[Vector2i(1, 1)]).is_equal("water")


func test_smooth_terrain_zero_passes_no_change() -> void:
	var grid := _build_grid(
		[
			["grass", "grass", "grass"],
			["grass", "dirt", "grass"],
			["grass", "grass", "grass"],
		]
	)
	TerrainMapperScript.smooth_terrain(grid, 3, 3, 0)
	assert_str(grid[Vector2i(1, 1)]).is_equal("dirt")


func test_smooth_terrain_requires_supermajority() -> void:
	# 4 grass vs 4 dirt neighbors — should NOT change (needs >= 5)
	var grid := _build_grid(
		[
			["dirt", "grass", "dirt"],
			["grass", "forest", "dirt"],
			["grass", "grass", "dirt"],
		]
	)
	TerrainMapperScript.smooth_terrain(grid, 3, 3, 1)
	assert_str(grid[Vector2i(1, 1)]).is_equal("forest")


# -- Blend borders tests --


func test_blend_borders_changes_border_tiles() -> void:
	# 5x3 grid: left half grass, right half dirt — border at x=2
	var grid := _build_grid(
		[
			["grass", "grass", "dirt", "dirt", "dirt"],
			["grass", "grass", "dirt", "dirt", "dirt"],
			["grass", "grass", "dirt", "dirt", "dirt"],
		]
	)
	# High blend chance to guarantee some changes
	TerrainMapperScript.blend_borders(grid, 5, 3, 42, 1.0)
	# Border tiles (x=1 or x=2) should have some blending
	var changed := 0
	for y in 3:
		if grid[Vector2i(1, y)] != "grass":
			changed += 1
		if grid[Vector2i(2, y)] != "dirt":
			changed += 1
	assert_int(changed).is_greater(0)


func test_blend_borders_zero_chance_no_change() -> void:
	var grid := _build_grid(
		[
			["grass", "grass", "dirt", "dirt"],
			["grass", "grass", "dirt", "dirt"],
		]
	)
	var original: Dictionary = grid.duplicate()
	TerrainMapperScript.blend_borders(grid, 4, 2, 42, 0.0)
	for pos: Vector2i in original:
		assert_str(grid[pos]).is_equal(original[pos])


func test_blend_borders_skips_water() -> void:
	var grid := _build_grid(
		[
			["grass", "water", "dirt"],
			["grass", "water", "dirt"],
		]
	)
	TerrainMapperScript.blend_borders(grid, 3, 2, 42, 1.0)
	# Water tiles should never change
	assert_str(grid[Vector2i(1, 0)]).is_equal("water")
	assert_str(grid[Vector2i(1, 1)]).is_equal("water")


func test_blend_borders_deterministic() -> void:
	var grid1 := _build_grid(
		[
			["grass", "grass", "dirt", "dirt"],
			["grass", "grass", "dirt", "dirt"],
			["grass", "grass", "dirt", "dirt"],
		]
	)
	var grid2 := _build_grid(
		[
			["grass", "grass", "dirt", "dirt"],
			["grass", "grass", "dirt", "dirt"],
			["grass", "grass", "dirt", "dirt"],
		]
	)
	TerrainMapperScript.blend_borders(grid1, 4, 3, 42, 0.5)
	TerrainMapperScript.blend_borders(grid2, 4, 3, 42, 0.5)
	for pos: Vector2i in grid1:
		assert_str(grid2[pos]).is_equal(grid1[pos])


# -- Forest clearings tests --


func test_forest_clearings_converts_some_forest_to_grass() -> void:
	# All-forest grid — some should become grass with high clearing chance
	var grid := _build_grid(
		[
			["forest", "forest", "forest", "forest", "forest"],
			["forest", "forest", "forest", "forest", "forest"],
			["forest", "forest", "forest", "forest", "forest"],
			["forest", "forest", "forest", "forest", "forest"],
			["forest", "forest", "forest", "forest", "forest"],
		]
	)
	TerrainMapperScript.add_forest_clearings(grid, 5, 5, 42, 0.5)
	var grass_count := 0
	for pos: Vector2i in grid:
		if grid[pos] == "grass":
			grass_count += 1
	assert_int(grass_count).is_greater(0)


func test_forest_clearings_zero_chance_no_change() -> void:
	var grid := _build_grid(
		[
			["forest", "forest", "forest"],
			["forest", "forest", "forest"],
		]
	)
	TerrainMapperScript.add_forest_clearings(grid, 3, 2, 42, 0.0)
	for pos: Vector2i in grid:
		assert_str(grid[pos]).is_equal("forest")


func test_forest_clearings_ignores_non_forest() -> void:
	var grid := _build_grid(
		[
			["grass", "dirt", "sand"],
			["water", "stone", "mountain"],
		]
	)
	var original: Dictionary = grid.duplicate()
	TerrainMapperScript.add_forest_clearings(grid, 3, 2, 42, 1.0)
	for pos: Vector2i in original:
		assert_str(grid[pos]).is_equal(original[pos])


func test_forest_clearings_deterministic() -> void:
	var grid1 := _build_grid(
		[
			["forest", "forest", "forest", "forest"],
			["forest", "forest", "forest", "forest"],
			["forest", "forest", "forest", "forest"],
		]
	)
	var grid2 := _build_grid(
		[
			["forest", "forest", "forest", "forest"],
			["forest", "forest", "forest", "forest"],
			["forest", "forest", "forest", "forest"],
		]
	)
	TerrainMapperScript.add_forest_clearings(grid1, 4, 3, 42, 0.3)
	TerrainMapperScript.add_forest_clearings(grid2, 4, 3, 42, 0.3)
	for pos: Vector2i in grid1:
		assert_str(grid2[pos]).is_equal(grid1[pos])
