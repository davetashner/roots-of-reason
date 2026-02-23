extends Node2D
## Prototype unit — colored circle with direction indicator, click-to-select,
## right-click-to-move. Villagers can build construction sites and gather resources.

enum GatherState { NONE, MOVING_TO_RESOURCE, GATHERING, MOVING_TO_DROP_OFF, DEPOSITING }

const RADIUS: float = 12.0
const MOVE_SPEED: float = 150.0
const SELECTION_RING_RADIUS: float = 16.0

@export var unit_color: Color = Color(0.2, 0.4, 0.9)
@export var owner_id: int = 0
@export var unit_type: String = "land"
@export var entity_category: String = ""

var selected: bool = false
var _target_pos: Vector2 = Vector2.ZERO
var _moving: bool = false
var _path: Array[Vector2] = []
var _path_index: int = 0
var _facing: Vector2 = Vector2.RIGHT

var _build_target: Node2D = null
var _build_speed: float = 1.0
var _build_reach: float = 80.0
var _pending_build_target_name: String = ""

var _gather_target: Node2D = null
var _gather_state: GatherState = GatherState.NONE
var _gather_type: String = ""
var _carried_amount: int = 0
var _carry_capacity: int = 10
var _gather_rates: Dictionary = {}
var _gather_reach: float = 80.0
var _drop_off_reach: float = 80.0
var _gather_accumulator: float = 0.0
var _drop_off_target: Node2D = null
var _scene_root: Node = null
var _pending_gather_target_name: String = ""


func _ready() -> void:
	_target_pos = position
	_load_build_config()
	_load_gather_config()


func _load_build_config() -> void:
	# Load build_speed from unit stats
	var unit_cfg: Dictionary = {}
	if Engine.has_singleton("DataLoader"):
		unit_cfg = DataLoader.get_unit_stats("villager")
	elif is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_unit_stats"):
			unit_cfg = dl.get_unit_stats("villager")
	if not unit_cfg.is_empty():
		_build_speed = float(unit_cfg.get("build_speed", _build_speed))
	# Load build_reach from construction settings
	var con_cfg: Dictionary = {}
	if Engine.has_singleton("DataLoader"):
		con_cfg = DataLoader.get_settings("construction")
	elif is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_settings"):
			con_cfg = dl.get_settings("construction")
	if not con_cfg.is_empty():
		_build_reach = float(con_cfg.get("build_reach", _build_reach))


func _load_gather_config() -> void:
	var unit_cfg: Dictionary = {}
	if Engine.has_singleton("DataLoader"):
		unit_cfg = DataLoader.get_unit_stats("villager")
	elif is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_unit_stats"):
			unit_cfg = dl.get_unit_stats("villager")
	if not unit_cfg.is_empty():
		_carry_capacity = int(unit_cfg.get("carry_capacity", _carry_capacity))
		var rates: Variant = unit_cfg.get("gather_rates", {})
		if rates is Dictionary:
			_gather_rates = rates
	var gather_cfg: Dictionary = {}
	if Engine.has_singleton("DataLoader"):
		gather_cfg = DataLoader.get_settings("gathering")
	elif is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_settings"):
			gather_cfg = dl.get_settings("gathering")
	if not gather_cfg.is_empty():
		_gather_reach = float(gather_cfg.get("gather_reach", _gather_reach))
		_drop_off_reach = float(gather_cfg.get("drop_off_reach", _drop_off_reach))


func _process(delta: float) -> void:
	var game_delta := GameManager.get_game_delta(delta)
	if game_delta == 0.0:
		return
	if _moving:
		var dist := position.distance_to(_target_pos)
		if dist < 2.0:
			position = _target_pos
			# Advance to next waypoint if following a path
			if _path_index < _path.size() - 1:
				_path_index += 1
				_target_pos = _path[_path_index]
			else:
				_moving = false
				_path.clear()
				_path_index = 0
		else:
			var direction := (_target_pos - position).normalized()
			_facing = direction
			position = position.move_toward(_target_pos, MOVE_SPEED * game_delta)
		queue_redraw()
	_tick_build(game_delta)
	_tick_gather(game_delta)


func _tick_build(game_delta: float) -> void:
	if _build_target == null:
		return
	if not is_instance_valid(_build_target):
		_build_target = null
		return
	if not _build_target.under_construction:
		_build_target = null
		return
	var dist: float = position.distance_to(_build_target.global_position)
	if dist > _build_reach:
		return
	# Stop moving — we're in range
	_moving = false
	_path.clear()
	_path_index = 0
	# Apply build work: build_speed / build_time per second
	var build_time: float = _build_target._build_time
	var work: float = (_build_speed / build_time) * game_delta
	_build_target.apply_build_work(work)
	# Check if construction completed
	if not _build_target.under_construction:
		_build_target = null


