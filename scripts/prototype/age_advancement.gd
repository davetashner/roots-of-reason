class_name AgeAdvancement
extends Node
## Manages age advancement research at the Town Center.
## Loads age data from DataLoader, checks prerequisites and costs,
## runs research timer, and advances the age on completion.

signal advancement_started(from_age: int, to_age: int)
signal advancement_completed(new_age: int)
signal advancement_cancelled(age: int)
signal advancement_progress(progress: float)

const RESOURCE_NAME_TO_TYPE: Dictionary = {
	"food": ResourceManager.ResourceType.FOOD,
	"wood": ResourceManager.ResourceType.WOOD,
	"stone": ResourceManager.ResourceType.STONE,
	"gold": ResourceManager.ResourceType.GOLD,
	"knowledge": ResourceManager.ResourceType.KNOWLEDGE,
}

const MAX_AGE: int = 6

var _advancing: bool = false
var _advance_target: int = -1
var _advance_progress: float = 0.0
var _advance_time: float = 0.0
var _advance_cost: Dictionary = {}
var _player_id: int = 0
var _ages_data: Array = []


func _ready() -> void:
	_ages_data = DataLoader.get_ages_data()


func _process(delta: float) -> void:
	if not _advancing:
		return
	var game_delta: float = GameManager.get_game_delta(delta)
	if game_delta <= 0.0:
		return
	_advance_progress += game_delta
	var progress_ratio: float = 0.0
	if _advance_time > 0.0:
		progress_ratio = clampf(_advance_progress / _advance_time, 0.0, 1.0)
	else:
		progress_ratio = 1.0
	advancement_progress.emit(progress_ratio)
	if _advance_progress >= _advance_time:
		_complete_advancement()


func can_advance(player_id: int) -> bool:
	if _advancing:
		return false
	if GameManager.current_age >= MAX_AGE:
		return false
	var next_age: int = GameManager.current_age + 1
	var age_data: Dictionary = _get_age_data(next_age)
	if age_data.is_empty():
		return false
	if not _has_prerequisites(age_data, player_id):
		return false
	var costs: Dictionary = _parse_costs(age_data.get("advance_cost", {}))
	if not ResourceManager.can_afford(player_id, costs):
		return false
	return true


func start_advancement(player_id: int) -> bool:
	if not can_advance(player_id):
		return false
	var from_age: int = GameManager.current_age
	var next_age: int = from_age + 1
	var age_data: Dictionary = _get_age_data(next_age)
	var costs: Dictionary = _parse_costs(age_data.get("advance_cost", {}))
	if not ResourceManager.spend(player_id, costs):
		return false
	_player_id = player_id
	_advance_target = next_age
	_advance_cost = costs
	_advance_time = float(age_data.get("research_time", 0))
	_advance_progress = 0.0
	_advancing = true
	advancement_started.emit(from_age, next_age)
	# Immediate completion for zero research time
	if _advance_time <= 0.0:
		_complete_advancement()
	return true


func cancel_advancement(player_id: int) -> void:
	if not _advancing:
		return
	if player_id != _player_id:
		return
	var cancelled_target: int = _advance_target
	# Refund resources
	for resource_type: ResourceManager.ResourceType in _advance_cost:
		ResourceManager.add_resource(_player_id, resource_type, _advance_cost[resource_type])
	_advancing = false
	_advance_target = -1
	_advance_progress = 0.0
	_advance_time = 0.0
	_advance_cost = {}
	advancement_cancelled.emit(cancelled_target)


func get_advance_cost(age_index: int) -> Dictionary:
	var age_data: Dictionary = _get_age_data(age_index)
	if age_data.is_empty():
		return {}
	return _parse_costs(age_data.get("advance_cost", {}))


func get_advance_cost_raw(age_index: int) -> Dictionary:
	var age_data: Dictionary = _get_age_data(age_index)
	if age_data.is_empty():
		return {}
	return age_data.get("advance_cost", {})


func get_research_time(age_index: int) -> float:
	var age_data: Dictionary = _get_age_data(age_index)
	if age_data.is_empty():
		return 0.0
	return float(age_data.get("research_time", 0))


func get_advance_progress() -> float:
	if not _advancing or _advance_time <= 0.0:
		return 0.0
	return clampf(_advance_progress / _advance_time, 0.0, 1.0)


func is_advancing() -> bool:
	return _advancing


func get_advance_target() -> int:
	return _advance_target


func save_state() -> Dictionary:
	return {
		"advancing": _advancing,
		"advance_target": _advance_target,
		"advance_progress": _advance_progress,
		"advance_time": _advance_time,
		"advance_cost": _serialize_costs(_advance_cost),
		"player_id": _player_id,
	}


