extends Node
## Spatial entity lookup — finds the closest targetable entity at a world position.
## Searches all registered entities (player units, enemy units, buildings, resources).

var _entities: Array[Node] = []


func register_entity(entity: Node) -> void:
	if entity not in _entities:
		_entities.append(entity)


func unregister_entity(entity: Node) -> void:
	_entities.erase(entity)


## Returns the closest entity whose is_point_inside() contains world_pos, or null.
func detect(world_pos: Vector2) -> Node:
	var closest: Node = null
	var closest_dist: float = INF
	for entity in _entities:
		if not is_instance_valid(entity):
			continue
		if not entity.has_method("is_point_inside"):
			continue
		if entity.is_point_inside(world_pos):
			var dist: float = world_pos.distance_squared_to(entity.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = entity
	return closest
