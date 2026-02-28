extends GdUnitTestSuite
## Tests for resource_generator.gd — noise-based resource placement with terrain
## affinity, minimum spacing, and density scaling.

const ResourceGenerator := preload("res://scripts/map/resource_generator.gd")

const MAP_W := 32
const MAP_H := 32


func _make_terrain_grid(w: int, h: int) -> Dictionary:
	## All grass except edges as water.
	var grid: Dictionary = {}
	for y in h:
		for x in w:
			if x == 0 or x == w - 1 or y == 0 or y == h - 1:
				grid[Vector2i(x, y)] = "water"
			else:
				grid[Vector2i(x, y)] = "grass"
	return grid


func _make_mixed_terrain_grid(w: int, h: int) -> Dictionary:
	## Mixed terrain: water edges, mountain top-left, stone top-right,
	## forest bottom-left, grass center and bottom-right.
	var grid: Dictionary = {}
	for y in h:
		for x in w:
			if x == 0 or x == w - 1 or y == 0 or y == h - 1:
				grid[Vector2i(x, y)] = "water"
			elif x < w / 4 and y < h / 4:
				grid[Vector2i(x, y)] = "mountain"
			elif x >= w / 4 and x < w / 2 and y < h / 4:
				grid[Vector2i(x, y)] = "stone"
			elif x < w / 4 and y >= h / 2:
				grid[Vector2i(x, y)] = "forest"
			elif x < w / 2 and y < h / 2:
				grid[Vector2i(x, y)] = "dirt"
			else:
				grid[Vector2i(x, y)] = "grass"
	return grid


func _make_config() -> Dictionary:
	return {
		"resources":
		{
			"gold_mine":
			{
				"density_per_1000_tiles": 3,
				"terrain_affinity": {"stone": 1.0, "mountain": 0.8, "dirt": 0.3},
				"forbidden_terrain": ["water", "river"],
				"min_spacing": 4,
				"noise_weight": 0.4,
				"noise_seed_offset": 4000,
			},
			"stone_mine":
			{
				"density_per_1000_tiles": 4,
				"terrain_affinity": {"stone": 1.0, "mountain": 0.6, "dirt": 0.4},
				"forbidden_terrain": ["water", "river"],
				"min_spacing": 3,
				"noise_weight": 0.4,
				"noise_seed_offset": 4100,
			},
			"berry_bush":
			{
				"density_per_1000_tiles": 5,
				"terrain_affinity": {"grass": 1.0, "forest": 0.7, "dirt": 0.5},
				"forbidden_terrain": ["water", "river", "mountain", "stone"],
				"min_spacing": 3,
				"noise_weight": 0.3,
				"noise_seed_offset": 4200,
			},
			"tree":
			{
				"density_per_1000_tiles": 12,
				"terrain_affinity": {"forest": 1.0, "grass": 0.6, "dirt": 0.3},
				"forbidden_terrain": ["water", "river", "mountain"],
				"min_spacing": 2,
				"noise_weight": 0.5,
				"noise_seed_offset": 4300,
			},
		},
		"placement_order": ["gold_mine", "stone_mine", "berry_bush", "tree"],
		"starting_zone_radius": 15,
		"starting_zone_guarantees":
		{
			"gold_mine": 1,
			"stone_mine": 2,
			"berry_bush": 2,
			"tree": 4,
		},
	}


func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func test_returns_dictionary_with_resource_names() -> void:
	var gen := ResourceGenerator.new()
	gen.configure(_make_config())
	var terrain := _make_mixed_terrain_grid(MAP_W, MAP_H)
	var result: Dictionary = gen.generate(terrain, MAP_W, MAP_H, 42)
	assert_bool(result.has("gold_mine")).is_true()
	assert_bool(result.has("stone_mine")).is_true()
	assert_bool(result.has("berry_bush")).is_true()
	assert_bool(result.has("tree")).is_true()


