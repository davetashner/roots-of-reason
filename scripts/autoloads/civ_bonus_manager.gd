extends Node
## Manages civilization bonuses — loads civ data, applies stat modifiers to units,
## and provides multiplier queries for gameplay systems.

signal bonuses_applied(player_id: int, civ_id: String)
signal bonuses_removed(player_id: int, civ_id: String)

## Maps bonus keys to unit stat names and filter criteria
const _BONUS_ROUTING := {
	"military_attack": {"stat": "attack", "filter": "military"},
	"military_defense": {"stat": "defense", "filter": "military"},
	"naval_speed": {"stat": "speed", "filter": "water"},
}

## Maps player_id -> civ_id for active civilizations
var _active_civs: Dictionary = {}

## Cached civ data dictionaries
var _civ_cache: Dictionary = {}


func apply_civ_bonuses(player_id: int, civ_id: String) -> void:
	# Remove existing bonuses first if switching civs
	if player_id in _active_civs:
		remove_civ_bonuses(player_id)
	var data := _load_civ_data(civ_id)
	if data.is_empty():
		push_warning("CivBonusManager: Unknown civ '%s'" % civ_id)
		return
	_active_civs[player_id] = civ_id
	bonuses_applied.emit(player_id, civ_id)


func remove_civ_bonuses(player_id: int) -> void:
	if player_id not in _active_civs:
		return
	var civ_id: String = _active_civs[player_id]
	_active_civs.erase(player_id)
	bonuses_removed.emit(player_id, civ_id)


func get_active_civ(player_id: int) -> String:
	return str(_active_civs.get(player_id, ""))


func get_bonus_value(player_id: int, bonus_key: String) -> float:
	if player_id not in _active_civs:
		return 1.0
	var data := _load_civ_data(_active_civs[player_id])
	var bonuses: Dictionary = data.get("bonuses", {})
	return float(bonuses.get(bonus_key, 1.0))


func get_build_speed_multiplier(player_id: int) -> float:
	return get_bonus_value(player_id, "build_speed")


func get_resolved_building_id(player_id: int, building_id: String) -> String:
	if player_id not in _active_civs:
		return building_id
	var data := _load_civ_data(_active_civs[player_id])
	var unique: Dictionary = data.get("unique_building", {})
	if unique.is_empty():
		return building_id
	if str(unique.get("replaces", "")) != building_id:
		return building_id
	return str(unique.get("name", "")).to_lower().replace(" ", "_")


func get_resolved_unit_id(player_id: int, unit_id: String) -> String:
	if player_id not in _active_civs:
		return unit_id
	var data := _load_civ_data(_active_civs[player_id])
	var unique: Dictionary = data.get("unique_unit", {})
	if unique.is_empty():
		return unit_id
	if str(unique.get("base_unit", "")) != unit_id:
		return unit_id
	return str(unique.get("name", "")).to_lower().replace(" ", "_")


func apply_bonus_to_unit(unit_stats: UnitStats, unit_id: String, player_id: int) -> void:
	if unit_stats == null:
		return
	if player_id not in _active_civs:
		return
	var civ_id: String = _active_civs[player_id]
	var data := _load_civ_data(civ_id)
	var bonuses: Dictionary = data.get("bonuses", {})
	var source := "civ:%s" % civ_id
	# Look up unit data to determine category and movement type
	var unit_data: Dictionary = DataLoader.get_unit_stats(unit_id)
	var unit_category: String = str(unit_data.get("unit_category", ""))
	var movement_type: String = str(unit_data.get("movement_type", "land"))
	for bonus_key: String in bonuses:
		if bonus_key not in _BONUS_ROUTING:
			continue
		var route: Dictionary = _BONUS_ROUTING[bonus_key]
		var stat_name: String = route["stat"]
		var filter: String = route["filter"]
		if not _unit_matches_filter(unit_category, movement_type, filter):
			continue
		# Bonus value is a multiplier (e.g. 1.10) — convert to percent modifier (0.10)
		var multiplier: float = float(bonuses[bonus_key])
		var percent_value: float = multiplier - 1.0
		if not is_zero_approx(percent_value):
			unit_stats.add_modifier(stat_name, source, percent_value, "percent")


func apply_starting_bonuses(player_id: int) -> void:
	if player_id not in _active_civs:
		return
	var data := _load_civ_data(_active_civs[player_id])
	var starting: Dictionary = data.get("starting_bonuses", {})
	if starting.is_empty():
		return
	var extra_resources: Dictionary = starting.get("extra_resources", {})
	for res_name: String in extra_resources:
		var amount: int = int(extra_resources[res_name])
		var res_type: Variant = _resource_name_to_type(res_name)
		if res_type != null:
			ResourceManager.add_resource(player_id, res_type, amount)


func reset() -> void:
	_active_civs.clear()
	_civ_cache.clear()


func save_state() -> Dictionary:
	return {"active_civs": _active_civs.duplicate()}


func load_state(data: Dictionary) -> void:
	_active_civs.clear()
	var saved: Dictionary = data.get("active_civs", {})
	for key: Variant in saved:
		var player_id: int = int(key)
		var civ_id: String = str(saved[key])
		apply_civ_bonuses(player_id, civ_id)


func _load_civ_data(civ_id: String) -> Dictionary:
	if civ_id in _civ_cache:
		return _civ_cache[civ_id]
	var data: Dictionary = DataLoader.get_civ_data(civ_id)
	if not data.is_empty():
		_civ_cache[civ_id] = data
	return data


func _unit_matches_filter(unit_category: String, movement_type: String, filter: String) -> bool:
	match filter:
		"military":
			return unit_category == "military"
		"water":
			return movement_type == "water"
	return false


func _resource_name_to_type(res_name: String) -> Variant:
	match res_name:
		"food":
			return ResourceManager.ResourceType.FOOD
		"wood":
			return ResourceManager.ResourceType.WOOD
		"stone":
			return ResourceManager.ResourceType.STONE
		"gold":
			return ResourceManager.ResourceType.GOLD
		"knowledge":
			return ResourceManager.ResourceType.KNOWLEDGE
	return null
