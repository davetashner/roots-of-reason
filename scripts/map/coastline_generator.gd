extends RefCounted
## Reclassifies water and adjacent land tiles into shore, shallows, and deep_water
## based on 8-directional adjacency. Creates natural 3-band coastlines:
## land -> shore -> shallows -> deep_water.

const DIRECTIONS_8 := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]

## Cardinal directions for shore orientation detection (isometric diamond-down).
const CARDINAL_DIRS := [
	Vector2i(0, -1),  # NE in screen space
	Vector2i(-1, 0),  # NW in screen space
	Vector2i(1, 0),  # SE in screen space
	Vector2i(0, 1),  # SW in screen space
]

## Land types that never become shore (they have special terrain behavior).
const NEVER_SHORE := ["mountain", "river", "canyon"]

## Water-like terrain types used for orientation detection.
const WATER_TYPES := ["water", "shallows", "deep_water"]

var _shore_enabled: bool = true


func configure(config: Dictionary) -> void:
	_shore_enabled = bool(config.get("shore_enabled", _shore_enabled))


func generate(tile_grid: Dictionary, map_width: int, map_height: int) -> Dictionary:
	var changes: Dictionary = {}  # Vector2i -> String
	var shore_orientations: Dictionary = {}  # Vector2i -> Vector2i

	if not _shore_enabled:
		return {
			"changes": changes,
			"shore_orientations": shore_orientations,
			"shore_segments": {},
		}

	# Two-phase collect-then-apply: scan all tiles, then apply changes.
	# This prevents cascading (e.g. a newly-assigned shore triggering more shore).
	for y in map_height:
		for x in map_width:
			var pos := Vector2i(x, y)
			var terrain: String = tile_grid.get(pos, "")
			if terrain.is_empty():
				continue

			if terrain == "water":
				# Water adjacent to any land -> shallows; otherwise -> deep_water
				if _has_land_neighbor(pos, tile_grid):
					changes[pos] = "shallows"
				else:
					changes[pos] = "deep_water"
			elif terrain not in NEVER_SHORE:
				# Walkable land adjacent to water -> shore
				if _has_water_neighbor(pos, tile_grid):
					changes[pos] = "shore"

	# Determine orientation for each shore tile (which direction has water).
	# Uses the merged grid (original + changes) so shallows count as water.
	for pos: Vector2i in changes:
		if changes[pos] == "shore":
			shore_orientations[pos] = _get_water_direction(pos, tile_grid, changes)

	# Smooth orientations so adjacent shore tiles face the same direction.
	shore_orientations = _smooth_orientations(shore_orientations)

	# Label connected shore segments sharing the same orientation.
	var shore_segments: Dictionary = _label_shore_segments(shore_orientations)

	return {
		"changes": changes,
		"shore_orientations": shore_orientations,
		"shore_segments": shore_segments,
	}


func _get_water_direction(pos: Vector2i, tile_grid: Dictionary, changes: Dictionary) -> Vector2i:
	## Returns the cardinal direction toward the dominant water mass from pos.
	## Checks original tile_grid merged with coastline changes so that shallows
	## (which were water before reclassification) also count.
	var best_dir := Vector2i(0, -1)  # Default: NE
	var best_count := 0

	for dir: Vector2i in CARDINAL_DIRS:
		var count := 0
		# Check the cardinal neighbor and its two diagonal extensions
		var neighbor := pos + dir
		var terrain: String = changes.get(neighbor, tile_grid.get(neighbor, ""))
		if terrain in WATER_TYPES:
			count += 1
		# Also check the two diagonals that share this cardinal direction
		for other_dir: Vector2i in CARDINAL_DIRS:
			if other_dir == dir or other_dir == -dir:
				continue
			var diag := pos + dir + other_dir
			var diag_terrain: String = changes.get(diag, tile_grid.get(diag, ""))
			if diag_terrain in WATER_TYPES:
				count += 1
		if count > best_count:
			best_count = count
			best_dir = dir

	return best_dir


func _has_land_neighbor(pos: Vector2i, tile_grid: Dictionary) -> bool:
	for dir: Vector2i in DIRECTIONS_8:
		var neighbor := pos + dir
		var t: String = tile_grid.get(neighbor, "")
		if not t.is_empty() and t != "water":
			return true
	return false


func _has_water_neighbor(pos: Vector2i, tile_grid: Dictionary) -> bool:
	for dir: Vector2i in DIRECTIONS_8:
		var neighbor := pos + dir
		var t: String = tile_grid.get(neighbor, "")
		if t == "water":
			return true
	return false


func _smooth_orientations(orientations: Dictionary) -> Dictionary:
	## Run 2 smoothing passes so each shore tile matches the majority of its
	## shore neighbors. Prevents isolated direction flips at coastline bends.
	var smoothed: Dictionary = orientations.duplicate()
	for _pass in 2:
		var next: Dictionary = smoothed.duplicate()
		for pos: Vector2i in smoothed:
			var counts: Dictionary = {}  # Vector2i -> int
			for dir: Vector2i in DIRECTIONS_8:
				var neighbor := pos + dir
				if smoothed.has(neighbor):
					var n_dir: Vector2i = smoothed[neighbor]
					counts[n_dir] = counts.get(n_dir, 0) + 1
			if counts.is_empty():
				continue
			# Find majority direction among neighbors
			var best_dir: Vector2i = smoothed[pos]
			var best_count: int = 0
			for d: Vector2i in counts:
				if counts[d] > best_count:
					best_count = counts[d]
					best_dir = d
			next[pos] = best_dir
		smoothed = next
	return smoothed


func _label_shore_segments(orientations: Dictionary) -> Dictionary:
	## Flood-fill connected shore tiles that share the same orientation into
	## numbered segments. Returns Dictionary of Vector2i -> int (segment_id).
	var segments: Dictionary = {}  # Vector2i -> int
	var segment_id := 0
	for pos: Vector2i in orientations:
		if segments.has(pos):
			continue
		# BFS flood-fill from this tile
		var orientation: Vector2i = orientations[pos]
		var queue: Array[Vector2i] = [pos]
		segments[pos] = segment_id
		var head := 0
		while head < queue.size():
			var current: Vector2i = queue[head]
			head += 1
			for dir: Vector2i in CARDINAL_DIRS:
				var neighbor := current + dir
				if segments.has(neighbor):
					continue
				if not orientations.has(neighbor):
					continue
				if orientations[neighbor] == orientation:
					segments[neighbor] = segment_id
					queue.append(neighbor)
		segment_id += 1
	return segments
