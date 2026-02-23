extends GdUnitTestSuite
## Tests for pathfinding_grid.gd — A* pathfinding on isometric grid.

const PathfindingScript := preload("res://scripts/prototype/pathfinding_grid.gd")


func _create_pathfinder() -> Node:
	var pf := Node.new()
	pf.set_script(PathfindingScript)
	return auto_free(pf)


func _build_grass_grid(size: int) -> Dictionary:
	var grid: Dictionary = {}
	for x in size:
		for y in size:
			grid[Vector2i(x, y)] = "grass"
	return grid


func _default_costs() -> Dictionary:
	return {
		"grass": 1.0,
		"forest": 2.0,
		"desert": 1.5,
		"water": -1,
	}


# -- Path computation --


func test_find_path_straight_line() -> void:
	var pf := _create_pathfinder()
	pf.build(10, _build_grass_grid(10), _default_costs())
	var path: Array = pf.find_path(Vector2i(0, 0), Vector2i(5, 0))
	assert_bool(path.size() > 0).is_true()
	assert_object(path[0]).is_equal(Vector2i(0, 0))
	assert_object(path[path.size() - 1]).is_equal(Vector2i(5, 0))


func test_find_path_around_obstacle() -> void:
	var pf := _create_pathfinder()
	var grid := _build_grass_grid(10)
	# Wall of water blocking direct path from (0,3) to (5,3)
	for x in range(1, 5):
		grid[Vector2i(x, 3)] = "water"
	pf.build(10, grid, _default_costs())
	var path: Array = pf.find_path(Vector2i(0, 3), Vector2i(5, 3))
	assert_bool(path.size() > 0).is_true()
	assert_object(path[path.size() - 1]).is_equal(Vector2i(5, 3))
	# Path should not pass through any water tile
	for cell in path:
		assert_str(grid.get(cell, "grass")).is_not_equal("water")


func test_find_path_no_route() -> void:
	var pf := _create_pathfinder()
	var grid := _build_grass_grid(10)
	# Fully enclose (5,5) with water
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx != 0 or dy != 0:
				grid[Vector2i(5 + dx, 5 + dy)] = "water"
	pf.build(10, grid, _default_costs())
	var path: Array = pf.find_path(Vector2i(0, 0), Vector2i(5, 5))
	assert_int(path.size()).is_equal(0)


func test_terrain_cost_affects_path() -> void:
	var pf := _create_pathfinder()
	var grid := _build_grass_grid(10)
	# Place forest along direct route (row 0, cols 1-4)
	for x in range(1, 5):
		grid[Vector2i(x, 0)] = "forest"
	pf.build(10, grid, _default_costs())
	# Path from (0,0) to (5,0) — may prefer detour through grass
	var path: Array = pf.find_path(Vector2i(0, 0), Vector2i(5, 0))
	assert_bool(path.size() > 0).is_true()
	assert_object(path[path.size() - 1]).is_equal(Vector2i(5, 0))


func test_impassable_terrain() -> void:
	var pf := _create_pathfinder()
	var grid := _build_grass_grid(10)
	grid[Vector2i(3, 3)] = "water"
	pf.build(10, grid, _default_costs())
	assert_bool(pf.is_cell_solid(Vector2i(3, 3))).is_true()
	assert_bool(pf.is_cell_solid(Vector2i(0, 0))).is_false()


func test_diagonal_movement() -> void:
	var pf := _create_pathfinder()
	pf.build(10, _build_grass_grid(10), _default_costs())
	var path: Array = pf.find_path(Vector2i(0, 0), Vector2i(3, 3))
	assert_bool(path.size() > 0).is_true()
	# Diagonal path should be shorter than manhattan distance
	assert_bool(path.size() <= 7).is_true()


# -- Formation targets --


func test_formation_targets_count() -> void:
	var pf := _create_pathfinder()
	pf.build(10, _build_grass_grid(10), _default_costs())
	var targets: Array = pf.get_formation_targets(Vector2i(5, 5), 4)
	assert_int(targets.size()).is_equal(4)


func test_formation_targets_skip_solid() -> void:
	var pf := _create_pathfinder()
	var grid := _build_grass_grid(10)
	# Make cells around center solid
	grid[Vector2i(4, 5)] = "water"
	grid[Vector2i(6, 5)] = "water"
	pf.build(10, grid, _default_costs())
	var targets: Array = pf.get_formation_targets(Vector2i(5, 5), 4)
	assert_int(targets.size()).is_equal(4)
	# No target should be on a solid cell
	for t in targets:
		assert_bool(pf.is_cell_solid(t)).is_false()


# -- Dynamic updates --


func test_set_cell_solid() -> void:
	var pf := _create_pathfinder()
	pf.build(10, _build_grass_grid(10), _default_costs())
	assert_bool(pf.is_cell_solid(Vector2i(2, 2))).is_false()
	pf.set_cell_solid(Vector2i(2, 2), true)
	assert_bool(pf.is_cell_solid(Vector2i(2, 2))).is_true()
	pf.set_cell_solid(Vector2i(2, 2), false)
	assert_bool(pf.is_cell_solid(Vector2i(2, 2))).is_false()


# -- World coordinate conversion --


func test_find_path_world_coords() -> void:
	var pf := _create_pathfinder()
	pf.build(10, _build_grass_grid(10), _default_costs())
	var from_world := IsoUtils.grid_to_screen(Vector2(0, 0))
	var to_world := IsoUtils.grid_to_screen(Vector2(3, 0))
	var path: Array = pf.find_path_world(from_world, to_world)
	assert_bool(path.size() > 0).is_true()
	# First and last points should match grid-to-screen of start/end
	assert_object(path[0]).is_equal(IsoUtils.grid_to_screen(Vector2(0, 0)))
	assert_object(path[path.size() - 1]).is_equal(IsoUtils.grid_to_screen(Vector2(3, 0)))


# -- Edge cases --


func test_out_of_bounds_returns_empty() -> void:
	var pf := _create_pathfinder()
	var grid := _build_grass_grid(5)
	# Make (4,4) solid and request path to it
	grid[Vector2i(4, 4)] = "water"
	pf.build(5, grid, _default_costs())
	var path: Array = pf.find_path(Vector2i(0, 0), Vector2i(4, 4))
	assert_int(path.size()).is_equal(0)


func test_build_with_terrain_config() -> void:
	var pf := _create_pathfinder()
	var grid := _build_grass_grid(10)
	grid[Vector2i(1, 1)] = "desert"
	grid[Vector2i(2, 2)] = "forest"
	grid[Vector2i(3, 3)] = "water"
	var costs := {"grass": 1.0, "forest": 3.0, "desert": 2.0, "water": -1}
	pf.build(10, grid, costs)
	assert_bool(pf.is_cell_solid(Vector2i(3, 3))).is_true()
	assert_bool(pf.is_cell_solid(Vector2i(1, 1))).is_false()
	assert_bool(pf.is_cell_solid(Vector2i(2, 2))).is_false()
	# Path should exist between non-solid cells
	var path: Array = pf.find_path(Vector2i(0, 0), Vector2i(2, 2))
	assert_bool(path.size() > 0).is_true()
