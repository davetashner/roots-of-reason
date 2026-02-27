extends Node
## Tracks cumulative game statistics per player for post-game display.
## Created by prototype_main, NOT an autoload.

var _player_stats: Dictionary = {}
var _snapshot_interval: float = 30.0
var _elapsed_since_snapshot: float = 0.0
var _game_time: float = 0.0


func setup(config: Dictionary = {}, tech_mgr: Node = null) -> void:
	_snapshot_interval = config.get("snapshot_interval_seconds", 30.0)
	ResourceManager.resources_changed.connect(record_resource_change)
	GameManager.age_advanced.connect(record_age_change)
	if tech_mgr != null:
		tech_mgr.tech_researched.connect(record_tech_researched)


func init_player(player_id: int) -> void:
	_player_stats[player_id] = {
		"resources_gathered": {},
		"resources_spent": {},
		"units_produced": {},
		"units_killed": 0,
		"units_lost": 0,
		"buildings_built": {},
		"buildings_lost": 0,
		"techs_researched": [],
		"age_timestamps": {},
		"time_snapshots": [],
	}


func get_player_stats(player_id: int) -> Dictionary:
	return _player_stats.get(player_id, {})


func get_all_stats() -> Dictionary:
	return _player_stats.duplicate(true)


func get_game_time() -> float:
	return _game_time


func _process(delta: float) -> void:
	_game_time += delta
	_elapsed_since_snapshot += delta
	if _elapsed_since_snapshot >= _snapshot_interval:
		_elapsed_since_snapshot -= _snapshot_interval
		_take_snapshot()


func _take_snapshot() -> void:
	for player_id: int in _player_stats:
		var stats: Dictionary = _player_stats[player_id]
		var snapshot := {
			"time": _game_time,
			"resources_gathered_total": _sum_dict(stats["resources_gathered"]),
			"resources_spent_total": _sum_dict(stats["resources_spent"]),
			"units_killed": stats["units_killed"],
			"units_lost": stats["units_lost"],
			"buildings_built_total": _sum_dict(stats["buildings_built"]),
			"buildings_lost": stats["buildings_lost"],
			"techs_count": stats["techs_researched"].size(),
		}
		stats["time_snapshots"].append(snapshot)


func _sum_dict(d: Dictionary) -> int:
	var total := 0
	for val: int in d.values():
		total += val
	return total


# --- Recording methods ---


func record_resource_change(player_id: int, resource_type: String, old_amount: int, new_amount: int) -> void:
	if player_id not in _player_stats:
		return
	var delta: int = new_amount - old_amount
	var stats: Dictionary = _player_stats[player_id]
	if delta > 0:
		var gathered: Dictionary = stats["resources_gathered"]
		gathered[resource_type] = gathered.get(resource_type, 0) + delta
	elif delta < 0:
		var spent: Dictionary = stats["resources_spent"]
		spent[resource_type] = spent.get(resource_type, 0) + absi(delta)


func record_unit_produced(player_id: int, unit_type: String) -> void:
	if player_id not in _player_stats:
		return
	var produced: Dictionary = _player_stats[player_id]["units_produced"]
	produced[unit_type] = produced.get(unit_type, 0) + 1


func record_unit_kill(player_id: int) -> void:
	if player_id not in _player_stats:
		return
	_player_stats[player_id]["units_killed"] += 1


func record_unit_lost(player_id: int) -> void:
	if player_id not in _player_stats:
		return
	_player_stats[player_id]["units_lost"] += 1


func record_building_built(player_id: int, building_name: String) -> void:
	if player_id not in _player_stats:
		return
	var built: Dictionary = _player_stats[player_id]["buildings_built"]
	built[building_name] = built.get(building_name, 0) + 1


func record_building_lost(player_id: int) -> void:
	if player_id not in _player_stats:
		return
	_player_stats[player_id]["buildings_lost"] += 1


func record_tech_researched(player_id: int, tech_id: String, _effects: Dictionary) -> void:
	if player_id not in _player_stats:
		return
	var techs: Array = _player_stats[player_id]["techs_researched"]
	if tech_id not in techs:
		techs.append(tech_id)


func record_age_change(new_age: int, player_id: int = 0) -> void:
	if player_id not in _player_stats:
		return
	var timestamps: Dictionary = _player_stats[player_id]["age_timestamps"]
	if new_age not in timestamps:
		timestamps[new_age] = _game_time


# --- Serialization ---


func save_state() -> Dictionary:
	return {
		"player_stats": _player_stats.duplicate(true),
		"game_time": _game_time,
		"elapsed_since_snapshot": _elapsed_since_snapshot,
	}


func load_state(data: Dictionary) -> void:
	_player_stats = data.get("player_stats", {})
	_game_time = data.get("game_time", 0.0)
	_elapsed_since_snapshot = data.get("elapsed_since_snapshot", 0.0)


func reset() -> void:
	_player_stats.clear()
	_game_time = 0.0
	_elapsed_since_snapshot = 0.0
