class_name HistoricalEventManager
extends Node
## Manages named historical events: Black Plague (guaranteed mega-pandemic in
## Medieval Age) and Renaissance (per-player golden age on tech milestones).
## Config loaded from data/settings/historical_events.json.

signal event_started(event_id: String, player_id: int)
signal event_ended(event_id: String, player_id: int)

var _config: Dictionary = {}
var _pop_manager: Node = null
var _tech_manager: Node = null
var _trade_manager: Node = null
var _building_placer: Node = null
var _scene_root: Node = null

# -- Black Plague global state --
var _plague_fired: bool = false
var _plague_delay_timer: float = -1.0  # <0 means not counting down
var _plague_active: bool = false
var _plague_timer: float = 0.0
var _plague_death_timer: float = 0.0
var _plague_end_times: Dictionary = {}  # player_id -> game_time when plague ended

# -- Per-player state objects --
var _plague_states: Dictionary = {}  # player_id -> PlaguePlayerState
var _aftermath_states: Dictionary = {}  # player_id -> AftermathState
var _renaissance_states: Dictionary = {}  # player_id -> RenaissanceState

# -- State inner classes --


class PlaguePlayerState:
	extends RefCounted
	var death_chance_reduction: float = 0.0
	var duration_remaining: float = 0.0
	var original_rates: Dictionary = {}  # instance_id -> rate

	func save_data() -> Dictionary:
		var rates_out: Dictionary = {}
		for vid: int in original_rates:
			rates_out[str(vid)] = original_rates[vid]
		return {
			"death_chance_reduction": death_chance_reduction,
			"duration_remaining": duration_remaining,
			"original_rates": rates_out,
		}

	static func from_data(data: Dictionary) -> PlaguePlayerState:
		var state := PlaguePlayerState.new()
		state.death_chance_reduction = float(data.get("death_chance_reduction", 0.0))
		state.duration_remaining = float(data.get("duration_remaining", 0.0))
		var rates_in: Dictionary = data.get("original_rates", {})
		for vid_str: String in rates_in:
			state.original_rates[int(vid_str)] = float(rates_in[vid_str])
		return state


class AftermathState:
	extends RefCounted
	var timer: float = 0.0

	func save_data() -> Dictionary:
		return {"timer": timer}

	static func from_data(data: Dictionary) -> AftermathState:
		var state := AftermathState.new()
		state.timer = float(data.get("timer", 0.0))
		return state


class RenaissanceState:
	extends RefCounted
	var triggered: bool = false
	var active: bool = false
	var timer: float = 0.0
	var phoenix: bool = false

	func save_data() -> Dictionary:
		return {
			"triggered": triggered,
			"active": active,
			"timer": timer,
			"phoenix": phoenix,
		}

	static func from_data(data: Dictionary) -> RenaissanceState:
		var state := RenaissanceState.new()
		state.triggered = bool(data.get("triggered", false))
		state.active = bool(data.get("active", false))
		state.timer = float(data.get("timer", 0.0))
		state.phoenix = bool(data.get("phoenix", false))
		return state


func _ready() -> void:
	_load_config()


func _load_config() -> void:
	var cfg: Dictionary = GameUtils.dl_settings("historical_events")
	if cfg.is_empty():
		return
	_config = cfg


func setup(
	pop_mgr: Node,
	tech_mgr: Node,
	trade_mgr: Node,
	building_placer: Node,
	scene_root: Node,
) -> void:
	_pop_manager = pop_mgr
	_tech_manager = tech_mgr
	_trade_manager = trade_mgr
	_building_placer = building_placer
	_scene_root = scene_root
	# Connect age advancement for plague trigger
	if GameManager.has_signal("age_advanced"):
		GameManager.age_advanced.connect(_on_age_advanced)
	# Connect tech researched for renaissance trigger
	if _tech_manager != null and _tech_manager.has_signal("tech_researched"):
		_tech_manager.tech_researched.connect(_on_tech_researched)


func _process(delta: float) -> void:
	var game_delta: float = GameUtils.get_game_delta(delta)
	if game_delta == 0.0:
		return
	if not _config.get("enabled", true):
		return
	_tick_plague_delay(game_delta)
	_tick_plague(game_delta)
	_tick_aftermath(game_delta)
	_tick_renaissance(game_delta)


# -- Black Plague --


