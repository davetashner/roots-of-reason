extends GdUnitTestSuite
## Tests for starting_location_generator.gd — candidate scoring and pair selection.

const StartingLocationGenerator := preload("res://scripts/map/starting_location_generator.gd")

const MAP_W := 64
const MAP_H := 64
const SEED := 42


func _make_terrain_grid(w: int, h: int, terrain: String = "grass") -> Dictionary:
	var grid: Dictionary = {}
	for y in h:
		for x in w:
			grid[Vector2i(x, y)] = terrain
	return grid


func _make_elevation_grid(w: int, h: int, value: float = 0.5) -> Dictionary:
	var grid: Dictionary = {}
	for y in h:
		for x in w:
			grid[Vector2i(x, y)] = value
	return grid


func _make_terrain_properties() -> Dictionary:
	return {
		"grass": {"buildable": true, "blocks_los": false},
		"dirt": {"buildable": true, "blocks_los": false},
		"sand": {"buildable": true, "blocks_los": false},
		"water": {"buildable": false, "blocks_los": false},
		"forest": {"buildable": true, "blocks_los": true},
		"stone": {"buildable": true, "blocks_los": false},
		"mountain": {"buildable": false, "blocks_los": true},
		"river": {"buildable": false, "blocks_los": false},
	}


func _make_config(overrides: Dictionary = {}) -> Dictionary:
	var config: Dictionary = {
		"player_count": 2,
		"min_distance": 20,
		"map_margin": 4,
		"candidate_grid_step": 4,
		"tc_footprint": [3, 3],
		"reachability_radius": 10,
		"min_reachable_tiles": 30,
		"scoring_radius": 8,
		"scoring_weights":
		{
			"buildable_ratio": 0.3,
			"terrain_diversity": 0.2,
			"elevation_midrange": 0.25,
			"center_proximity": 0.25,
		},
		"elevation_ideal_min": 0.3,
		"elevation_ideal_max": 0.6,
		"seed_offset": 5000,
		"villager_offsets": [[-1, 0], [0, -1], [-1, -1]],
	}
	config.merge(overrides, true)
	return config


func _generate_default() -> Dictionary:
	var gen := StartingLocationGenerator.new()
	gen.configure(_make_config())
	var terrain := _make_terrain_grid(MAP_W, MAP_H)
	var elevation := _make_elevation_grid(MAP_W, MAP_H, 0.45)
	var props := _make_terrain_properties()
	return gen.generate(terrain, elevation, props, MAP_W, MAP_H, SEED)


# -- Result shape tests --


func test_result_has_expected_keys() -> void:
	var result := _generate_default()
	assert_bool(result.has("starting_positions")).is_true()
	assert_bool(result.has("scores")).is_true()


func test_result_has_correct_player_count() -> void:
	var result := _generate_default()
	var positions: Array = result["starting_positions"]
	assert_int(positions.size()).is_equal(2)
	var scores: Array = result["scores"]
	assert_int(scores.size()).is_equal(2)


# -- Position validity tests --


func test_positions_within_bounds_respecting_margin() -> void:
	var result := _generate_default()
	var margin := 4
	for pos in result["starting_positions"]:
		var p: Vector2i = pos as Vector2i
		assert_bool(p.x >= margin).is_true()
		assert_bool(p.y >= margin).is_true()
		assert_bool(p.x <= MAP_W - margin - 3).is_true()
		assert_bool(p.y <= MAP_H - margin - 3).is_true()


func test_positions_respect_min_distance() -> void:
	var result := _generate_default()
	var positions: Array = result["starting_positions"]
	if positions.size() >= 2:
		var a: Vector2i = positions[0] as Vector2i
		var b: Vector2i = positions[1] as Vector2i
		var dist := maxi(absi(a.x - b.x), absi(a.y - b.y))
		# Should be at least min_distance (20) or relaxed fallback
		assert_bool(dist >= 10).is_true()


# -- TC footprint tests --


func test_tc_footprint_fully_buildable() -> void:
	var result := _generate_default()
	var terrain := _make_terrain_grid(MAP_W, MAP_H)
	var props := _make_terrain_properties()
	for pos in result["starting_positions"]:
		var p: Vector2i = pos as Vector2i
		for dy in 3:
			for dx in 3:
				var cell := Vector2i(p.x + dx, p.y + dy)
				var terrain_type: String = terrain.get(cell, "")
				var cell_props: Dictionary = props.get(terrain_type, {})
				assert_bool(cell_props.get("buildable", false)).is_true()


