class_name WarResearchBonus
extends Node
## Tracks combat state per player and provides war research bonus.
## Bonus scales by current age per research.json configuration.
## Lingers for a configurable duration after combat ends.

signal war_bonus_activated(player_id: int, bonus: float)
signal war_bonus_expired(player_id: int)
signal spillover_applied(player_id: int, tech_id: String, bonuses: Dictionary)

## Loaded from research.json
var _bonus_by_age: Dictionary = {}
var _linger_seconds: float = 30.0
var _spillover_map: Dictionary = {}

## Per-player combat tracking
var _in_combat: Dictionary = {}  # {player_id: bool}
var _last_combat_time: Dictionary = {}  # {player_id: float} — GameManager.game_time when combat ended
var _bonus_active: Dictionary = {}  # {player_id: bool}

## Accumulated spillover bonuses per player: {player_id: {bonus_key: float}}
var _applied_spillovers: Dictionary = {}


func _ready() -> void:
	_load_config()


func _process(delta: float) -> void:
	var game_delta: float = GameManager.get_game_delta(delta)
	if game_delta <= 0.0:
		return
	# Check linger expiration for each player with active bonus
	for player_id: int in _bonus_active:
		if not _bonus_active[player_id]:
			continue
		if _in_combat.get(player_id, false):
			continue
		# Player is not in combat — check linger
		var last_time: float = _last_combat_time.get(player_id, 0.0)
		if GameManager.game_time - last_time >= _linger_seconds:
			_bonus_active[player_id] = false
			war_bonus_expired.emit(player_id)


func notify_combat_started(player_id: int) -> void:
	## Called externally when at least 1 military unit enters combat.
	_in_combat[player_id] = true
	if not _bonus_active.get(player_id, false):
		_bonus_active[player_id] = true
		var bonus: float = _get_age_bonus()
		war_bonus_activated.emit(player_id, bonus)


func notify_combat_ended(player_id: int) -> void:
	## Called externally when no military units are in combat.
	_in_combat[player_id] = false
	_last_combat_time[player_id] = GameManager.game_time


func get_war_bonus(player_id: int) -> float:
	## Returns the current war bonus for the player (0.0 if inactive).
	if not _bonus_active.get(player_id, false):
		return 0.0
	return _get_age_bonus()


func is_bonus_active(player_id: int) -> bool:
	## Returns true if the war research bonus is currently active for the player.
	return _bonus_active.get(player_id, false)


func apply_spillover(player_id: int, tech_id: String, tech_data: Dictionary) -> void:
	## Checks if a completed tech has war_spillover bonuses and applies them.
	## Called when tech_researched is emitted.
	var spillover: Dictionary = tech_data.get("war_spillover", {})
	# Also check the spillover map from research.json
	var config_spillover: Dictionary = _spillover_map.get(tech_id, {})
	# Merge both sources (tech_tree data takes precedence)
	var merged: Dictionary = config_spillover.duplicate()
	merged.merge(spillover, true)
	if merged.is_empty():
		return
	# Accumulate spillover bonuses for this player
	if player_id not in _applied_spillovers:
		_applied_spillovers[player_id] = {}
	for bonus_key: String in merged:
		var current: float = _applied_spillovers[player_id].get(bonus_key, 0.0)
		_applied_spillovers[player_id][bonus_key] = current + float(merged[bonus_key])
	spillover_applied.emit(player_id, tech_id, merged)


func get_applied_spillovers(player_id: int) -> Dictionary:
	## Returns accumulated spillover bonuses for the player.
	return _applied_spillovers.get(player_id, {}).duplicate()


func save_state() -> Dictionary:
	return {
		"in_combat": _in_combat.duplicate(),
		"last_combat_time": _last_combat_time.duplicate(),
		"bonus_active": _bonus_active.duplicate(),
		"applied_spillovers": _applied_spillovers.duplicate(true),
	}


func load_state(data: Dictionary) -> void:
	_in_combat = {}
	var raw_combat: Dictionary = data.get("in_combat", {})
	for key: Variant in raw_combat:
		_in_combat[int(key)] = bool(raw_combat[key])
	_last_combat_time = {}
	var raw_time: Dictionary = data.get("last_combat_time", {})
	for key: Variant in raw_time:
		_last_combat_time[int(key)] = float(raw_time[key])
	_bonus_active = {}
	var raw_active: Dictionary = data.get("bonus_active", {})
	for key: Variant in raw_active:
		_bonus_active[int(key)] = bool(raw_active[key])
	_applied_spillovers = {}
	var raw_spillovers: Dictionary = data.get("applied_spillovers", {})
	for key: Variant in raw_spillovers:
		var pid: int = int(key)
		_applied_spillovers[pid] = {}
		for bonus_key: String in raw_spillovers[key]:
			_applied_spillovers[pid][bonus_key] = float(raw_spillovers[key][bonus_key])


func _load_config() -> void:
	var config: Dictionary = DataLoader.get_settings("research")
	if config.is_empty():
		return
	_bonus_by_age = config.get("war_research_bonus_by_age", {})
	_linger_seconds = float(config.get("war_bonus_linger_seconds", 30))
	_spillover_map = config.get("military_tech_spillovers", {})


func _get_age_bonus() -> float:
	## Returns the war bonus for the current age from config.
	var age_str: String = str(GameManager.current_age)
	return float(_bonus_by_age.get(age_str, 0.0))
