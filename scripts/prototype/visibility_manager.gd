extends Node
## Per-player explored/visible tile tracking with periodic updates.
## Explored tiles persist permanently; visible tiles are recomputed each cycle.
## FOV results are cached per unit — only recomputed when a unit moves to a new
## grid cell or its LOS radius changes.

signal visibility_changed(player_id: int)

const LOSCalculator := preload("res://scripts/map/los_calculator.gd")

var _explored: Dictionary = {}  # player_id -> Dictionary(Vector2i -> true)
var _visible: Dictionary = {}  # player_id -> Dictionary(Vector2i -> true)
var _prev_visible: Dictionary = {}  # player_id -> Dictionary — for diff-based updates
var _blocks_los_fn: Callable
var _no_block_fn: Callable = func(_pos: Vector2i) -> bool: return false
var _map_width: int = 64
var _map_height: int = 64
var _update_timer: float = 0.0
var _update_interval: float = 0.2  # 200ms
var _dirty: Dictionary = {}  # player_id -> bool — true when visibility changed

# FOV cache: unit instance_id -> { grid_pos: Vector2i, los_radius: int, tiles: Dictionary }
var _fov_cache: Dictionary = {}


func setup(map_width: int, map_height: int, blocks_los_fn: Callable) -> void:
	_map_width = map_width
	_map_height = map_height
	_blocks_los_fn = blocks_los_fn


func update_visibility(player_id: int, units: Array, pinned_tiles: Array[Vector2i] = []) -> void:
	if not _explored.has(player_id):
		_explored[player_id] = {}

	# Save previous visible for diff
	_prev_visible[player_id] = _visible.get(player_id, {}).duplicate()

	# Clear visible — recompute fresh by merging cached FOV tiles
	var new_visible: Dictionary = {}

	# Track which cached unit IDs are still alive this frame
	var active_ids: Dictionary = {}

	for unit in units:
		if not is_instance_valid(unit):
			continue
		if not (unit is Node2D):
			continue

		# Get LOS radius from unit stats or default
		var los_radius: int = 6
		if unit.has_method("get_stat"):
			var stat_los: float = unit.get_stat("los")
			if stat_los > 0.0:
				los_radius = int(stat_los)
		elif unit.has_method("get_los"):
			los_radius = unit.get_los()
		elif "los" in unit:
			los_radius = int(unit.los)

		# Convert unit screen position to grid position.
		# For buildings with a footprint, use the center tile instead of the origin corner.
		var grid_pos: Vector2i
		var is_building: bool = "grid_pos" in unit and "footprint" in unit
		if is_building:
			var fp: Vector2i = unit.footprint
			grid_pos = Vector2i(unit.grid_pos.x + fp.x / 2, unit.grid_pos.y + fp.y / 2)
		else:
			grid_pos = _screen_to_grid(unit.global_position)

		var uid: int = unit.get_instance_id()
		active_ids[uid] = true

		# Check cache — reuse if unit hasn't moved and LOS is unchanged
		var cached: Dictionary = _fov_cache.get(uid, {})
		var tiles: Dictionary
		if cached.size() > 0 and cached.get("grid_pos") == grid_pos and cached.get("los_radius") == los_radius:
			tiles = cached["tiles"]
		else:
			# Buildings have unobstructed LOS (not blocked by terrain like forests)
			var block_fn: Callable = _no_block_fn if is_building else _blocks_los_fn
			tiles = (
				LOSCalculator
				. compute_visible_tiles(
					grid_pos,
					los_radius,
					_map_width,
					_map_height,
					block_fn,
				)
			)
			_fov_cache[uid] = {
				"grid_pos": grid_pos,
				"los_radius": los_radius,
				"tiles": tiles,
			}

		for tile: Vector2i in tiles:
			new_visible[tile] = true
			_explored[player_id][tile] = true

	# Merge pinned tiles (own entity positions) — always visible regardless of LOS
	for tile: Vector2i in pinned_tiles:
		new_visible[tile] = true
		_explored[player_id][tile] = true

	# Evict stale cache entries for units no longer in the list
	var stale_ids: Array = []
	for uid: int in _fov_cache:
		if not active_ids.has(uid):
			stale_ids.append(uid)
	for uid: int in stale_ids:
		_fov_cache.erase(uid)

	# Check if visibility actually changed before emitting signal
	var old_visible: Dictionary = _prev_visible.get(player_id, {})
	var changed := false
	if new_visible.size() != old_visible.size():
		changed = true
	else:
		for tile: Vector2i in new_visible:
			if not old_visible.has(tile):
				changed = true
				break

	_visible[player_id] = new_visible
	_dirty[player_id] = changed
	if changed:
		visibility_changed.emit(player_id)


func invalidate_fov_cache() -> void:
	## Call when the map changes (e.g. building placed/destroyed) to force
	## full FOV recomputation on next update.
	_fov_cache.clear()


func is_visible(player_id: int, tile: Vector2i) -> bool:
	var player_visible: Dictionary = _visible.get(player_id, {})
	return player_visible.has(tile)


func is_explored(player_id: int, tile: Vector2i) -> bool:
	var player_explored: Dictionary = _explored.get(player_id, {})
	return player_explored.has(tile)


func get_visible_tiles(player_id: int) -> Dictionary:
	return _visible.get(player_id, {})


func get_explored_tiles(player_id: int) -> Dictionary:
	return _explored.get(player_id, {})


func get_prev_visible_tiles(player_id: int) -> Dictionary:
	return _prev_visible.get(player_id, {})


func has_changes(player_id: int) -> bool:
	return _dirty.get(player_id, false)


func clear_dirty(player_id: int) -> void:
	_dirty[player_id] = false


func get_fov_cache_size() -> int:
	## Diagnostic: returns the number of cached FOV entries.
	return _fov_cache.size()


func _screen_to_grid(screen_pos: Vector2) -> Vector2i:
	# Use IsoUtils if available
	if Engine.has_singleton("IsoUtils"):
		return Vector2i(IsoUtils.screen_to_grid(screen_pos))
	if is_instance_valid(Engine.get_main_loop()):
		var root: Node = Engine.get_main_loop().root
		var iso: Node = root.get_node_or_null("IsoUtils")
		if iso != null and iso.has_method("screen_to_grid"):
			return Vector2i(iso.screen_to_grid(screen_pos))
	# Fallback: isometric conversion (128x64 tiles)
	var tile_w := 128.0
	var tile_h := 64.0
	var gx := screen_pos.x / tile_w + screen_pos.y / tile_h
	var gy := screen_pos.y / tile_h - screen_pos.x / tile_w
	return Vector2i(roundi(gx), roundi(gy))


func save_state() -> Dictionary:
	var data: Dictionary = {}
	for player_id: int in _explored:
		var tiles: Array = []
		for tile: Vector2i in _explored[player_id]:
			tiles.append("%d,%d" % [tile.x, tile.y])
		data[str(player_id)] = tiles
	return {"explored": data}


func load_state(state: Dictionary) -> void:
	_explored.clear()
	_visible.clear()
	_prev_visible.clear()
	_dirty.clear()
	_fov_cache.clear()

	var explored_data: Dictionary = state.get("explored", {})
	for player_id_str: String in explored_data:
		var player_id := int(player_id_str)
		_explored[player_id] = {}
		var tiles: Array = explored_data[player_id_str]
		for tile_str in tiles:
			var parts := str(tile_str).split(",")
			if parts.size() == 2:
				_explored[player_id][Vector2i(int(parts[0]), int(parts[1]))] = true