func _tick_gather(game_delta: float) -> void:
	match _gather_state:
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


func _tick_moving_to_resource() -> void:
	if _gather_target == null or not is_instance_valid(_gather_target):
		_cancel_gather()
		return
	if _gather_target.current_yield <= 0:
		_try_find_replacement_resource()
		return
	var dist: float = position.distance_to(_gather_target.global_position)
	if dist <= _gather_reach and not _moving:
		_gather_state = GatherState.GATHERING
		_gather_accumulator = 0.0


func _tick_gathering(game_delta: float) -> void:
	if _gather_target == null or not is_instance_valid(_gather_target):
		if _carried_amount > 0:
			_start_drop_off_trip()
		else:
			_try_find_replacement_resource()
		return
	if _gather_target.current_yield <= 0:
		if _carried_amount > 0:
			_start_drop_off_trip()
		else:
			_try_find_replacement_resource()
		return
	var rate: float = float(_gather_rates.get(_gather_type, 0.0))
	_gather_accumulator += rate * game_delta
	if _gather_accumulator >= 1.0:
		var whole := int(_gather_accumulator)
		var room := _carry_capacity - _carried_amount
		var to_extract := mini(whole, room)
		var gathered: int = _gather_target.apply_gather_work(float(to_extract))
		_carried_amount += gathered
		_gather_accumulator -= float(to_extract)
	if _carried_amount >= _carry_capacity:
		_start_drop_off_trip()


func _tick_moving_to_drop_off() -> void:
	if _drop_off_target == null or not is_instance_valid(_drop_off_target):
		_drop_off_target = _find_nearest_drop_off(_gather_type)
		if _drop_off_target == null:
			_cancel_gather()
			return
		move_to(_drop_off_target.global_position)
		return
	var dist: float = position.distance_to(_drop_off_target.global_position)
	if dist <= _drop_off_reach and not _moving:
		_gather_state = GatherState.DEPOSITING


func _tick_depositing() -> void:
	var res_enum: Variant = _resource_type_to_enum(_gather_type)
	if res_enum != null:
		ResourceManager.add_resource(owner_id, res_enum, _carried_amount)
	_carried_amount = 0
	_drop_off_target = null
	# Return to resource or find replacement
	if _gather_target != null and is_instance_valid(_gather_target) and _gather_target.current_yield > 0:
		_gather_state = GatherState.MOVING_TO_RESOURCE
		move_to(_gather_target.global_position)
	else:
		_try_find_replacement_resource()


func _start_drop_off_trip() -> void:
	_drop_off_target = _find_nearest_drop_off(_gather_type)
	if _drop_off_target == null:
		_cancel_gather()
		return
	_gather_state = GatherState.MOVING_TO_DROP_OFF
	move_to(_drop_off_target.global_position)


func _find_nearest_drop_off(res_type: String) -> Node2D:
	var root := _scene_root if _scene_root != null else get_parent()
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
		var dist: float = position.distance_to(child.global_position)
		if dist < best_dist:
			best_dist = dist
			best = child
	return best


func _try_find_replacement_resource() -> void:
	var root := _scene_root if _scene_root != null else get_parent()
	if root == null:
		_cancel_gather()
		return
	var best: Node2D = null
	var best_dist := INF
	for child in root.get_children():
		if child == _gather_target:
			continue
		if "entity_category" not in child:
			continue
		if child.entity_category != "resource_node":
			continue
		if "resource_type" not in child or child.resource_type != _gather_type:
			continue
		if "current_yield" in child and child.current_yield <= 0:
			continue
		var dist: float = position.distance_to(child.global_position)
		if dist < best_dist:
			best_dist = dist
			best = child
	if best != null:
		_gather_target = best
		_gather_state = GatherState.MOVING_TO_RESOURCE
		_gather_accumulator = 0.0
		move_to(best.global_position)
	elif _carried_amount > 0:
		_start_drop_off_trip()
	else:
		_cancel_gather()


func _cancel_gather() -> void:
	_gather_target = null
	_gather_state = GatherState.NONE
	_gather_type = ""
	_gather_accumulator = 0.0
	_drop_off_target = null


func _resource_type_to_enum(res_type: String) -> Variant:
	match res_type:
		"food":
			return ResourceManager.ResourceType.FOOD
		"wood":
			return ResourceManager.ResourceType.WOOD
		"stone":
			return ResourceManager.ResourceType.STONE
		"gold":
			return ResourceManager.ResourceType.GOLD
	return null


