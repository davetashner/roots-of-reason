extends RefCounted
## Generates resource node positions using noise-based suitability scoring
## with terrain affinity weights, minimum spacing, and starting zone guarantees.
##
## Usage:
##   var gen := ResourceGenerator.new()
##   gen.configure(config)
##   var result := gen.generate(terrain_grid, 64, 64, 42)
##   var gold_positions: Array[Vector2i] = gen.get_positions_for("gold_mine")

var _config: Dictionary = {}
var _resource_positions: Dictionary = {}  # resource_name -> Array[Vector2i]


func configure(config: Dictionary) -> void:
	_config = config


func generate(
	terrain_grid: Dictionary,
	map_width: int,
	map_height: int,
	base_seed: int,
	starting_positions: Array = [],
) -> Dictionary:
	_resource_positions.clear()

	var resources_cfg: Dictionary = _config.get("resources", {})
	var placement_order: Array = _config.get("placement_order", [])
	if resources_cfg.is_empty() or placement_order.is_empty():
		return _resource_positions

	var map_area: int = map_width * map_height
	# Track all placed positions globally to prevent overlap
	var occupied: Dictionary = {}  # Vector2i -> true

	for res_name in placement_order:
		var res_name_str: String = str(res_name)
		var res_cfg: Dictionary = resources_cfg.get(res_name_str, {})
		if res_cfg.is_empty():
			continue

		var positions: Array[Vector2i] = _place_resource(
			res_name_str,
			res_cfg,
			terrain_grid,
			map_width,
			map_height,
			map_area,
			base_seed,
			occupied,
		)
		_resource_positions[res_name_str] = positions
		for pos: Vector2i in positions:
			occupied[pos] = true

	# Starting zone guarantees
	var starting_zone_radius: int = int(_config.get("starting_zone_radius", 15))
	var guarantees: Dictionary = _config.get("starting_zone_guarantees", {})
	if not starting_positions.is_empty() and not guarantees.is_empty():
		_apply_starting_guarantees(
			starting_positions,
			starting_zone_radius,
			guarantees,
			resources_cfg,
			terrain_grid,
			map_width,
			map_height,
			base_seed,
			occupied,
		)

	return _resource_positions


func get_resource_positions() -> Dictionary:
	return _resource_positions


