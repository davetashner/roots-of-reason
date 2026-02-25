extends RefCounted
## Selects fair starting locations for all players using candidate scoring
## and pair selection. Ensures TC footprints are fully buildable, positions
## are reachable via flood fill, and scores are balanced between players.

const DIRECTIONS_4 := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

var _player_count: int = 2
var _min_distance: int = 30
var _map_margin: int = 8
var _candidate_grid_step: int = 4
var _tc_footprint: Vector2i = Vector2i(3, 3)
var _reachability_radius: int = 10
var _min_reachable_tiles: int = 120
var _scoring_radius: int = 12
var _scoring_weights: Dictionary = {
	"buildable_ratio": 0.3,
	"terrain_diversity": 0.2,
	"elevation_midrange": 0.25,
	"center_proximity": 0.25,
}
var _elevation_ideal_min: float = 0.3
var _elevation_ideal_max: float = 0.6
var _seed_offset: int = 5000
var _villager_offsets: Array = [[-1, 0], [0, -1], [-1, -1], [1, -1], [-1, 1]]


func configure(config: Dictionary) -> void:
	_player_count = int(config.get("player_count", _player_count))
	_min_distance = int(config.get("min_distance", _min_distance))
	_map_margin = int(config.get("map_margin", _map_margin))
	_candidate_grid_step = int(config.get("candidate_grid_step", _candidate_grid_step))
	var fp = config.get("tc_footprint", null)
	if fp is Array and fp.size() == 2:
		_tc_footprint = Vector2i(int(fp[0]), int(fp[1]))
	_reachability_radius = int(config.get("reachability_radius", _reachability_radius))
	_min_reachable_tiles = int(config.get("min_reachable_tiles", _min_reachable_tiles))
	_scoring_radius = int(config.get("scoring_radius", _scoring_radius))
	var sw = config.get("scoring_weights", null)
	if sw is Dictionary and not sw.is_empty():
		_scoring_weights = sw
	_elevation_ideal_min = float(config.get("elevation_ideal_min", _elevation_ideal_min))
	_elevation_ideal_max = float(config.get("elevation_ideal_max", _elevation_ideal_max))
	_seed_offset = int(config.get("seed_offset", _seed_offset))
	var vo = config.get("villager_offsets", null)
	if vo is Array and not vo.is_empty():
		_villager_offsets = vo


func generate(
	terrain_grid: Dictionary,
	elevation_grid: Dictionary,
	terrain_properties: Dictionary,
	map_width: int,
	map_height: int,
	base_seed: int,
) -> Dictionary:
	# Step 1: Build candidates
	var candidates: Array[Vector2i] = _build_candidates(
		terrain_grid, elevation_grid, terrain_properties, map_width, map_height
	)

	if candidates.is_empty():
		return {"starting_positions": [] as Array[Vector2i], "scores": [] as Array[float]}

	# Step 2: Score candidates
	var scores: Dictionary = {}  # Vector2i -> float
	for candidate: Vector2i in candidates:
		scores[candidate] = _score_candidate(
			candidate, terrain_grid, elevation_grid, terrain_properties, map_width, map_height
		)

	# Step 3: Select positions
	if _player_count == 1:
		var best_pos := candidates[0]
		var best_score: float = scores[best_pos]
		for candidate: Vector2i in candidates:
			if scores[candidate] > best_score:
				best_score = scores[candidate]
				best_pos = candidate
		var positions: Array[Vector2i] = [best_pos]
		var result_scores: Array[float] = [best_score]
		return {"starting_positions": positions, "scores": result_scores}

	var result := _select_pair(candidates, scores, base_seed)
	return result


func get_villager_offsets() -> Array:
	return _villager_offsets


func _build_candidates(
	terrain_grid: Dictionary,
	_elevation_grid: Dictionary,
	terrain_properties: Dictionary,
	map_width: int,
	map_height: int,
) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	var step := _candidate_grid_step
	var margin := _map_margin

	var x_start := margin
	var x_end := map_width - margin - _tc_footprint.x
	var y_start := margin
	var y_end := map_height - margin - _tc_footprint.y

	var x := x_start
	while x <= x_end:
		var y := y_start
		while y <= y_end:
			var pos := Vector2i(x, y)
			if _is_footprint_buildable(pos, terrain_grid, terrain_properties):
				var reachable := _flood_fill_count(pos, terrain_grid, terrain_properties, map_width, map_height)
				if reachable >= _min_reachable_tiles:
					candidates.append(pos)
			y += step
		x += step

	return candidates


func _is_footprint_buildable(
	pos: Vector2i,
	terrain_grid: Dictionary,
	terrain_properties: Dictionary,
) -> bool:
	for dy in _tc_footprint.y:
		for dx in _tc_footprint.x:
			var cell := Vector2i(pos.x + dx, pos.y + dy)
			var terrain: String = terrain_grid.get(cell, "")
			if terrain.is_empty():
				return false
			var props: Dictionary = terrain_properties.get(terrain, {})
			if not props.get("buildable", true):
				return false
	return true


