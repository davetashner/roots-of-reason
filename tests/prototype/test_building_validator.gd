extends GdUnitTestSuite
## Tests for building_validator.gd — footprint generation and placement validation.

const MapScript := preload("res://scripts/prototype/prototype_map.gd")
const PathfindingScript := preload("res://scripts/prototype/pathfinding_grid.gd")


func _build_grass_grid(size: int) -> Dictionary:
	var grid: Dictionary = {}
	for x in size:
		for y in size:
			grid[Vector2i(x, y)] = "grass"
	return grid


func _default_costs() -> Dictionary:
	return {"grass": 1.0, "forest": 2.0, "desert": 1.5, "water": -1}


func _create_map(grid: Dictionary) -> Node2D:
	var map := Node2D.new()
	map.set_script(MapScript)
	map._tile_grid = grid
	return auto_free(map)


func _create_pathfinder(size: int, grid: Dictionary) -> Node:
	var pf := Node.new()
	pf.set_script(PathfindingScript)
	pf.build(size, grid, _default_costs())
	return auto_free(pf)


# -- Footprint generation --


func test_footprint_1x1() -> void:
	var cells := BuildingValidator.get_footprint_cells(Vector2i(3, 3), Vector2i(1, 1))
	assert_int(cells.size()).is_equal(1)
	assert_object(cells[0]).is_equal(Vector2i(3, 3))


func test_footprint_2x2() -> void:
	var cells := BuildingValidator.get_footprint_cells(Vector2i(5, 5), Vector2i(2, 2))
	assert_int(cells.size()).is_equal(4)
	assert_bool(Vector2i(5, 5) in cells).is_true()
	assert_bool(Vector2i(6, 5) in cells).is_true()
	assert_bool(Vector2i(5, 6) in cells).is_true()
	assert_bool(Vector2i(6, 6) in cells).is_true()


func test_footprint_3x3() -> void:
	var cells := BuildingValidator.get_footprint_cells(Vector2i(0, 0), Vector2i(3, 3))
	assert_int(cells.size()).is_equal(9)
	for x in 3:
		for y in 3:
			assert_bool(Vector2i(x, y) in cells).is_true()


# -- Placement validity --


func test_valid_placement_on_grass() -> void:
	var grid := _build_grass_grid(20)
	var map := _create_map(grid)
	var pf := _create_pathfinder(20, grid)
	assert_bool(BuildingValidator.is_placement_valid(Vector2i(5, 5), Vector2i(2, 2), map, pf)).is_true()


func test_invalid_placement_on_water() -> void:
	var grid := _build_grass_grid(20)
	grid[Vector2i(6, 5)] = "water"
	var map := _create_map(grid)
	var pf := _create_pathfinder(20, grid)
	# 2x2 at (5,5) covers (5,5), (6,5), (5,6), (6,6) — (6,5) is water
	assert_bool(BuildingValidator.is_placement_valid(Vector2i(5, 5), Vector2i(2, 2), map, pf)).is_false()


func test_invalid_placement_on_solid_cell() -> void:
	var grid := _build_grass_grid(20)
	var map := _create_map(grid)
	var pf := _create_pathfinder(20, grid)
	pf.set_cell_solid(Vector2i(5, 6), true)
	assert_bool(BuildingValidator.is_placement_valid(Vector2i(5, 5), Vector2i(2, 2), map, pf)).is_false()


func test_invalid_placement_out_of_bounds() -> void:
	var grid := _build_grass_grid(10)
	var map := _create_map(grid)
	var pf := _create_pathfinder(10, grid)
	# 3x3 at (8,8) extends to (10,10) which is out of bounds for size=10
	assert_bool(BuildingValidator.is_placement_valid(Vector2i(8, 8), Vector2i(3, 3), map, pf)).is_false()


func test_valid_placement_at_edge() -> void:
	var grid := _build_grass_grid(10)
	var map := _create_map(grid)
	var pf := _create_pathfinder(10, grid)
	# 3x3 at (7,7) extends to (9,9) — just barely fits
	assert_bool(BuildingValidator.is_placement_valid(Vector2i(7, 7), Vector2i(3, 3), map, pf)).is_true()


