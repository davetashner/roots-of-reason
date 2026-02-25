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
var _river_scoring_weights: Dictionary = {
	"river_proximity": 0.15,
	"river_direction_diversity": 0.05,
	"river_adjacent_buildable": 0.10,
}
var _river_proximity_radius: int = 12
var _max_river_score_variance: float = 0.3


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
	var rsw = config.get("river_scoring_weights", null)
	if rsw is Dictionary and not rsw.is_empty():
		_river_scoring_weights = rsw
	_river_proximity_radius = int(config.get("river_proximity_radius", _river_proximity_radius))
	_max_river_score_variance = float(config.get("max_river_score_variance", _max_river_score_variance))


func generate(
	terrain_grid: Dictionary,
	elevation_grid: Dictionary,
	terrain_properties: Dictionary,
	map_width: int,
	map_height: int,
	base_seed: int,
	river_tiles: Dictionary = {},
	flow_directions: Dictionary = {},
) -> Dictionary:
	var has_rivers := not river_tiles.is_empty()

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
			candidate,
			terrain_grid,
			elevation_grid,
			terrain_properties,
			map_width,
			map_height,
			river_tiles,
			flow_directions,
			has_rivers,
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

	# Step 3b: Precompute per-candidate river scores for variance check
	var river_scores: Dictionary = {}  # Vector2i -> float
	if has_rivers:
		for candidate: Vector2i in candidates:
			river_scores[candidate] = _compute_river_score(
				candidate,
				terrain_grid,
				terrain_properties,
				river_tiles,
				flow_directions,
				map_width,
				map_height,
			)

	var result := _select_pair(candidates, scores, base_seed, river_scores, has_rivers)
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
	river_tiles: Dictionary = {},
	flow_directions: Dictionary = {},
	has_rivers: bool = false,
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

	if not has_rivers:
		return (
			buildable_ratio * w_buildable
			+ diversity * w_diversity
			+ midrange_ratio * w_elevation
			+ center_score * w_center
		)

	# River sub-scores
	var river_scores := _score_river_access(
		pos, terrain_grid, terrain_properties, river_tiles, flow_directions, map_width, map_height
	)

	var w_river_prox: float = float(_river_scoring_weights.get("river_proximity", 0.15))
	var w_river_dir: float = float(_river_scoring_weights.get("river_direction_diversity", 0.05))
	var w_river_build: float = float(_river_scoring_weights.get("river_adjacent_buildable", 0.10))
	var river_weight_total: float = w_river_prox + w_river_dir + w_river_build

	# Scale original weights down to make room for river weights
	var original_total: float = w_buildable + w_diversity + w_elevation + w_center
	var scale: float = (1.0 - river_weight_total) / original_total if original_total > 0.0 else 0.7

	return (
		buildable_ratio * w_buildable * scale
		+ diversity * w_diversity * scale
		+ midrange_ratio * w_elevation * scale
		+ center_score * w_center * scale
		+ river_scores.proximity * w_river_prox
		+ river_scores.direction_diversity * w_river_dir
		+ river_scores.adjacent_buildable * w_river_build
	)


func _score_river_access(
	pos: Vector2i,
	terrain_grid: Dictionary,
	terrain_properties: Dictionary,
	river_tiles: Dictionary,
	flow_directions: Dictionary,
	map_width: int,
	map_height: int,
) -> Dictionary:
	var radius := _river_proximity_radius
	var river_count := 0
	var total_tiles := 0
	var flow_dirs: Dictionary = {}  # Vector2i -> true (distinct directions)
	var river_adjacent_buildable_count := 0

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
			total_tiles += 1

			if river_tiles.has(cell):
				river_count += 1
				var flow_dir: Vector2i = flow_directions.get(cell, Vector2i.ZERO)
				if flow_dir != Vector2i.ZERO:
					flow_dirs[flow_dir] = true
				# Check 4-adjacent tiles for buildable
				for dir: Vector2i in DIRECTIONS_4:
					var adj := cell + dir
					var adj_terrain: String = terrain_grid.get(adj, "")
					if adj_terrain.is_empty():
						continue
					var props: Dictionary = terrain_properties.get(adj_terrain, {})
					if props.get("buildable", true):
						river_adjacent_buildable_count += 1
						break  # Count this river tile once

	var proximity: float = 0.5  # neutral when no rivers nearby
	if total_tiles > 0 and river_count > 0:
		proximity = clampf(float(river_count) / float(total_tiles) * 10.0, 0.0, 1.0)

	var direction_diversity: float = clampf(float(flow_dirs.size()) / 4.0, 0.0, 1.0)

	var adjacent_buildable: float = 0.0
	if total_tiles > 0:
		adjacent_buildable = clampf(float(river_adjacent_buildable_count) / float(total_tiles) * 10.0, 0.0, 1.0)

	return {
		"proximity": proximity,
		"direction_diversity": direction_diversity,
		"adjacent_buildable": adjacent_buildable,
	}