func get_positions_for(resource_name: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var raw: Array = _resource_positions.get(resource_name, [])
	for pos in raw:
		result.append(pos as Vector2i)
	return result


func _place_resource(
	_res_name: String,
	res_cfg: Dictionary,
	terrain_grid: Dictionary,
	map_width: int,
	map_height: int,
	map_area: int,
	base_seed: int,
	occupied: Dictionary,
) -> Array[Vector2i]:
	var density: float = float(res_cfg.get("density_per_1000_tiles", 1))
	var target_count: int = maxi(1, ceili(density * float(map_area) / 1000.0))
	var terrain_affinity: Dictionary = res_cfg.get("terrain_affinity", {})
	var forbidden_terrain: Array = res_cfg.get("forbidden_terrain", [])
	var min_spacing: int = int(res_cfg.get("min_spacing", 2))
	var noise_weight: float = float(res_cfg.get("noise_weight", 0.4))
	var noise_seed_offset: int = int(res_cfg.get("noise_seed_offset", 4000))

	# Build forbidden set for fast lookup
	var forbidden_set: Dictionary = {}
	for ft in forbidden_terrain:
		forbidden_set[str(ft)] = true

	# Generate noise grid
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = base_seed + noise_seed_offset
	noise.frequency = 0.05

	# Score all candidate tiles
	var candidates: Array = []  # Array of [score, Vector2i]
	for y in map_height:
		for x in map_width:
			var pos := Vector2i(x, y)
			var terrain: String = terrain_grid.get(pos, "")
			if terrain.is_empty():
				continue
			# Skip forbidden terrain
			if forbidden_set.has(terrain):
				continue
			# Skip already occupied
			if occupied.has(pos):
				continue
			# Compute suitability
			var affinity: float = float(terrain_affinity.get(terrain, 0.0))
			if affinity <= 0.0:
				continue
			var raw_noise: float = noise.get_noise_2d(float(x), float(y))
			var noise_value: float = (raw_noise + 1.0) / 2.0
			var score: float = affinity * (1.0 - noise_weight) + noise_value * noise_weight
			candidates.append([score, pos])

	# Sort by score descending
	candidates.sort_custom(_compare_candidates_desc)

	# Greedy pick with spacing enforcement
	var occupied_arr: Array = _get_all_occupied_array(occupied)
	var placed: Array[Vector2i] = []
	for candidate in candidates:
		if placed.size() >= target_count:
			break
		var pos: Vector2i = candidate[1]
		if _violates_spacing(pos, placed, min_spacing):
			continue
		if _violates_spacing(pos, occupied_arr, min_spacing):
			continue
		placed.append(pos)

	return placed


func _compare_candidates_desc(a: Array, b: Array) -> bool:
	return a[0] > b[0]


func _violates_spacing(pos: Vector2i, existing: Array, min_spacing: int) -> bool:
	for other in existing:
		var other_pos: Vector2i = other as Vector2i
		if _chebyshev_distance(pos, other_pos) < min_spacing:
			return true
	return false


func _chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _get_all_occupied_array(occupied: Dictionary) -> Array:
	# Only check spacing against occupied if there are not too many
	# For performance, skip global spacing check if occupied is huge
	if occupied.size() > 5000:
		return []
	var arr: Array = []
	for key: Vector2i in occupied:
		arr.append(key)
	return arr


func _apply_starting_guarantees(
	starting_positions: Array,
	radius: int,
	guarantees: Dictionary,
	resources_cfg: Dictionary,
	terrain_grid: Dictionary,
	map_width: int,
	map_height: int,
	base_seed: int,
	occupied: Dictionary,
) -> void:
	for start_pos in starting_positions:
		var sp: Vector2i = start_pos as Vector2i
		for res_name_variant in guarantees:
			var res_name: String = str(res_name_variant)
			var required: int = int(guarantees[res_name])
			var current_positions: Array = _resource_positions.get(res_name, [])

			# Count how many are already within radius
			var nearby_count := 0
			for pos in current_positions:
				var p: Vector2i = pos as Vector2i
				if _chebyshev_distance(p, sp) <= radius:
					nearby_count += 1

			if nearby_count >= required:
				continue

			# Need to place more within the starting zone
			var res_cfg: Dictionary = resources_cfg.get(res_name, {})
			var terrain_affinity: Dictionary = res_cfg.get("terrain_affinity", {})
			var forbidden_terrain: Array = res_cfg.get("forbidden_terrain", [])
			var min_spacing: int = int(res_cfg.get("min_spacing", 2))
			var noise_weight: float = float(res_cfg.get("noise_weight", 0.4))
			var noise_seed_offset: int = int(res_cfg.get("noise_seed_offset", 4000))

			var forbidden_set: Dictionary = {}
			for ft in forbidden_terrain:
				forbidden_set[str(ft)] = true

			var noise := FastNoiseLite.new()
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			noise.seed = base_seed + noise_seed_offset + 999
			noise.frequency = 0.05

			# Find candidates within radius
			var zone_candidates: Array = []
			var x_min: int = maxi(0, sp.x - radius)
			var x_max: int = mini(map_width - 1, sp.x + radius)
			var y_min: int = maxi(0, sp.y - radius)
			var y_max: int = mini(map_height - 1, sp.y + radius)

			for y in range(y_min, y_max + 1):
				for x in range(x_min, x_max + 1):
					var pos := Vector2i(x, y)
					if _chebyshev_distance(pos, sp) > radius:
						continue
					if occupied.has(pos):
						continue
					var terrain: String = terrain_grid.get(pos, "")
					if terrain.is_empty() or forbidden_set.has(terrain):
						continue
					var affinity: float = float(terrain_affinity.get(terrain, 0.0))
					if affinity <= 0.0:
						continue
					var raw_noise: float = noise.get_noise_2d(float(x), float(y))
					var noise_value: float = (raw_noise + 1.0) / 2.0
					var score: float = affinity * (1.0 - noise_weight) + noise_value * noise_weight
					zone_candidates.append([score, pos])

			zone_candidates.sort_custom(_compare_candidates_desc)

			var needed: int = required - nearby_count
			var typed_positions: Array[Vector2i] = []
			for pos in current_positions:
				typed_positions.append(pos as Vector2i)

			for candidate in zone_candidates:
				if needed <= 0:
					break
				var pos: Vector2i = candidate[1]
				if _violates_spacing(pos, typed_positions, min_spacing):
					continue
				typed_positions.append(pos)
				occupied[pos] = true
				needed -= 1

			_resource_positions[res_name] = typed_positions