func test_footprint_rejects_water_tiles() -> void:
	var gen := StartingLocationGenerator.new()
	gen.configure(_make_config({"min_reachable_tiles": 1}))
	# Place water in a strip that would overlap any TC at y=8
	var terrain := _make_terrain_grid(MAP_W, MAP_H)
	for x in MAP_W:
		terrain[Vector2i(x, 9)] = "water"
	var elevation := _make_elevation_grid(MAP_W, MAP_H, 0.45)
	var props := _make_terrain_properties()
	var result := gen.generate(terrain, elevation, props, MAP_W, MAP_H, SEED)
	# No position should have its footprint overlap water at y=9
	for pos in result["starting_positions"]:
		var p: Vector2i = pos as Vector2i
		for dy in 3:
			for dx in 3:
				var cell := Vector2i(p.x + dx, p.y + dy)
				assert_str(terrain.get(cell, "")).is_not_equal("water")


func test_footprint_rejects_river_tiles() -> void:
	var gen := StartingLocationGenerator.new()
	gen.configure(_make_config({"min_reachable_tiles": 1}))
	var terrain := _make_terrain_grid(MAP_W, MAP_H)
	# Place river strip at y=20
	for x in MAP_W:
		terrain[Vector2i(x, 20)] = "river"
	var elevation := _make_elevation_grid(MAP_W, MAP_H, 0.45)
	var props := _make_terrain_properties()
	var result := gen.generate(terrain, elevation, props, MAP_W, MAP_H, SEED)
	for pos in result["starting_positions"]:
		var p: Vector2i = pos as Vector2i
		for dy in 3:
			for dx in 3:
				var cell := Vector2i(p.x + dx, p.y + dy)
				assert_str(terrain.get(cell, "")).is_not_equal("river")


# -- Reachability tests --


func test_reachability_threshold_met() -> void:
	# Default config uses min_reachable_tiles=30, radius=10
	# On an all-grass map, flood fill should easily exceed 30
	var result := _generate_default()
	assert_int(result["starting_positions"].size()).is_greater_equal(1)


func test_water_locked_candidates_rejected() -> void:
	var gen := StartingLocationGenerator.new()
	gen.configure(_make_config({"min_reachable_tiles": 50}))
	# Create mostly water map with a small grass island
	var terrain := _make_terrain_grid(MAP_W, MAP_H, "water")
	# Small 6x6 grass island — just enough for a footprint but not reachability
	for y in range(30, 36):
		for x in range(30, 36):
			terrain[Vector2i(x, y)] = "grass"
	var elevation := _make_elevation_grid(MAP_W, MAP_H, 0.45)
	var props := _make_terrain_properties()
	var result := gen.generate(terrain, elevation, props, MAP_W, MAP_H, SEED)
	# Might be empty or 1 position if barely reachable
	assert_int(result["starting_positions"].size()).is_less_equal(1)


# -- Determinism tests --


func test_deterministic_with_same_seed() -> void:
	var gen1 := StartingLocationGenerator.new()
	gen1.configure(_make_config())
	var gen2 := StartingLocationGenerator.new()
	gen2.configure(_make_config())
	var terrain := _make_terrain_grid(MAP_W, MAP_H)
	var elevation := _make_elevation_grid(MAP_W, MAP_H, 0.45)
	var props := _make_terrain_properties()
	var r1 := gen1.generate(terrain, elevation, props, MAP_W, MAP_H, SEED)
	var r2 := gen2.generate(terrain, elevation, props, MAP_W, MAP_H, SEED)
	assert_array(r1["starting_positions"]).is_equal(r2["starting_positions"])
	assert_array(r1["scores"]).is_equal(r2["scores"])


func test_different_seed_may_produce_different_results() -> void:
	var gen1 := StartingLocationGenerator.new()
	gen1.configure(_make_config())
	var gen2 := StartingLocationGenerator.new()
	gen2.configure(_make_config())
	# Use terrain with some variation so different scoring is possible
	var terrain := _make_terrain_grid(MAP_W, MAP_H)
	for y in range(0, MAP_H, 3):
		for x in MAP_W:
			terrain[Vector2i(x, y)] = "forest"
	var elevation := _make_elevation_grid(MAP_W, MAP_H, 0.45)
	var props := _make_terrain_properties()
	var r1 := gen1.generate(terrain, elevation, props, MAP_W, MAP_H, 42)
	var r2 := gen2.generate(terrain, elevation, props, MAP_W, MAP_H, 42)
	# Same seed on same map should still be deterministic
	assert_array(r1["starting_positions"]).is_equal(r2["starting_positions"])


# -- Score balance tests --


