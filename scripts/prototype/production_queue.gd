class_name ProductionQueue
extends Node
## Manages a single building's unit production queue.
## Units are queued by type, resources spent immediately, and refunded on cancel.
## Training progresses using game-speed-aware delta. Production pauses at pop cap.

signal unit_produced(unit_type: String, building: Node2D)
signal queue_changed(building: Node2D)
signal production_paused(building: Node2D, reason: String)

const RESOURCE_NAME_TO_TYPE: Dictionary = {
	"food": ResourceManager.ResourceType.FOOD,
	"wood": ResourceManager.ResourceType.WOOD,
	"stone": ResourceManager.ResourceType.STONE,
	"gold": ResourceManager.ResourceType.GOLD,
	"knowledge": ResourceManager.ResourceType.KNOWLEDGE,
}

var _building: Node2D = null
var _owner_id: int = 0
var _queue: Array[String] = []
var _costs_queue: Array[Dictionary] = []  # parallel array: parsed ResourceType costs
var _max_queue_size: int = 5
var _progress: float = 0.0
var _current_train_time: float = 0.0
var _paused: bool = false
var _population_manager: Node = null
var _rally_point_offset: Vector2i = Vector2i(1, 1)


func _ready() -> void:
	_load_config()


func _load_config() -> void:
	var cfg: Dictionary = {}
	if Engine.has_singleton("DataLoader"):
		cfg = DataLoader.get_settings("production")
	elif is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_settings"):
			cfg = dl.get_settings("production")
	if cfg.is_empty():
		return
	_max_queue_size = int(cfg.get("max_queue_size", _max_queue_size))
	var offset: Array = cfg.get("rally_point_offset", [_rally_point_offset.x, _rally_point_offset.y])
	if offset.size() >= 2:
		_rally_point_offset = Vector2i(int(offset[0]), int(offset[1]))


func setup(building: Node2D, owner_id: int, population_manager: Node = null) -> void:
	_building = building
	_owner_id = owner_id
	_population_manager = population_manager


func _process(delta: float) -> void:
	if _queue.is_empty():
		return
	# Check pop cap each frame — may resume or pause
	_check_pop_cap()
	if _paused:
		return
	var game_delta: float = 0.0
	if Engine.has_singleton("GameManager"):
		game_delta = GameManager.get_game_delta(delta)
	elif is_instance_valid(Engine.get_main_loop()):
		var gm: Node = Engine.get_main_loop().root.get_node_or_null("GameManager")
		if gm and gm.has_method("get_game_delta"):
			game_delta = gm.get_game_delta(delta)
		else:
			game_delta = delta
	else:
		game_delta = delta
	if game_delta <= 0.0:
		return
	if _current_train_time <= 0.0:
		_start_next()
		if _current_train_time <= 0.0:
			return
	_progress += game_delta
	if _progress >= _current_train_time:
		_complete_production()


func can_produce(unit_type: String) -> bool:
	if _queue.size() >= _max_queue_size:
		return false
	if not _building_produces(unit_type):
		return false
	var costs := _get_train_costs(unit_type)
	if costs.is_empty():
		return true
	return _can_afford(costs)


func add_to_queue(unit_type: String) -> bool:
	if _queue.size() >= _max_queue_size:
		return false
	if not _building_produces(unit_type):
		return false
	var raw_costs := _get_raw_train_costs(unit_type)
	var costs := _parse_costs(raw_costs)
	if not costs.is_empty() and not _spend(costs):
		return false
	_queue.append(unit_type)
	_costs_queue.append(costs)
	if _queue.size() == 1:
		_start_next()
	queue_changed.emit(_building)
	return true


func cancel_at(index: int) -> void:
	if index < 0 or index >= _queue.size():
		return
	var costs: Dictionary = _costs_queue[index]
	_refund(costs)
	_queue.remove_at(index)
	_costs_queue.remove_at(index)
	if index == 0:
		# Cancelled the actively training unit — reset progress
		_progress = 0.0
		_current_train_time = 0.0
		_paused = false
		if not _queue.is_empty():
			_start_next()
	queue_changed.emit(_building)


func cancel_all() -> void:
	for i in range(_queue.size()):
		_refund(_costs_queue[i])
	_queue.clear()
	_costs_queue.clear()
	_progress = 0.0
	_current_train_time = 0.0
	_paused = false
	queue_changed.emit(_building)


func get_queue() -> Array[String]:
	return _queue.duplicate()


func get_progress() -> float:
	if _current_train_time <= 0.0:
		return 0.0
	return clampf(_progress / _current_train_time, 0.0, 1.0)


func is_paused() -> bool:
	return _paused


func get_rally_point_offset() -> Vector2i:
	return _rally_point_offset


func _check_pop_cap() -> void:
	if _queue.is_empty():
		_paused = false
		return
	if _population_manager == null:
		_paused = false
		return
	if not _population_manager.has_method("can_train"):
		_paused = false
		return
	var unit_type: String = _queue[0]
	var pop_cost := _get_population_cost(unit_type)
	var was_paused := _paused
	_paused = not _population_manager.can_train(_owner_id, pop_cost)
	if _paused and not was_paused:
		production_paused.emit(_building, "population_cap")


