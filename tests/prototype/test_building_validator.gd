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
