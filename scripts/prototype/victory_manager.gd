extends Node
## Manages victory and defeat conditions for all players.
## Defeat: all Town Centers destroyed.
## Victory: all enemies defeated (military), Singularity age reached, or Wonder countdown expires.

signal player_defeated(player_id: int)
signal player_victorious(player_id: int, condition: String)
signal wonder_countdown_started(player_id: int, duration: float)
signal wonder_countdown_cancelled(player_id: int)
signal wonder_countdown_paused(player_id: int)
signal wonder_countdown_resumed(player_id: int)
signal agi_core_built(player_id: int)

# Config loaded from data/settings/game/victory.json
var _wonder_countdown_duration: float = 600.0
var _defeat_delay: float = 5.0
var _allow_continue: bool = true
var _singularity_age: int = 6
var _nomadic_grace_duration: float = 300.0
var _wonder_hp_pause_threshold: float = 0.5
var _condition_labels: Dictionary = {
	"military": "Military Conquest",
	"singularity": "Singularity Achieved",
	"wonder": "Wonder Built",
}

# Town center tracking: player_id -> Array[Node2D]
var _town_centers: Dictionary = {}

# Defeated players set
var _defeated_players: Dictionary = {}

# Wonder countdown state: player_id -> { "remaining": float, "node": Node2D }
var _wonder_countdowns: Dictionary = {}

# Game result
var _game_over: bool = false
var _winner: int = -1
var _win_condition: String = ""

# References
var _building_placer: Node = null

# Defeat delay timers: player_id -> float remaining
var _defeat_timers: Dictionary = {}

# Nomadic grace: player_id -> float remaining seconds (players who start without a TC)
var _nomadic_players: Dictionary = {}


func _ready() -> void:
	_load_config()


func _load_config() -> void:
	var cfg := _load_settings("victory")
	_wonder_countdown_duration = float(cfg.get("wonder_countdown_duration", _wonder_countdown_duration))
	_defeat_delay = float(cfg.get("defeat_delay", _defeat_delay))
	_allow_continue = bool(cfg.get("allow_continue_after_victory", _allow_continue))
	_singularity_age = int(cfg.get("singularity_age", _singularity_age))
	_nomadic_grace_duration = float(cfg.get("nomadic_grace_duration", _nomadic_grace_duration))
	_wonder_hp_pause_threshold = float(cfg.get("wonder_hp_pause_threshold", _wonder_hp_pause_threshold))
	var conditions: Dictionary = cfg.get("victory_conditions", {})
	for key: String in conditions:
		var cond: Dictionary = conditions[key]
		if cond.has("label"):
			_condition_labels[key] = str(cond["label"])


func _load_settings(settings_name: String) -> Dictionary:
	if is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_settings"):
			return dl.get_settings(settings_name)
	var dl_class: GDScript = load("res://scripts/autoloads/data_loader.gd")
	var subpath: String = dl_class.SETTINGS_PATHS.get(settings_name, settings_name)
	var path := "res://data/settings/%s.json" % subpath
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	if json.data is Dictionary:
		return json.data
	return {}


func setup(building_placer: Node) -> void:
	_building_placer = building_placer
	if _building_placer and _building_placer.has_signal("building_placed"):
		_building_placer.building_placed.connect(_on_building_placed)


func _process(delta: float) -> void:
	if _game_over:
		return
	var game_delta: float = delta
	if GameManager.has_method("get_game_delta"):
		game_delta = GameManager.get_game_delta(delta)
	if game_delta <= 0.0:
		return
	_tick_wonder_countdowns(game_delta)
	_tick_defeat_timers(game_delta)
	_tick_nomadic_grace(game_delta)


func _tick_wonder_countdowns(game_delta: float) -> void:
	var completed_players: Array = []
	for player_id: int in _wonder_countdowns:
		var state: Dictionary = _wonder_countdowns[player_id]
		if state.get("paused", false):
			continue
		state["remaining"] = float(state["remaining"]) - game_delta
		if float(state["remaining"]) <= 0.0:
			completed_players.append(player_id)
	for pid: int in completed_players:
		_wonder_countdowns.erase(pid)
		_trigger_victory(pid, "wonder")


