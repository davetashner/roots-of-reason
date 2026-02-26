extends GdUnitTestSuite
## Tests for tilemap_terrain.gd — terrain property lookups, save/load, bounds.

const TerrainScript := preload("res://scripts/map/tilemap_terrain.gd")


func _create_terrain_map() -> TileMapLayer:
	var map := TileMapLayer.new()
	map.set_script(TerrainScript)
	# Inject small config to avoid file loading in tests
	map._map_width = 8
	map._map_height = 8
	map._seed_value = 42
	map._terrain_weights = {
		"grass": 40,
		"dirt": 10,
		"sand": 5,
		"water": 10,
		"forest": 15,
		"stone": 10,
		"mountain": 10,
	}
	map._terrain_properties = {
		"grass": {"buildable": true, "blocks_los": false},
		"dirt": {"buildable": true, "blocks_los": false},
		"sand": {"buildable": true, "blocks_los": false},
		"water": {"buildable": false, "blocks_los": false},
		"forest": {"buildable": true, "blocks_los": true},
		"stone": {"buildable": true, "blocks_los": false},
		"mountain": {"buildable": false, "blocks_los": true},
		"shore": {"buildable": true, "blocks_los": false},
		"shallows": {"buildable": false, "blocks_los": false},
		"deep_water": {"buildable": false, "blocks_los": false},
	}
	map._terrain_costs = {
		"grass": 1.0,
		"dirt": 1.0,
		"sand": 1.5,
		"forest": 2.0,
		"stone": 1.5,
		"water": -1,
		"mountain": -1,
		"shore": 1.0,
		"shallows": 3.0,
		"deep_water": -1,
	}
	map._map_gen_config = {
		"elevation_noise":
		{
			"frequency": 0.015,
			"octaves": 4,
			"lacunarity": 2.0,
			"gain": 0.5,
			"seed_offset": 1000,
		},
		"moisture_noise":
		{
			"frequency": 0.02,
			"octaves": 3,
			"lacunarity": 2.0,
			"gain": 0.5,
			"seed_offset": 3000,
		},
		"terrain_thresholds":
		{
			"water": 0.30,
			"sand": 0.40,
			"grass": 0.70,
			"stone": 0.85,
			"mountain": 1.0,
		},
		"forest_moisture_threshold": 0.55,
		"dirt_moisture_threshold": 0.30,
		"island_edge_width": 1,
		"island_falloff_width": 2,
		"coastline_generation": {"shore_enabled": true},
	}
	# Build tileset and generate map without _ready (avoid DataLoader dependency)
	map._build_tileset()
	map._generate_map()
	return auto_free(map)


# -- Terrain property lookups --


func test_get_terrain_at_returns_valid_terrain() -> void:
	var map := _create_terrain_map()
	var terrain: String = map.get_terrain_at(Vector2i(0, 0))
	assert_str(terrain).is_not_empty()
	var valid_types := [
		"grass", "dirt", "sand", "water", "forest", "stone", "mountain", "shore", "shallows", "deep_water"
	]
	assert_bool(terrain in valid_types).is_true()


func test_get_terrain_at_out_of_bounds_returns_empty() -> void:
	var map := _create_terrain_map()
	assert_str(map.get_terrain_at(Vector2i(-1, 0))).is_empty()
	assert_str(map.get_terrain_at(Vector2i(100, 100))).is_empty()


func test_water_is_not_buildable() -> void:
	var map := _create_terrain_map()
	# Manually set a cell to water for deterministic test
	map._tile_grid[Vector2i(0, 0)] = "water"
	assert_bool(map.is_buildable(Vector2i(0, 0))).is_false()


func test_mountain_is_not_buildable() -> void:
	var map := _create_terrain_map()
	map._tile_grid[Vector2i(0, 0)] = "mountain"
	assert_bool(map.is_buildable(Vector2i(0, 0))).is_false()


func test_grass_is_buildable() -> void:
	var map := _create_terrain_map()
	map._tile_grid[Vector2i(0, 0)] = "grass"
	assert_bool(map.is_buildable(Vector2i(0, 0))).is_true()


func test_forest_blocks_los() -> void:
	var map := _create_terrain_map()
	map._tile_grid[Vector2i(0, 0)] = "forest"
	assert_bool(map.blocks_los(Vector2i(0, 0))).is_true()


func test_mountain_blocks_los() -> void:
	var map := _create_terrain_map()
	map._tile_grid[Vector2i(0, 0)] = "mountain"
	assert_bool(map.blocks_los(Vector2i(0, 0))).is_true()


