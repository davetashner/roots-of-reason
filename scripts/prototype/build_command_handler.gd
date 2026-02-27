extends CommandHandler
## Handles the "build" command — assigns buildings as build targets for villagers.


func can_handle(cmd: String, target: Node, _selected: Array[Node], _world_pos: Vector2) -> bool:
	return cmd == "build" and target != null and target.has_method("apply_build_work")


func execute(cmd: String, target: Node, selected: Array[Node], _world_pos: Vector2) -> bool:
	if cmd != "build" or target == null or not target.has_method("apply_build_work"):
		return false
	for unit in selected:
		if unit.has_method("assign_build_target"):
			unit.assign_build_target(target)
	return true
