extends Node
## Spatial entity lookup — finds the closest targetable entity at a world position.
## Searches all registered entities (player units, enemy units, buildings, resources).

var _entities: Array[Node] = []
var _visibility_manager: Node = null


func register_entity(entity: Node) -> void:
	if entity not in _entities:
		_entities.append(entity)


func unregister_entity(entity: Node) -> void:
	_entities.erase(entity)


func set_visibility_manager(mgr: Node) -> void:
	_visibility_manager = mgr


## Returns the closest entity whose is_point_inside() contains world_pos, or null.
## Filters out non-player entities on tiles not visible to player 0.
func detect(world_pos: Vector2) -> Node:
	var closest: Node = null
	var closest_dist: float = INF
	for entity in _entities:
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