# -- River-aware mock map --


class RiverMockMap:
	extends Node2D
	var _tile_grid: Dictionary = {}
	var _river_tiles: Dictionary = {}
	var _map_size: int = 20

	func get_terrain_at(grid_pos: Vector2i) -> String:
		return _tile_grid.get(grid_pos, "")

	func get_map_size() -> int:
		return _map_size

	func is_river(grid_pos: Vector2i) -> bool:
		return _river_tiles.has(grid_pos)

	func is_buildable(grid_pos: Vector2i) -> bool:
		var terrain := get_terrain_at(grid_pos)
		return terrain != "water" and terrain != "river"


func _create_river_map(grid: Dictionary, river_tiles: Array[Vector2i]) -> Node2D:
	var map := RiverMockMap.new()
	map._tile_grid = grid
	for pos in river_tiles:
		map._river_tiles[pos] = true
		map._tile_grid[pos] = "river"
	return auto_free(map)


# -- Placement constraint: adjacent_to_river --


func test_valid_placement_adjacent_to_river_cardinal() -> void:
	var grid := _build_grass_grid(20)
	var river_tiles: Array[Vector2i] = [Vector2i(5, 4)]  # river north of (5,5)
	var map := _create_river_map(grid, river_tiles)
	var pf := _create_pathfinder(20, grid)
	(
		assert_bool(BuildingValidator.is_placement_valid(Vector2i(5, 5), Vector2i(1, 1), map, pf, "adjacent_to_river"))
		. is_true()
	)


func test_valid_placement_adjacent_to_river_diagonal() -> void:
	var grid := _build_grass_grid(20)
	var river_tiles: Array[Vector2i] = [Vector2i(6, 6)]  # river SE of (5,5)
	var map := _create_river_map(grid, river_tiles)
	var pf := _create_pathfinder(20, grid)
	(
		assert_bool(BuildingValidator.is_placement_valid(Vector2i(5, 5), Vector2i(1, 1), map, pf, "adjacent_to_river"))
		. is_true()
	)


func test_invalid_placement_no_river_nearby() -> void:
	var grid := _build_grass_grid(20)
	var river_tiles: Array[Vector2i] = [Vector2i(0, 0)]  # river far away
	var map := _create_river_map(grid, river_tiles)
	var pf := _create_pathfinder(20, grid)
	(
		assert_bool(
			BuildingValidator.is_placement_valid(Vector2i(10, 10), Vector2i(1, 1), map, pf, "adjacent_to_river")
		)
		. is_false()
	)


func test_placement_on_river_tile_fails_unbuildable() -> void:
	var grid := _build_grass_grid(20)
	var river_tiles: Array[Vector2i] = [Vector2i(5, 5)]
	var map := _create_river_map(grid, river_tiles)
	var pf := _create_pathfinder(20, grid)
	# River tiles are unbuildable — fails before constraint check
	(
		assert_bool(BuildingValidator.is_placement_valid(Vector2i(5, 5), Vector2i(1, 1), map, pf, "adjacent_to_river"))
		. is_false()
	)


func test_empty_constraint_backward_compatible() -> void:
	var grid := _build_grass_grid(20)
	var map := _create_map(grid)
	var pf := _create_pathfinder(20, grid)
	# Empty constraint should behave same as no constraint
	assert_bool(BuildingValidator.is_placement_valid(Vector2i(5, 5), Vector2i(1, 1), map, pf, "")).is_true()


func test_unknown_constraint_passes_with_warning() -> void:
	var grid := _build_grass_grid(20)
	var map := _create_map(grid)
	var pf := _create_pathfinder(20, grid)
	# Unknown constraint should pass (with a warning)
	assert_bool(BuildingValidator.is_placement_valid(Vector2i(5, 5), Vector2i(1, 1), map, pf, "near_volcano")).is_true()


# -- Water-aware mock map --


