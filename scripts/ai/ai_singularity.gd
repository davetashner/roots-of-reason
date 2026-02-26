class_name AISingularity
extends Node
## AI Singularity awareness — monitors opponent progress toward the Singularity
## victory condition and adjusts military aggression and tech priorities in response.
## On Hard/Expert difficulty, also pursues the Singularity path if the AI has a tech lead.

var player_id: int = 1
var difficulty: String = "normal"
var personality: AIPersonality = null

var _tech_manager: Node = null
var _ai_military: Node = null
var _ai_tech: Node = null

var _config: Dictionary = {}
var _current_threat_stage: String = ""
var _pursuit_active: bool = false
var _base_attack_threshold: int = 0
var _base_attack_cooldown: float = 0.0


func setup(tech_manager: Node, ai_military: Node, ai_tech: Node) -> void:
	_tech_manager = tech_manager
	_ai_military = ai_military
	_ai_tech = ai_tech
	_load_config()
	# Snapshot base military config values for multiplier application
	if _ai_military != null:
		_base_attack_threshold = int(_ai_military._config.get("army_attack_threshold", 8))
		_base_attack_cooldown = float(_ai_military._config.get("attack_cooldown", 90.0))
	# Connect signals
	if _tech_manager != null:
		if _tech_manager.has_signal("singularity_tech_researched"):
			_tech_manager.singularity_tech_researched.connect(_on_enemy_singularity_tech)
		if _tech_manager.has_signal("tech_researched"):
			_tech_manager.tech_researched.connect(_on_tech_researched)


func _load_config() -> void:
	var data: Variant = DataLoader.load_json("res://data/ai/singularity_config.json")
	if data == null or not data is Dictionary:
		_config = {}
		return
	_config = data
	_apply_personality_overrides()


func _apply_personality_overrides() -> void:
	if personality == null:
		return
	var overrides: Dictionary = _config.get("personality_overrides", {})
	var pid: String = personality.personality_id
	if pid not in overrides:
		return
	var pov: Dictionary = overrides[pid]
	for key: String in pov:
		var parts: Array = key.split(".")
		if parts.size() < 2:
			continue
		# Navigate nested config: "response.aggression_multiplier.mid" -> _config["response"]["aggression_multiplier"]["mid"]
		var current: Variant = _config
		var valid := true
		for i in parts.size() - 1:
			if current is Dictionary and parts[i] in current:
				current = current[parts[i]]
			else:
				valid = false
				break
		if valid and current is Dictionary:
			var last_key: String = parts[parts.size() - 1]
			current[last_key] = pov[key]


func assess_enemy_threat(enemy_pid: int) -> Dictionary:
	if _tech_manager == null:
		return {"stage": "", "count": 0, "progress_ratio": 0.0}
	var chain_techs: Array = _config.get("threat_assessment", {}).get("singularity_chain_techs", [])
	var researched: Array = _tech_manager.get_researched_techs(enemy_pid)
	var count: int = 0
	for tech_id in chain_techs:
		if tech_id in researched:
			count += 1
	var stage: String = _classify_stage(count)
	var total: int = chain_techs.size()
	var ratio: float = float(count) / float(maxi(total, 1))
	return {"stage": stage, "count": count, "progress_ratio": ratio}


func _classify_stage(count: int) -> String:
	var thresholds: Dictionary = _config.get("threat_assessment", {}).get("stage_thresholds", {})
	var critical: int = int(thresholds.get("critical", 7))
	var late: int = int(thresholds.get("late", 5))
	var mid: int = int(thresholds.get("mid", 3))
	var early: int = int(thresholds.get("early", 1))
	if count >= critical:
		return "critical"
	if count >= late:
		return "late"
	if count >= mid:
		return "mid"
	if count >= early:
		return "early"
	return ""


func apply_aggression_response(threat: Dictionary) -> void:
	var stage: String = threat.get("stage", "")
	if stage == "" or _ai_military == null:
		if _current_threat_stage != "" and _ai_military != null:
			_ai_military.clear_aggression_override()
			_ai_military.singularity_target_buildings.clear()
		_current_threat_stage = stage
		return
	_current_threat_stage = stage
	var response: Dictionary = _config.get("response", {})
	var aggr_mults: Dictionary = response.get("aggression_multiplier", {})
	var cd_mults: Dictionary = response.get("attack_cooldown_multiplier", {})
	var threshold_mult: float = float(aggr_mults.get(stage, 1.0))
	var cooldown_mult: float = float(cd_mults.get(stage, 1.0))
	_ai_military.set_aggression_override(threshold_mult, cooldown_mult)
	# Set priority building targets
	_update_priority_targets()


