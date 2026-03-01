extends RefCounted
## GathererComponent — handles resource gathering, drop-off, and replacement logic.
## Extracted from prototype_unit.gd to reduce coordinator size.

enum GatherState { NONE, MOVING_TO_RESOURCE, GATHERING, MOVING_TO_DROP_OFF, DEPOSITING, WAITING_FOR_DROP_OFF }

var gather_target: Node2D = null
var gather_state: GatherState = GatherState.NONE
var gather_type: String = ""
var carried_amount: int = 0
var carry_capacity: int = 10
var gather_rate_multiplier: float = 1.0
var gather_rates: Dictionary = {}
var gather_reach: float = 80.0
var drop_off_reach: float = 80.0
var gather_accumulator: float = 0.0
var drop_off_target: Node2D = null
var pending_gather_target_name: String = ""

var _unit: Node2D = null


func _init(unit: Node2D = null) -> void:
	_unit = unit


## Return the pathfinding position for a resource node. Uses grid_position
## (the logical tile) rather than global_position (which includes visual
## cluster offsets that may map to adjacent impassable tiles like water).
static func _nav_position(node: Node2D) -> Vector2:
	if "grid_position" in node and node.grid_position != Vector2i.ZERO:
		return IsoUtils.grid_to_screen(Vector2(node.grid_position))
	return node.global_position


func load_config(unit_cfg: Dictionary, gather_cfg: Dictionary) -> void:
	if not unit_cfg.is_empty():
		carry_capacity = int(unit_cfg.get("carry_capacity", carry_capacity))
		var rates: Variant = unit_cfg.get("gather_rates", {})
		if rates is Dictionary:
			gather_rates = rates
	if not gather_cfg.is_empty():
		gather_reach = float(gather_cfg.get("gather_reach", gather_reach))
		drop_off_reach = float(gather_cfg.get("drop_off_reach", drop_off_reach))


func tick(game_delta: float) -> void:
	match gather_state:
		GatherState.NONE:
			return
		GatherState.MOVING_TO_RESOURCE:
			_tick_moving_to_resource()
		GatherState.GATHERING:
			_tick_gathering(game_delta)
		GatherState.MOVING_TO_DROP_OFF:
			_tick_moving_to_drop_off()
		GatherState.DEPOSITING:
			_tick_depositing()
		GatherState.WAITING_FOR_DROP_OFF:
			_tick_waiting_for_drop_off()


func _tick_moving_to_resource() -> void:
	if gather_target == null or not is_instance_valid(gather_target):
		cancel()
		return
	if not _is_target_harvestable(gather_target):
		_try_find_replacement_resource()
		return
	var dist: float = _unit.position.distance_to(_nav_position(gather_target))
	if dist <= gather_reach and not _unit._moving:
		gather_state = GatherState.GATHERING
		gather_accumulator = 0.0


func _tick_gathering(game_delta: float) -> void:
	if gather_target == null or not is_instance_valid(gather_target):
		if carried_amount > 0:
			_start_drop_off_trip()
		else:
			_try_find_replacement_resource()
		return
	if not _is_target_harvestable(gather_target):
		if carried_amount > 0:
			_start_drop_off_trip()
		else:
			_try_find_replacement_resource()
		return
	var rate: float = float(gather_rates.get(gather_type, 0.0))
	gather_accumulator += rate * gather_rate_multiplier * game_delta
	if gather_accumulator >= 1.0:
		var whole := int(gather_accumulator)
		var room := carry_capacity - carried_amount
		var to_extract := mini(whole, room)
		var gathered: int = gather_target.apply_gather_work(float(to_extract))
		carried_amount += gathered
		gather_accumulator -= float(to_extract)
	if carried_amount >= carry_capacity:
		_start_drop_off_trip()


func _tick_moving_to_drop_off() -> void:
	if drop_off_target == null or not is_instance_valid(drop_off_target):
		drop_off_target = _find_nearest_drop_off(gather_type)
		if drop_off_target == null:
			gather_state = GatherState.WAITING_FOR_DROP_OFF
			return
		_unit.move_to(drop_off_target.global_position)
		return
	var dist: float = _unit.position.distance_to(drop_off_target.global_position)
	if dist <= drop_off_reach and not _unit._moving:
		gather_state = GatherState.DEPOSITING


