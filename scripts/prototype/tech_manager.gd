class_name TechManager
extends Node
## Manages per-age technology research state for all players.
## Each player can have one active research and a queue of pending techs.
## Loads tech data from DataLoader, checks prerequisites and age requirements,
## spends resources, and emits signals on completion.

signal tech_researched(player_id: int, tech_id: String, effects: Dictionary)
signal tech_research_started(player_id: int, tech_id: String)
signal research_progress(player_id: int, tech_id: String, progress: float)
signal research_queue_changed(player_id: int)

const RESOURCE_NAME_TO_TYPE: Dictionary = {
	"food": ResourceManager.ResourceType.FOOD,
	"wood": ResourceManager.ResourceType.WOOD,
	"stone": ResourceManager.ResourceType.STONE,
	"gold": ResourceManager.ResourceType.GOLD,
	"knowledge": ResourceManager.ResourceType.KNOWLEDGE,
}

## {player_id: Array[String]} — completed tech IDs per player
var _researched_techs: Dictionary = {}

## {player_id: Array[String]} — queued tech IDs per player (first is in-progress)
var _research_queue: Dictionary = {}

## {player_id: float} — seconds elapsed on current research
var _research_progress: Dictionary = {}

## {player_id: Dictionary} — parsed ResourceType costs for the in-progress tech
var _active_costs: Dictionary = {}

## Loaded tech tree array from tech_tree.json
var _tech_tree: Array = []

## 1 in-progress + N queued — loaded from data/settings/tech_research.json
var _max_queue_size: int = 4


func _ready() -> void:
	_load_config()
	_load_tech_tree()


func _process(delta: float) -> void:
	var game_delta: float = GameManager.get_game_delta(delta)
	if game_delta <= 0.0:
		return
	for player_id: int in _research_queue:
		var queue: Array = _research_queue[player_id]
		if queue.is_empty():
			continue
		var tech_id: String = queue[0]
		var tech_data: Dictionary = get_tech_data(tech_id)
		if tech_data.is_empty():
			continue
		var research_time: float = float(tech_data.get("research_time", 0))
		var current: float = _research_progress.get(player_id, 0.0)
		current += game_delta
		_research_progress[player_id] = current
		# Emit progress
		var ratio: float = 0.0
		if research_time > 0.0:
			ratio = clampf(current / research_time, 0.0, 1.0)
		else:
			ratio = 1.0
		research_progress.emit(player_id, tech_id, ratio)
		# Check completion
		if current >= research_time:
			_complete_research(player_id)


func can_research(player_id: int, tech_id: String) -> bool:
	## Returns true if the player can start or queue this tech.
	var tech_data: Dictionary = get_tech_data(tech_id)
	if tech_data.is_empty():
		return false
	# Already researched or in queue
	if is_tech_researched(tech_id, player_id) or _is_in_queue(player_id, tech_id):
		return false
	# Age requirement and prerequisites
	var required_age: int = int(tech_data.get("age", 0))
	if required_age > GameManager.current_age or not _check_prerequisites(player_id, tech_id):
		return false
	# Cost check
	var costs: Dictionary = _parse_costs(tech_data.get("cost", {}))
	return ResourceManager.can_afford(player_id, costs)


func start_research(player_id: int, tech_id: String) -> bool:
	## Attempts to add tech to the player's research queue.
	## Spends resources immediately. Returns false if not possible.
	if not can_research(player_id, tech_id):
		return false
	# Queue limit check
	var queue: Array = _research_queue.get(player_id, [])
	if queue.size() >= _max_queue_size:
		return false
	# Spend resources
	var tech_data: Dictionary = get_tech_data(tech_id)
	var costs: Dictionary = _parse_costs(tech_data.get("cost", {}))
	if not ResourceManager.spend(player_id, costs):
		return false
	# Add to queue
	if player_id not in _research_queue:
		_research_queue[player_id] = []
	_research_queue[player_id].append(tech_id)
	# Store costs for potential refund
	if player_id not in _active_costs:
		_active_costs[player_id] = {}
	_active_costs[player_id][tech_id] = costs
	# If this is the first item, it becomes active
	if _research_queue[player_id].size() == 1:
		_research_progress[player_id] = 0.0
		tech_research_started.emit(player_id, tech_id)
	research_queue_changed.emit(player_id)
	return true


func cancel_research(player_id: int, tech_id: String) -> void:
	## Removes tech from queue, refunding resources.
	if player_id not in _research_queue:
		return
	var queue: Array = _research_queue[player_id]
	var idx: int = queue.find(tech_id)
	if idx == -1:
		return
	# Refund resources
	var costs: Dictionary = _active_costs.get(player_id, {}).get(tech_id, {})
	for resource_type: ResourceManager.ResourceType in costs:
		ResourceManager.add_resource(player_id, resource_type, costs[resource_type])
	# Remove from cost tracking
	if player_id in _active_costs and tech_id in _active_costs[player_id]:
		_active_costs[player_id].erase(tech_id)
	# Remove from queue
	queue.remove_at(idx)
	# If we removed the active research, reset progress and start next
	if idx == 0:
		_research_progress[player_id] = 0.0
		if not queue.is_empty():
			tech_research_started.emit(player_id, queue[0])
	research_queue_changed.emit(player_id)


