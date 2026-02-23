extends RefCounted
## Generates rivers by tracing downhill paths from high-elevation sources.
## Takes an elevation grid and terrain grid, produces river overlay data including
## flow directions, river IDs, and widths. Rivers merge and widen at confluences.
##
## TODO (ovr.4): Starting position proximity constraints — 8-tile exclusion zone,
## 10-tile access requirement.

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

var _river_count_min: int = 2
var _river_count_max: int = 4
var _source_elevation_threshold: float = 0.70
var _noise_wander_strength: float = 0.04
var _min_river_length: int = 5
var _min_source_spacing: int = 15
var _seed_offset: int = 2000

# Result data
var _river_tiles: Dictionary = {}  # Vector2i -> true
var _flow_directions: Dictionary = {}  # Vector2i -> Vector2i
var _river_ids: Dictionary = {}  # Vector2i -> int
var _river_widths: Dictionary = {}  # Vector2i -> int


func configure(config: Dictionary) -> void:
	_river_count_min = int(config.get("river_count_min", _river_count_min))
	_river_count_max = int(config.get("river_count_max", _river_count_max))
	_source_elevation_threshold = float(config.get("source_elevation_threshold", _source_elevation_threshold))
	_noise_wander_strength = float(config.get("noise_wander_strength", _noise_wander_strength))
	_min_river_length = int(config.get("min_river_length", _min_river_length))
	_min_source_spacing = int(config.get("min_source_spacing", _min_source_spacing))
	_seed_offset = int(config.get("seed_offset", _seed_offset))


func generate(
	elevation_grid: Dictionary,
	terrain_grid: Dictionary,
	map_width: int,
	map_height: int,
	base_seed: int,
) -> Dictionary:
	_river_tiles.clear()
	_flow_directions.clear()
	_river_ids.clear()
	_river_widths.clear()

	var rng := RandomNumberGenerator.new()
	rng.seed = base_seed + _seed_offset

	# Wander noise for natural curves
	var wander_noise := FastNoiseLite.new()
	wander_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	wander_noise.seed = base_seed + _seed_offset + 500
	wander_noise.frequency = 0.1

	# Step 1: Find candidate sources
	var candidates := _find_source_candidates(elevation_grid, terrain_grid)

	# Shuffle with seeded RNG
	_shuffle_array(candidates, rng)

	# Step 2: Select sources with minimum spacing
	var target_count: int = rng.randi_range(_river_count_min, _river_count_max)
	var sources := _select_spaced_sources(candidates, target_count, elevation_grid)

	# Step 3: Trace rivers from each source
	var river_paths: Array = []
	for i in sources.size():
		var path := _trace_river(sources[i], elevation_grid, terrain_grid, map_width, map_height, wander_noise, rng)
		if path.size() >= _min_river_length:
			river_paths.append(path)

	# Step 4: Apply river data with IDs and detect merges
	var merge_points: Array[Vector2i] = []
	for river_id in river_paths.size():
		var path: Array = river_paths[river_id]
		for pos: Vector2i in path:
			if _river_tiles.has(pos):
				# Merge point — existing river
				merge_points.append(pos)
			_river_tiles[pos] = true
			_river_ids[pos] = river_id
			_river_widths[pos] = 1

		# Set flow directions
		for j in path.size() - 1:
			var current: Vector2i = path[j]
			var next_pos: Vector2i = path[j + 1]
			_flow_directions[current] = next_pos - current

	# Step 5: Widen at merge points, propagated downstream
	for merge_pos: Vector2i in merge_points:
		_widen_downstream(merge_pos, 10)

	return {
		"river_tiles": _river_tiles,
		"flow_directions": _flow_directions,
		"river_ids": _river_ids,
		"river_widths": _river_widths,
	}


func is_river(pos: Vector2i) -> bool:
	return _river_tiles.has(pos)


func get_flow_direction(pos: Vector2i) -> Vector2i:
	return _flow_directions.get(pos, Vector2i.ZERO)


func get_river_id(pos: Vector2i) -> int:
	return _river_ids.get(pos, -1)


func get_river_width(pos: Vector2i) -> int:
	return _river_widths.get(pos, 0)


func _find_source_candidates(
	elevation_grid: Dictionary,
	terrain_grid: Dictionary,
) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	var threshold := _source_elevation_threshold

	# Try with configured threshold, then relax if needed
	for attempt in 3:
		candidates.clear()
		for pos: Vector2i in elevation_grid:
			var elev: float = elevation_grid[pos]
			if elev < threshold:
				continue
			var terrain: String = terrain_grid.get(pos, "")
			if terrain == "mountain" or terrain == "stone":
				candidates.append(pos)
		if candidates.size() >= _river_count_min:
			break
		threshold -= 0.05

	return candidates


func _select_spaced_sources(
	candidates: Array[Vector2i],
	target_count: int,
	_elev_grid: Dictionary,
) -> Array[Vector2i]:
	var selected: Array[Vector2i] = []
	for candidate: Vector2i in candidates:
		if selected.size() >= target_count:
			break
		var too_close := false
		for existing: Vector2i in selected:
			var dist := _chebyshev_distance(candidate, existing)
			if dist < _min_source_spacing:
				too_close = true
				break
		if not too_close:
			selected.append(candidate)
	return selected


func _trace_river(
	source: Vector2i,
	elevation_grid: Dictionary,
	terrain_grid: Dictionary,
	map_width: int,
	map_height: int,
	wander_noise: FastNoiseLite,
	_rng: RandomNumberGenerator,
) -> Array:
	var path: Array = [source]
	var current := source
	var visited: Dictionary = {source: true}
	var max_steps: int = map_width + map_height  # Safety limit

	for _step in max_steps:
		var best_neighbor := Vector2i(-1, -1)
		var best_score: float = INF

		for dir: Vector2i in DIRECTIONS_8:
			var neighbor := current + dir
			if visited.has(neighbor):
				continue
			if not elevation_grid.has(neighbor):
				continue
			if neighbor.x < 0 or neighbor.x >= map_width:
				continue
			if neighbor.y < 0 or neighbor.y >= map_height:
				continue

			var neighbor_terrain: String = terrain_grid.get(neighbor, "")
			if neighbor_terrain == "mountain":
				continue

			var elev: float = elevation_grid[neighbor]
			# Add noise wander for natural curves
			var wander: float = wander_noise.get_noise_2d(float(neighbor.x), float(neighbor.y)) * _noise_wander_strength
			var score: float = elev + wander

			if score < best_score:
				best_score = score
				best_neighbor = neighbor

		if best_neighbor == Vector2i(-1, -1):
			# No valid neighbor — reached edge or dead end
			break

		path.append(best_neighbor)
		visited[best_neighbor] = true
		current = best_neighbor

		# Check termination conditions
		var current_terrain: String = terrain_grid.get(current, "")
		if current_terrain == "water":
			break
		if _river_tiles.has(current):
			break  # Merge with existing river

	return path


func _widen_downstream(start: Vector2i, steps: int) -> void:
	var current := start
	for _i in steps:
		_river_widths[current] = 2
		var dir: Vector2i = _flow_directions.get(current, Vector2i.ZERO)
		if dir == Vector2i.ZERO:
			break
		var next_pos := current + dir
		if not _river_tiles.has(next_pos):
			break
		current = next_pos


func _chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _shuffle_array(arr: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Vector2i = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