func _start_next() -> void:
	if _queue.is_empty():
		_progress = 0.0
		_current_train_time = 0.0
		return
	_progress = 0.0
	var unit_type: String = _queue[0]
	_current_train_time = _get_train_time(unit_type)


func _complete_production() -> void:
	if _queue.is_empty():
		return
	var unit_type: String = _queue[0]
	_queue.remove_at(0)
	_costs_queue.remove_at(0)
	_progress = 0.0
	_current_train_time = 0.0
	unit_produced.emit(unit_type, _building)
	queue_changed.emit(_building)
	if not _queue.is_empty():
		_start_next()


func _building_produces(unit_type: String) -> bool:
	if _building == null:
		return false
	var building_name: String = ""
	if "building_name" in _building:
		building_name = _building.building_name
	if building_name == "":
		return false
	var stats := _get_building_stats(building_name)
	var units_produced: Array = stats.get("units_produced", [])
	return units_produced.has(unit_type)


func _get_building_stats(building_name: String) -> Dictionary:
	if Engine.has_singleton("DataLoader"):
		return DataLoader.get_building_stats(building_name)
	if is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_building_stats"):
			return dl.get_building_stats(building_name)
	return {}


func _get_unit_stats(unit_type: String) -> Dictionary:
	if Engine.has_singleton("DataLoader"):
		return DataLoader.get_unit_stats(unit_type)
	if is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_unit_stats"):
			return dl.get_unit_stats(unit_type)
	return {}


func _get_train_time(unit_type: String) -> float:
	var stats := _get_unit_stats(unit_type)
	return float(stats.get("train_time", 25.0))


func _get_population_cost(unit_type: String) -> int:
	var stats := _get_unit_stats(unit_type)
	return int(stats.get("population_cost", 1))


func _get_raw_train_costs(unit_type: String) -> Dictionary:
	var stats := _get_unit_stats(unit_type)
	return stats.get("train_cost", {})


func _get_train_costs(unit_type: String) -> Dictionary:
	return _parse_costs(_get_raw_train_costs(unit_type))


func _parse_costs(raw: Dictionary) -> Dictionary:
	var costs: Dictionary = {}
	for key in raw:
		var lower_key: String = str(key).to_lower()
		if RESOURCE_NAME_TO_TYPE.has(lower_key):
			costs[RESOURCE_NAME_TO_TYPE[lower_key]] = int(raw[key])
	return costs


func _can_afford(costs: Dictionary) -> bool:
	if Engine.has_singleton("ResourceManager"):
		return ResourceManager.can_afford(_owner_id, costs)
	if is_instance_valid(Engine.get_main_loop()):
		var rm: Node = Engine.get_main_loop().root.get_node_or_null("ResourceManager")
		if rm and rm.has_method("can_afford"):
			return rm.can_afford(_owner_id, costs)
	return true


func _spend(costs: Dictionary) -> bool:
	if Engine.has_singleton("ResourceManager"):
		return ResourceManager.spend(_owner_id, costs)
	if is_instance_valid(Engine.get_main_loop()):
		var rm: Node = Engine.get_main_loop().root.get_node_or_null("ResourceManager")
		if rm and rm.has_method("spend"):
			return rm.spend(_owner_id, costs)
	return true


func _refund(costs: Dictionary) -> void:
	for resource_type in costs:
		var amount: int = int(costs[resource_type])
		if amount <= 0:
			continue
		if Engine.has_singleton("ResourceManager"):
			ResourceManager.add_resource(_owner_id, resource_type, amount)
		elif is_instance_valid(Engine.get_main_loop()):
			var rm: Node = Engine.get_main_loop().root.get_node_or_null("ResourceManager")
			if rm and rm.has_method("add_resource"):
				rm.add_resource(_owner_id, resource_type, amount)


func save_state() -> Dictionary:
	var raw_costs_list: Array = []
	for costs in _costs_queue:
		var raw: Dictionary = {}
		for resource_type in costs:
			for res_name: String in RESOURCE_NAME_TO_TYPE:
				if RESOURCE_NAME_TO_TYPE[res_name] == resource_type:
					raw[res_name] = int(costs[resource_type])
					break
		raw_costs_list.append(raw)
	return {
		"queue": _queue.duplicate(),
		"costs_queue": raw_costs_list,
		"progress": _progress,
		"current_train_time": _current_train_time,
		"paused": _paused,
		"owner_id": _owner_id,
	}


func load_state(data: Dictionary) -> void:
	_queue.clear()
	_costs_queue.clear()
	var queue_data: Array = data.get("queue", [])
	for item in queue_data:
		_queue.append(str(item))
	var costs_data: Array = data.get("costs_queue", [])
	for raw in costs_data:
		_costs_queue.append(_parse_costs(raw))
	_progress = float(data.get("progress", 0.0))
	_current_train_time = float(data.get("current_train_time", 0.0))
	_paused = bool(data.get("paused", false))
	_owner_id = int(data.get("owner_id", _owner_id))
