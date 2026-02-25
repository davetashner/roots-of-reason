class_name UnitUpgradeManager
extends Node
## Connects tech tree stat_modifiers to UnitStats modifier system.
## When a tech is researched, reads its stat_modifiers, maps them via
## unit_upgrades.json, and applies bonuses to all matching units.

var _modifier_map: Dictionary = {}
var _applied_upgrades: Dictionary = {}  # {player_id: [{tech_id, modifier_key, stat, value, type, unit_types}]}
var _scene_root: Node = null


func setup(scene_root: Node) -> void:
	_scene_root = scene_root
	_load_config()


func on_tech_researched(player_id: int, tech_id: String, effects: Dictionary) -> void:
	var stat_modifiers: Dictionary = effects.get("stat_modifiers", {})
	if stat_modifiers.is_empty():
		return
	for modifier_key: String in stat_modifiers:
		if modifier_key not in _modifier_map:
			continue
		var mapping: Dictionary = _modifier_map[modifier_key]
		var stat: String = mapping["stat"]
		var mod_type: String = mapping["type"]
		var unit_types: Array = mapping["unit_types"]
		var value: float = float(stat_modifiers[modifier_key])
		var source: String = "tech:" + tech_id
		# Record the upgrade
		if player_id not in _applied_upgrades:
			_applied_upgrades[player_id] = []
		(
			_applied_upgrades[player_id]
			. append(
				{
					"tech_id": tech_id,
					"modifier_key": modifier_key,
					"stat": stat,
					"value": value,
					"type": mod_type,
					"unit_types": unit_types,
				}
			)
		)
		# Apply to all matching units
		_apply_to_matching_units(player_id, stat, source, value, mod_type, unit_types)


func on_tech_regressed(player_id: int, tech_id: String, _tech_data: Dictionary) -> void:
	var source: String = "tech:" + tech_id
	# Remove from all units owned by this player
	if _scene_root != null:
		for child in _scene_root.get_children():
			if not _is_unit(child):
				continue
			if child.owner_id != player_id:
				continue
			child.stats.remove_all_from_source(source)
	# Remove from applied upgrades
	if player_id in _applied_upgrades:
		_applied_upgrades[player_id] = _applied_upgrades[player_id].filter(
			func(entry: Dictionary) -> bool: return entry["tech_id"] != tech_id
		)


func apply_upgrades_to_unit(unit: Node2D, player_id: int) -> void:
	if player_id not in _applied_upgrades:
		return
	for entry: Dictionary in _applied_upgrades[player_id]:
		var unit_types: Array = entry["unit_types"]
		if unit.unit_type not in unit_types:
			continue
		var source: String = "tech:" + entry["tech_id"]
		unit.stats.add_modifier(entry["stat"], source, entry["value"], entry["type"])


func save_state() -> Dictionary:
	var serialized: Dictionary = {}
	for player_id: int in _applied_upgrades:
		serialized[str(player_id)] = _applied_upgrades[player_id].duplicate(true)
	return {"applied_upgrades": serialized}


func load_state(data: Dictionary) -> void:
	_applied_upgrades = {}
	var raw: Dictionary = data.get("applied_upgrades", {})
	for key: Variant in raw:
		var pid: int = int(key)
		_applied_upgrades[pid] = []
		for entry: Dictionary in raw[key]:
			_applied_upgrades[pid].append(entry.duplicate(true))


func _load_config() -> void:
	var config: Dictionary = DataLoader.get_settings("unit_upgrades")
	if config.is_empty():
		return
	_modifier_map = config.get("modifier_map", {})


func _apply_to_matching_units(
	player_id: int, stat: String, source: String, value: float, mod_type: String, unit_types: Array
) -> void:
	if _scene_root == null:
		return
	for child in _scene_root.get_children():
		if not _is_unit(child):
			continue
		if child.owner_id != player_id:
			continue
		if child.unit_type not in unit_types:
			continue
		child.stats.add_modifier(stat, source, value, mod_type)


func _is_unit(child: Node) -> bool:
	return "stats" in child and "owner_id" in child and "unit_type" in child
