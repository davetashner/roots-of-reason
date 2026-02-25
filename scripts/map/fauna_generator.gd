extends RefCounted
## Generates fauna pack positions using noise-based suitability scoring
## with terrain affinity, minimum spacing from starts and other packs,
## and a contested pack placed equidistant between players.

var _config: Dictionary = {}


func configure(config: Dictionary) -> void:
	_config = config


func generate(
	terrain_grid: Dictionary,
	map_width: int,
	map_height: int,
	base_seed: int,
	starting_positions: Array = [],
) -> Dictionary:
	var result: Dictionary = {}

	var fauna_types: Dictionary = _config.get("fauna_types", {})
	if fauna_types.is_empty():
		return result

	for fauna_name: String in fauna_types:
		var fauna_cfg: Dictionary = fauna_types[fauna_name]
		var packs: Array[Dictionary] = _place_fauna(
			fauna_cfg,
			terrain_grid,
			map_width,
			map_height,
			base_seed,
			starting_positions,
		)
		result[fauna_name] = packs

	return result


func _place_fauna(
	fauna_cfg: Dictionary,
	terrain_grid: Dictionary,
	map_width: int,
	map_height: int,
	base_seed: int,
	starting_positions: Array,
) -> Array[Dictionary]:
	var map_area: int = map_width * map_height
	var base_count: int = int(fauna_cfg.get("base_pack_count", 3))
	var pack_count_min: int = int(fauna_cfg.get("pack_count_min", 2))
	var pack_count_max: int = int(fauna_cfg.get("pack_count_max", 6))
	var target_count: int = clampi(ceili(float(map_area) / 4096.0 * float(base_count)), pack_count_min, pack_count_max)

	var min_distance_from_start: int = int(fauna_cfg.get("min_distance_from_start", 12))
	var min_distance_between: int = int(fauna_cfg.get("min_distance_between_packs", 8))
	var pack_size_min: int = int(fauna_cfg.get("pack_size_min", 2))
	var pack_size_max: int = int(fauna_cfg.get("pack_size_max", 3))
	var terrain_affinity: Dictionary = fauna_cfg.get("terrain_affinity", {})
	var forbidden_terrain: Array = fauna_cfg.get("forbidden_terrain", [])
	var noise_weight: float = float(fauna_cfg.get("noise_weight", 0.4))
	var noise_seed_offset: int = int(fauna_cfg.get("noise_seed_offset", 6000))

	var forbidden_set: Dictionary = {}
	for ft in forbidden_terrain:
		forbidden_set[str(ft)] = true

	# Build noise grid
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
			if forbidden_set.has(terrain):
				continue
			# Check min distance from starting positions
			if _too_close_to_starts(pos, starting_positions, min_distance_from_start):
				continue
			var affinity: float = float(terrain_affinity.get(terrain, 0.0))
			if affinity <= 0.0:
				continue
			var raw_noise: float = noise.get_noise_2d(float(x), float(y))
			var noise_value: float = (raw_noise + 1.0) / 2.0
			var score: float = affinity * (1.0 - noise_weight) + noise_value * noise_weight
			candidates.append([score, pos])

	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])

	var rng := RandomNumberGenerator.new()
	rng.seed = base_seed + noise_seed_offset + 1

	var packs: Array[Dictionary] = []

	# Place contested pack first if 2+ starting positions
	if starting_positions.size() >= 2 and not candidates.is_empty():
		var contested_pos := _find_contested_position(candidates, starting_positions)
		if contested_pos != Vector2i(-1, -1):
			var pack_size: int = rng.randi_range(pack_size_min, pack_size_max)
			packs.append({"position": contested_pos, "pack_size": pack_size, "contested": true})

	# Greedy remaining packs
	for candidate in candidates:
		if packs.size() >= target_count:
			break
		var pos: Vector2i = candidate[1]
		if _too_close_to_packs(pos, packs, min_distance_between):
			continue
		var pack_size: int = rng.randi_range(pack_size_min, pack_size_max)
		packs.append({"position": pos, "pack_size": pack_size, "contested": false})

	return packs


func _too_close_to_starts(pos: Vector2i, starts: Array, min_dist: int) -> bool:
	for start in starts:
		var sp: Vector2i = start as Vector2i
		if _chebyshev_distance(pos, sp) < min_dist:
			return true
	return false


func _too_close_to_packs(pos: Vector2i, packs: Array[Dictionary], min_dist: int) -> bool:
	for pack: Dictionary in packs:
		var pack_pos: Vector2i = pack.position
		if _chebyshev_distance(pos, pack_pos) < min_dist:
			return true
	return false


func _find_contested_position(candidates: Array, starting_positions: Array) -> Vector2i:
	var sp_a: Vector2i = starting_positions[0] as Vector2i
	var sp_b: Vector2i = starting_positions[1] as Vector2i
	var best_pos := Vector2i(-1, -1)
	var best_diff := 999999

	for candidate in candidates:
		var pos: Vector2i = candidate[1]
		var dist_a := _chebyshev_distance(pos, sp_a)
		var dist_b := _chebyshev_distance(pos, sp_b)
		var diff := absi(dist_a - dist_b)
		if diff < best_diff:
			best_diff = diff
			best_pos = pos
		if diff == 0:
			break

	return best_pos


func _chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
