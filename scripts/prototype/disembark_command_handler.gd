extends CommandHandler
## Handles disembark — transports with passengers right-clicking ground unload units.


static func has_transport_with_passengers(units: Array[Node]) -> bool:
	for unit in units:
		if unit.has_method("get_embarked_count") and unit.get_embarked_count() > 0:
			return true
	return false


func can_handle(_cmd: String, target: Node, selected: Array[Node], _world_pos: Vector2) -> bool:
	return target == null and has_transport_with_passengers(selected)


func execute(_cmd: String, target: Node, selected: Array[Node], world_pos: Vector2) -> bool:
	if target != null or not has_transport_with_passengers(selected):
		return false
	for unit in selected:
		if unit.has_method("disembark_all") and unit.get_embarked_count() > 0:
			unit.disembark_all(world_pos)
		elif unit.has_method("move_to"):
			unit.move_to(world_pos)
	return true