func _tick_defeat_timers(game_delta: float) -> void:
	var triggered: Array = []
	for player_id: int in _defeat_timers:
		_defeat_timers[player_id] = float(_defeat_timers[player_id]) - game_delta
		if float(_defeat_timers[player_id]) <= 0.0:
			triggered.append(player_id)
	for pid: int in triggered:
		_defeat_timers.erase(pid)
		_confirm_defeat(pid)


func register_nomadic_player(player_id: int) -> void:
	_nomadic_players[player_id] = _nomadic_grace_duration


func _tick_nomadic_grace(game_delta: float) -> void:
	var expired: Array = []
	for player_id: int in _nomadic_players:
		_nomadic_players[player_id] = float(_nomadic_players[player_id]) - game_delta
		if float(_nomadic_players[player_id]) <= 0.0:
			expired.append(player_id)
	for pid: int in expired:
		_nomadic_players.erase(pid)
		# Grace expired — if still no TC, start defeat
		if check_defeat(pid):
			if _defeat_delay <= 0.0:
				_confirm_defeat(pid)
			elif not _defeat_timers.has(pid):
				_defeat_timers[pid] = _defeat_delay


func register_town_center(player_id: int, building: Node2D) -> void:
	if not _town_centers.has(player_id):
		_town_centers[player_id] = []
	var tc_list: Array = _town_centers[player_id]
	if building not in tc_list:
		tc_list.append(building)
	# Building a TC ends nomadic grace
	_nomadic_players.erase(player_id)


func unregister_town_center(player_id: int, building: Node2D) -> void:
	if not _town_centers.has(player_id):
		return
	var tc_list: Array = _town_centers[player_id]
	tc_list.erase(building)


func check_defeat(player_id: int) -> bool:
	if _defeated_players.has(player_id):
		return true
	if _nomadic_players.has(player_id):
		return false
	if not _town_centers.has(player_id):
		return true
	var tc_list: Array = _town_centers[player_id]
	# Clean up freed nodes
	var i := tc_list.size() - 1
	while i >= 0:
		if not is_instance_valid(tc_list[i]):
			tc_list.remove_at(i)
		i -= 1
	return tc_list.is_empty()


func check_military_victory(player_id: int) -> bool:
	if _defeated_players.has(player_id):
		return false
	# All other tracked players must be defeated
	for pid: int in _town_centers:
		if pid == player_id:
			continue
		if not _defeated_players.has(pid):
			return false
	# Must have at least one other player tracked
	var other_count: int = 0
	for pid: int in _town_centers:
		if pid != player_id:
			other_count += 1
	for pid: int in _defeated_players:
		if pid != player_id:
			other_count += 1
	return other_count > 0


func check_singularity_victory(player_id: int) -> bool:
	if _defeated_players.has(player_id):
		return false
	return GameManager.current_age >= _singularity_age


func check_wonder_victory(player_id: int) -> bool:
	# Wonder victory triggers via countdown completion, not instant check
	if _defeated_players.has(player_id):
		return false
	return false


func start_wonder_countdown(player_id: int, wonder_node: Node2D) -> void:
	if _wonder_countdowns.has(player_id):
		return
	_wonder_countdowns[player_id] = {
		"remaining": _wonder_countdown_duration,
		"node": wonder_node,
		"paused": false,
	}
	wonder_countdown_started.emit(player_id, _wonder_countdown_duration)


func cancel_wonder_countdown(player_id: int) -> void:
	if not _wonder_countdowns.has(player_id):
		return
	_wonder_countdowns.erase(player_id)
	wonder_countdown_cancelled.emit(player_id)


func get_wonder_countdown_remaining(player_id: int) -> float:
	if not _wonder_countdowns.has(player_id):
		return -1.0
	return float(_wonder_countdowns[player_id]["remaining"])