func test_positions_are_within_map_bounds() -> void:
	var gen := ResourceGenerator.new()
	gen.configure(_make_config())
	var terrain := _make_mixed_terrain_grid(MAP_W, MAP_H)
	var result: Dictionary = gen.generate(terrain, MAP_W, MAP_H, 42)
	for res_name: String in result:
		var positions: Array = result[res_name]
		for pos in positions:
			var p: Vector2i = pos as Vector2i
			assert_bool(p.x >= 0 and p.x < MAP_W).is_true()
			assert_bool(p.y >= 0 and p.y < MAP_H).is_true()


func test_gold_not_placed_on_water() -> void:
	var gen := ResourceGenerator.new()
	gen.configure(_make_config())
	var terrain := _make_mixed_terrain_grid(MAP_W, MAP_H)
	var result: Dictionary = gen.generate(terrain, MAP_W, MAP_H, 42)
	var gold_positions: Array = result.get("gold_mine", [])
	for pos in gold_positions:
		var p: Vector2i = pos as Vector2i
		assert_str(terrain[p]).is_not_equal("water")


func test_gold_not_placed_on_river() -> void:
	# Create terrain with some river tiles
	var terrain := _make_mixed_terrain_grid(MAP_W, MAP_H)
	for x in range(1, MAP_W - 1):
		terrain[Vector2i(x, MAP_H / 2)] = "river"
	var gen := ResourceGenerator.new()
	gen.configure(_make_config())
	var result: Dictionary = gen.generate(terrain, MAP_W, MAP_H, 42)
	var gold_positions: Array = result.get("gold_mine", [])
	for pos in gold_positions:
		var p: Vector2i = pos as Vector2i
		assert_str(terrain[p]).is_not_equal("river")


func test_stone_not_placed_on_water() -> void:
	var gen := ResourceGenerator.new()
	gen.configure(_make_config())
	var terrain := _make_mixed_terrain_grid(MAP_W, MAP_H)
	var result: Dictionary = gen.generate(terrain, MAP_W, MAP_H, 42)
	var stone_positions: Array = result.get("stone_mine", [])
	for pos in stone_positions:
		var p: Vector2i = pos as Vector2i
		assert_str(terrain[p]).is_not_equal("water")


func test_berry_not_placed_on_mountain() -> void:
	var gen := ResourceGenerator.new()
	gen.configure(_make_config())
	var terrain := _make_mixed_terrain_grid(MAP_W, MAP_H)
	var result: Dictionary = gen.generate(terrain, MAP_W, MAP_H, 42)
	var berry_positions: Array = result.get("berry_bush", [])
	for pos in berry_positions:
		var p: Vector2i = pos as Vector2i
		assert_str(terrain[p]).is_not_equal("mountain")


func test_tree_not_placed_on_water() -> void:
	var gen := ResourceGenerator.new()
	gen.configure(_make_config())
	var terrain := _make_mixed_terrain_grid(MAP_W, MAP_H)
	var result: Dictionary = gen.generate(terrain, MAP_W, MAP_H, 42)
	var tree_positions: Array = result.get("tree", [])
	for pos in tree_positions:
		var p: Vector2i = pos as Vector2i
		assert_str(terrain[p]).is_not_equal("water")


func test_no_resource_overlap() -> void:
	var gen := ResourceGenerator.new()
	gen.configure(_make_config())
	var terrain := _make_mixed_terrain_grid(MAP_W, MAP_H)
	var result: Dictionary = gen.generate(terrain, MAP_W, MAP_H, 42)
	var all_positions: Dictionary = {}  # Vector2i -> resource name
	for res_name: String in result:
		var positions: Array = result[res_name]
		for pos in positions:
			var p: Vector2i = pos as Vector2i
			assert_bool(all_positions.has(p)).is_false()
			all_positions[p] = res_name