func assign_gather_target(node: Node2D) -> void:
	# Cancel build task
	_build_target = null
	_pending_build_target_name = ""
	# Set up gather
	_gather_target = node
	_gather_type = node.resource_type if "resource_type" in node else ""
	_gather_state = GatherState.MOVING_TO_RESOURCE
	_gather_accumulator = 0.0
	_carried_amount = 0
	_drop_off_target = null
	move_to(node.global_position)


func assign_build_target(building: Node2D) -> void:
	# Cancel gather task
	_cancel_gather()
	_build_target = building
	move_to(building.global_position)


func is_idle() -> bool:
	return not _moving and _build_target == null and _gather_state == GatherState.NONE


func resolve_build_target(scene_root: Node) -> void:
	if _pending_build_target_name == "":
		return
	var target := scene_root.get_node_or_null(_pending_build_target_name)
	if target is Node2D:
		_build_target = target
	_pending_build_target_name = ""


func resolve_gather_target(scene_root: Node) -> void:
	if _pending_gather_target_name == "":
		return
	var target := scene_root.get_node_or_null(_pending_gather_target_name)
	if target is Node2D:
		_gather_target = target
	_pending_gather_target_name = ""


func _draw() -> void:
	# Selection ring
	if selected:
		draw_arc(Vector2.ZERO, SELECTION_RING_RADIUS, 0, TAU, 32, Color(0.0, 1.0, 0.0, 0.8), 2.0)

	# Unit body
	draw_circle(Vector2.ZERO, RADIUS, unit_color)

	# Direction triangle (points toward facing direction)
	var dir := _facing
	var tip := dir * (RADIUS + 4.0)
	var left := dir.rotated(2.5) * RADIUS * 0.5
	var right := dir.rotated(-2.5) * RADIUS * 0.5
	draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(1, 1, 1, 0.9))

	# Movement target indicator
	if _moving:
		var local_target := _target_pos - position
		draw_circle(local_target, 3.0, Color(1, 1, 0, 0.6))
		draw_arc(local_target, 6.0, 0, TAU, 16, Color(1, 1, 0, 0.4), 1.0)

	# Carry indicator
	if _carried_amount > 0:
		var carry_color := Color(0.9, 0.8, 0.1, 0.8)
		var ratio := float(_carried_amount) / float(_carry_capacity)
		draw_arc(Vector2.ZERO, RADIUS + 2.0, 0, TAU * ratio, 16, carry_color, 2.0)


func move_to(world_pos: Vector2) -> void:
	_path.clear()
	_path_index = 0
	_target_pos = world_pos
	_moving = true
	queue_redraw()


func follow_path(waypoints: Array[Vector2]) -> void:
	if waypoints.is_empty():
		return
	_path = waypoints
	_path_index = 0
	_target_pos = _path[0]
	_moving = true
	queue_redraw()


func select() -> void:
	selected = true
	queue_redraw()


func deselect() -> void:
	selected = false
	queue_redraw()


func is_point_inside(point: Vector2) -> bool:
	return point.distance_to(global_position) <= RADIUS * 1.5


func get_entity_category() -> String:
	if entity_category != "":
		return entity_category
	return "enemy_unit" if owner_id != 0 else ""


func save_state() -> Dictionary:
	var state := {
		"position_x": position.x,
		"position_y": position.y,
		"unit_type": unit_type,
		"gather_state": _gather_state,
		"gather_type": _gather_type,
		"carried_amount": _carried_amount,
		"gather_accumulator": _gather_accumulator,
	}
	if _build_target != null and is_instance_valid(_build_target):
		state["build_target_name"] = str(_build_target.name)
	if _gather_target != null and is_instance_valid(_gather_target):
		state["gather_target_name"] = str(_gather_target.name)
	return state


func load_state(data: Dictionary) -> void:
	position = Vector2(
		float(data.get("position_x", 0)),
		float(data.get("position_y", 0)),
	)
	unit_type = str(data.get("unit_type", "land"))
	_pending_build_target_name = str(data.get("build_target_name", ""))
	_pending_gather_target_name = str(data.get("gather_target_name", ""))
	_gather_state = int(data.get("gather_state", GatherState.NONE)) as GatherState
	_gather_type = str(data.get("gather_type", ""))
	_carried_amount = int(data.get("carried_amount", 0))
	_gather_accumulator = float(data.get("gather_accumulator", 0.0))