func is_wonder_countdown_paused(player_id: int) -> bool:
	if not _wonder_countdowns.has(player_id):
		return false
	return bool(_wonder_countdowns[player_id].get("paused", false))


func pause_wonder_countdown(player_id: int) -> void:
	if not _wonder_countdowns.has(player_id):
		return
	var state: Dictionary = _wonder_countdowns[player_id]
	if state.get("paused", false):
		return
	state["paused"] = true
	wonder_countdown_paused.emit(player_id)


func resume_wonder_countdown(player_id: int) -> void:
	if not _wonder_countdowns.has(player_id):
		return
	var state: Dictionary = _wonder_countdowns[player_id]
	if not state.get("paused", false):
		return
	state["paused"] = false
	wonder_countdown_resumed.emit(player_id)


func on_wonder_hp_changed(player_id: int, current_hp: int, max_hp: int) -> void:
	## Called when a Wonder's HP changes. Pauses countdown if HP ratio drops below
	## threshold, resumes if HP ratio is restored above threshold.
	if not _wonder_countdowns.has(player_id):
		return
	if max_hp <= 0:
		return
	var ratio: float = float(current_hp) / float(max_hp)
	if ratio < _wonder_hp_pause_threshold:
		pause_wonder_countdown(player_id)
	else:
		resume_wonder_countdown(player_id)


func get_game_result() -> Dictionary:
	if not _game_over:
		return {}
	return {
		"winner": _winner,
		"condition": _win_condition,
		"condition_label": _condition_labels.get(_win_condition, _win_condition),
		"defeated_players": _defeated_players.keys(),
		"allow_continue": _allow_continue,
	}


func is_game_over() -> bool:
	return _game_over


func _trigger_victory(player_id: int, condition: String) -> void:
	if _game_over:
		return
	_game_over = true
	_winner = player_id
	_win_condition = condition
	player_victorious.emit(player_id, condition)


func _confirm_defeat(player_id: int) -> void:
	if _defeated_players.has(player_id):
		return
	_defeated_players[player_id] = true
	player_defeated.emit(player_id)
	# Check if this triggers military victory for any remaining player
	for pid: int in _town_centers:
		if _defeated_players.has(pid):
			continue
		if check_military_victory(pid):
			_trigger_victory(pid, "military")
			break


func _on_building_placed(building: Node2D) -> void:
	if not is_instance_valid(building):
		return
	if building.building_name == "town_center":
		var pid: int = building.owner_id
		if building.under_construction:
			building.construction_complete.connect(_on_tc_construction_complete)
		else:
			register_town_center(pid, building)
	elif building.building_name == "wonder":
		var pid: int = building.owner_id
		if building.under_construction:
			building.construction_complete.connect(_on_wonder_construction_complete)
		else:
			start_wonder_countdown(pid, building)
	elif building.building_name == "agi_core":
		if building.under_construction:
			building.construction_complete.connect(_on_agi_core_construction_complete)
		else:
			_trigger_singularity_from_building(building.owner_id)
	# Listen for destruction
	if building.has_signal("building_destroyed"):
		building.building_destroyed.connect(_on_building_destroyed)


func _on_tc_construction_complete(building: Node2D) -> void:
	register_town_center(building.owner_id, building)


func _on_wonder_construction_complete(building: Node2D) -> void:
	start_wonder_countdown(building.owner_id, building)


func _on_agi_core_construction_complete(building: Node2D) -> void:
	_trigger_singularity_from_building(building.owner_id)


func _trigger_singularity_from_building(player_id: int) -> void:
	if _game_over:
		return
	if _defeated_players.has(player_id):
		return
	agi_core_built.emit(player_id)


