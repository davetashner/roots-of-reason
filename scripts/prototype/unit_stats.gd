class_name UnitStats
extends RefCounted
## Manages base stats, modifiers, and computed current stats for a unit.
## Modifiers are tracked by source string for easy add/remove (e.g., "tech:bronze_working").

signal stats_changed

var unit_id: String = ""
var _base_stats: Dictionary = {}
var _modifiers: Dictionary = {}


func _init(id: String = "", base: Dictionary = {}) -> void:
	unit_id = id
	_base_stats = base.duplicate()


func get_stat(stat_name: String) -> float:
	var base: float = float(_base_stats.get(stat_name, 0.0))
	var flat_bonus: float = 0.0
	var percent_bonus: float = 0.0
	for mod in _modifiers.get(stat_name, []):
		if mod.type == "flat":
			flat_bonus += mod.value
		elif mod.type == "percent":
			percent_bonus += mod.value
	return (base + flat_bonus) * (1.0 + percent_bonus)


func get_base_stat(stat_name: String) -> float:
	return float(_base_stats.get(stat_name, 0.0))


func set_base_stat(stat_name: String, value: float) -> void:
	_base_stats[stat_name] = value
	stats_changed.emit()


func add_modifier(stat_name: String, source: String, value: float, type: String = "flat") -> void:
	if stat_name not in _modifiers:
		_modifiers[stat_name] = []
	_modifiers[stat_name].append({"source": source, "value": value, "type": type})
	stats_changed.emit()


func remove_modifier(stat_name: String, source: String) -> void:
	if stat_name not in _modifiers:
		return
	_modifiers[stat_name] = _modifiers[stat_name].filter(func(m: Dictionary) -> bool: return m.source != source)
	if _modifiers[stat_name].is_empty():
		_modifiers.erase(stat_name)
	stats_changed.emit()


func remove_all_from_source(source: String) -> void:
	for stat_name in _modifiers.keys():
		remove_modifier(stat_name, source)


func has_modifier(stat_name: String, source: String) -> bool:
	for mod in _modifiers.get(stat_name, []):
		if mod.source == source:
			return true
	return false


func get_all_stats() -> Dictionary:
	var result: Dictionary = {}
	for stat_name in _base_stats:
		result[stat_name] = get_stat(stat_name)
	return result


func save_state() -> Dictionary:
	return {
		"unit_id": unit_id,
		"base_stats": _base_stats.duplicate(),
		"modifiers": _modifiers.duplicate(true),
	}


func load_state(data: Dictionary) -> void:
	unit_id = str(data.get("unit_id", ""))
	_base_stats = data.get("base_stats", {}).duplicate()
	_modifiers = data.get("modifiers", {}).duplicate(true)


static func from_data(id: String) -> UnitStats:
	var raw: Dictionary = DataLoader.get_unit_stats(id)
	if raw.is_empty():
		push_warning("UnitStats: No data found for unit '%s'" % id)
		return UnitStats.new(id)
	return UnitStats.new(id, raw)
