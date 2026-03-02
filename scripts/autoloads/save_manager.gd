extends Node
## Orchestrates save/load file I/O for game state.
## Collects save_state() from autoloads (GameManager, ResourceManager,
## CivBonusManager) and optionally from a registered scene provider
## (prototype_main) for full scene entity persistence.

signal load_complete

const SAVE_DIR := "user://saves/"
const MAX_SLOTS := 3
const SAVE_VERSION := 2

var _scene_provider: Node = null


func register_scene_provider(node: Node) -> void:
	_scene_provider = node


func save_game(slot: int) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		push_error("SaveManager: Invalid slot %d" % slot)
		return false
	_ensure_save_dir()
	var data := {
		"version": SAVE_VERSION,
		"timestamp": Time.get_unix_time_from_system(),
		"game_manager": GameManager.save_state(),
		"resource_manager": ResourceManager.save_state(),
		"civ_bonus_manager": CivBonusManager.save_state(),
		"audio_manager": AudioManager.save_state(),
	}
	if _scene_provider != null and _scene_provider.has_method("save_state"):
		data["scene"] = _scene_provider.save_state()
	var json_str := JSON.stringify(data, "\t")
	var path := _slot_path(slot)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: Failed to open %s for writing: %s" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(json_str)
	file.close()
	return true


func load_game(slot: int) -> Dictionary:
	if slot < 0 or slot >= MAX_SLOTS:
		push_error("SaveManager: Invalid slot %d" % slot)
		return {}
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SaveManager: Failed to open %s for reading" % path)
		return {}
	var json_str := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_str)
	if parsed == null or not (parsed is Dictionary):
		push_error("SaveManager: Failed to parse save file %s" % path)
		return {}
	var data: Dictionary = parsed as Dictionary
	var version: int = int(data.get("version", 1))
	if version < 2:
		data = _migrate_v1_to_v2(data)
	return data


func apply_loaded_state(data: Dictionary) -> void:
	if data.has("game_manager"):
		GameManager.load_state(data["game_manager"])
	if data.has("resource_manager"):
		ResourceManager.load_state(data["resource_manager"])
	if data.has("civ_bonus_manager"):
		CivBonusManager.load_state(data["civ_bonus_manager"])
	if data.has("audio_manager"):
		AudioManager.load_state(data["audio_manager"])
	if data.has("scene") and _scene_provider != null and _scene_provider.has_method("load_state"):
		await _scene_provider.load_state(data["scene"])
	load_complete.emit()


func get_save_info(slot: int) -> Dictionary:
	if slot < 0 or slot >= MAX_SLOTS:
		return {"exists": false}
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return {"exists": false}
	var data := load_game(slot)
	if data.is_empty():
		return {"exists": false}
	var gm: Dictionary = data.get("game_manager", {})
	var civs: Dictionary = gm.get("player_civilizations", {})
	var civ_name: String = str(civs.get("0", civs.get(0, "Unknown")))
	var age_idx: int = int(gm.get("current_age", 0))
	var age_name: String = "Unknown"
	if age_idx >= 0 and age_idx < GameManager.AGE_NAMES.size():
		age_name = GameManager.AGE_NAMES[age_idx]
	return {
		"exists": true,
		"timestamp": float(data.get("timestamp", 0.0)),
		"civ_name": civ_name,
		"age_name": age_name,
	}


func delete_save(slot: int) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		return false
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return false
	var err := DirAccess.remove_absolute(path)
	return err == OK


func _slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d.json" % slot


func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func _migrate_v1_to_v2(data: Dictionary) -> Dictionary:
	if not data.has("scene"):
		data["scene"] = {}
	data["version"] = 2
	return data
