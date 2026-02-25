extends RefCounted
## Pure symmetric shadowcasting FOV calculator.
## Computes visible tiles from an origin given LOS radius and a
## blocking function. No side effects — returns a Dictionary of
## visible Vector2i positions.


static func compute_visible_tiles(
	origin: Vector2i,
	los_radius: int,
	map_width: int,
	map_height: int,
	blocks_los_fn: Callable,
) -> Dictionary:
	var visible: Dictionary = {}  # Vector2i -> true

	if los_radius <= 0:
		visible[origin] = true
		return visible

	# Origin is always visible
	visible[origin] = true

	# Process 8 octants
	for octant in 8:
		_scan_octant(origin, los_radius, map_width, map_height, blocks_los_fn, visible, octant, 1, 0.0, 1.0)

	return visible


static func _scan_octant(
	origin: Vector2i,
	radius: int,
	map_width: int,
	map_height: int,
	blocks_los_fn: Callable,
	visible: Dictionary,
	octant: int,
	row: int,
	start_slope: float,
	end_slope: float,
) -> void:
	if start_slope >= end_slope:
		return
	if row > radius:
		return

	var prev_blocked := false
	var new_start := start_slope

	for col in range(row + 1):
		var slope_start: float = (float(col) - 0.5) / (float(row) + 0.5)
		var slope_end: float = (float(col) + 0.5) / (float(row) - 0.5) if row > 0 else 1.0

		if slope_end <= start_slope:
			continue
		if slope_start >= end_slope:
			break

		var tile := _transform_octant(origin, row, col, octant)

		# Check bounds
		if tile.x < 0 or tile.x >= map_width or tile.y < 0 or tile.y >= map_height:
			prev_blocked = true
			new_start = slope_end
			continue

		# Check if within radius (circular LOS)
		var dx := tile.x - origin.x
		var dy := tile.y - origin.y
		if dx * dx + dy * dy > radius * radius:
			prev_blocked = true
			new_start = slope_end
			continue

		visible[tile] = true

		var is_blocked: bool = blocks_los_fn.call(tile)

		if is_blocked:
			if not prev_blocked:
				# Start of a blocked section — recurse with narrowed slope
				_scan_octant(
					origin,
					radius,
					map_width,
					map_height,
					blocks_los_fn,
					visible,
					octant,
					row + 1,
					new_start,
					slope_start,
				)
			prev_blocked = true
			new_start = slope_end
		else:
			prev_blocked = false

	if not prev_blocked:
		_scan_octant(
			origin,
			radius,
			map_width,
			map_height,
			blocks_los_fn,
			visible,
			octant,
			row + 1,
			new_start,
			end_slope,
		)


static func _transform_octant(origin: Vector2i, row: int, col: int, octant: int) -> Vector2i:
	match octant:
		0:
			return Vector2i(origin.x + col, origin.y - row)
		1:
			return Vector2i(origin.x + row, origin.y - col)
		2:
			return Vector2i(origin.x + row, origin.y + col)
		3:
			return Vector2i(origin.x + col, origin.y + row)
		4:
			return Vector2i(origin.x - col, origin.y + row)
		5:
			return Vector2i(origin.x - row, origin.y + col)
		6:
			return Vector2i(origin.x - row, origin.y - col)
		7:
			return Vector2i(origin.x - col, origin.y - row)
	return origin
