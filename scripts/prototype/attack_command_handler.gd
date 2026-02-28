extends CommandHandler
## Handles the "attack" command — assigns a hostile target for selected units to attack.


func can_handle(cmd: String, target: Node, _selected: Array[Node], _world_pos: Vector2) -> bool:
	return cmd == "attack" and target != null


func execute(cmd: String, target: Node, selected: Array[Node], _world_pos: Vector2) -> bool:
	if cmd != "attack" or target == null:
		return false
	for unit in selected:
		if unit.has_method("assign_attack_target"):
			unit.assign_attack_target(target)
	return true