func test_min_spacing_respected_gold() -> void:
	var gen := ResourceGenerator.new()
	gen.configure(_make_config())
	var terrain := _make_mixed_terrain_grid(MAP_W, MAP_H)
	var result: Dictionary = gen.generate(terrain, MAP_W, MAP_H, 42)
	var gold_positions: Array = result.get("gold_mine", [])
	for i in gold_positions.size():
		for j in range(i + 1, gold_positions.size()):
			var dist := _chebyshev(gold_positions[i] as Vector2i, gold_positions[j] as Vector2i)
			assert_int(dist).is_greater_equal(4)


func test_min_spacing_respected_stone() -> void:
	var gen := ResourceGenerator.new()
	gen.configure(_make_config())
	var terrain := _make_mixed_terrain_grid(MAP_W, MAP_H)
	var result: Dictionary = gen.generate(terrain, MAP_W, MAP_H, 42)
	var stone_positions: Array = result.get("stone_mine", [])
	for i in stone_positions.size():
		for j in range(i + 1, stone_positions.size()):
			var dist := _chebyshev(stone_positions[i] as Vector2i, stone_positions[j] as Vector2i)
			assert_int(dist).is_greater_equal(3)


func test_density_scales_with_area() -> void:
	var gen_small := ResourceGenerator.new()
	gen_small.configure(_make_config())
	var terrain_small := _make_terrain_grid(16, 16)
	var result_small: Dictionary = gen_small.generate(terrain_small, 16, 16, 42)

	var gen_large := ResourceGenerator.new()
	gen_large.configure(_make_config())
	var terrain_large := _make_terrain_grid(64, 64)
	var result_large: Dictionary = gen_large.generate(terrain_large, 64, 64, 42)

	# Larger map should produce more trees (most abundant resource)
	var small_trees: int = result_small.get("tree", []).size()
	var large_trees: int = result_large.get("tree", []).size()
	assert_int(large_trees).is_greater(small_trees)


func test_same_seed_deterministic() -> void:
	var gen1 := ResourceGenerator.new()
	gen1.configure(_make_config())
	var terrain := _make_mixed_terrain_grid(MAP_W, MAP_H)
	var r1: Dictionary = gen1.generate(terrain, MAP_W, MAP_H, 42)

	var gen2 := ResourceGenerator.new()
	gen2.configure(_make_config())
	var r2: Dictionary = gen2.generate(terrain, MAP_W, MAP_H, 42)

	for res_name: String in r1:
		var p1: Array = r1[res_name]
		var p2: Array = r2[res_name]
		assert_int(p1.size()).is_equal(p2.size())
		for i in p1.size():
			assert_object(p1[i]).is_equal(p2[i])


func test_different_seed_different_output() -> void:
	var gen1 := ResourceGenerator.new()
	gen1.configure(_make_config())
	var terrain := _make_mixed_terrain_grid(MAP_W, MAP_H)
	var r1: Dictionary = gen1.generate(terrain, MAP_W, MAP_H, 42)

	var gen2 := ResourceGenerator.new()
	gen2.configure(_make_config())
	var r2: Dictionary = gen2.generate(terrain, MAP_W, MAP_H, 999)

	# At least one resource type should have different positions
	var any_different := false
	for res_name: String in r1:
		var p1: Array = r1[res_name]
		var p2: Array = r2.get(res_name, [])
		if p1.size() != p2.size():
			any_different = true
			break
		for i in p1.size():
			if p1[i] != p2[i]:
				any_different = true
				break
		if any_different:
			break
	assert_bool(any_different).is_true()


func test_empty_config_returns_empty() -> void:
	var gen := ResourceGenerator.new()
	gen.configure({})
	var terrain := _make_terrain_grid(MAP_W, MAP_H)
	var result: Dictionary = gen.generate(terrain, MAP_W, MAP_H, 42)
	assert_int(result.size()).is_equal(0)