func _tick_depositing() -> void:
	var res_enum: Variant = _resource_type_to_enum(gather_type)
	if res_enum != null:
		ResourceManager.add_resource(_unit.owner_id, res_enum, carried_amount)
	carried_amount = 0
	drop_off_target = null
	# Return to resource or find replacement
	if gather_target != null and is_instance_valid(gather_target) and _is_target_harvestable(gather_target):
		gather_state = GatherState.MOVING_TO_RESOURCE
		_unit.move_to(_nav_position(gather_target))
	else:
		_try_find_replacement_resource()


func _start_drop_off_trip() -> void:
	drop_off_target = _find_nearest_drop_off(gather_type)
	if drop_off_target == null:
		gather_state = GatherState.WAITING_FOR_DROP_OFF
		return
	gather_state = GatherState.MOVING_TO_DROP_OFF
	_unit.move_to(drop_off_target.global_position)


func _tick_waiting_for_drop_off() -> void:
	drop_off_target = _find_nearest_drop_off(gather_type)
	if drop_off_target != null:
		gather_state = GatherState.MOVING_TO_DROP_OFF
		_unit.move_to(drop_off_target.global_position)


func _find_nearest_drop_off(res_type: String) -> Node2D:
	var root: Node = _unit._scene_root if _unit._scene_root != null else _unit.get_parent()
	if root == null:
		return null
	var best: Node2D = null
	var best_dist := INF
	for child in root.get_children():
		if not child.has_method("save_state"):
			continue
		if "is_drop_off" not in child or not child.is_drop_off:
			continue
		if "drop_off_types" in child:
			var types: Array = child.drop_off_types
			if not types.has(res_type):
				continue
		var dist: float = _unit.position.distance_to(child.global_position)
		if dist < best_dist:
			best_dist = dist
			best = child
	return best


func _try_find_replacement_resource() -> void:
	var root: Node = _unit._scene_root if _unit._scene_root != null else _unit.get_parent()
	if root == null:
		cancel()
		return
	var best: Node2D = null
	var best_dist := INF
	for child in root.get_children():
		if child == gather_target or "entity_category" not in child:
			continue
		if child.entity_category != "resource_node":
			continue
		if "resource_type" not in child or child.resource_type != gather_type:
			continue
		if not _is_target_harvestable(child):
			continue
		var dist: float = _unit.position.distance_to(_nav_position(child))
		if dist < best_dist:
			best_dist = dist
			best = child
	if best != null:
		gather_target = best
		gather_state = GatherState.MOVING_TO_RESOURCE
		gather_accumulator = 0.0
		_unit.move_to(_nav_position(best))
	elif carried_amount > 0:
		_start_drop_off_trip()
	else:
		cancel()


static func _is_target_harvestable(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.has_method("is_harvestable"):
		return target.is_harvestable()
	if "current_yield" in target:
		return target.current_yield > 0
	return false


func cancel() -> void:
	gather_target = null
	gather_state = GatherState.NONE
	gather_type = ""
	gather_accumulator = 0.0
	drop_off_target = null


func assign_target(node: Node2D) -> void:
	gather_target = node
	gather_type = node.resource_type if "resource_type" in node else ""
	gather_state = GatherState.MOVING_TO_RESOURCE
	gather_accumulator = 0.0
	carried_amount = 0
	drop_off_target = null
	_unit.move_to(_nav_position(node))


func resolve_target(scene_root: Node) -> void:
	if pending_gather_target_name == "":
		return
	var target := scene_root.get_node_or_null(pending_gather_target_name)
	if target is Node2D:
		gather_target = target
	pending_gather_target_name = ""


static func _resource_type_to_enum(res_type: String) -> Variant:
	match res_type:
		"food":
			return ResourceManager.ResourceType.FOOD
		"wood":
			return ResourceManager.ResourceType.WOOD
		"stone":
			return ResourceManager.ResourceType.STONE
		"gold":
			return ResourceManager.ResourceType.GOLD
		_:
			return null


func save_state() -> Dictionary:
	var state := {
		"gather_state": gather_state,
		"gather_type": gather_type,
		"carried_amount": carried_amount,
		"gather_accumulator": gather_accumulator,
		"gather_rate_multiplier": gather_rate_multiplier,
	}
	if gather_target != null and is_instance_valid(gather_target):
		state["gather_target_name"] = str(gather_target.name)
	return state


func load_state(data: Dictionary) -> void:
	pending_gather_target_name = str(data.get("gather_target_name", ""))
	gather_state = int(data.get("gather_state", GatherState.NONE)) as GatherState
	gather_type = str(data.get("gather_type", ""))
	carried_amount = int(data.get("carried_amount", 0))
	gather_accumulator = float(data.get("gather_accumulator", 0.0))
	gather_rate_multiplier = float(data.get("gather_rate_multiplier", 1.0))