class WaterMockMap:
	extends Node2D
	var _tile_grid: Dictionary = {}
	var _river_tiles: Dictionary = {}
	var _map_size: int = 20

	func get_terrain_at(grid_pos: Vector2i) -> String:
		return _tile_grid.get(grid_pos, "")

	func get_map_size() -> int:
		return _map_size

	func is_river(grid_pos: Vector2i) -> bool:
		return _river_tiles.has(grid_pos)

	func is_buildable(grid_pos: Vector2i) -> bool:
		var terrain := get_terrain_at(grid_pos)
		return terrain != "water" and terrain != "shallows" and terrain != "deep_water"


func _create_water_map(grid: Dictionary) -> Node2D:
	var map := WaterMockMap.new()
	map._tile_grid = grid
	return auto_free(map)


# -- Placement constraint: adjacent_to_water --


func test_valid_placement_adjacent_to_water_cardinal() -> void:
	var grid := _build_grass_grid(20)
	grid[Vector2i(5, 4)] = "water"
	var map := _create_water_map(grid)
	var pf := _create_pathfinder(20, grid)
	# Shore tile at (5,5) with water to the north
	(
		assert_bool(BuildingValidator.is_placement_valid(Vector2i(5, 5), Vector2i(1, 1), map, pf, "adjacent_to_water"))
		. is_true()
	)


func test_valid_placement_adjacent_to_shallows_diagonal() -> void:
	var grid := _build_grass_grid(20)
	grid[Vector2i(6, 6)] = "shallows"
	var map := _create_water_map(grid)
	var pf := _create_pathfinder(20, grid)
	# Shore tile at (5,5) with shallows to SE
	(
		assert_bool(BuildingValidator.is_placement_valid(Vector2i(5, 5), Vector2i(1, 1), map, pf, "adjacent_to_water"))
		. is_true()
	)


func test_invalid_placement_no_water_nearby() -> void:
	var grid := _build_grass_grid(20)
	grid[Vector2i(0, 0)] = "water"
	var map := _create_water_map(grid)
	var pf := _create_pathfinder(20, grid)
	# No water adjacent to (10,10)
	(
		assert_bool(
			BuildingValidator.is_placement_valid(Vector2i(10, 10), Vector2i(1, 1), map, pf, "adjacent_to_water")
		)
		. is_false()
	)


func test_dock_footprint_on_water_fails() -> void:
	var grid := _build_grass_grid(20)
	# Place water at one of the dock's footprint cells
	grid[Vector2i(5, 5)] = "water"
	grid[Vector2i(5, 4)] = "water"
	var map := _create_water_map(grid)
	var pf := _create_pathfinder(20, grid)
	# 1x1 at (5,5) is water — unbuildable, fails before constraint check
	(
		assert_bool(BuildingValidator.is_placement_valid(Vector2i(5, 5), Vector2i(1, 1), map, pf, "adjacent_to_water"))
		. is_false()
	)


func test_dock_footprint_shore_with_deep_water_neighbor() -> void:
	var grid := _build_grass_grid(20)
	grid[Vector2i(5, 4)] = "deep_water"
	var map := _create_water_map(grid)
	var pf := _create_pathfinder(20, grid)
	# Shore at (5,5) with deep_water neighbor to the north
	(
		assert_bool(BuildingValidator.is_placement_valid(Vector2i(5, 5), Vector2i(1, 1), map, pf, "adjacent_to_water"))
		. is_true()
	)


func test_adjacent_to_river_does_not_satisfy_adjacent_to_water() -> void:
	var grid := _build_grass_grid(20)
	# Only river nearby, no water/shallows/deep_water
	grid[Vector2i(5, 4)] = "river"
	var map := WaterMockMap.new()
	map._tile_grid = grid
	map._river_tiles[Vector2i(5, 4)] = true
	auto_free(map)
	var pf := _create_pathfinder(20, grid)
	(
		assert_bool(BuildingValidator.is_placement_valid(Vector2i(5, 5), Vector2i(1, 1), map, pf, "adjacent_to_water"))
		. is_false()
	)
