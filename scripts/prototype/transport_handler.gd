extends RefCounted
## Transport handler — manages embarking/disembarking land units on transports.
## Mirrors the garrison pattern from prototype_building.gd.

const TILE_SIZE: float = 64.0

var embarked_units: Array[Node2D] = []
var load_queue: Array[Node2D] = []
var unload_queue: Array[Node2D] = []
var capacity: int = 0
var config: Dictionary = {}
var is_unloading: bool = false
var pending_disembark_pos: Vector2 = Vector2.ZERO
var pending_names: Array[String] = []

var _load_timer: float = 0.0


func embark_unit(unit: Node2D) -> bool:
	if capacity <= 0:
		return false
	if embarked_units.size() + load_queue.size() >= capacity:
		return false
	# Only land units can embark
	var mt: String = "land"
	if "movement_type" in unit:
		mt = str(unit.movement_type)
	elif "stats" in unit and unit.stats != null and "_base_stats" in unit.stats:
		mt = str(unit.stats._base_stats.get("movement_type", "land"))
	if mt == "water":
		return false
	if unit in embarked_units or unit in load_queue:
		return false
	load_queue.append(unit)
	return true


func can_embark() -> bool:
	if capacity <= 0:
		return false
	return embarked_units.size() + load_queue.size() < capacity


func get_count() -> int:
	return embarked_units.size() + load_queue.size()


func tick(game_delta: float, is_moving: bool) -> void:
	_tick_loading(game_delta)
	_tick_unloading(game_delta, is_moving)


func _tick_loading(game_delta: float) -> void:
	if load_queue.is_empty():
		return
	var load_time: float = float(config.get("load_time_per_unit", 1.5))
	_load_timer += game_delta
	if _load_timer >= load_time:
		_load_timer = 0.0
		var unit: Node2D = load_queue.pop_front()
		if is_instance_valid(unit):
			unit.visible = false
			unit.set_process(false)
			embarked_units.append(unit)


func _tick_unloading(game_delta: float, is_moving: bool) -> void:
	if not is_unloading or is_moving:
		return
	if unload_queue.is_empty() and not embarked_units.is_empty():
		for unit in embarked_units:
			unload_queue.append(unit)
		embarked_units.clear()
		_load_timer = 0.0
	if not unload_queue.is_empty():
		var unload_time: float = float(config.get("unload_time_per_unit", 1.0))
		_load_timer += game_delta
		if _load_timer >= unload_time:
			_load_timer = 0.0
			var unit: Node2D = unload_queue.pop_front()
			if is_instance_valid(unit):
				_place_unit(unit)
	if unload_queue.is_empty() and embarked_units.is_empty():
		is_unloading = false


func _place_unit(unit: Node2D) -> void:
	var spread: float = float(config.get("unload_spread_radius_tiles", 2)) * TILE_SIZE
	var count: int = embarked_units.size() + unload_queue.size() + 1
	var angle := TAU * float(count) / float(maxi(count + 1, 1))
	var offset := Vector2(cos(angle), sin(angle)) * spread
	unit.global_position = pending_disembark_pos + offset
	unit.visible = true
	unit.set_process(true)


func kill_passengers() -> void:
	for passenger in embarked_units:
		if is_instance_valid(passenger):
			passenger.visible = true
			passenger.set_process(true)
			if "hp" in passenger:
				passenger.hp = 0
			if passenger.has_method("_die"):
				passenger._die()
	embarked_units.clear()
	for passenger in load_queue:
		if is_instance_valid(passenger):
			if "hp" in passenger:
				passenger.hp = 0
			if passenger.has_method("_die"):
				passenger._die()
	load_queue.clear()


func resolve(scene_root: Node) -> void:
	for unit_name in pending_names:
		var unit := scene_root.get_node_or_null(unit_name)
		if unit is Node2D:
			embarked_units.append(unit)
			unit.visible = false
			unit.set_process(false)
	pending_names.clear()


func save_state() -> Dictionary:
	var names: Array[String] = []
	for unit in embarked_units:
		if is_instance_valid(unit):
			names.append(str(unit.name))
	return {
		"embarked_unit_names": names,
		"is_unloading": is_unloading,
		"pending_disembark_pos_x": pending_disembark_pos.x,
		"pending_disembark_pos_y": pending_disembark_pos.y,
	}


func load_state(data: Dictionary) -> void:
	if data.has("embarked_unit_names"):
		var raw_names: Array = data["embarked_unit_names"]
		pending_names.clear()
		for n in raw_names:
			pending_names.append(str(n))
	is_unloading = bool(data.get("is_unloading", false))
	pending_disembark_pos = Vector2(
		float(data.get("pending_disembark_pos_x", 0)),
		float(data.get("pending_disembark_pos_y", 0)),
	)
