extends RefCounted
## Grid-based spatial index for O(1) entity lookups.
## Replaces O(N) scene-tree scanning with a hash-grid that buckets entities
## by world position.  Cell size is configurable (default 128 px = 2 tiles).

const DEFAULT_CELL_SIZE: float = 128.0

var _cell_size: float = DEFAULT_CELL_SIZE
var _inv_cell_size: float = 1.0 / DEFAULT_CELL_SIZE

# Grid storage: Dictionary[Vector2i, Array[Node]]
var _grid: Dictionary = {}

# Reverse lookup: entity -> cell key, for fast moves / removal.
var _entity_cells: Dictionary = {}

# Flat list kept for backward compat (scene_save_handler reads _entities).
var _entities: Array[Node] = []


func _init(cell_size: float = DEFAULT_CELL_SIZE) -> void:
	_cell_size = cell_size
	_inv_cell_size = 1.0 / cell_size


# ── Registration ──────────────────────────────────────────────────────


func register_entity(entity: Node) -> void:
	if entity in _entity_cells:
		return
	_entities.append(entity)
	var cell := _world_to_cell(entity.global_position)
	_entity_cells[entity] = cell
	if not _grid.has(cell):
		_grid[cell] = []
	_grid[cell].append(entity)


func unregister_entity(entity: Node) -> void:
	if entity not in _entity_cells:
		return
	var cell: Vector2i = _entity_cells[entity]
	if _grid.has(cell):
		_grid[cell].erase(entity)
		if _grid[cell].is_empty():
			_grid.erase(cell)
	_entity_cells.erase(entity)
	_entities.erase(entity)


func update_position(entity: Node) -> void:
	if entity not in _entity_cells:
		return
	var old_cell: Vector2i = _entity_cells[entity]
	var new_cell := _world_to_cell(entity.global_position)
	if old_cell == new_cell:
		return
	# Move between cells
	if _grid.has(old_cell):
		_grid[old_cell].erase(entity)
		if _grid[old_cell].is_empty():
			_grid.erase(old_cell)
	_entity_cells[entity] = new_cell
	if not _grid.has(new_cell):
		_grid[new_cell] = []
	_grid[new_cell].append(entity)


func clear() -> void:
	_grid.clear()
	_entity_cells.clear()
	_entities.clear()


## Batch-update all entity positions.  Cheap when most entities stay in
## the same cell — only a Vector2i comparison per entity.
func tick_positions() -> void:
	for entity in _entities:
		if not is_instance_valid(entity):
			continue
		var old_cell: Vector2i = _entity_cells.get(entity, Vector2i.MAX)
		var new_cell := _world_to_cell(entity.global_position)
		if old_cell == new_cell:
			continue
		# Move between cells
		if _grid.has(old_cell):
			_grid[old_cell].erase(entity)
			if _grid[old_cell].is_empty():
				_grid.erase(old_cell)
		_entity_cells[entity] = new_cell
		if not _grid.has(new_cell):
			_grid[new_cell] = []
		_grid[new_cell].append(entity)


# ── Queries ───────────────────────────────────────────────────────────


## Returns all entities whose cell is within `radius` world-pixels of `origin`.
## An optional `filter` dictionary narrows results (see _matches_filter).
func get_entities_in_radius(origin: Vector2, radius: float, filter: Dictionary = {}) -> Array[Node]:
	var results: Array[Node] = []
	var radius_sq := radius * radius
	var cell_radius := ceili(radius * _inv_cell_size)
	var center_cell := _world_to_cell(origin)
	for dx in range(-cell_radius, cell_radius + 1):
		for dy in range(-cell_radius, cell_radius + 1):
			var cell := Vector2i(center_cell.x + dx, center_cell.y + dy)
			if not _grid.has(cell):
				continue
			for entity in _grid[cell]:
				if not is_instance_valid(entity):
					continue
				if origin.distance_squared_to(entity.global_position) > radius_sq:
					continue
				if not filter.is_empty() and not _matches_filter(entity, filter):
					continue
				results.append(entity)
	return results


