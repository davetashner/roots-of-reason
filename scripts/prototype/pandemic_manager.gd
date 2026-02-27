class_name PandemicManager
extends Node
## Timer-based pandemic events that reduce villager productivity and cause deaths.
## Probability increases with population density; mitigated by techs (Herbalism,
## Sanitation, Vaccines). Config loaded from data/settings/pandemics.json.

signal pandemic_started(player_id: int, severity: float)
signal pandemic_ended(player_id: int)

var _config: Dictionary = {}
var _pop_manager: Node = null
var _tech_manager: Node = null
var _scene_root: Node = null
var _check_timer: float = 0.0
var _active_outbreaks: Dictionary = {}  # player_id -> {timer, severity, death_timer, original_rates}


func _ready() -> void:
	_load_config()


func _load_config() -> void:
	var cfg: Dictionary = {}
	if Engine.has_singleton("DataLoader"):
		cfg = DataLoader.get_settings("pandemics")
	elif is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_settings"):
			cfg = dl.get_settings("pandemics")
	if cfg.is_empty():
		return
	_config = cfg


func setup(pop_mgr: Node, tech_mgr: Node, scene_root: Node) -> void:
	_pop_manager = pop_mgr
	_tech_manager = tech_mgr
	_scene_root = scene_root


func _process(delta: float) -> void:
	var game_delta: float = _get_game_delta(delta)
	if game_delta == 0.0:
		return
	if not _config.get("enabled", true):
		return
	# Tick active outbreaks
	_tick_outbreaks(game_delta)
	# Tick check timer
	var interval: float = float(_config.get("check_interval_seconds", 120))
	_check_timer += game_delta
	if _check_timer >= interval:
		_check_timer -= interval
		_roll_pandemics()


func _tick_outbreaks(game_delta: float) -> void:
	var ended_players: Array[int] = []
	for pid: int in _active_outbreaks:
		var outbreak: Dictionary = _active_outbreaks[pid]
		outbreak.timer -= game_delta
		if outbreak.timer <= 0.0:
			ended_players.append(pid)
			continue
		# Death sub-timer — roll every 5 game-seconds
		outbreak.death_timer += game_delta
		if outbreak.death_timer >= 5.0:
			outbreak.death_timer -= 5.0
			_roll_deaths(pid, float(outbreak.severity))
	for pid: int in ended_players:
		_end_outbreak(pid)


func _roll_pandemics() -> void:
	var active_ages: Array = _config.get("active_ages", [0, 1, 2, 3])
	if _get_current_age() not in active_ages:
		return
	# Roll for each player that doesn't have an active outbreak
	var player_ids: Array[int] = _get_player_ids()
	for pid: int in player_ids:
		if pid in _active_outbreaks:
			continue
		var probability: float = _calculate_probability(pid)
		if randf() < probability:
			_start_outbreak(pid)


func _calculate_probability(player_id: int) -> float:
	var base: float = float(_config.get("base_probability", 0.05))
	var threshold: int = int(_config.get("density_threshold", 15))
	var scaling: float = float(_config.get("density_scaling", 0.02))
	var pop: int = 0
	if _pop_manager != null and _pop_manager.has_method("get_population"):
		pop = _pop_manager.get_population(player_id)
	var density_bonus: float = maxf(0.0, float(pop - threshold) * scaling)
	var prob: float = base + density_bonus
	# Tech reductions
	var mitigations: Dictionary = _config.get("tech_mitigations", {})
	for tech_id: String in mitigations:
		if _is_tech_researched(tech_id, player_id):
			var mit: Dictionary = mitigations[tech_id]
			if mit.get("immune", false):
				return 0.0
			prob -= float(mit.get("probability_reduction", 0.0))
	return clampf(prob, 0.0, 1.0)


func _calculate_severity(player_id: int) -> float:
	var severity: float = 1.0
	var mitigations: Dictionary = _config.get("tech_mitigations", {})
	for tech_id: String in mitigations:
		if _is_tech_researched(tech_id, player_id):
			var mit: Dictionary = mitigations[tech_id]
			severity -= float(mit.get("severity_reduction", 0.0))
	return clampf(severity, 0.0, 1.0)


func _start_outbreak(player_id: int) -> void:
	var severity: float = _calculate_severity(player_id)
	var effects: Dictionary = _config.get("effects", {})
	var duration: float = float(effects.get("duration_seconds", 45))
	var penalty: float = float(effects.get("villager_work_rate_penalty", -0.30))
	# Store original rates and apply penalty
	var original_rates: Dictionary = {}
	var villagers: Array = _get_villagers(player_id)
	for v: Node2D in villagers:
		var vid: int = v.get_instance_id()
		original_rates[vid] = v._gather_rate_multiplier
		v._gather_rate_multiplier = v._gather_rate_multiplier + (penalty * severity)
		if v._gather_rate_multiplier < 0.0:
			v._gather_rate_multiplier = 0.0
	_active_outbreaks[player_id] = {
		"timer": duration,
		"severity": severity,
		"death_timer": 0.0,
		"original_rates": original_rates,
	}
	pandemic_started.emit(player_id, severity)


