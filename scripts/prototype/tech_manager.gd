class_name TechManager
extends Node
## Manages per-age technology research state for all players.
## Each player can have one active research and a queue of pending techs.
## Loads tech data from DataLoader, checks prerequisites and age requirements,
## spends resources, and emits signals on completion.

signal tech_researched(player_id: int, tech_id: String, effects: Dictionary)
signal tech_regressed(player_id: int, tech_id: String, tech_data: Dictionary)
signal tech_research_started(player_id: int, tech_id: String)
signal research_progress(player_id: int, tech_id: String, progress: float)
signal research_queue_changed(player_id: int)
signal victory_tech_completed(player_id: int, tech_id: String)
signal victory_tech_research_started(player_id: int, tech_id: String)
signal victory_tech_disrupted(player_id: int, tech_id: String)

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

## Research speed config loaded from research.json
var _research_config: Dictionary = {}

## Optional reference to WarResearchBonus node (set via setup_war_bonus)
var _war_bonus_node: WarResearchBonus = null

## 1 in-progress + N queued — loaded from data/settings/tech_research.json
var _max_queue_size: int = 4

## {player_id: Array[String]} — techs that were regressed (for re-research cost multiplier)
var _regressed_techs: Dictionary = {}

## Knowledge burning config
var _kb_enabled: bool = true
var _kb_tech_loss_count: int = 1
var _kb_protect_first_n: int = 0
var _kb_re_research_multiplier: float = 1.0
var _kb_cooldown: float = 0.0

## {player_id: float} — game_time of last regression per player
var _kb_last_regression_time: Dictionary = {}


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
		var effective_speed: float = _get_effective_speed(player_id)
		current += game_delta * effective_speed
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
	# Civ exclusivity check
	var civ_exclusive: String = tech_data.get("civ_exclusive", "")
	if civ_exclusive != "":
		var player_civ: String = GameManager.get_player_civilization(player_id)
		if player_civ != civ_exclusive:
			return false
	# Age requirement and prerequisites
	var required_age: int = int(tech_data.get("age", 0))
	if required_age > GameManager.current_age or not _check_prerequisites(player_id, tech_id):
		return false
	# Cost check (apply re-research multiplier if previously regressed)
	var costs: Dictionary = _parse_costs(tech_data.get("cost", {}))
	if _is_regressed_tech(player_id, tech_id) and not is_equal_approx(_kb_re_research_multiplier, 1.0):
		var scaled: Dictionary = {}
		for res_type: ResourceManager.ResourceType in costs:
			scaled[res_type] = int(costs[res_type] * _kb_re_research_multiplier)
		costs = scaled
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
	# Spend resources (apply re-research multiplier if previously regressed)
	var tech_data: Dictionary = get_tech_data(tech_id)
	var costs: Dictionary = _parse_costs(tech_data.get("cost", {}))
	if _is_regressed_tech(player_id, tech_id) and not is_equal_approx(_kb_re_research_multiplier, 1.0):
		var scaled: Dictionary = {}
		for res_type: ResourceManager.ResourceType in costs:
			scaled[res_type] = int(costs[res_type] * _kb_re_research_multiplier)
		costs = scaled
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
		# Notify if a victory tech research has begun
		if tech_data.get("victory_tech", false):
			victory_tech_research_started.emit(player_id, tech_id)
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
	# Check if this is a victory tech being disrupted while active
	var was_active_victory_tech: bool = idx == 0 and _is_victory_tech(tech_id)
	# Remove from queue
	queue.remove_at(idx)
	# If we removed the active research, reset progress and start next
	if idx == 0:
		_research_progress[player_id] = 0.0
		if was_active_victory_tech:
			victory_tech_disrupted.emit(player_id, tech_id)
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


func regress_latest_tech(player_id: int) -> Dictionary:
	## Pops the most recently researched tech from the player's history.
	## Returns the tech data dictionary, or empty dict if nothing to regress.
	if not _kb_enabled:
		return {}
	# Cooldown check
	var last_time: float = _kb_last_regression_time.get(player_id, -INF)
	if _kb_cooldown > 0.0 and (GameManager.game_time - last_time) < _kb_cooldown:
		return {}
	var history: Array = _researched_techs.get(player_id, [])
	if history.is_empty() or history.size() <= _kb_protect_first_n:
		return {}
	var tech_id: String = history[-1]
	history.remove_at(history.size() - 1)
	# Track as regressed for re-research cost multiplier
	if player_id not in _regressed_techs:
		_regressed_techs[player_id] = []
	if tech_id not in _regressed_techs[player_id]:
		_regressed_techs[player_id].append(tech_id)
	var tech_data: Dictionary = get_tech_data(tech_id)
	_kb_last_regression_time[player_id] = GameManager.game_time
	tech_regressed.emit(player_id, tech_id, tech_data)
	return tech_data