func test_grass_does_not_block_los() -> void:
	var map := _create_terrain_map()
	map._tile_grid[Vector2i(0, 0)] = "grass"
	assert_bool(map.blocks_los(Vector2i(0, 0))).is_false()


func test_water_movement_cost_is_impassable() -> void:
	var map := _create_terrain_map()
	map._tile_grid[Vector2i(0, 0)] = "water"
	assert_float(map.get_movement_cost(Vector2i(0, 0))).is_equal(-1.0)


func test_grass_movement_cost() -> void:
	var map := _create_terrain_map()
	map._tile_grid[Vector2i(0, 0)] = "grass"
	assert_float(map.get_movement_cost(Vector2i(0, 0))).is_equal(1.0)


func test_forest_movement_cost() -> void:
	var map := _create_terrain_map()
	map._tile_grid[Vector2i(0, 0)] = "forest"
	assert_float(map.get_movement_cost(Vector2i(0, 0))).is_equal(2.0)


func test_sand_movement_cost() -> void:
	var map := _create_terrain_map()
	map._tile_grid[Vector2i(0, 0)] = "sand"
	assert_float(map.get_movement_cost(Vector2i(0, 0))).is_equal(1.5)


func test_out_of_bounds_movement_cost_is_impassable() -> void:
	var map := _create_terrain_map()
	assert_float(map.get_movement_cost(Vector2i(-1, -1))).is_equal(-1.0)


func test_out_of_bounds_is_not_buildable() -> void:
	var map := _create_terrain_map()
	assert_bool(map.is_buildable(Vector2i(-1, -1))).is_false()


# -- Map size and grid --


func test_get_map_size_returns_width() -> void:
	var map := _create_terrain_map()
	assert_int(map.get_map_size()).is_equal(8)


func test_get_map_dimensions() -> void:
	var map := _create_terrain_map()
	assert_object(map.get_map_dimensions()).is_equal(Vector2i(8, 8))


func test_get_tile_grid_is_populated() -> void:
	var map := _create_terrain_map()
	var grid: Dictionary = map.get_tile_grid()
	assert_int(grid.size()).is_equal(64)  # 8x8


func test_all_cells_have_terrain() -> void:
	var map := _create_terrain_map()
	var grid: Dictionary = map.get_tile_grid()
	for row in 8:
		for col in 8:
			assert_bool(grid.has(Vector2i(col, row))).is_true()


# -- Save / Load roundtrip --


func test_save_state_contains_expected_keys() -> void:
	var map := _create_terrain_map()
	var state: Dictionary = map.save_state()
	assert_bool(state.has("map_width")).is_true()
	assert_bool(state.has("map_height")).is_true()
	assert_bool(state.has("seed")).is_true()
	assert_bool(state.has("tile_grid")).is_true()


func test_save_load_roundtrip_preserves_terrain() -> void:
	var map := _create_terrain_map()
	# Remember terrain at a specific position
	var original_terrain: String = map.get_terrain_at(Vector2i(3, 3))
	var state: Dictionary = map.save_state()

	# Create a new map and load state
	var map2 := _create_terrain_map()
	map2.load_state(state)

	assert_str(map2.get_terrain_at(Vector2i(3, 3))).is_equal(original_terrain)
	assert_int(map2.get_map_size()).is_equal(8)


func test_save_load_roundtrip_preserves_all_cells() -> void:
	var map := _create_terrain_map()
	var state: Dictionary = map.save_state()

	var map2 := _create_terrain_map()
	map2.load_state(state)

	var grid1: Dictionary = map.get_tile_grid()
	var grid2: Dictionary = map2.get_tile_grid()
	assert_int(grid2.size()).is_equal(grid1.size())
	for pos: Vector2i in grid1:
		assert_str(grid2.get(pos, "")).is_equal(grid1[pos])


# -- Deterministic generation --


func test_same_seed_produces_same_map() -> void:
	var map1 := _create_terrain_map()
	var map2 := _create_terrain_map()
	var grid1: Dictionary = map1.get_tile_grid()
	var grid2: Dictionary = map2.get_tile_grid()
	for pos: Vector2i in grid1:
		assert_str(grid2.get(pos, "")).is_equal(grid1[pos])


# -- River integration --