func _end_outbreak(player_id: int) -> void:
	if player_id not in _active_outbreaks:
		return
	var outbreak: Dictionary = _active_outbreaks[player_id]
	var original_rates: Dictionary = outbreak.get("original_rates", {})
	# Restore original gather rates for surviving villagers
	var villagers: Array = _get_villagers(player_id)
	for v: Node2D in villagers:
		var vid: int = v.get_instance_id()
		if vid in original_rates:
			v._gather_rate_multiplier = float(original_rates[vid])
	_active_outbreaks.erase(player_id)
	pandemic_ended.emit(player_id)


func _roll_deaths(player_id: int, severity: float) -> void:
	var effects: Dictionary = _config.get("effects", {})
	var death_chance: float = float(effects.get("villager_death_chance", 0.05))
	var effective_chance: float = death_chance * severity
	# Check if antibiotics grants villager death immunity
	if _has_villager_death_immunity(player_id):
		return
	var villagers: Array = _get_villagers(player_id)
	for v: Node2D in villagers:
		if randf() < effective_chance:
			v.take_damage(9999, null)


func _has_villager_death_immunity(player_id: int) -> bool:
	var mitigations: Dictionary = _config.get("tech_mitigations", {})
	for tech_id: String in mitigations:
		if _is_tech_researched(tech_id, player_id):
			var mit: Dictionary = mitigations[tech_id]
			if mit.get("villager_death_immunity", false):
				return true
	return false


func _get_villagers(player_id: int) -> Array:
	var result: Array = []
	if _scene_root == null:
		return result
	for child in _scene_root.get_children():
		if not (child is Node2D):
			continue
		if "owner_id" not in child or "unit_type" not in child:
			continue
		if child.owner_id != player_id:
			continue
		if child.unit_type != "villager":
			continue
		if "hp" in child and child.hp <= 0:
			continue
		result.append(child)
	return result


func _get_player_ids() -> Array[int]:
	# Default to players 0 and 1
	return [0, 1]


func _is_tech_researched(tech_id: String, player_id: int) -> bool:
	if _tech_manager == null:
		return false
	if _tech_manager.has_method("is_tech_researched"):
		return _tech_manager.is_tech_researched(tech_id, player_id)
	return false


func _get_current_age() -> int:
	if Engine.has_singleton("GameManager"):
		return GameManager.current_age
	if is_instance_valid(Engine.get_main_loop()):
		var gm: Node = Engine.get_main_loop().root.get_node_or_null("GameManager")
		if gm and "current_age" in gm:
			return gm.current_age
	return 0


func _get_game_delta(delta: float) -> float:
	if Engine.has_singleton("GameManager"):
		return GameManager.get_game_delta(delta)
	var ml := Engine.get_main_loop() if is_instance_valid(Engine.get_main_loop()) else null
	var gm: Node = ml.root.get_node_or_null("GameManager") if ml else null
	if gm and gm.has_method("get_game_delta"):
		return gm.get_game_delta(delta)
	return delta


func is_outbreak_active(player_id: int) -> bool:
	return player_id in _active_outbreaks


func get_outbreak_severity(player_id: int) -> float:
	if player_id in _active_outbreaks:
		return float(_active_outbreaks[player_id].severity)
	return 0.0


func get_outbreak_time_remaining(player_id: int) -> float:
	if player_id in _active_outbreaks:
		return float(_active_outbreaks[player_id].timer)
	return 0.0


# -- Save / Load --


func save_state() -> Dictionary:
	var outbreaks: Dictionary = {}
	for pid: int in _active_outbreaks:
		var ob: Dictionary = _active_outbreaks[pid]
		var rates: Dictionary = {}
		for vid: int in ob.original_rates:
			rates[str(vid)] = ob.original_rates[vid]
		outbreaks[str(pid)] = {
			"timer": ob.timer,
			"severity": ob.severity,
			"death_timer": ob.death_timer,
			"original_rates": rates,
		}
	return {
		"check_timer": _check_timer,
		"active_outbreaks": outbreaks,
	}


func load_state(data: Dictionary) -> void:
	_check_timer = float(data.get("check_timer", 0.0))
	_active_outbreaks.clear()
	var outbreaks: Dictionary = data.get("active_outbreaks", {})
	for pid_str: String in outbreaks:
		var pid: int = int(pid_str)
		var ob: Dictionary = outbreaks[pid_str]
		var rates: Dictionary = {}
		var saved_rates: Dictionary = ob.get("original_rates", {})
		for vid_str: String in saved_rates:
			rates[int(vid_str)] = float(saved_rates[vid_str])
		_active_outbreaks[pid] = {
			"timer": float(ob.get("timer", 0.0)),
			"severity": float(ob.get("severity", 1.0)),
			"death_timer": float(ob.get("death_timer", 0.0)),
			"original_rates": rates,
		}
	# Reapply work rate penalties to currently alive villagers
	for pid: int in _active_outbreaks:
		var outbreak: Dictionary = _active_outbreaks[pid]
		var effects: Dictionary = _config.get("effects", {})
		var penalty: float = float(effects.get("villager_work_rate_penalty", -0.30))
		var severity: float = float(outbreak.severity)
		var villagers: Array = _get_villagers(pid)
		for v: Node2D in villagers:
			v._gather_rate_multiplier = v._gather_rate_multiplier + (penalty * severity)
			if v._gather_rate_multiplier < 0.0:
				v._gather_rate_multiplier = 0.0