func _on_age_advanced(new_age: int) -> void:
	if _plague_fired:
		return
	var plague_cfg: Dictionary = _get_event_config("black_plague")
	if plague_cfg.is_empty():
		return
	var trigger: Dictionary = plague_cfg.get("trigger", {})
	var trigger_age: int = int(trigger.get("trigger_age", 3))
	if new_age < trigger_age:
		return
	_plague_fired = true
	var delay_range: Array = trigger.get("trigger_delay_seconds", [180, 360])
	var min_delay: float = float(delay_range[0]) if delay_range.size() > 0 else 180.0
	var max_delay: float = float(delay_range[1]) if delay_range.size() > 1 else 360.0
	_plague_delay_timer = randf_range(min_delay, max_delay)


func _tick_plague_delay(game_delta: float) -> void:
	if _plague_delay_timer < 0.0:
		return
	_plague_delay_timer -= game_delta
	if _plague_delay_timer <= 0.0:
		_plague_delay_timer = -1.0
		_start_black_plague()


func _start_black_plague() -> void:
	var plague_cfg: Dictionary = _get_event_config("black_plague")
	var effects: Dictionary = plague_cfg.get("effects", {})
	var duration: float = float(effects.get("duration_seconds", 90))
	var penalty: float = float(effects.get("villager_work_rate_penalty", -0.50))
	var trade_penalty: float = float(effects.get("trade_income_penalty", -0.75))
	# trade_income_penalty is -0.75, meaning multiplier = 1.0 + (-0.75) = 0.25
	var trade_mult: float = 1.0 + trade_penalty
	var mitigations: Dictionary = plague_cfg.get("tech_mitigations", {})
	var player_ids: Array[int] = _get_player_ids()
	_plague_states.clear()
	for pid: int in player_ids:
		# Check vaccine immunity
		if _has_plague_immunity(pid, mitigations):
			event_started.emit("black_plague", pid)
			event_ended.emit("black_plague", pid)
			continue
		# Calculate per-player mitigated work rate reduction
		var mit_work_reduction: float = 0.0
		var death_red: float = 0.0
		var dur: float = duration
		for tech_id: String in mitigations:
			if _is_tech_researched(tech_id, pid):
				var mit: Dictionary = mitigations[tech_id]
				mit_work_reduction += float(mit.get("work_rate_penalty_reduction", 0.0))
				death_red += float(mit.get("death_chance_reduction", 0.0))
				dur *= (1.0 - float(mit.get("duration_reduction", 0.0)))
		# Create per-player plague state
		var pstate := PlaguePlayerState.new()
		pstate.death_chance_reduction = death_red
		pstate.duration_remaining = dur
		# Apply work rate penalty (mitigated)
		var effective_penalty: float = penalty * (1.0 - mit_work_reduction)
		var villagers: Array = _get_villagers(pid)
		for v: Node2D in villagers:
			var vid: int = v.get_instance_id()
			pstate.original_rates[vid] = v._gather_rate_multiplier
			v._gather_rate_multiplier = maxf(0.0, v._gather_rate_multiplier + effective_penalty)
		_plague_states[pid] = pstate
		# Apply trade income penalty
		if _trade_manager != null and _trade_manager.has_method("set_trade_income_multiplier"):
			_trade_manager.set_trade_income_multiplier(pid, trade_mult)
		event_started.emit("black_plague", pid)
	_plague_active = true
	_plague_timer = duration
	_plague_death_timer = 0.0


func _tick_plague(game_delta: float) -> void:
	if not _plague_active:
		return
	var plague_cfg: Dictionary = _get_event_config("black_plague")
	var effects: Dictionary = plague_cfg.get("effects", {})
	var hp_drain: float = float(effects.get("military_hp_drain_per_second", 2))
	_plague_timer -= game_delta
	# Death sub-timer — roll every 5 game-seconds
	_plague_death_timer += game_delta
	if _plague_death_timer >= 5.0:
		_plague_death_timer -= 5.0
		_roll_plague_deaths(effects)
	# Military HP drain
	_drain_military_hp(game_delta, hp_drain)
	# Check per-player end (some players may end sooner due to tech)
	var player_ids: Array[int] = _get_player_ids()
	for pid: int in player_ids:
		if pid not in _plague_states:
			continue
		_plague_states[pid].duration_remaining -= game_delta
		if _plague_states[pid].duration_remaining <= 0.0:
			_end_plague_for_player(pid)
	# End plague globally when base timer expires
	if _plague_timer <= 0.0:
		_end_black_plague()