func load_state(data: Dictionary) -> void:
	_advancing = bool(data.get("advancing", false))
	_advance_target = int(data.get("advance_target", -1))
	_advance_progress = float(data.get("advance_progress", 0.0))
	_advance_time = float(data.get("advance_time", 0.0))
	_advance_cost = _parse_costs(data.get("advance_cost", {}))
	_player_id = int(data.get("player_id", 0))


func _complete_advancement() -> void:
	var new_age: int = _advance_target
	_advancing = false
	_advance_target = -1
	_advance_progress = 0.0
	_advance_time = 0.0
	_advance_cost = {}
	GameManager.advance_age(new_age)
	advancement_completed.emit(new_age)


func has_prerequisites(player_id: int) -> bool:
	## Public check — returns true if the player meets all prerequisites
	## for the next age advancement.
	var next_age: int = GameManager.current_age + 1
	var age_data: Dictionary = _get_age_data(next_age)
	if age_data.is_empty():
		return false
	return _has_prerequisites(age_data, player_id)


func get_missing_techs(player_id: int) -> Array[String]:
	## Returns a list of tech IDs the player still needs to research
	## before advancing to the next age.
	var current_age: int = GameManager.current_age
	var next_age_data: Dictionary = _get_age_data(current_age + 1)
	if next_age_data.is_empty():
		return []
	var required: Array[String] = _get_required_tech_ids(next_age_data, current_age)
	var missing: Array[String] = []
	var tech_manager: Node = _get_tech_manager()
	if tech_manager == null:
		return []
	for tech_id: String in required:
		if not tech_manager.is_tech_researched(tech_id, player_id):
			missing.append(tech_id)
	return missing


func _has_prerequisites(age_data: Dictionary, player_id: int = 0) -> bool:
	var prereqs = age_data.get("advance_prerequisites", [])
	if prereqs is String and prereqs == "all_previous_age":
		return _has_all_age_techs(GameManager.current_age, player_id)
	if prereqs is Array:
		if prereqs.is_empty():
			return true
		var tech_manager: Node = _get_tech_manager()
		if tech_manager == null:
			return true
		for tech_id: String in prereqs:
			if not tech_manager.is_tech_researched(tech_id, player_id):
				return false
		return true
	return true


func _has_all_age_techs(age_index: int, player_id: int) -> bool:
	## Returns true if the player has researched every tech in the given age.
	var tech_manager: Node = _get_tech_manager()
	if tech_manager == null:
		return true
	var tech_tree: Array = DataLoader.get_tech_tree()
	for tech: Dictionary in tech_tree:
		if int(tech.get("age", -1)) == age_index:
			if not tech_manager.is_tech_researched(str(tech["id"]), player_id):
				return false
	return true


func _get_required_tech_ids(age_data: Dictionary, current_age: int) -> Array[String]:
	## Returns the list of tech IDs required for advancement.
	var prereqs = age_data.get("advance_prerequisites", [])
	var result: Array[String] = []
	if prereqs is String and prereqs == "all_previous_age":
		var tech_tree: Array = DataLoader.get_tech_tree()
		for tech: Dictionary in tech_tree:
			if int(tech.get("age", -1)) == current_age:
				result.append(str(tech["id"]))
	elif prereqs is Array:
		for tech_id in prereqs:
			result.append(str(tech_id))
	return result


func _get_tech_manager() -> Node:
	if has_node("/root/TechManager"):
		return get_node("/root/TechManager")
	var parent: Node = get_parent()
	if parent != null:
		var tm: Node = parent.get_node_or_null("TechManager")
		if tm != null and tm.has_method("is_tech_researched"):
			return tm
	return null


func _get_age_data(age_index: int) -> Dictionary:
	if _ages_data.is_empty():
		_ages_data = DataLoader.get_ages_data()
	for age: Dictionary in _ages_data:
		if int(age.get("index", -1)) == age_index:
			return age
	return {}


func _parse_costs(raw_costs: Dictionary) -> Dictionary:
	var costs: Dictionary = {}
	for key: String in raw_costs:
		var lower_key := key.to_lower()
		if RESOURCE_NAME_TO_TYPE.has(lower_key):
			costs[RESOURCE_NAME_TO_TYPE[lower_key]] = int(raw_costs[key])
	return costs


func _serialize_costs(costs: Dictionary) -> Dictionary:
	## Convert ResourceType enum keys back to string keys for serialization.
	var result: Dictionary = {}
	for resource_type: ResourceManager.ResourceType in costs:
		for res_name: String in RESOURCE_NAME_TO_TYPE:
			if RESOURCE_NAME_TO_TYPE[res_name] == resource_type:
				result[res_name] = costs[resource_type]
				break
	return result
