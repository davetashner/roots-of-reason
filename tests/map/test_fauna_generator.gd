extends GdUnitTestSuite
## Tests for fauna_generator.gd — wolf pack placement with terrain affinity,
## starting position distance, and contested pack placement.

const FaunaGenerator := preload("res://scripts/map/fauna_generator.gd")

const MAP_W := 64
const MAP_H := 64
const SEED := 42


func _make_terrain_grid(w: int, h: int, terrain: String = "grass") -> Dictionary:
	var grid: Dictionary = {}
	for y in h:
		for x in w:
			grid[Vector2i(x, y)] = terrain
	return grid


func _make_config(overrides: Dictionary = {}) -> Dictionary:
	var config: Dictionary = {
		"fauna_types":
		{
			"wolf":
			{
				"base_pack_count": 3,
				"pack_count_min": 2,
				"pack_count_max": 6,
				"pack_size_min": 2,
				"pack_size_max": 3,
				"min_distance_from_start": 12,
				"min_distance_between_packs": 8,
				"terrain_affinity": {"forest": 1.0, "grass": 0.6, "dirt": 0.3},
				"forbidden_terrain": ["water", "river", "mountain"],
				"noise_weight": 0.4,
				"noise_seed_offset": 6000,
			}
		}
	}
	config.merge(overrides, true)
	return config


func _generate_default(
	starts: Array = [Vector2i(8, 8), Vector2i(56, 56)],
) -> Dictionary:
	var gen := FaunaGenerator.new()
	gen.configure(_make_config())
	var terrain := _make_terrain_grid(MAP_W, MAP_H)
	return gen.generate(terrain, MAP_W, MAP_H, SEED, starts)


# -- Result shape tests --


func test_result_has_expected_keys() -> void:
	var result := _generate_default()
	assert_bool(result.has("wolf")).is_true()


func test_pack_count_in_bounds() -> void:
	var result := _generate_default()
	var packs: Array = result["wolf"]
	assert_int(packs.size()).is_greater_equal(2)
	assert_int(packs.size()).is_less_equal(6)


func test_pack_size_in_bounds() -> void:
	var result := _generate_default()
	var packs: Array = result["wolf"]
	for pack in packs:
		var p: Dictionary = pack as Dictionary
		assert_int(int(p.pack_size)).is_greater_equal(2)
		assert_int(int(p.pack_size)).is_less_equal(3)


# -- Placement constraint tests --


func test_min_distance_from_starting_positions() -> void:
	var starts: Array = [Vector2i(8, 8), Vector2i(56, 56)]
	var result := _generate_default(starts)
	var packs: Array = result["wolf"]
	for pack in packs:
		var p: Dictionary = pack as Dictionary
		var pos: Vector2i = p.position
		for start in starts:
			var sp: Vector2i = start as Vector2i
			var dist := maxi(absi(pos.x - sp.x), absi(pos.y - sp.y))
			assert_int(dist).is_greater_equal(12)


func test_min_distance_between_packs() -> void:
	var result := _generate_default()
	var packs: Array = result["wolf"]
	for i in packs.size():
		for j in range(i + 1, packs.size()):
			var pos_a: Vector2i = (packs[i] as Dictionary).position
			var pos_b: Vector2i = (packs[j] as Dictionary).position
			var dist := maxi(absi(pos_a.x - pos_b.x), absi(pos_a.y - pos_b.y))
			assert_int(dist).is_greater_equal(8)


func test_contested_pack_roughly_equidistant() -> void:
	var starts: Array = [Vector2i(8, 8), Vector2i(56, 56)]
	var result := _generate_default(starts)
	var packs: Array = result["wolf"]
	var contested_found := false
	for pack in packs:
		var p: Dictionary = pack as Dictionary
		if bool(p.contested):
			contested_found = true
			var pos: Vector2i = p.position
			var dist_a := maxi(absi(pos.x - 8), absi(pos.y - 8))
			var dist_b := maxi(absi(pos.x - 56), absi(pos.y - 56))
			# Should be roughly equidistant (within 5 tiles difference)
			assert_int(absi(dist_a - dist_b)).is_less_equal(5)
	assert_bool(contested_found).is_true()