func _roll_plague_deaths(effects: Dictionary) -> void:
	var base_chance: float = float(effects.get("villager_death_chance", 0.15))
	for pid: int in _plague_states:
		var pstate: PlaguePlayerState = _plague_states[pid]
		if pstate.duration_remaining <= 0.0:
			continue
		var chance: float = base_chance * (1.0 - pstate.death_chance_reduction)
		if chance <= 0.0:
			continue
		var villagers: Array = _get_villagers(pid)
		for v: Node2D in villagers:
			if randf() < chance:
				v.take_damage(9999, null)


func _drain_military_hp(game_delta: float, hp_drain: float) -> void:
	if _scene_root == null:
		return
	for pid: int in _plague_states:
		var pstate: PlaguePlayerState = _plague_states[pid]
		if pstate.duration_remaining <= 0.0:
			continue
		for child in _scene_root.get_children():
			if not (child is Node2D):
				continue
			if "owner_id" not in child or "unit_type" not in child:
				continue
			if child.owner_id != pid:
				continue
			if child.unit_type == "villager":
				continue
			if "hp" in child and child.hp > 0:
				child.take_damage(int(hp_drain * game_delta), null)


func _end_plague_for_player(pid: int) -> void:
	if pid not in _plague_states:
		return
	var pstate: PlaguePlayerState = _plague_states[pid]
	# Restore work rates
	var villagers: Array = _get_villagers(pid)
	for v: Node2D in villagers:
		var vid: int = v.get_instance_id()
		if vid in pstate.original_rates:
			v._gather_rate_multiplier = float(pstate.original_rates[vid])
	_plague_states.erase(pid)
	# Clear trade penalty
	if _trade_manager != null and _trade_manager.has_method("clear_trade_income_multiplier"):
		_trade_manager.clear_trade_income_multiplier(pid)
	# Record plague end time for Phoenix interaction
	_plague_end_times[pid] = _get_game_time()
	event_ended.emit("black_plague", pid)
	# Start aftermath
	_start_aftermath(pid)


func _end_black_plague() -> void:
	# End for any remaining players
	var remaining: Array = _plague_states.keys()
	for pid: int in remaining:
		_end_plague_for_player(pid)
	_plague_active = false
	_plague_death_timer = 0.0


# -- Plague Aftermath --


func _start_aftermath(pid: int) -> void:
	var plague_cfg: Dictionary = _get_event_config("black_plague")
	var aftermath: Dictionary = plague_cfg.get("aftermath", {})
	var labor: Dictionary = aftermath.get("labor_scarcity_bonus", {})
	var innovation: Dictionary = aftermath.get("innovation_pressure", {})
	var duration: float = float(labor.get("duration_seconds", 120))
	var work_bonus: float = float(labor.get("villager_work_rate_bonus", 0.15))
	var research_bonus: float = float(innovation.get("research_speed_bonus", 0.20))
	# Apply work rate bonus to surviving villagers
	var villagers: Array = _get_villagers(pid)
	for v: Node2D in villagers:
		v._gather_rate_multiplier += work_bonus
	# Apply research speed bonus
	if _tech_manager != null and _tech_manager.has_method("set_event_research_bonus"):
		_tech_manager.set_event_research_bonus(pid, research_bonus)
	var astate := AftermathState.new()
	astate.timer = duration
	_aftermath_states[pid] = astate


func _tick_aftermath(game_delta: float) -> void:
	var ended: Array[int] = []
	for pid: int in _aftermath_states:
		_aftermath_states[pid].timer -= game_delta
		if _aftermath_states[pid].timer <= 0.0:
			ended.append(pid)
	for pid: int in ended:
		_end_aftermath(pid)


func _end_aftermath(pid: int) -> void:
	var plague_cfg: Dictionary = _get_event_config("black_plague")
	var aftermath: Dictionary = plague_cfg.get("aftermath", {})
	var labor: Dictionary = aftermath.get("labor_scarcity_bonus", {})
	var work_bonus: float = float(labor.get("villager_work_rate_bonus", 0.15))
	# Remove work rate bonus from villagers
	var villagers: Array = _get_villagers(pid)
	for v: Node2D in villagers:
		v._gather_rate_multiplier = maxf(0.0, v._gather_rate_multiplier - work_bonus)
	# Clear research speed bonus
	if _tech_manager != null and _tech_manager.has_method("clear_event_research_bonus"):
		_tech_manager.clear_event_research_bonus(pid)
	_aftermath_states.erase(pid)