func _flood_fill_count(
	origin: Vector2i,
	terrain_grid: Dictionary,
	terrain_properties: Dictionary,
	map_width: int,
	map_height: int,
) -> int:
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [origin]
	visited[origin] = true
	var count := 0
	var radius := _reachability_radius

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		count += 1

		for dir: Vector2i in DIRECTIONS_4:
			var neighbor := current + dir
			if visited.has(neighbor):
				continue
			if _chebyshev_distance(neighbor, origin) > radius:
				continue
			if neighbor.x < 0 or neighbor.x >= map_width:
				continue
			if neighbor.y < 0 or neighbor.y >= map_height:
				continue
			var terrain: String = terrain_grid.get(neighbor, "")
			if terrain.is_empty():
				continue
			var props: Dictionary = terrain_properties.get(terrain, {})
			if not props.get("buildable", true):
				continue
			visited[neighbor] = true
			queue.append(neighbor)

	return count


func _score_candidate(
	pos: Vector2i,
	terrain_grid: Dictionary,
	elevation_grid: Dictionary,
	terrain_properties: Dictionary,
	map_width: int,
	map_height: int,
) -> float:
	var radius := _scoring_radius
	var buildable_count := 0
	var total_count := 0
	var terrain_types: Dictionary = {}
	var midrange_count := 0
	var elevation_total := 0

	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var cell := Vector2i(pos.x + dx, pos.y + dy)
			if cell.x < 0 or cell.x >= map_width:
				continue
			if cell.y < 0 or cell.y >= map_height:
				continue
			var terrain: String = terrain_grid.get(cell, "")
			if terrain.is_empty():
				continue
			total_count += 1
			var props: Dictionary = terrain_properties.get(terrain, {})
			if props.get("buildable", true):
				buildable_count += 1
			terrain_types[terrain] = true
			var elev: float = elevation_grid.get(cell, 0.5)
			elevation_total += 1
			if elev >= _elevation_ideal_min and elev <= _elevation_ideal_max:
				midrange_count += 1

	if total_count == 0:
		return 0.0

	var buildable_ratio: float = float(buildable_count) / float(total_count)
	# Normalize terrain diversity: 7 terrain types max
	var diversity: float = clampf(float(terrain_types.size()) / 5.0, 0.0, 1.0)
	var midrange_ratio: float = 0.0
	if elevation_total > 0:
		midrange_ratio = float(midrange_count) / float(elevation_total)

	# Center proximity: closer to center is slightly better (avoid corner starts)
	var center := Vector2(float(map_width) / 2.0, float(map_height) / 2.0)
	var max_dist := center.length()
	var dist_to_center := Vector2(pos).distance_to(center)
	var center_score: float = 1.0 - clampf(dist_to_center / max_dist, 0.0, 1.0)

	var w_buildable: float = float(_scoring_weights.get("buildable_ratio", 0.3))
	var w_diversity: float = float(_scoring_weights.get("terrain_diversity", 0.2))
	var w_elevation: float = float(_scoring_weights.get("elevation_midrange", 0.25))
	var w_center: float = float(_scoring_weights.get("center_proximity", 0.25))

	return (
		buildable_ratio * w_buildable + diversity * w_diversity + midrange_ratio * w_elevation + center_score * w_center
	)


func _select_pair(
	candidates: Array[Vector2i],
	scores: Dictionary,
	_base_seed: int,
) -> Dictionary:
	var best_value: float = -1.0
	var best_a := Vector2i(-1, -1)
	var best_b := Vector2i(-1, -1)

	# Try with configured min_distance, then relax
	@warning_ignore("integer_division")
	var distances_to_try: Array[int] = [_min_distance, _min_distance / 2, 15, 0]

	for min_dist: int in distances_to_try:
		best_value = -1.0
		for i in candidates.size():
			for j in range(i + 1, candidates.size()):
				var a := candidates[i]
				var b := candidates[j]
				var dist := _chebyshev_distance(a, b)
				if dist < min_dist:
					continue
				var s1: float = scores[a]
				var s2: float = scores[b]
				var max_s := maxf(s1, s2)
				if max_s <= 0.0:
					continue
				var balance: float = minf(s1, s2) / max_s
				var value: float = float(dist) * balance
				if value > best_value:
					best_value = value
					best_a = a
					best_b = b

		if best_value > 0.0:
			break

	if best_value <= 0.0:
		# Absolute fallback: pick two best-scoring candidates
		var sorted_candidates := candidates.duplicate()
		sorted_candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return scores[a] > scores[b])
		if sorted_candidates.size() >= 2:
			best_a = sorted_candidates[0]
			best_b = sorted_candidates[1]
		elif sorted_candidates.size() == 1:
			var single_pos: Array[Vector2i] = [sorted_candidates[0]]
			var single_scores: Array[float] = [scores[sorted_candidates[0]]]
			return {"starting_positions": single_pos, "scores": single_scores}
		else:
			return {"starting_positions": [] as Array[Vector2i], "scores": [] as Array[float]}

	var positions: Array[Vector2i] = [best_a, best_b]
	var result_scores: Array[float] = [scores[best_a], scores[best_b]]
	return {"starting_positions": positions, "scores": result_scores}


func _chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
