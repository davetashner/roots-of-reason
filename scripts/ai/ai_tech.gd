class_name AITech
extends Node
## AI tech research brain — queues technologies for the AI player based on
## personality-driven priority lists. Age advancement prerequisites are always
## prioritised first so AIEconomy's advance_age step can succeed.
## Runs on a configurable tick timer independent of AIEconomy and AIMilitary.

var player_id: int = 1
var difficulty: String = "normal"
var personality: String = "balanced"
var gameplay_personality: AIPersonality = null

var _tech_manager: Node = null
var _tick_timer: float = 0.0
var _tick_interval: float = 3.0
var _max_queue_size: int = 2
var _personalities: Dictionary = {}
var _regressed_requeue: Array[String] = []


func setup(tech_manager: Node) -> void:
	_tech_manager = tech_manager
	if gameplay_personality != null:
		personality = gameplay_personality.get_tech_personality()
	_load_config()


func _load_config() -> void:
	var data: Variant = DataLoader.load_json("res://data/ai/tech_config.json")
	if data == null or not data is Dictionary:
		return
	var diff_config: Dictionary = data.get(difficulty, {})
	_tick_interval = float(diff_config.get("tick_interval", 3.0))
	_max_queue_size = int(diff_config.get("max_queue_size", 2))
	_personalities = data.get("personalities", {})


func _process(delta: float) -> void:
	var game_delta := GameManager.get_game_delta(delta)
	if game_delta <= 0.0:
		return
	_tick_timer += game_delta
	if _tick_timer < _tick_interval:
		return
	_tick_timer -= _tick_interval
	_tick()


func _tick() -> void:
	if _tech_manager == null:
		return
	# Queue techs up to max_queue_size
	var queue: Array = _tech_manager.get_research_queue(player_id)
	while queue.size() < _max_queue_size:
		var tech_id: String = _find_next_tech(queue)
		if tech_id == "":
			break
		if not _tech_manager.start_research(player_id, tech_id):
			break
		queue = _tech_manager.get_research_queue(player_id)


func on_tech_regressed(p_id: int, tech_id: String, _tech_data: Dictionary) -> void:
	if p_id != player_id:
		return
	if tech_id not in _regressed_requeue:
		_regressed_requeue.append(tech_id)


func _find_regressed_tech(current_queue: Array) -> String:
	# Return first re-researchable tech from the requeue list, cleaning completed entries.
	var i: int = 0
	while i < _regressed_requeue.size():
		var tech_id: String = _regressed_requeue[i]
		if _tech_manager.is_tech_researched(tech_id, player_id):
			_regressed_requeue.remove_at(i)
			continue
		if tech_id in current_queue:
			i += 1
			continue
		if _tech_manager.can_research(player_id, tech_id):
			return tech_id
		i += 1
	return ""


func _find_next_tech(current_queue: Array) -> String:
	# Priority 1: age prerequisites for next age
	var prereq_tech: String = _find_unresearched_prereq(current_queue)
	if prereq_tech != "":
		return prereq_tech
	# Priority 1.5: re-research regressed techs
	var regressed_tech: String = _find_regressed_tech(current_queue)
	if regressed_tech != "":
		return regressed_tech
	# Priority 2: personality tech list for current age
	var personality_tech: String = _find_personality_tech(current_queue, GameManager.current_age)
	if personality_tech != "":
		return personality_tech
	# Priority 3: try next age's personality list (future-proofing)
	var next_age_tech: String = _find_personality_tech(current_queue, GameManager.current_age + 1)
	if next_age_tech != "":
		return next_age_tech
	return ""


func _find_unresearched_prereq(current_queue: Array) -> String:
	var prereqs: Array = _get_age_prerequisites()
	for tech_id: String in prereqs:
		if _tech_manager.is_tech_researched(tech_id, player_id):
			continue
		if tech_id in current_queue:
			continue
		if _tech_manager.can_research(player_id, tech_id):
			return tech_id
	return ""


func _get_age_prerequisites() -> Array:
	var next_age: int = GameManager.current_age + 1
	var ages_data: Array = DataLoader.get_ages_data()
	if next_age >= ages_data.size():
		return []
	var age_entry: Dictionary = ages_data[next_age]
	return age_entry.get("advance_prerequisites", [])


func _find_personality_tech(current_queue: Array, age: int) -> String:
	var tech_list: Array = _get_priority_techs(age)
	for tech_id: String in tech_list:
		if _tech_manager.is_tech_researched(tech_id, player_id):
			continue
		if tech_id in current_queue:
			continue
		if _tech_manager.can_research(player_id, tech_id):
			return tech_id
	return ""


func _get_priority_techs(age: int) -> Array:
	var personality_data: Dictionary = _personalities.get(personality, {})
	return personality_data.get(str(age), [])


func save_state() -> Dictionary:
	var state: Dictionary = {
		"personality": personality,
		"difficulty": difficulty,
		"player_id": player_id,
		"tick_timer": _tick_timer,
		"regressed_requeue": _regressed_requeue.duplicate(),
	}
	if gameplay_personality != null:
		state["gameplay_personality_id"] = gameplay_personality.personality_id
	return state


func load_state(data: Dictionary) -> void:
	difficulty = str(data.get("difficulty", difficulty))
	player_id = int(data.get("player_id", player_id))
	_tick_timer = float(data.get("tick_timer", 0.0))
	var gp_id: String = str(data.get("gameplay_personality_id", ""))
	if gp_id != "":
		gameplay_personality = AIPersonality.get_personality(gp_id)
	if gameplay_personality != null:
		personality = gameplay_personality.get_tech_personality()
	else:
		personality = str(data.get("personality", personality))
	_regressed_requeue.clear()
	var rq: Array = data.get("regressed_requeue", [])
	for tech_id in rq:
		_regressed_requeue.append(str(tech_id))
	_load_config()
