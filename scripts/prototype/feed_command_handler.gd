extends CommandHandler
## Handles the "feed" command — assigns wild fauna as feed targets for villagers.


func can_handle(cmd: String, target: Node, _selected: Array[Node], _world_pos: Vector2) -> bool:
	return cmd == "feed" and target != null


func execute(cmd: String, target: Node, selected: Array[Node], _world_pos: Vector2) -> bool:
	if cmd != "feed" or target == null:
		return false
	for unit in selected:
		if unit.has_method("assign_feed_target"):
			unit.assign_feed_target(target)
	return true
