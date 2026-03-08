extends CommandHandler
## Handles manual resource drop-off — when a carrying villager is directed
## to a valid drop-off building, deposit resources instead of garrisoning.


func can_handle(cmd: String, target: Node, selected: Array[Node], _world_pos: Vector2) -> bool:
	if cmd != "garrison" or target == null:
		return false
	if not ("is_drop_off" in target and target.is_drop_off):
		return false
	# Only handle if at least one selected unit is carrying resources
	for unit in selected:
		if "_carried_amount" in unit and int(unit._carried_amount) > 0:
			if "drop_off_types" in target:
				var types: Array = target.drop_off_types
				if "_gather_type" in unit and types.has(str(unit._gather_type)):
					return true
	return false


func execute(cmd: String, target: Node, selected: Array[Node], _world_pos: Vector2) -> bool:
	if cmd != "garrison" or target == null:
		return false
	for unit in selected:
		if not (unit is Node2D and unit.has_method("send_to_drop_off")):
			continue
		if "_carried_amount" in unit and int(unit._carried_amount) > 0:
			if "drop_off_types" in target:
				var types: Array = target.drop_off_types
				if "_gather_type" in unit and types.has(str(unit._gather_type)):
					unit.send_to_drop_off(target)
					continue
		# Non-carrying units garrison normally
		if unit.has_method("move_to") and target.has_method("garrison_unit"):
			unit.move_to(target.global_position)
			target.garrison_unit(unit)
	return true