# -- Renaissance --


func _on_tech_researched(player_id: int, _tech_id: String, _effects: Dictionary) -> void:
	var rstate: RenaissanceState = _renaissance_states.get(player_id)
	if rstate != null and rstate.triggered:
		return
	_check_renaissance(player_id)


func _check_renaissance(player_id: int) -> void:
	var rstate: RenaissanceState = _renaissance_states.get(player_id)
	if rstate != null and rstate.triggered:
		return
	var ren_cfg: Dictionary = _get_event_config("renaissance")
	if ren_cfg.is_empty():
		return
	var trigger: Dictionary = ren_cfg.get("trigger", {})
	var min_age: int = int(trigger.get("trigger_age_minimum", 3))
	if _get_current_age() < min_age:
		return
	var required: Array = trigger.get("required_techs", [])
	for tech_id: String in required:
		if not _is_tech_researched(tech_id, player_id):
			return
	_start_renaissance(player_id)


func _start_renaissance(player_id: int) -> void:
	var rstate := RenaissanceState.new()
	rstate.triggered = true
	rstate.active = true
	var ren_cfg: Dictionary = _get_event_config("renaissance")
	var effects: Dictionary = ren_cfg.get("effects", {})
	var duration: float = float(effects.get("duration_seconds", 180))
	var research_bonus: float = float(effects.get("research_speed_bonus", 0.35))
	var gold_bonus: float = float(effects.get("gold_income_bonus", 0.20))
	# Check Phoenix interaction: Renaissance within 120s of plague end
	var is_phoenix: bool = false
	var phoenix_cfg: Dictionary = _config.get("plague_renaissance_interaction", {})
	var phoenix_data: Dictionary = phoenix_cfg.get("phoenix_bonus", {})
	var phoenix_mult: float = float(phoenix_data.get("all_effects_multiplied", 1.5))
	var phoenix_window: float = 120.0
	if player_id in _plague_end_times:
		var elapsed: float = _get_game_time() - _plague_end_times[player_id]
		if elapsed <= phoenix_window:
			is_phoenix = true
			research_bonus *= phoenix_mult
			gold_bonus *= phoenix_mult
			duration *= phoenix_mult
	rstate.phoenix = is_phoenix
	# Check building bonuses
	var bonus_triggers: Dictionary = ren_cfg.get("bonus_triggers", {})
	var library_bonus: Dictionary = bonus_triggers.get("has_library_count_3_plus", {})
	var market_bonus: Dictionary = bonus_triggers.get("has_market_count_2_plus", {})
	var extra_research: float = 0.0
	var extra_gold: float = 0.0
	if _count_buildings(player_id, "library") >= 3:
		extra_research = float(library_bonus.get("extra_knowledge_bonus", 0.25))
		if is_phoenix:
			extra_research *= phoenix_mult
	if _count_buildings(player_id, "market") >= 2:
		extra_gold = float(market_bonus.get("extra_gold_bonus", 0.15))
		if is_phoenix:
			extra_gold *= phoenix_mult
	# Apply research speed bonus (stacks with aftermath if still active)
	var total_research: float = research_bonus + extra_research
	if _tech_manager != null and _tech_manager.has_method("set_event_research_bonus"):
		var existing: float = 0.0
		if _aftermath_states.has(player_id):
			# Aftermath bonus is already set; add renaissance on top
			var plague_cfg: Dictionary = _get_event_config("black_plague")
			var innovation: Dictionary = plague_cfg.get("aftermath", {}).get("innovation_pressure", {})
			existing = float(innovation.get("research_speed_bonus", 0.20))
		_tech_manager.set_event_research_bonus(player_id, existing + total_research)
	# Apply trade gold multiplier
	var total_gold_mult: float = 1.0 + gold_bonus + extra_gold
	if _trade_manager != null and _trade_manager.has_method("set_trade_income_multiplier"):
		_trade_manager.set_trade_income_multiplier(player_id, total_gold_mult)
	rstate.timer = duration
	_renaissance_states[player_id] = rstate
	# population_growth_halt: No growth system exists yet — flag stored but no-op
	# knowledge_generation_bonus: No passive knowledge tick — research speed covers intent
	# building_cost_reduction: Deferred — requires touching building_placer cost flow
	event_started.emit("renaissance", player_id)