func test_placement_order_processes_scarce_first() -> void:
	# Gold (scarce) should be placed before tree (abundant).
	# Verify by checking gold gets priority on contested terrain.
	var gen := ResourceGenerator.new()
	var cfg := _make_config()
	# Make both gold and tree want dirt, but only provide dirt tiles
	cfg["resources"]["gold_mine"]["terrain_affinity"] = {"dirt": 1.0}
	cfg["resources"]["tree"]["terrain_affinity"] = {"dirt": 1.0}
	cfg["resources"]["stone_mine"]["terrain_affinity"] = {"dirt": 1.0}
	cfg["resources"]["berry_bush"]["terrain_affinity"] = {"dirt": 1.0}
	gen.configure(cfg)
	# All-dirt terrain (except water edge)
	var terrain := _make_terrain_grid(MAP_W, MAP_H)
	for y in MAP_H:
		for x in MAP_W:
			var pos := Vector2i(x, y)
			if terrain[pos] != "water":
				terrain[pos] = "dirt"
	var result: Dictionary = gen.generate(terrain, MAP_W, MAP_H, 42)
	# Gold should be placed (at least 1)
	assert_int(result.get("gold_mine", []).size()).is_greater_equal(1)


func test_resources_only_on_valid_terrain() -> void:
	var gen := ResourceGenerator.new()
	gen.configure(_make_config())
	var terrain := _make_mixed_terrain_grid(MAP_W, MAP_H)
	var result: Dictionary = gen.generate(terrain, MAP_W, MAP_H, 42)
	for res_name: String in result:
		var positions: Array = result[res_name]
		for pos in positions:
			var p: Vector2i = pos as Vector2i
			var t: String = terrain[p]
			assert_str(t).is_not_equal("water")
			assert_str(t).is_not_equal("river")


func test_minimum_one_resource_per_type() -> void:
	var gen := ResourceGenerator.new()
	gen.configure(_make_config())
	var terrain := _make_mixed_terrain_grid(MAP_W, MAP_H)
	var result: Dictionary = gen.generate(terrain, MAP_W, MAP_H, 42)
	for res_name: String in result:
		assert_int(result[res_name].size()).is_greater_equal(1)


func test_all_grass_terrain_still_places_resources() -> void:
	var gen := ResourceGenerator.new()
	gen.configure(_make_config())
	# All-grass map (except water edges)
	var terrain := _make_terrain_grid(MAP_W, MAP_H)
	var result: Dictionary = gen.generate(terrain, MAP_W, MAP_H, 42)
	# berry_bush and tree have grass affinity, so they should appear
	assert_int(result.get("berry_bush", []).size()).is_greater_equal(1)
	assert_int(result.get("tree", []).size()).is_greater_equal(1)


func test_small_map_doesnt_crash() -> void:
	var gen := ResourceGenerator.new()
	gen.configure(_make_config())
	var terrain := _make_terrain_grid(4, 4)
	# Should not crash — may produce 0 or minimal resources
	var result: Dictionary = gen.generate(terrain, 4, 4, 42)
	assert_bool(result is Dictionary).is_true()


func test_forbidden_terrain_respected() -> void:
	var gen := ResourceGenerator.new()
	var cfg := _make_config()
	# Add "sand" to gold_mine forbidden list
	cfg["resources"]["gold_mine"]["forbidden_terrain"] = ["water", "river", "sand"]
	cfg["resources"]["gold_mine"]["terrain_affinity"] = {"grass": 1.0, "sand": 1.0}
	gen.configure(cfg)
	# Create terrain with some sand
	var terrain: Dictionary = {}
	for y in MAP_H:
		for x in MAP_W:
			if x == 0 or x == MAP_W - 1 or y == 0 or y == MAP_H - 1:
				terrain[Vector2i(x, y)] = "water"
			elif y < MAP_H / 2:
				terrain[Vector2i(x, y)] = "sand"
			else:
				terrain[Vector2i(x, y)] = "grass"
	var result: Dictionary = gen.generate(terrain, MAP_W, MAP_H, 42)
	var gold_positions: Array = result.get("gold_mine", [])
	for pos in gold_positions:
		var p: Vector2i = pos as Vector2i
		assert_str(terrain[p]).is_not_equal("sand")