# -- Terrain tests --


func test_packs_on_valid_terrain() -> void:
	var gen := FaunaGenerator.new()
	gen.configure(_make_config())
	# Mix terrain: forest + water + mountain
	var terrain := _make_terrain_grid(MAP_W, MAP_H)
	for y in range(0, MAP_H, 4):
		for x in MAP_W:
			terrain[Vector2i(x, y)] = "water"
	var starts: Array = [Vector2i(8, 8), Vector2i(56, 56)]
	var result := gen.generate(terrain, MAP_W, MAP_H, SEED, starts)
	var packs: Array = result.get("wolf", [])
	for pack in packs:
		var p: Dictionary = pack as Dictionary
		var pos: Vector2i = p.position
		var t: String = terrain.get(pos, "")
		assert_str(t).is_not_equal("water")
		assert_str(t).is_not_equal("river")
		assert_str(t).is_not_equal("mountain")


func test_prefer_forest_terrain() -> void:
	var gen := FaunaGenerator.new()
	gen.configure(_make_config())
	# Make right half forest, left half grass
	var terrain: Dictionary = {}
	for y in MAP_H:
		for x in MAP_W:
			if x >= 32:
				terrain[Vector2i(x, y)] = "forest"
			else:
				terrain[Vector2i(x, y)] = "grass"
	var starts: Array = [Vector2i(4, 4), Vector2i(4, 56)]
	var result := gen.generate(terrain, MAP_W, MAP_H, SEED, starts)
	var packs: Array = result.get("wolf", [])
	var forest_count := 0
	for pack in packs:
		var p: Dictionary = pack as Dictionary
		var pos: Vector2i = p.position
		if terrain.get(pos, "") == "forest":
			forest_count += 1
	# Most packs should be in forest
	assert_int(forest_count).is_greater_equal(packs.size() / 2)


# -- Edge cases --


func test_empty_starting_positions_still_works() -> void:
	var gen := FaunaGenerator.new()
	gen.configure(_make_config())
	var terrain := _make_terrain_grid(MAP_W, MAP_H)
	var result := gen.generate(terrain, MAP_W, MAP_H, SEED, [])
	var packs: Array = result.get("wolf", [])
	assert_int(packs.size()).is_greater_equal(2)


func test_deterministic_with_same_seed() -> void:
	var gen1 := FaunaGenerator.new()
	gen1.configure(_make_config())
	var gen2 := FaunaGenerator.new()
	gen2.configure(_make_config())
	var terrain := _make_terrain_grid(MAP_W, MAP_H)
	var starts: Array = [Vector2i(8, 8), Vector2i(56, 56)]
	var r1 := gen1.generate(terrain, MAP_W, MAP_H, SEED, starts)
	var r2 := gen2.generate(terrain, MAP_W, MAP_H, SEED, starts)
	var p1: Array = r1["wolf"]
	var p2: Array = r2["wolf"]
	assert_int(p1.size()).is_equal(p2.size())
	for i in p1.size():
		assert_object(p1[i]).is_equal(p2[i])


func test_all_water_returns_empty() -> void:
	var gen := FaunaGenerator.new()
	gen.configure(_make_config())
	var terrain := _make_terrain_grid(MAP_W, MAP_H, "water")
	var result := gen.generate(terrain, MAP_W, MAP_H, SEED, [])
	var packs: Array = result.get("wolf", [])
	assert_array(packs).is_empty()


func test_tiny_map_no_crash() -> void:
	var gen := FaunaGenerator.new()
	gen.configure(_make_config())
	var terrain := _make_terrain_grid(8, 8)
	var result := gen.generate(terrain, 8, 8, SEED, [Vector2i(2, 2)])
	# May have 0 packs due to small map + distance constraint, but no crash
	assert_bool(result.has("wolf")).is_true()