func is_tech_researched(tech_id: String, player_id: int = 0) -> bool:
	## Returns true if the given tech has been researched by the player.
	## Signature supports the age_advancement.gd forward-compatible stub
	## which calls is_tech_researched(tech_id) with one argument.
	var techs: Array = _researched_techs.get(player_id, [])
	return tech_id in techs


func get_researched_techs(player_id: int = 0) -> Array:
	## Returns the list of researched tech IDs for the player.
	return _researched_techs.get(player_id, []).duplicate()


func get_tech_data(tech_id: String) -> Dictionary:
	## Wrapper around DataLoader.get_tech_data().
	return DataLoader.get_tech_data(tech_id)


func get_research_progress(player_id: int = 0) -> float:
	## Returns 0.0-1.0 progress ratio for the active research.
	var queue: Array = _research_queue.get(player_id, [])
	if queue.is_empty():
		return 0.0
	var tech_id: String = queue[0]
	var tech_data: Dictionary = get_tech_data(tech_id)
	var research_time: float = float(tech_data.get("research_time", 0))
	if research_time <= 0.0:
		return 0.0
	var current: float = _research_progress.get(player_id, 0.0)
	return clampf(current / research_time, 0.0, 1.0)


func get_current_research(player_id: int = 0) -> String:
	## Returns the tech_id currently being researched, or "" if idle.
	var queue: Array = _research_queue.get(player_id, [])
	if queue.is_empty():
		return ""
	return queue[0]


func get_research_queue(player_id: int = 0) -> Array:
	## Returns a copy of the research queue for the player.
	return _research_queue.get(player_id, []).duplicate()


func save_state() -> Dictionary:
	var serialized_costs: Dictionary = {}
	for player_id: int in _active_costs:
		serialized_costs[str(player_id)] = {}
		for tech_id: String in _active_costs[player_id]:
			serialized_costs[str(player_id)][tech_id] = _serialize_costs(_active_costs[player_id][tech_id])
	return {
		"researched_techs": _researched_techs.duplicate(true),
		"research_queue": _research_queue.duplicate(true),
		"research_progress": _research_progress.duplicate(),
		"active_costs": serialized_costs,
		"max_queue_size": _max_queue_size,
	}


func load_state(data: Dictionary) -> void:
	_researched_techs = data.get("researched_techs", {}).duplicate(true)
	_research_queue = data.get("research_queue", {}).duplicate(true)
	# Handle both string and int keys for progress (JSON round-trip gives strings)
	_research_progress = {}
	var raw_progress: Dictionary = data.get("research_progress", {})
	for key: Variant in raw_progress:
		_research_progress[int(key)] = float(raw_progress[key])
	# Deserialize costs
	_active_costs = {}
	var raw_costs: Dictionary = data.get("active_costs", {})
	for player_key: Variant in raw_costs:
		var pid: int = int(player_key)
		_active_costs[pid] = {}
		for tech_id: String in raw_costs[player_key]:
			_active_costs[pid][tech_id] = _parse_costs(raw_costs[player_key][tech_id])
	_max_queue_size = int(data.get("max_queue_size", 4))


func _load_config() -> void:
	var config: Dictionary = DataLoader.get_settings("tech_research")
	if config.is_empty():
		return
	_max_queue_size = int(config.get("max_queue_size", 4))


func _load_tech_tree() -> void:
	var data: Variant = DataLoader.load_json("res://data/tech/tech_tree.json")
	if data is Array:
		_tech_tree = data


func _check_prerequisites(player_id: int, tech_id: String) -> bool:
	var tech_data: Dictionary = get_tech_data(tech_id)
	var prereqs: Array = tech_data.get("prerequisites", [])
	for prereq: String in prereqs:
		if not is_tech_researched(prereq, player_id):
			return false
	return true


func _is_in_queue(player_id: int, tech_id: String) -> bool:
	var queue: Array = _research_queue.get(player_id, [])
	return tech_id in queue


func _complete_research(player_id: int) -> void:
	var queue: Array = _research_queue.get(player_id, [])
	if queue.is_empty():
		return
	var tech_id: String = queue[0]
	var tech_data: Dictionary = get_tech_data(tech_id)
	var effects: Dictionary = tech_data.get("effects", {})
	# Add to researched list
	if player_id not in _researched_techs:
		_researched_techs[player_id] = []
	_researched_techs[player_id].append(tech_id)
	# Remove from queue and cost tracking
	queue.remove_at(0)
	if player_id in _active_costs and tech_id in _active_costs[player_id]:
		_active_costs[player_id].erase(tech_id)
	_research_progress[player_id] = 0.0
	# Emit completion signal
	tech_researched.emit(player_id, tech_id, effects)
	research_queue_changed.emit(player_id)
	# Start next in queue if available
	if not queue.is_empty():
		tech_research_started.emit(player_id, queue[0])


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
