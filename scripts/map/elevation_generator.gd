extends RefCounted
## Generates an elevation grid using FastNoiseLite simplex noise.
## Produces a Dictionary of Vector2i -> float values normalized to [0.0, 1.0].
## Designed as a minimal elevation layer for river generation (ovr.6).
## ovr.2 (Perlin noise terrain) can expand this without touching river code.

var _frequency: float = 0.015
var _octaves: int = 4
var _lacunarity: float = 2.0
var _gain: float = 0.5
var _seed_offset: int = 1000


func configure(config: Dictionary) -> void:
	_frequency = float(config.get("frequency", _frequency))
	_octaves = int(config.get("octaves", _octaves))
	_lacunarity = float(config.get("lacunarity", _lacunarity))
	_gain = float(config.get("gain", _gain))
	_seed_offset = int(config.get("seed_offset", _seed_offset))


func generate(map_width: int, map_height: int, base_seed: int) -> Dictionary:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.frequency = _frequency
	noise.fractal_octaves = _octaves
	noise.fractal_lacunarity = _lacunarity
	noise.fractal_gain = _gain
	noise.seed = base_seed + _seed_offset

	# First pass: sample raw noise values and track min/max for normalization
	var raw_values: Dictionary = {}
	var min_val: float = INF
	var max_val: float = -INF

	for y in map_height:
		for x in map_width:
			var val: float = noise.get_noise_2d(float(x), float(y))
			raw_values[Vector2i(x, y)] = val
			if val < min_val:
				min_val = val
			if val > max_val:
				max_val = val

	# Second pass: normalize to [0.0, 1.0]
	var grid: Dictionary = {}
	var range_val: float = max_val - min_val
	if range_val < 0.0001:
		# Flat map — all same elevation
		for pos: Vector2i in raw_values:
			grid[pos] = 0.5
	else:
		for pos: Vector2i in raw_values:
			grid[pos] = (raw_values[pos] - min_val) / range_val

	return grid
