extends Node
## Loads and caches game data from JSON files in data/.

var _cache: Dictionary = {}


func load_json(path: String) -> Variant:
	if path in _cache:
		return _cache[path]
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DataLoader: Failed to open %s" % path)
		return null
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		push_error("DataLoader: JSON parse error in %s: %s" % [path, json.get_error_message()])
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


func get_civ_data(civ_name: String) -> Dictionary:
	var data: Variant = load_json("res://data/civilizations/%s.json" % civ_name)
	if data == null:
		return {}
	return data


func get_settings(settings_name: String) -> Dictionary:
	var data: Variant = load_json("res://data/settings/%s.json" % settings_name)
	if data == null:
		return {}
	return data


func clear_cache() -> void:
	_cache.clear()