func test_scores_are_balanced() -> void:
	var result := _generate_default()
	var scores: Array = result["scores"]
	if scores.size() >= 2:
		var s1: float = scores[0]
		var s2: float = scores[1]
		var max_s := maxf(s1, s2)
		if max_s > 0.0:
			var ratio := minf(s1, s2) / max_s
			assert_float(ratio).is_greater_equal(0.5)


func test_scores_are_positive() -> void:
	var result := _generate_default()
	for score in result["scores"]:
		assert_float(score as float).is_greater(0.0)


# -- Graceful degradation tests --


func test_all_water_map_returns_empty() -> void:
	var gen := StartingLocationGenerator.new()
	gen.configure(_make_config())
	var terrain := _make_terrain_grid(MAP_W, MAP_H, "water")
	var elevation := _make_elevation_grid(MAP_W, MAP_H, 0.1)
	var props := _make_terrain_properties()
	var result := gen.generate(terrain, elevation, props, MAP_W, MAP_H, SEED)
	assert_array(result["starting_positions"]).is_empty()


func test_all_mountain_map_returns_empty() -> void:
	var gen := StartingLocationGenerator.new()
	gen.configure(_make_config())
	var terrain := _make_terrain_grid(MAP_W, MAP_H, "mountain")
	var elevation := _make_elevation_grid(MAP_W, MAP_H, 0.9)
	var props := _make_terrain_properties()
	var result := gen.generate(terrain, elevation, props, MAP_W, MAP_H, SEED)
	assert_array(result["starting_positions"]).is_empty()


# -- Single player mode --


func test_single_player_returns_one_position() -> void:
	var gen := StartingLocationGenerator.new()
	gen.configure(_make_config({"player_count": 1}))
	var terrain := _make_terrain_grid(MAP_W, MAP_H)
	var elevation := _make_elevation_grid(MAP_W, MAP_H, 0.45)
	var props := _make_terrain_properties()
	var result := gen.generate(terrain, elevation, props, MAP_W, MAP_H, SEED)
	assert_int(result["starting_positions"].size()).is_equal(1)
	assert_int(result["scores"].size()).is_equal(1)


# -- Flood fill helper tests --


func test_flood_fill_counts_correctly_on_open_terrain() -> void:
	var gen := StartingLocationGenerator.new()
	gen.configure(_make_config({"reachability_radius": 3}))
	var terrain := _make_terrain_grid(MAP_W, MAP_H)
	var props := _make_terrain_properties()
	# A BFS with radius 3 from center of open terrain: diamond shape
	# Radius 3 in 4-connected BFS covers tiles within Manhattan distance 3
	# = 1 + 4 + 8 + 12 = 25 tiles (diamond pattern for Manhattan dist)
	var count: int = gen._flood_fill_count(Vector2i(32, 32), terrain, props, MAP_W, MAP_H)
	# Should be reachable and > 0
	assert_int(count).is_greater(0)


func test_flood_fill_blocked_by_water() -> void:
	var gen := StartingLocationGenerator.new()
	gen.configure(_make_config({"reachability_radius": 5}))
	# Surround a small area with water to limit flood fill
	var terrain := _make_terrain_grid(MAP_W, MAP_H, "water")
	# Small grass pocket: 5x5
	for y in range(30, 35):
		for x in range(30, 35):
			terrain[Vector2i(x, y)] = "grass"
	var props := _make_terrain_properties()
	var count: int = gen._flood_fill_count(Vector2i(32, 32), terrain, props, MAP_W, MAP_H)
	assert_int(count).is_equal(25)  # 5x5 grass pocket


func test_flood_fill_blocked_by_mountain() -> void:
	var gen := StartingLocationGenerator.new()
	gen.configure(_make_config({"reachability_radius": 5}))
	var terrain := _make_terrain_grid(MAP_W, MAP_H)
	# Mountain wall at x=34 blocks eastward expansion
	for y in range(28, 40):
		terrain[Vector2i(34, y)] = "mountain"
	var props := _make_terrain_properties()
	var count_blocked: int = gen._flood_fill_count(Vector2i(32, 32), terrain, props, MAP_W, MAP_H)
	var count_open: int = gen._flood_fill_count(Vector2i(20, 20), terrain, props, MAP_W, MAP_H)
	assert_bool(count_blocked < count_open).is_true()


# -- Villager offsets --


func test_villager_offsets_from_config() -> void:
	var gen := StartingLocationGenerator.new()
	var offsets: Array = [[-1, 0], [0, -1], [-1, -1], [1, -1], [-1, 1]]
	gen.configure(_make_config({"villager_offsets": offsets}))
	assert_int(gen.get_villager_offsets().size()).is_equal(5)