func _compute_river_score(
	pos: Vector2i,
	terrain_grid: Dictionary,
	terrain_properties: Dictionary,
	river_tiles: Dictionary,
	flow_directions: Dictionary,
	map_width: int,
	map_height: int,
) -> float:
	var rs := _score_river_access(
		pos, terrain_grid, terrain_properties, river_tiles, flow_directions, map_width, map_height
	)
	var w_prox: float = float(_river_scoring_weights.get("river_proximity", 0.15))
	var w_dir: float = float(_river_scoring_weights.get("river_direction_diversity", 0.05))
	var w_build: float = float(_river_scoring_weights.get("river_adjacent_buildable", 0.10))
	return rs.proximity * w_prox + rs.direction_diversity * w_dir + rs.adjacent_buildable * w_build


func _select_pair(
	candidates: Array[Vector2i],
	scores: Dictionary,
	_base_seed: int,
	river_scores: Dictionary = {},
	has_rivers: bool = false,
) -> Dictionary:
	# Collect top pairs sorted by value (distance * balance)
	var top_pairs: Array[Dictionary] = []  # [{a, b, value}]
	var max_pairs := 4 if has_rivers else 1

	# Try with configured min_distance, then relax
	@warning_ignore("integer_division")
	var distances_to_try: Array[int] = [_min_distance, _min_distance / 2, 15, 0]

	for min_dist: int in distances_to_try:
		top_pairs.clear()
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
				# Insert into top_pairs maintaining sorted order (descending)
				var inserted := false
				for k in top_pairs.size():
					if value > float(top_pairs[k].value):
						top_pairs.insert(k, {"a": a, "b": b, "value": value})
						inserted = true
						break
				if not inserted and top_pairs.size() < max_pairs:
					top_pairs.append({"a": a, "b": b, "value": value})
				if top_pairs.size() > max_pairs:
					top_pairs.resize(max_pairs)

		if not top_pairs.is_empty():
			break

	if top_pairs.is_empty():
		# Absolute fallback: pick two best-scoring candidates
		var sorted_candidates := candidates.duplicate()
		sorted_candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return scores[a] > scores[b])
		if sorted_candidates.size() >= 2:
			top_pairs.append({"a": sorted_candidates[0], "b": sorted_candidates[1], "value": 0.0})
		elif sorted_candidates.size() == 1:
			var single_pos: Array[Vector2i] = [sorted_candidates[0]]
			var single_scores: Array[float] = [scores[sorted_candidates[0]]]
			return {"starting_positions": single_pos, "scores": single_scores}
		else:
			return {"starting_positions": [] as Array[Vector2i], "scores": [] as Array[float]}

	# Apply river variance constraint if rivers exist
	if has_rivers and not river_scores.is_empty():
		for pair: Dictionary in top_pairs:
			var rs_a: float = river_scores.get(pair.a, 0.0)
			var rs_b: float = river_scores.get(pair.b, 0.0)
			var max_rs := maxf(rs_a, rs_b)
			if max_rs <= 0.0:
				# Both have zero river score — acceptable (equally river-poor)
				var positions: Array[Vector2i] = [pair.a, pair.b]
				var result_scores: Array[float] = [scores[pair.a], scores[pair.b]]
				return {"starting_positions": positions, "scores": result_scores}
			var variance: float = absf(rs_a - rs_b) / max_rs
			if variance <= _max_river_score_variance:
				var positions: Array[Vector2i] = [pair.a, pair.b]
				var result_scores: Array[float] = [scores[pair.a], scores[pair.b]]
				return {"starting_positions": positions, "scores": result_scores}
		# Fallback: use best pair anyway if none pass variance check

	var best: Dictionary = top_pairs[0]
	var positions: Array[Vector2i] = [best.a, best.b]
	var result_scores: Array[float] = [scores[best.a], scores[best.b]]
	return {"starting_positions": positions, "scores": result_scores}


func _chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
