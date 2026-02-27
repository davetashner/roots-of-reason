extends Node
## A* pathfinding wrapper for the isometric grid.
## Uses Godot's AStarGrid2D with terrain costs from data/settings/terrain.json.

var _astar: AStarGrid2D
var _map_size: int = 0
var _terrain_costs: Dictionary = {}
var _diagonal_multiplier: float = 1.414


func _ready() -> void:
	_load_config()


func _load_config() -> void:
	var cfg: Dictionary = GameUtils.dl_settings("terrain")
	if cfg.is_empty():
		return
	_terrain_costs = cfg.get("terrain_costs", _terrain_costs)
	_diagonal_multiplier = float(cfg.get("diagonal_cost_multiplier", _diagonal_multiplier))


func build(map_size: int, tile_grid: Dictionary, terrain_costs: Dictionary = {}) -> void:
	_map_size = map_size
	if not terrain_costs.is_empty():
		_terrain_costs = terrain_costs

	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, map_size, map_size)
	_astar.cell_size = Vector2(1, 1)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_astar.update()

	for pos: Vector2i in tile_grid:
		var terrain: String = tile_grid[pos]
		var cost: float = _get_terrain_cost(terrain)
		if cost < 0:
			_astar.set_point_solid(pos, true)
		elif cost != 1.0:
			_astar.set_point_weight_scale(pos, cost)

	_astar.update()


func _get_terrain_cost(terrain: String) -> float:
	if _terrain_costs.has(terrain):
		return float(_terrain_costs[terrain])
	# Backward compat: old saves may still have "water" tiles — treat as deep_water
	if terrain == "water" and _terrain_costs.has("deep_water"):
		return float(_terrain_costs["deep_water"])
	return 1.0


func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if _astar == null:
		return []
	# Clamp to grid bounds
	from = _clamp_to_grid(from)
	to = _clamp_to_grid(to)
	if _astar.is_point_solid(from) or _astar.is_point_solid(to):
		return []
	var packed: PackedVector2Array = _astar.get_id_path(from, to)
	var result: Array[Vector2i] = []
	for point in packed:
		result.append(Vector2i(point))
	return result


func find_path_world(from_world: Vector2, to_world: Vector2) -> Array[Vector2]:
	var from_grid := IsoUtils.snap_to_grid(from_world)
	var to_grid := IsoUtils.snap_to_grid(to_world)
	var grid_path := find_path(from_grid, to_grid)
	var world_path: Array[Vector2] = []
	for cell in grid_path:
		world_path.append(IsoUtils.grid_to_screen(Vector2(cell)))
	return world_path


func get_formation_targets(
	center: Vector2i,
	count: int,
	formation_type: int = -1,
	facing: Vector2 = Vector2.RIGHT,
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if count <= 0:
		return result
	# Use FormationManager for shape computation
	var fm := preload("res://scripts/prototype/formation_manager.gd").new()
	if formation_type < 0:
		formation_type = fm.FormationType.STAGGERED
	var offsets: Array[Vector2] = fm.get_offsets(formation_type, count, facing)
	# Dictionary set for O(1) membership checks instead of O(n) array scan
	var used: Dictionary = {}
	# Convert pixel offsets to grid cell offsets and validate
	for offset in offsets:
		var grid_offset := Vector2i(roundi(offset.x / 64.0), roundi(offset.y / 64.0))
		var pos := center + grid_offset
		if _is_valid_cell(pos) and not _astar.is_point_solid(pos) and not used.has(pos):
			result.append(pos)
			used[pos] = true
	# Fill remaining with spiral fallback if some slots were solid
	if result.size() < count:
		var radius := 1
		while result.size() < count and radius <= _map_size:
			for dx in range(-radius, radius + 1):
				for dy in range(-radius, radius + 1):
					if abs(dx) != radius and abs(dy) != radius:
						continue
					var pos := center + Vector2i(dx, dy)
					if _is_valid_cell(pos) and not _astar.is_point_solid(pos) and not used.has(pos):
						result.append(pos)
						used[pos] = true
						if result.size() >= count:
							return result
			radius += 1
	return result


func set_cell_solid(pos: Vector2i, solid: bool) -> void:
	if _astar == null or not _is_valid_cell(pos):
		return
	_astar.set_point_solid(pos, solid)
	_astar.update()


func is_cell_solid(pos: Vector2i) -> bool:
	if _astar == null or not _is_valid_cell(pos):
		return true
	return _astar.is_point_solid(pos)


func _clamp_to_grid(pos: Vector2i) -> Vector2i:
	return Vector2i(
		clampi(pos.x, 0, _map_size - 1),
		clampi(pos.y, 0, _map_size - 1),
	)


func _is_valid_cell(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < _map_size and pos.y >= 0 and pos.y < _map_size
