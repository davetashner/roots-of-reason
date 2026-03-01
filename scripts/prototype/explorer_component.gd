extends RefCounted
## ExplorerComponent — auto-explore state machine that pathfinds units through
## unexplored territory then returns them to the town center when done.

enum ExploreState { NONE, EXPLORING, RETURNING_TO_TC }

const _RETARGET_INTERVAL: float = 1.0

var explore_state: ExploreState = ExploreState.NONE
var visibility_manager: Node = null

var _unit: Node2D = null
var _retarget_timer: float = 0.0
var _explore_target: Vector2i = Vector2i(-1, -1)


func _init(unit: Node2D = null) -> void:
	_unit = unit


func start_exploring() -> void:
	explore_state = ExploreState.EXPLORING
	_retarget_timer = 0.0
	_explore_target = Vector2i(-1, -1)


func cancel() -> void:
	explore_state = ExploreState.NONE
	_retarget_timer = 0.0
	_explore_target = Vector2i(-1, -1)


func tick(game_delta: float) -> void:
	if explore_state == ExploreState.NONE:
		return
	# Pause exploring while in combat (e.g. auto-retaliation)
	if _unit._combatant != null and _unit._combatant.combat_state != 0:
		return
	if explore_state == ExploreState.EXPLORING:
		_tick_exploring(game_delta)
	elif explore_state == ExploreState.RETURNING_TO_TC:
		_tick_returning()


func _tick_exploring(game_delta: float) -> void:
	if _unit._moving:
		return
	_retarget_timer -= game_delta
	if _retarget_timer > 0.0:
		return
	_retarget_timer = _RETARGET_INTERVAL
	var target := _pick_next_explore_target()
	if target == Vector2i(-1, -1):
		# Map fully explored — head home
		explore_state = ExploreState.RETURNING_TO_TC
		_navigate_to_town_center()
		return
	_explore_target = target
	var world_pos := IsoUtils.grid_to_screen(Vector2(target))
	if _unit._pathfinder != null and _unit._pathfinder.has_method("find_path_world"):
		var path: Array[Vector2] = _unit._pathfinder.find_path_world(_unit.position, world_pos)
		if path.size() > 0:
			_unit.follow_path(path)
			return
	# Fallback direct move
	_unit.move_to(world_pos)


func _tick_returning() -> void:
	if _unit._moving:
		return
	# Arrived at TC (or close enough)
	explore_state = ExploreState.NONE
	_explore_target = Vector2i(-1, -1)


func _pick_next_explore_target() -> Vector2i:
	if visibility_manager == null:
		return Vector2i(-1, -1)
	var explored: Dictionary = visibility_manager.get_explored_tiles(_unit.owner_id)
	var map_w: int = visibility_manager._map_width
	var map_h: int = visibility_manager._map_height
	var unit_grid := Vector2i(IsoUtils.screen_to_grid(_unit.position))
	var best := Vector2i(-1, -1)
	var best_dist := 999999
	for y in map_h:
		for x in map_w:
			var cell := Vector2i(x, y)
			if explored.has(cell):
				continue
			# Must be adjacent to at least one explored tile (reachable frontier)
			if not _is_frontier(cell, explored):
				continue
			# Skip solid cells
			if _unit._pathfinder != null and _unit._pathfinder.has_method("is_cell_solid"):
				if _unit._pathfinder.is_cell_solid(cell):
					continue
			var dist: int = absi(cell.x - unit_grid.x) + absi(cell.y - unit_grid.y)
			if dist < best_dist:
				best_dist = dist
				best = cell
	return best


func _is_frontier(cell: Vector2i, explored: Dictionary) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			if explored.has(cell + Vector2i(dx, dy)):
				return true
	return false


func _navigate_to_town_center() -> void:
	var tc := _find_owner_town_center()
	if tc == null:
		explore_state = ExploreState.NONE
		return
	if _unit._pathfinder != null and _unit._pathfinder.has_method("find_path_world"):
		var path: Array[Vector2] = _unit._pathfinder.find_path_world(_unit.position, tc.global_position)
		if path.size() > 0:
			_unit.follow_path(path)
			return
	_unit.move_to(tc.global_position)


func _find_owner_town_center() -> Node2D:
	if _unit._scene_root == null:
		return null
	for child in _unit._scene_root.get_children():
		if not (child is Node2D):
			continue
		if "building_name" in child and child.building_name == "town_center":
			if "owner_id" in child and child.owner_id == _unit.owner_id:
				return child
	return null


func save_state() -> Dictionary:
	var state: Dictionary = {}
	if explore_state != ExploreState.NONE:
		state["explore_state"] = int(explore_state)
		state["explore_target_x"] = _explore_target.x
		state["explore_target_y"] = _explore_target.y
	return state


func load_state(data: Dictionary) -> void:
	explore_state = int(data.get("explore_state", 0)) as ExploreState
	_explore_target = Vector2i(
		int(data.get("explore_target_x", -1)),
		int(data.get("explore_target_y", -1)),
	)
