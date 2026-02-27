extends Node
## Spatial entity lookup — finds the closest targetable entity at a world position.
## Backed by a grid-based spatial index for O(1)-amortized lookups instead of
## O(N) scene-tree scans.

const SpatialIndexScript := preload("res://scripts/prototype/spatial_index.gd")

## Detection radius used by detect() — entities within this many pixels of the
## query point are candidates.  Units use is_point_inside() which is ~18 px,
## so a generous radius ensures we never miss a valid click target.
const DETECT_RADIUS: float = 128.0

var _spatial_index: RefCounted = null
var _visibility_manager: Node = null

## Backward-compat: scene_save_handler reads _entities directly.
var _entities: Array[Node]:
	get:
		if _spatial_index != null:
			return _spatial_index._entities
		return []
	set(value):
		if _spatial_index != null:
			_spatial_index._entities = value


func _ready() -> void:
	_spatial_index = SpatialIndexScript.new()


func _process(_delta: float) -> void:
	if _spatial_index != null:
		_spatial_index.tick_positions()


func register_entity(entity: Node) -> void:
	if _spatial_index == null:
		_spatial_index = SpatialIndexScript.new()
	_spatial_index.register_entity(entity)


func unregister_entity(entity: Node) -> void:
	if _spatial_index != null:
		_spatial_index.unregister_entity(entity)


func update_position(entity: Node) -> void:
	if _spatial_index != null:
		_spatial_index.update_position(entity)


func clear() -> void:
	if _spatial_index != null:
		_spatial_index.clear()


func set_visibility_manager(mgr: Node) -> void:
	_visibility_manager = mgr


## Returns the spatial index for advanced queries (get_nearest, etc.).
func get_spatial_index() -> RefCounted:
	return _spatial_index


## Returns the closest entity whose is_point_inside() contains world_pos, or null.
## Filters out non-player entities on tiles not visible to player 0.
func detect(world_pos: Vector2) -> Node:
	if _spatial_index == null:
		return null
	var candidates: Array[Node] = _spatial_index.get_entities_in_radius(world_pos, DETECT_RADIUS)
	var closest: Node = null
	var closest_dist: float = INF
	for entity: Node in candidates:
		if not is_instance_valid(entity):
			continue
		if not entity.has_method("is_point_inside"):
			continue
		if entity.is_point_inside(world_pos):
			# Filter out non-player entities not visible to player 0
			if _visibility_manager != null and "owner_id" in entity and entity.owner_id != 0:
				var grid_pos := _screen_to_grid(entity.global_position)
				if not _visibility_manager.is_visible(0, grid_pos):
					continue
			var dist: float = world_pos.distance_squared_to(entity.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = entity
	return closest


func _screen_to_grid(screen_pos: Vector2) -> Vector2i:
	var tile_w := 128.0
	var tile_h := 64.0
	var gx := screen_pos.x / tile_w + screen_pos.y / tile_h
	var gy := screen_pos.y / tile_h - screen_pos.x / tile_w
	return Vector2i(roundi(gx), roundi(gy))
