extends Node
## Per-player explored/visible tile tracking with periodic updates.
## Explored tiles persist permanently; visible tiles are recomputed each cycle.

signal visibility_changed(player_id: int)

const LOSCalculator := preload("res://scripts/map/los_calculator.gd")

var _explored: Dictionary = {}  # player_id -> Dictionary(Vector2i -> true)
var _visible: Dictionary = {}  # player_id -> Dictionary(Vector2i -> true)
var _prev_visible: Dictionary = {}  # player_id -> Dictionary — for diff-based updates
var _blocks_los_fn: Callable
var _map_width: int = 64
var _map_height: int = 64
var _update_timer: float = 0.0
var _update_interval: float = 0.2  # 200ms


func setup(map_width: int, map_height: int, blocks_los_fn: Callable) -> void:
	_map_width = map_width
	_map_height = map_height
	_blocks_los_fn = blocks_los_fn


func update_visibility(player_id: int, units: Array) -> void:
	if not _explored.has(player_id):
		_explored[player_id] = {}

	# Save previous visible for diff
	_prev_visible[player_id] = _visible.get(player_id, {}).duplicate()

	# Clear visible — recompute fresh
	var new_visible: Dictionary = {}

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
		elif "los" in unit:
			los_radius = int(unit.los)

		# Convert unit screen position to grid position
		var grid_pos := _screen_to_grid(unit.global_position)

		var tiles := (
			LOSCalculator
			. compute_visible_tiles(
				grid_pos,
				los_radius,
				_map_width,
				_map_height,
				_blocks_los_fn,
			)
		)

		for tile: Vector2i in tiles:
			new_visible[tile] = true
			_explored[player_id][tile] = true

	_visible[player_id] = new_visible
	visibility_changed.emit(player_id)


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

	var explored_data: Dictionary = state.get("explored", {})
	for player_id_str: String in explored_data:
		var player_id := int(player_id_str)
		_explored[player_id] = {}
		var tiles: Array = explored_data[player_id_str]
		for tile_str in tiles:
			var parts := str(tile_str).split(",")
			if parts.size() == 2:
				_explored[player_id][Vector2i(int(parts[0]), int(parts[1]))] = true