func _update_priority_targets() -> void:
	if _ai_military == null or _tech_manager == null:
		return
	var priority_list: Array = _config.get("response", {}).get("priority_targets", [])
	var enemy_pid: int = 0 if player_id != 0 else 1
	var researched: Array = _tech_manager.get_researched_techs(enemy_pid)
	var targets: Array[String] = []
	for building_name: String in priority_list:
		if building_name in researched:
			targets.append(building_name)
	_ai_military.singularity_target_buildings = targets


func evaluate_pursuit() -> void:
	if _ai_tech == null or _tech_manager == null:
		_pursuit_active = false
		return
	var pursuit: Dictionary = _config.get("pursuit", {})
	var min_diff: String = str(pursuit.get("min_difficulty", "hard"))
	if not _difficulty_meets_minimum(difficulty, min_diff):
		_pursuit_active = false
		_ai_tech.singularity_priority_techs.clear()
		return
	var tech_lead_threshold: int = int(pursuit.get("tech_lead_threshold", 3))
	var min_age: int = int(pursuit.get("min_age", 5))
	if GameManager.current_age < min_age:
		_pursuit_active = false
		_ai_tech.singularity_priority_techs.clear()
		return
	var enemy_pid: int = 0 if player_id != 0 else 1
	var own_count: int = _tech_manager.get_researched_techs(player_id).size()
	var enemy_count: int = _tech_manager.get_researched_techs(enemy_pid).size()
	if own_count - enemy_count < tech_lead_threshold:
		_pursuit_active = false
		_ai_tech.singularity_priority_techs.clear()
		return
	_pursuit_active = true
	var boost_techs: Array = pursuit.get("priority_boost_techs", [])
	var typed_techs: Array[String] = []
	for tech_id in boost_techs:
		typed_techs.append(str(tech_id))
	_ai_tech.singularity_priority_techs = typed_techs


func _difficulty_meets_minimum(current: String, minimum: String) -> bool:
	var order: Array = ["easy", "normal", "hard", "expert"]
	var current_idx: int = order.find(current)
	var min_idx: int = order.find(minimum)
	if current_idx < 0 or min_idx < 0:
		return false
	return current_idx >= min_idx


func get_priority_building_targets() -> Array[String]:
	if _ai_military == null:
		return []
	return _ai_military.singularity_target_buildings


func _on_enemy_singularity_tech(p_id: int, _tech_id: String, _tech_name: String) -> void:
	if p_id == player_id:
		return
	var threat: Dictionary = assess_enemy_threat(p_id)
	apply_aggression_response(threat)
	evaluate_pursuit()


func _on_tech_researched(p_id: int, _tech_id: String, _effects: Dictionary) -> void:
	if p_id != player_id:
		return
	# Re-evaluate pursuit when AI completes its own tech
	evaluate_pursuit()


func save_state() -> Dictionary:
	var state: Dictionary = {
		"player_id": player_id,
		"difficulty": difficulty,
		"current_threat_stage": _current_threat_stage,
		"pursuit_active": _pursuit_active,
		"base_attack_threshold": _base_attack_threshold,
		"base_attack_cooldown": _base_attack_cooldown,
	}
	if personality != null:
		state["personality_id"] = personality.personality_id
	return state


func load_state(data: Dictionary) -> void:
	player_id = int(data.get("player_id", player_id))
	difficulty = str(data.get("difficulty", difficulty))
	_current_threat_stage = str(data.get("current_threat_stage", ""))
	_pursuit_active = bool(data.get("pursuit_active", false))
	_base_attack_threshold = int(data.get("base_attack_threshold", 0))
	_base_attack_cooldown = float(data.get("base_attack_cooldown", 0.0))
	var pid: String = str(data.get("personality_id", ""))
	if pid != "":
		personality = AIPersonality.get_personality(pid)
	_load_config()