func revert_tech_effects(player_id: int, tech_id: String) -> void:
	## Removes a specific tech from the player's researched list and emits
	## tech_regressed so listeners can revert stat changes.
	var history: Array = _researched_techs.get(player_id, [])
	var idx: int = history.find(tech_id)
	if idx == -1:
		return
	history.remove_at(idx)
	if player_id not in _regressed_techs:
		_regressed_techs[player_id] = []
	if tech_id not in _regressed_techs[player_id]:
		_regressed_techs[player_id].append(tech_id)
	var tech_data: Dictionary = get_tech_data(tech_id)
	tech_regressed.emit(player_id, tech_id, tech_data)
	if tech_data.get("victory_tech", false):
		victory_tech_disrupted.emit(player_id, tech_id)


func trigger_knowledge_burning(player_id: int) -> Array:
	## Regresses up to _kb_tech_loss_count techs from the player.
	## Returns an array of regressed tech data dictionaries.
	var results: Array = []
	for i in _kb_tech_loss_count:
		var tech_data: Dictionary = regress_latest_tech(player_id)
		if tech_data.is_empty():
			break
		results.append(tech_data)
	return results


func get_regressed_techs(player_id: int = 0) -> Array:
	## Returns the list of tech IDs that have been regressed for the player.
	return _regressed_techs.get(player_id, []).duplicate()


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
		"regressed_techs": _regressed_techs.duplicate(true),
		"kb_last_regression_time": _kb_last_regression_time.duplicate(),
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
	_regressed_techs = data.get("regressed_techs", {}).duplicate(true)
	# Deserialize kb_last_regression_time (JSON round-trip gives string keys)
	_kb_last_regression_time = {}
	var raw_kb_time: Dictionary = data.get("kb_last_regression_time", {})
	for key: Variant in raw_kb_time:
		_kb_last_regression_time[int(key)] = float(raw_kb_time[key])


func setup_war_bonus(war_bonus_node: WarResearchBonus) -> void:
	## Connects the war research bonus node for speed multiplier integration.
	_war_bonus_node = war_bonus_node


func _load_config() -> void:
	var config: Dictionary = DataLoader.get_settings("tech_research")
	if not config.is_empty():
		_max_queue_size = int(config.get("max_queue_size", 4))
	var kb_config: Dictionary = DataLoader.get_settings("knowledge_burning")
	if not kb_config.is_empty():
		_kb_enabled = bool(kb_config.get("enabled", true))
		_kb_tech_loss_count = int(kb_config.get("tech_loss_count", 1))
		_kb_protect_first_n = int(kb_config.get("protect_first_n_techs", 0))
		_kb_re_research_multiplier = float(kb_config.get("re_research_cost_multiplier", 1.0))
		_kb_cooldown = float(kb_config.get("cooldown_seconds", 0))
	_research_config = DataLoader.get_settings("research")


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
	# Check if this is a victory tech
	if tech_data.get("victory_tech", false):
		victory_tech_completed.emit(player_id, tech_id)
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


func _is_regressed_tech(player_id: int, tech_id: String) -> bool:
	return tech_id in _regressed_techs.get(player_id, [])


func _is_victory_tech(tech_id: String) -> bool:
	var tech_data: Dictionary = get_tech_data(tech_id)
	return tech_data.get("victory_tech", false)


func _get_effective_speed(player_id: int) -> float:
	## Computes effective research speed using ResearchSpeed helper.
	## Backward-compatible: returns 1.0 if no research config is loaded.
	if _research_config.is_empty():
		return 1.0
	var war_bonus: float = 0.0
	if _war_bonus_node != null:
		war_bonus = _war_bonus_node.get_war_bonus(player_id)
	return ResearchSpeed.get_effective_speed(1.0, GameManager.current_age, _research_config, war_bonus)
