extends CommandHandler
## Handles the "gather" command — assigns resource nodes as gather targets.
## When multiple units gather the same resource, formation offsets spread them
## around the resource tile so they don't stack on top of each other.

var _pathfinder: Node = null


func setup(pathfinder: Node) -> void:
	_pathfinder = pathfinder


func can_handle(cmd: String, target: Node, _selected: Array[Node], _world_pos: Vector2) -> bool:
	return cmd == "gather" and target != null


func execute(cmd: String, target: Node, selected: Array[Node], _world_pos: Vector2) -> bool:
	if cmd != "gather" or target == null:
		return false
	var gatherers: Array[Node] = []
	for unit in selected:
		if unit.has_method("assign_gather_target"):
			gatherers.append(unit)
	if gatherers.is_empty():
		return true
	var offsets: Array[Vector2] = _compute_gather_offsets(target, gatherers.size())
	for i in gatherers.size():
		var offset_pos: Vector2 = offsets[i] if i < offsets.size() else Vector2.ZERO
		gatherers[i].assign_gather_target(target, offset_pos)
	return true


func _compute_gather_offsets(target: Node, count: int) -> Array[Vector2]:
	## Compute world-space offset positions around the resource for each gatherer.
	## Uses the pathfinding grid's formation targets to find valid passable cells.
	var nav_pos: Vector2 = _nav_position(target)
	if count <= 1 or _pathfinder == null or not _pathfinder.has_method("get_formation_targets"):
		var result: Array[Vector2] = []
		result.resize(count)
		result.fill(Vector2.ZERO)
		return result
	var center_grid := IsoUtils.snap_to_grid(nav_pos)
	var cells: Array[Vector2i] = _pathfinder.get_formation_targets(center_grid, count)
	var result: Array[Vector2] = []
	for cell in cells:
		var cell_world := IsoUtils.grid_to_screen(Vector2(cell))
		result.append(cell_world - nav_pos)
	# Pad with zero offsets if not enough valid cells
	while result.size() < count:
		result.append(Vector2.ZERO)
	return result


static func _nav_position(node: Node) -> Vector2:
	if "grid_position" in node and node.grid_position != Vector2i.ZERO:
		return IsoUtils.grid_to_screen(Vector2(node.grid_position))
	if node is Node2D:
		return (node as Node2D).global_position
	return Vector2.ZERO