func _tick_renaissance(game_delta: float) -> void:
	var ended: Array[int] = []
	for pid: int in _renaissance_states:
		var rstate: RenaissanceState = _renaissance_states[pid]
		if not rstate.active:
			continue
		rstate.timer -= game_delta
		if rstate.timer <= 0.0:
			ended.append(pid)
	for pid: int in ended:
		_end_renaissance(pid)


func _end_renaissance(player_id: int) -> void:
	var rstate: RenaissanceState = _renaissance_states.get(player_id)
	if rstate == null:
		return
	rstate.active = false
	rstate.phoenix = false
	# Remove research bonus (keep aftermath if still active)
	if _tech_manager != null and _tech_manager.has_method("set_event_research_bonus"):
		if _aftermath_states.has(player_id):
			var plague_cfg: Dictionary = _get_event_config("black_plague")
			var innovation: Dictionary = plague_cfg.get("aftermath", {}).get("innovation_pressure", {})
			var aftermath_bonus: float = float(innovation.get("research_speed_bonus", 0.20))
			_tech_manager.set_event_research_bonus(player_id, aftermath_bonus)
		else:
			_tech_manager.clear_event_research_bonus(player_id)
	# Remove trade multiplier
	if _trade_manager != null and _trade_manager.has_method("clear_trade_income_multiplier"):
		_trade_manager.clear_trade_income_multiplier(player_id)
	event_ended.emit("renaissance", player_id)


# -- Helpers --


func _get_event_config(event_id: String) -> Dictionary:
	var events: Dictionary = _config.get("events", {})
	return events.get(event_id, {})


func _has_plague_immunity(player_id: int, mitigations: Dictionary) -> bool:
	for tech_id: String in mitigations:
		if _is_tech_researched(tech_id, player_id):
			var mit: Dictionary = mitigations[tech_id]
			if mit.get("immune", false):
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


func _get_military_units(player_id: int) -> Array:
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
		if child.unit_type == "villager":
			continue
		if "hp" in child and child.hp <= 0:
			continue
		result.append(child)
	return result


func _count_buildings(player_id: int, building_name: String) -> int:
	if _building_placer == null:
		return 0
	if not ("_placed_buildings" in _building_placer):
		return 0
	var count: int = 0
	for entry: Dictionary in _building_placer._placed_buildings:
		var node: Node2D = entry.get("node")
		if not is_instance_valid(node):
			continue
		if entry.get("building_name", "") != building_name:
			continue
		if "owner_id" in node and node.owner_id == player_id:
			count += 1
	return count


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


func _get_game_time() -> float:
	if Engine.has_singleton("GameManager"):
		return GameManager.game_time
	if is_instance_valid(Engine.get_main_loop()):
		var gm: Node = Engine.get_main_loop().root.get_node_or_null("GameManager")
		if gm and "game_time" in gm:
			return float(gm.game_time)
	return 0.0


func _get_player_ids() -> Array[int]:
	return [0, 1]


# -- Query API --


func is_plague_active() -> bool:
	return _plague_active


func is_renaissance_active(player_id: int) -> bool:
	var rstate: RenaissanceState = _renaissance_states.get(player_id)
	return rstate != null and rstate.active


func is_phoenix_active(player_id: int) -> bool:
	var rstate: RenaissanceState = _renaissance_states.get(player_id)
	return rstate != null and rstate.phoenix


func is_aftermath_active(player_id: int) -> bool:
	return _aftermath_states.has(player_id)


func get_plague_time_remaining() -> float:
	return maxf(0.0, _plague_timer) if _plague_active else 0.0


func get_renaissance_time_remaining(player_id: int) -> float:
	var rstate: RenaissanceState = _renaissance_states.get(player_id)
	if rstate == null:
		return 0.0
	return maxf(0.0, rstate.timer)


# -- Save / Load --


