class_name AIPersonality
extends RefCounted
## Loads AI personality definitions from personalities.json and applies
## multiplier modifiers on top of difficulty-based configs. Personality is
## a modifier layer — difficulty sets the baseline, personality adjusts it.

static var _all_personalities: Dictionary = {}

var personality_id: String = ""
var _data: Dictionary = {}


static func load_all() -> Dictionary:
	if not _all_personalities.is_empty():
		return _all_personalities
	var data: Variant = DataLoader.load_json("res://data/ai/personalities.json")
	if data == null or not data is Dictionary:
		return {}
	for pid: String in data:
		var p := AIPersonality.new()
		p.personality_id = pid
		p._data = data[pid]
		_all_personalities[pid] = p
	return _all_personalities


static func get_personality(pid: String) -> AIPersonality:
	var all := load_all()
	return all.get(pid, null)


static func get_random_id() -> String:
	var all := load_all()
	if all.is_empty():
		return "builder"
	var keys: Array = all.keys()
	return keys[randi() % keys.size()]


static func clear_cache() -> void:
	_all_personalities.clear()


func get_name() -> String:
	return str(_data.get("name", personality_id))


func get_description() -> String:
	return str(_data.get("description", ""))


func get_tech_personality() -> String:
	return str(_data.get("tech_personality", "balanced"))


func get_build_order_override() -> String:
	return str(_data.get("build_order_override", ""))


func apply_economy_modifiers(base_config: Dictionary) -> Dictionary:
	var config := base_config.duplicate()
	var mods: Dictionary = _data.get("economy_modifiers", {})
	if mods.has("max_villagers_multiplier") and config.has("max_villagers"):
		config["max_villagers"] = int(float(config["max_villagers"]) * float(mods["max_villagers_multiplier"]))
	return config


func apply_military_modifiers(base_config: Dictionary) -> Dictionary:
	var config := base_config.duplicate()
	var mods: Dictionary = _data.get("military_modifiers", {})
	var key_map: Dictionary = {
		"army_attack_threshold_multiplier": "army_attack_threshold",
		"min_attack_game_time_multiplier": "min_attack_game_time",
		"attack_cooldown_multiplier": "attack_cooldown",
		"max_military_pop_ratio_multiplier": "max_military_pop_ratio",
		"military_budget_ratio_multiplier": "military_budget_ratio",
		"retreat_hp_ratio_multiplier": "retreat_hp_ratio",
	}
	for mod_key: String in key_map:
		if not mods.has(mod_key):
			continue
		var config_key: String = key_map[mod_key]
		if not config.has(config_key):
			continue
		var base_val: float = float(config[config_key])
		var multiplier: float = float(mods[mod_key])
		# Integer fields stay integer
		if config_key == "army_attack_threshold":
			config[config_key] = int(base_val * multiplier)
		else:
			config[config_key] = base_val * multiplier
	return config