func _on_building_destroyed(building: Node2D) -> void:
	if _game_over:
		return
	if building.building_name == "town_center":
		unregister_town_center(building.owner_id, building)
		if check_defeat(building.owner_id):
			# Start defeat delay timer
			if not _defeat_timers.has(building.owner_id):
				if _defeat_delay <= 0.0:
					_confirm_defeat(building.owner_id)
				else:
					_defeat_timers[building.owner_id] = _defeat_delay
	elif building.building_name == "wonder":
		cancel_wonder_countdown(building.owner_id)


func on_age_advanced(new_age: int) -> void:
	if _game_over:
		return
	if new_age >= _singularity_age:
		# Find the player who advanced (player 0 for now, since GameManager is global)
		_trigger_victory(0, "singularity")


func on_victory_tech_completed(player_id: int, _tech_id: String) -> void:
	## Called when a victory_tech (e.g. agi_core) research completes.
	## Triggers the Singularity victory for the researching player.
	if _game_over:
		return
	if _defeated_players.has(player_id):
		return
	_trigger_victory(player_id, "singularity")


func save_state() -> Dictionary:
	var tc_out: Dictionary = {}
	for pid: int in _town_centers:
		var names: Array = []
		for tc: Node2D in _town_centers[pid]:
			if is_instance_valid(tc):
				names.append(str(tc.name))
		tc_out[str(pid)] = names
	var wonder_out: Dictionary = {}
	for pid: int in _wonder_countdowns:
		var state: Dictionary = _wonder_countdowns[pid]
		var node_name: String = ""
		if is_instance_valid(state.get("node")):
			node_name = str(state["node"].name)
		wonder_out[str(pid)] = {
			"remaining": float(state["remaining"]),
			"node_name": node_name,
			"paused": bool(state.get("paused", false)),
		}
	var defeated_out: Array = []
	for pid: int in _defeated_players:
		defeated_out.append(pid)
	return {
		"game_over": _game_over,
		"winner": _winner,
		"win_condition": _win_condition,
		"defeated_players": defeated_out,
		"town_centers": tc_out,
		"wonder_countdowns": wonder_out,
		"defeat_timers": _serialize_defeat_timers(),
		"nomadic_players": _serialize_nomadic_players(),
	}


func load_state(data: Dictionary) -> void:
	_game_over = bool(data.get("game_over", false))
	_winner = int(data.get("winner", -1))
	_win_condition = str(data.get("win_condition", ""))
	_defeated_players.clear()
	var defeated_arr: Array = data.get("defeated_players", [])
	for pid in defeated_arr:
		_defeated_players[int(pid)] = true
	# Town centers and wonder countdowns are restored by matching node names
	# after the scene tree is reconstructed
	_town_centers.clear()
	var tc_data: Dictionary = data.get("town_centers", {})
	for pid_str: String in tc_data:
		var pid: int = int(pid_str)
		_town_centers[pid] = []
	_wonder_countdowns.clear()
	var wonder_data: Dictionary = data.get("wonder_countdowns", {})
	for pid_str: String in wonder_data:
		var pid: int = int(pid_str)
		var entry: Dictionary = wonder_data[pid_str]
		_wonder_countdowns[pid] = {
			"remaining": float(entry.get("remaining", 0.0)),
			"node": null,
			"paused": bool(entry.get("paused", false)),
		}
	var timer_data: Dictionary = data.get("defeat_timers", {})
	_defeat_timers.clear()
	for pid_str: String in timer_data:
		_defeat_timers[int(pid_str)] = float(timer_data[pid_str])
	var nomadic_data: Dictionary = data.get("nomadic_players", {})
	_nomadic_players.clear()
	for pid_str: String in nomadic_data:
		_nomadic_players[int(pid_str)] = float(nomadic_data[pid_str])


func _serialize_defeat_timers() -> Dictionary:
	var out: Dictionary = {}
	for pid: int in _defeat_timers:
		out[str(pid)] = float(_defeat_timers[pid])
	return out


func _serialize_nomadic_players() -> Dictionary:
	var out: Dictionary = {}
	for pid: int in _nomadic_players:
		out[str(pid)] = float(_nomadic_players[pid])
	return out
