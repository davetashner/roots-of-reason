extends CommandHandler
## Handles the "gather" command — assigns resource nodes as gather targets.


func can_handle(cmd: String, target: Node, _selected: Array[Node], _world_pos: Vector2) -> bool:
	return cmd == "gather" and target != null


func execute(cmd: String, target: Node, selected: Array[Node], _world_pos: Vector2) -> bool:
	if cmd != "gather" or target == null:
		return false
	for unit in selected:
		if unit.has_method("assign_gather_target"):
			unit.assign_gather_target(target)
	return true
