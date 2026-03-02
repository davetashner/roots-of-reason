extends Node
## Loads and caches game data from JSON files in data/.

const RESOURCE_NAMES := ["berry_bush", "tree", "stone_mine", "gold_mine", "fish"]

## Maps settings file names to their subdirectory under data/settings/.
const SETTINGS_PATHS: Dictionary = {
	"ai_economy": "ai/ai_economy",
	"building_destruction": "buildings/building_destruction",
	"combat": "combat/combat",
	"formations": "combat/formations",
	"war_survival": "combat/war_survival",
	"construction": "economy/construction",
	"corruption": "economy/corruption",
	"gathering": "economy/gathering",
	"population": "economy/population",
	"production": "economy/production",
	"trade": "economy/trade",
	"historical_events": "events/historical_events",
	"knowledge_burning": "events/knowledge_burning",
	"pandemics": "events/pandemics",
	"pirates": "events/pirates",
	"singularity_cinematic": "events/singularity_cinematic",
	"singularity_regression": "events/singularity_regression",
	"game_clock": "game/game_clock",
	"victory": "game/victory",
	"fauna": "map/fauna",
	"map_generation": "map/map_generation",
	"river_overlay": "map/river_overlay",
	"river_transport": "map/river_transport",
	"terrain": "map/terrain",
	"transport": "map/transport",
	"research": "tech/research",
	"tech_research": "tech/tech_research",
	"tech_visibility": "tech/tech_visibility",
	"unit_upgrades": "tech/unit_upgrades",
	"camera": "ui/camera",
	"command_panel": "ui/command_panel",
	"commands": "ui/commands",
	"hud": "ui/hud",
	"idle_villager_finder": "ui/idle_villager_finder",
	"info_panel": "ui/info_panel",
	"notifications": "ui/notifications",
	"postgame_stats": "ui/postgame_stats",
	"selection": "ui/selection",
}

var _cache: Dictionary = {}
var _tech_index: Dictionary = {}


func load_json(path: String) -> Variant:
	if path in _cache:
		return _cache[path]
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("DataLoader: Failed to open %s" % path)
		return null
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		push_warning("DataLoader: JSON parse error in %s: %s" % [path, json.get_error_message()])
		return null
	_cache[path] = json.data
	return json.data


func get_unit_stats(unit_name: String) -> Dictionary:
	var data: Variant = load_json("res://data/units/%s.json" % unit_name)
	if data == null:
		return {}
	return data


func get_building_stats(building_name: String) -> Dictionary:
	var data: Variant = load_json("res://data/buildings/%s.json" % building_name)
	if data == null:
		return {}
	return data


func get_building_data(building_name: String) -> Dictionary:
	return get_building_stats(building_name)


func get_tech_data(tech_id: String) -> Dictionary:
	if _tech_index.is_empty():
		_build_tech_index()
	if tech_id in _tech_index:
		return _tech_index[tech_id]
	push_warning("DataLoader: Tech '%s' not found" % tech_id)
	return {}


func get_ages_data() -> Array:
	var data: Variant = load_json("res://data/tech/ages.json")
	if data == null:
		return []
	return data


func get_civ_data(civ_name: String) -> Dictionary:
	var data: Variant = load_json("res://data/civilizations/%s.json" % civ_name)
	if data == null:
		return {}
	return data


func get_resource_data(resource_name: String) -> Dictionary:
	var data: Variant = load_json("res://data/resources/%s.json" % resource_name)
	if data == null:
		return {}
	return data


func get_resource_config() -> Dictionary:
	var config: Dictionary = {}
	for resource_name in RESOURCE_NAMES:
		var data := get_resource_data(resource_name)
		if not data.is_empty():
			config[resource_name] = data
	return config


func get_resource_config_data() -> Dictionary:
	var data: Variant = load_json("res://data/resources/resource_config.json")
	if data == null:
		return {}
	return data


func get_settings(settings_name: String) -> Dictionary:
	var subpath: String = SETTINGS_PATHS.get(settings_name, settings_name)
	var data: Variant = load_json("res://data/settings/%s.json" % subpath)
	if data == null:
		return {}
	return data


func get_setting(settings_name: String) -> Dictionary:
	return get_settings(settings_name)


func get_settings_path(settings_name: String) -> String:
	var subpath: String = SETTINGS_PATHS.get(settings_name, settings_name)
	return "res://data/settings/%s.json" % subpath


func clear_cache() -> void:
	_cache.clear()


func reload() -> void:
	_cache.clear()
	_tech_index.clear()


func get_all_civ_ids() -> Array:
	var ids := []
	var dir := DirAccess.open("res://data/civilizations")
	if dir == null:
		return ids
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			ids.append(file_name.get_basename())
		file_name = dir.get_next()
	ids.sort()
	return ids


func _build_tech_index() -> void:
	var data: Variant = load_json("res://data/tech/tech_tree.json")
	if data == null:
		return
	for entry in data:
		if entry is Dictionary and "id" in entry:
			_tech_index[entry["id"]] = entry
