extends CommandHandler
## Handles the "garrison" command — moves units into a garrisonable building.


func can_handle(cmd: String, target: Node, _selected: Array[Node], _world_pos: Vector2) -> bool:
	return cmd == "garrison" and target != null and target.has_method("garrison_unit")


func execute(cmd: String, target: Node, selected: Array[Node], _world_pos: Vector2) -> bool:
	if cmd != "garrison" or target == null or not target.has_method("garrison_unit"):
		return false
	for unit in selected:
		if unit is Node2D:
			target.garrison_unit(unit)
	return true