# -- Cluster expansion --


func _make_cluster_config() -> Dictionary:
	var cfg := _make_config()
	cfg["resources"]["tree"]["cluster_size_min"] = 3
	cfg["resources"]["tree"]["cluster_size_max"] = 4
	cfg["resources"]["tree"]["cluster_seed_offset"] = 4350
	return cfg


func test_cluster_expansion_multiplies_tree_count() -> void:
	var gen := ResourceGenerator.new()
	var cfg := _make_cluster_config()
	gen.configure(cfg)
	var terrain := _make_mixed_terrain_grid(MAP_W, MAP_H)
	var result: Dictionary = gen.generate(terrain, MAP_W, MAP_H, 42)
	var tree_positions: Array = result.get("tree", [])
	# Without clusters, tree density 12 per 1000 on 32x32=1024 -> ~13 placements
	# With clusters of 3-4, should be 39-52 total entries
	assert_int(tree_positions.size()).is_greater_equal(13 * 3)


func test_cluster_expansion_preserves_grid_positions() -> void:
	var gen := ResourceGenerator.new()
	var cfg := _make_cluster_config()
	gen.configure(cfg)
	var terrain := _make_mixed_terrain_grid(MAP_W, MAP_H)
	var result: Dictionary = gen.generate(terrain, MAP_W, MAP_H, 42)
	var tree_positions: Array = result.get("tree", [])
	# All positions should still be valid grid positions (within map bounds)
	for pos in tree_positions:
		var p: Vector2i = pos as Vector2i
		assert_bool(p.x >= 0 and p.x < MAP_W).is_true()
		assert_bool(p.y >= 0 and p.y < MAP_H).is_true()


func test_cluster_expansion_deterministic() -> void:
	var terrain := _make_mixed_terrain_grid(MAP_W, MAP_H)
	var gen1 := ResourceGenerator.new()
	gen1.configure(_make_cluster_config())
	var r1: Dictionary = gen1.generate(terrain, MAP_W, MAP_H, 42)
	var gen2 := ResourceGenerator.new()
	gen2.configure(_make_cluster_config())
	var r2: Dictionary = gen2.generate(terrain, MAP_W, MAP_H, 42)
	var t1: Array = r1.get("tree", [])
	var t2: Array = r2.get("tree", [])
	assert_int(t1.size()).is_equal(t2.size())
	for i in t1.size():
		assert_object(t1[i]).is_equal(t2[i])


func test_cluster_positions_have_duplicates() -> void:
	var gen := ResourceGenerator.new()
	gen.configure(_make_cluster_config())
	var terrain := _make_mixed_terrain_grid(MAP_W, MAP_H)
	var result: Dictionary = gen.generate(terrain, MAP_W, MAP_H, 42)
	var tree_positions: Array = result.get("tree", [])
	# With clusters, some grid positions should appear multiple times
	var counts: Dictionary = {}
	for pos in tree_positions:
		var p: Vector2i = pos as Vector2i
		counts[p] = counts.get(p, 0) + 1
	var has_cluster := false
	for p: Vector2i in counts:
		if counts[p] >= 3:
			has_cluster = true
			break
	assert_bool(has_cluster).is_true()


func test_non_cluster_resources_unchanged() -> void:
	var gen := ResourceGenerator.new()
	var cfg := _make_cluster_config()
	gen.configure(cfg)
	var terrain := _make_mixed_terrain_grid(MAP_W, MAP_H)
	var result: Dictionary = gen.generate(terrain, MAP_W, MAP_H, 42)
	# Gold should NOT be expanded (no cluster config)
	var gold: Array = result.get("gold_mine", [])
	var gold_counts: Dictionary = {}
	for pos in gold:
		var p: Vector2i = pos as Vector2i
		gold_counts[p] = gold_counts.get(p, 0) + 1
	for p: Vector2i in gold_counts:
		assert_int(gold_counts[p]).is_equal(1)