func save_state() -> Dictionary:
	var plague_states_out: Dictionary = {}
	for pid: int in _plague_states:
		plague_states_out[str(pid)] = _plague_states[pid].save_data()
	var plague_end_times_out: Dictionary = {}
	for pid: int in _plague_end_times:
		plague_end_times_out[str(pid)] = _plague_end_times[pid]
	var aftermath_states_out: Dictionary = {}
	for pid: int in _aftermath_states:
		aftermath_states_out[str(pid)] = _aftermath_states[pid].save_data()
	var renaissance_states_out: Dictionary = {}
	for pid: int in _renaissance_states:
		renaissance_states_out[str(pid)] = _renaissance_states[pid].save_data()
	return {
		"plague_fired": _plague_fired,
		"plague_delay_timer": _plague_delay_timer,
		"plague_active": _plague_active,
		"plague_timer": _plague_timer,
		"plague_death_timer": _plague_death_timer,
		"plague_states": plague_states_out,
		"plague_end_times": plague_end_times_out,
		"aftermath_states": aftermath_states_out,
		"renaissance_states": renaissance_states_out,
	}


func load_state(data: Dictionary) -> void:
	_plague_fired = bool(data.get("plague_fired", false))
	_plague_delay_timer = float(data.get("plague_delay_timer", -1.0))
	_plague_active = bool(data.get("plague_active", false))
	_plague_timer = float(data.get("plague_timer", 0.0))
	_plague_death_timer = float(data.get("plague_death_timer", 0.0))
	# Restore plague states
	_plague_states.clear()
	var plague_states_in: Dictionary = data.get("plague_states", {})
	for pid_str: String in plague_states_in:
		_plague_states[int(pid_str)] = PlaguePlayerState.from_data(plague_states_in[pid_str])
	# Restore plague end times
	_plague_end_times.clear()
	var end_times_in: Dictionary = data.get("plague_end_times", {})
	for pid_str: String in end_times_in:
		_plague_end_times[int(pid_str)] = float(end_times_in[pid_str])
	# Restore aftermath states
	_aftermath_states.clear()
	var aftermath_in: Dictionary = data.get("aftermath_states", {})
	for pid_str: String in aftermath_in:
		_aftermath_states[int(pid_str)] = AftermathState.from_data(aftermath_in[pid_str])
	# Restore renaissance states
	_renaissance_states.clear()
	var renaissance_in: Dictionary = data.get("renaissance_states", {})
	for pid_str: String in renaissance_in:
		_renaissance_states[int(pid_str)] = RenaissanceState.from_data(renaissance_in[pid_str])
	# -- Legacy format support (pre-refactor save files) --
	_load_legacy_state(data)


func _load_legacy_state(data: Dictionary) -> void:
	# Support loading saves from before the state-object refactor
	if data.has("plague_mit_death") and not data.has("plague_states"):
		var mit_death_in: Dictionary = data.get("plague_mit_death", {})
		var mit_dur_in: Dictionary = data.get("plague_mit_duration", {})
		var rates_in: Dictionary = data.get("plague_original_rates", {})
		for pid_str: String in mit_dur_in:
			var pid: int = int(pid_str)
			var pstate := PlaguePlayerState.new()
			pstate.death_chance_reduction = float(mit_death_in.get(pid_str, 0.0))
			pstate.duration_remaining = float(mit_dur_in[pid_str])
			if pid_str in rates_in:
				for vid_str: String in rates_in[pid_str]:
					pstate.original_rates[int(vid_str)] = float(rates_in[pid_str][vid_str])
			_plague_states[pid] = pstate
	if data.has("aftermath_active") and not data.has("aftermath_states"):
		var aftermath_timer_in: Dictionary = data.get("aftermath_timer", {})
		for pid_str: String in aftermath_timer_in:
			var astate := AftermathState.new()
			astate.timer = float(aftermath_timer_in[pid_str])
			_aftermath_states[int(pid_str)] = astate
	if data.has("renaissance_triggered") and not data.has("renaissance_states"):
		var ren_triggered_in: Dictionary = data.get("renaissance_triggered", {})
		var ren_active_in: Dictionary = data.get("renaissance_active", {})
		var ren_timer_in: Dictionary = data.get("renaissance_timer", {})
		var ren_phoenix_in: Dictionary = data.get("renaissance_phoenix", {})
		for pid_str: String in ren_triggered_in:
			var pid: int = int(pid_str)
			var rstate := RenaissanceState.new()
			rstate.triggered = true
			rstate.active = ren_active_in.has(pid_str)
			rstate.timer = float(ren_timer_in.get(pid_str, 0.0))
			rstate.phoenix = bool(ren_phoenix_in.get(pid_str, false))
			_renaissance_states[pid] = rstate
