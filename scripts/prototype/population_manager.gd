class_name PopulationManager
extends Node
## Tracks current population and housing-based population cap per player.
## Each completed housing building (House, Town Center) adds its population_bonus
## to the cap. Hard cap and starting cap are loaded from data/settings/economy/population.json.

signal population_changed(player_id: int, current: int, cap: int)
signal near_cap_warning(player_id: int)
signal building_count_changed(player_id: int, count: int)

var _current_population: Dictionary = {}  # player_id -> int
var _population_cap: Dictionary = {}  # player_id -> int
var _building_contributions: Dictionary = {}  # player_id -> Array[int] (instance_id -> bonus)
var _building_count: Dictionary = {}  # player_id -> int (total buildings including zero-bonus)
var _housing_tech_bonus: Dictionary = {}  # player_id -> int (extra pop per housing building from tech)

var _hard_cap: int = 200
var _starting_cap: int = 5
var _near_cap_threshold: int = 2


func _ready() -> void:
	_load_config()


func _load_config() -> void:
	var cfg: Dictionary = GameUtils.dl_settings("population")
	if cfg.is_empty():
		return
	_hard_cap = int(cfg.get("hard_cap", _hard_cap))
	_starting_cap = int(cfg.get("starting_cap", _starting_cap))


func _ensure_player(player_id: int) -> void:
	if player_id not in _current_population:
		_current_population[player_id] = 0
	if player_id not in _population_cap:
		_population_cap[player_id] = _starting_cap
	if player_id not in _building_contributions:
		_building_contributions[player_id] = {}
	if player_id not in _building_count:
		_building_count[player_id] = 0
	if player_id not in _housing_tech_bonus:
		_housing_tech_bonus[player_id] = 0


func register_building(building: Node, player_id: int = 0) -> void:
	_ensure_player(player_id)
	_building_count[player_id] = int(_building_count[player_id]) + 1
	building_count_changed.emit(player_id, int(_building_count[player_id]))
	var bonus: int = _get_population_bonus(building)
	if bonus <= 0:
		return
	var contributions: Dictionary = _building_contributions[player_id]
	contributions[building.get_instance_id()] = bonus
	_building_contributions[player_id] = contributions
	_recalculate_cap(player_id)


func unregister_building(building: Node, player_id: int = 0) -> void:
	_ensure_player(player_id)
	_building_count[player_id] = maxi(int(_building_count[player_id]) - 1, 0)
	building_count_changed.emit(player_id, int(_building_count[player_id]))
	var contributions: Dictionary = _building_contributions[player_id]
	var bid: int = building.get_instance_id()
	if bid in contributions:
		contributions.erase(bid)
		_building_contributions[player_id] = contributions
		_recalculate_cap(player_id)


func register_unit(_unit: Node, player_id: int = 0) -> void:
	_ensure_player(player_id)
	_current_population[player_id] = int(_current_population[player_id]) + 1
	_emit_population_changed(player_id)


func unregister_unit(_unit: Node, player_id: int = 0) -> void:
	_ensure_player(player_id)
	_current_population[player_id] = maxi(int(_current_population[player_id]) - 1, 0)
	_emit_population_changed(player_id)


func can_train(player_id: int, pop_cost: int = 1) -> bool:
	_ensure_player(player_id)
	return int(_current_population[player_id]) + pop_cost <= int(_population_cap[player_id])


func get_population(player_id: int) -> int:
	_ensure_player(player_id)
	return int(_current_population[player_id])


func get_building_count(player_id: int) -> int:
	_ensure_player(player_id)
	return int(_building_count[player_id])


func get_population_cap(player_id: int) -> int:
	_ensure_player(player_id)
	return int(_population_cap[player_id])


func is_near_cap(player_id: int, threshold: int = 2) -> bool:
	_ensure_player(player_id)
	var current: int = int(_current_population[player_id])
	var cap: int = int(_population_cap[player_id])
	return cap - current <= threshold and current < cap


func _get_population_bonus(building: Node) -> int:
	if "building_name" not in building:
		return 0
	var building_name: String = building.building_name
	if building_name == "":
		return 0
	var stats: Dictionary = {}
	if Engine.has_singleton("DataLoader"):
		stats = DataLoader.get_building_stats(building_name)
	elif is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_building_stats"):
			stats = dl.get_building_stats(building_name)
	return int(stats.get("population_bonus", 0))


func _recalculate_cap(player_id: int) -> void:
	var total: int = _starting_cap
	var contributions: Dictionary = _building_contributions.get(player_id, {})
	for bid in contributions:
		total += int(contributions[bid])
	var tech_bonus: int = int(_housing_tech_bonus.get(player_id, 0))
	if tech_bonus > 0:
		total += tech_bonus * contributions.size()
	_population_cap[player_id] = mini(total, _hard_cap)
	_emit_population_changed(player_id)


func apply_housing_tech_bonus(player_id: int, extra_per_house: int) -> void:
	_ensure_player(player_id)
	_housing_tech_bonus[player_id] = int(_housing_tech_bonus[player_id]) + extra_per_house
	_recalculate_cap(player_id)


func _on_tech_researched(player_id: int, _tech_id: String, effects: Dictionary) -> void:
	var econ: Dictionary = effects.get("economic_bonus", {})
	var bonus: int = int(econ.get("house_capacity", 0))
	if bonus > 0:
		apply_housing_tech_bonus(player_id, bonus)


func _emit_population_changed(player_id: int) -> void:
	var current: int = int(_current_population[player_id])
	var cap: int = int(_population_cap[player_id])
	population_changed.emit(player_id, current, cap)
	if is_near_cap(player_id, _near_cap_threshold):
		near_cap_warning.emit(player_id)


func save_state() -> Dictionary:
	var pop_data: Dictionary = {}
	for pid in _current_population:
		pop_data[str(pid)] = {
			"current": int(_current_population[pid]),
			"cap": int(_population_cap[pid]),
		}
	var bld_counts: Dictionary = {}
	for pid in _building_count:
		bld_counts[str(pid)] = int(_building_count[pid])
	var housing_bonus: Dictionary = {}
	for pid in _housing_tech_bonus:
		housing_bonus[str(pid)] = int(_housing_tech_bonus[pid])
	return {
		"population": pop_data,
		"hard_cap": _hard_cap,
		"starting_cap": _starting_cap,
		"building_counts": bld_counts,
		"housing_tech_bonus": housing_bonus,
	}


func load_state(data: Dictionary) -> void:
	_current_population.clear()
	_population_cap.clear()
	_building_contributions.clear()
	_building_count.clear()
	_housing_tech_bonus.clear()
	_hard_cap = int(data.get("hard_cap", _hard_cap))
	_starting_cap = int(data.get("starting_cap", _starting_cap))
	var pop_data: Dictionary = data.get("population", {})
	for pid_str in pop_data:
		var pid: int = int(pid_str)
		var entry: Dictionary = pop_data[pid_str]
		_current_population[pid] = int(entry.get("current", 0))
		_population_cap[pid] = int(entry.get("cap", _starting_cap))
		_building_contributions[pid] = {}
	var bld_counts: Dictionary = data.get("building_counts", {})
	for pid_str in bld_counts:
		_building_count[int(pid_str)] = int(bld_counts[pid_str])
	var housing_bonus: Dictionary = data.get("housing_tech_bonus", {})
	for pid_str in housing_bonus:
		_housing_tech_bonus[int(pid_str)] = int(housing_bonus[pid_str])
