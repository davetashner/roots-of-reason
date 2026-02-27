extends CommandHandler
## Handles the "embark" command — moves units onto a transport and embarks them.


func can_handle(cmd: String, target: Node, _selected: Array[Node], _world_pos: Vector2) -> bool:
	return cmd == "embark" and target != null and target.has_method("embark_unit")


func execute(cmd: String, target: Node, selected: Array[Node], _world_pos: Vector2) -> bool:
	if cmd != "embark" or target == null or not target.has_method("embark_unit"):
		return false
	for unit in selected:
		if unit is Node2D:
			unit.move_to(target.global_position)
			target.embark_unit(unit)
	return true