## Returns the closest entity within `radius` that passes `filter`, or null.
func get_nearest(origin: Vector2, radius: float, filter: Dictionary = {}) -> Node:
	var best: Node = null
	var best_dist_sq := INF
	var radius_sq := radius * radius
	var cell_radius := ceili(radius * _inv_cell_size)
	var center_cell := _world_to_cell(origin)
	for dx in range(-cell_radius, cell_radius + 1):
		for dy in range(-cell_radius, cell_radius + 1):
			var cell := Vector2i(center_cell.x + dx, center_cell.y + dy)
			if not _grid.has(cell):
				continue
			for entity in _grid[cell]:
				if not is_instance_valid(entity):
					continue
				var dist_sq := origin.distance_squared_to(entity.global_position)
				if dist_sq > radius_sq or dist_sq >= best_dist_sq:
					continue
				if not filter.is_empty() and not _matches_filter(entity, filter):
					continue
				best_dist_sq = dist_sq
				best = entity
	return best


## Returns all registered entities matching `filter` (no radius constraint).
func get_all_matching(filter: Dictionary = {}) -> Array[Node]:
	if filter.is_empty():
		return _entities.duplicate()
	var results: Array[Node] = []
	for entity in _entities:
		if not is_instance_valid(entity):
			continue
		if _matches_filter(entity, filter):
			results.append(entity)
	return results


# ── Filter logic ──────────────────────────────────────────────────────
# Supported keys:
#   owner_id       : int  — entity.owner_id must equal this
#   hostile_to     : Node — CombatResolver.is_hostile(hostile_to, entity)
#   entity_category: String
#   unit_category  : String
#   unit_type      : String
#   building_name  : String — entity.building_name must equal this
#   is_drop_off    : bool  — entity.is_drop_off must be true
#   resource_type  : String — entity.resource_type must equal this
#   alive          : bool  — if true, entity.hp must be > 0
#   exclude        : Node  — skip this specific entity
#   predicate      : Callable — arbitrary extra check


func _matches_filter(entity: Node, filter: Dictionary) -> bool:
	if filter.has("exclude") and entity == filter["exclude"]:
		return false
	if not _matches_identity(entity, filter):
		return false
	if not _matches_category(entity, filter):
		return false
	if not _matches_resource(entity, filter):
		return false
	return _matches_state(entity, filter)


func _matches_state(entity: Node, filter: Dictionary) -> bool:
	if filter.has("alive") and filter["alive"]:
		if "hp" in entity and entity.hp <= 0:
			return false
	if filter.has("predicate"):
		var pred: Callable = filter["predicate"]
		if not pred.call(entity):
			return false
	return true


func _matches_identity(entity: Node, filter: Dictionary) -> bool:
	if filter.has("owner_id"):
		if "owner_id" not in entity or entity.owner_id != filter["owner_id"]:
			return false
	if filter.has("hostile_to"):
		var source: Node = filter["hostile_to"]
		if not CombatResolver.is_hostile(source, entity):
			return false
	return true


func _matches_category(entity: Node, filter: Dictionary) -> bool:
	if filter.has("entity_category"):
		if "entity_category" not in entity or entity.entity_category != filter["entity_category"]:
			return false
	if filter.has("unit_category"):
		if "unit_category" not in entity or entity.unit_category != filter["unit_category"]:
			return false
	if filter.has("unit_type"):
		if "unit_type" not in entity or entity.unit_type != filter["unit_type"]:
			return false
	if filter.has("building_name"):
		if "building_name" not in entity or entity.building_name != filter["building_name"]:
			return false
	return true


func _matches_resource(entity: Node, filter: Dictionary) -> bool:
	if filter.has("is_drop_off"):
		if "is_drop_off" not in entity or not entity.is_drop_off:
			return false
		if filter.has("resource_type") and "drop_off_types" in entity:
			var types: Array = entity.drop_off_types
			if not types.has(filter["resource_type"]):
				return false
	if filter.has("resource_type") and not filter.has("is_drop_off"):
		if "resource_type" not in entity or entity.resource_type != filter["resource_type"]:
			return false
	return true


# ── Internals ─────────────────────────────────────────────────────────


func _world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x * _inv_cell_size), floori(pos.y * _inv_cell_size))
