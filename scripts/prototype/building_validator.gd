class_name BuildingValidator
## Pure static utility for building placement validation.
## No state — all functions are static and fully testable.


static func get_footprint_cells(origin: Vector2i, footprint: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in footprint.x:
		for y in footprint.y:
			cells.append(origin + Vector2i(x, y))
	return cells


static func is_placement_valid(
	origin: Vector2i,
	footprint: Vector2i,
	map_node: Node,
	pathfinder: Node,
	placement_constraint: String = "",
) -> bool:
	var cells := get_footprint_cells(origin, footprint)
	var map_size: int = 0
	if map_node != null and map_node.has_method("get_map_size"):
		map_size = map_node.get_map_size()
	for cell in cells:
		if not _is_in_bounds(cell, map_size):
			return false
		if _is_unbuildable(cell, map_node):
			return false
		if _is_solid(cell, pathfinder):
			return false
	if placement_constraint != "":
		if not _check_placement_constraint(cells, map_node, placement_constraint):
			return false
	return true


static func _is_in_bounds(cell: Vector2i, map_size: int) -> bool:
	return cell.x >= 0 and cell.x < map_size and cell.y >= 0 and cell.y < map_size


static func _is_unbuildable(cell: Vector2i, map_node: Node) -> bool:
	if map_node == null:
		return false
	if map_node.has_method("is_buildable"):
		return not map_node.is_buildable(cell)
	if map_node.has_method("get_terrain_at"):
		return map_node.get_terrain_at(cell) == "water"
	return false


static func _is_solid(cell: Vector2i, pathfinder: Node) -> bool:
	if pathfinder == null or not pathfinder.has_method("is_cell_solid"):
		return false
	return pathfinder.is_cell_solid(cell)


static func _check_placement_constraint(cells: Array[Vector2i], map_node: Node, constraint: String) -> bool:
	match constraint:
		"adjacent_to_river":
			return _has_adjacent_river(cells, map_node)
		"adjacent_to_water":
			return _has_adjacent_water(cells, map_node)
		_:
			push_warning("BuildingValidator: unknown placement_constraint '%s'" % constraint)
			return true


static func _has_adjacent_river(cells: Array[Vector2i], map_node: Node) -> bool:
	if map_node == null or not map_node.has_method("is_river"):
		return false
	var directions: Array[Vector2i] = [
		Vector2i(-1, -1),
		Vector2i(0, -1),
		Vector2i(1, -1),
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(-1, 1),
		Vector2i(0, 1),
		Vector2i(1, 1),
	]
	for cell in cells:
		for dir in directions:
			var neighbor := cell + dir
			if map_node.is_river(neighbor):
				return true
	return false


static func _has_adjacent_water(cells: Array[Vector2i], map_node: Node) -> bool:
	if map_node == null or not map_node.has_method("get_terrain_at"):
		return false
	var water_terrains: Array[String] = ["water", "shallows", "deep_water"]
	var directions: Array[Vector2i] = [
		Vector2i(-1, -1),
		Vector2i(0, -1),
		Vector2i(1, -1),
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(-1, 1),
		Vector2i(0, 1),
		Vector2i(1, 1),
	]
	for cell in cells:
		for dir in directions:
			var neighbor := cell + dir
			if map_node.get_terrain_at(neighbor) in water_terrains:
				return true
	return false