func _create_terrain_map_with_rivers() -> TileMapLayer:
	var map := TileMapLayer.new()
	map.set_script(TerrainScript)
	map._map_width = 32
	map._map_height = 32
	map._seed_value = 42
	map._terrain_weights = {
		"grass": 30,
		"dirt": 5,
		"sand": 5,
		"water": 10,
		"forest": 10,
		"stone": 20,
		"mountain": 20,
	}
	map._terrain_properties = {
		"grass": {"buildable": true, "blocks_los": false},
		"dirt": {"buildable": true, "blocks_los": false},
		"sand": {"buildable": true, "blocks_los": false},
		"water": {"buildable": false, "blocks_los": false},
		"forest": {"buildable": true, "blocks_los": true},
		"stone": {"buildable": true, "blocks_los": false},
		"mountain": {"buildable": false, "blocks_los": true},
		"river": {"buildable": false, "blocks_los": false},
	}
	map._terrain_costs = {
		"grass": 1.0,
		"dirt": 1.0,
		"sand": 1.5,
		"forest": 2.0,
		"stone": 1.5,
		"water": -1,
		"mountain": -1,
		"river": 3.0,
	}
	map._map_gen_config = {
		"elevation_noise":
		{
			"frequency": 0.015,
			"octaves": 4,
			"lacunarity": 2.0,
			"gain": 0.5,
			"seed_offset": 1000,
		},
		"moisture_noise":
		{
			"frequency": 0.02,
			"octaves": 3,
			"lacunarity": 2.0,
			"gain": 0.5,
			"seed_offset": 3000,
		},
		"terrain_thresholds":
		{
			"water": 0.30,
			"sand": 0.40,
			"grass": 0.70,
			"stone": 0.85,
			"mountain": 1.0,
		},
		"forest_moisture_threshold": 0.55,
		"dirt_moisture_threshold": 0.30,
		"island_edge_width": 2,
		"island_falloff_width": 4,
		"river_generation":
		{
			"river_count_min": 2,
			"river_count_max": 4,
			"source_elevation_threshold": 0.70,
			"noise_wander_strength": 0.04,
			"min_river_length": 3,
			"min_source_spacing": 8,
			"seed_offset": 2000,
		},
	}
	map._build_tileset()
	map._generate_map()
	return auto_free(map)


func test_save_state_includes_river_data_key() -> void:
	var map := _create_terrain_map_with_rivers()
	var state: Dictionary = map.save_state()
	assert_bool(state.has("river_data")).is_true()


func test_save_load_roundtrip_preserves_rivers() -> void:
	var map := _create_terrain_map_with_rivers()
	var state: Dictionary = map.save_state()

	var map2 := _create_terrain_map_with_rivers()
	map2.load_state(state)

	# Check river tiles match
	for pos: Vector2i in map._river_tiles:
		assert_bool(map2.is_river(pos)).is_true()
	# Check flow directions match
	for pos: Vector2i in map._flow_directions:
		assert_object(map2.get_flow_direction(pos)).is_equal(map.get_flow_direction(pos))


func test_river_tile_is_not_buildable() -> void:
	var map := _create_terrain_map()
	map._terrain_properties["river"] = {"buildable": false, "blocks_los": false}
	map._tile_grid[Vector2i(0, 0)] = "river"
	assert_bool(map.is_buildable(Vector2i(0, 0))).is_false()


func test_river_tile_does_not_block_los() -> void:
	var map := _create_terrain_map()
	map._terrain_properties["river"] = {"buildable": false, "blocks_los": false}
	map._tile_grid[Vector2i(0, 0)] = "river"
	assert_bool(map.blocks_los(Vector2i(0, 0))).is_false()


func test_get_river_id_returns_negative_for_non_river() -> void:
	var map := _create_terrain_map()
	assert_int(map.get_river_id(Vector2i(0, 0))).is_equal(-1)


func test_get_elevation_at_returns_zero_for_out_of_bounds() -> void:
	var map := _create_terrain_map()
	assert_float(map.get_elevation_at(Vector2i(-1, -1))).is_equal(0.0)


func test_backward_compat_load_without_river_data() -> void:
	var map := _create_terrain_map()
	# Simulate old save format (no river_data key)
	var old_state := {
		"map_width": 8,
		"map_height": 8,
		"seed": 42,
		"tile_grid": {"0,0": "grass", "1,0": "dirt"},
	}
	map.load_state(old_state)
	# Should not crash, rivers should be empty
	assert_bool(map.is_river(Vector2i(0, 0))).is_false()
	assert_int(map.get_river_id(Vector2i(0, 0))).is_equal(-1)


func test_river_movement_cost() -> void:
	var map := _create_terrain_map()
	map._terrain_costs["river"] = 3.0
	map._tile_grid[Vector2i(0, 0)] = "river"
	assert_float(map.get_movement_cost(Vector2i(0, 0))).is_equal(3.0)
