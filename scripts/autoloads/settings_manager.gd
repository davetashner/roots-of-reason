extends Node
## Manages game settings with JSON-backed persistence.
## Controls audio bus volumes, graphics settings, difficulty, hotkeys,
## and tutorial state. Saves to user://settings.json on every change.

const SETTINGS_PATH := "user://settings.json"

# Audio
var _master_volume: float = 1.0
var _music_volume: float = 0.8
var _sfx_volume: float = 1.0
var _ambient_volume: float = 0.7
var _ui_volume: float = 1.0

# Graphics
var _fullscreen: bool = false
var _vsync: bool = true

# Gameplay
var _difficulty: int = 1
var _tutorial_completed: bool = false

# Hotkey bindings: action_name -> key_scancode
var _hotkey_bindings: Dictionary = {}

var _config_path: String = SETTINGS_PATH


func _ready() -> void:
	_load()
	_apply_all()


func get_master_volume() -> float:
	return _master_volume


func get_music_volume() -> float:
	return _music_volume


func get_sfx_volume() -> float:
	return _sfx_volume


func get_ambient_volume() -> float:
	return _ambient_volume


func get_ui_volume() -> float:
	return _ui_volume


func is_fullscreen() -> bool:
	return _fullscreen


func is_vsync() -> bool:
	return _vsync


func get_difficulty() -> int:
	return _difficulty


func is_tutorial_completed() -> bool:
	return _tutorial_completed


func get_hotkey_bindings() -> Dictionary:
	return _hotkey_bindings.duplicate()


func set_master_volume(value: float) -> void:
	_master_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume("Master", _master_volume)
	_save()


func set_music_volume(value: float) -> void:
	_music_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume("Music", _music_volume)
	_save()


func set_sfx_volume(value: float) -> void:
	_sfx_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume("SFX", _sfx_volume)
	_save()


func set_ambient_volume(value: float) -> void:
	_ambient_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume("Ambient", _ambient_volume)
	_save()


func set_ui_volume(value: float) -> void:
	_ui_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume("UI", _ui_volume)
	_save()


func set_fullscreen(enabled: bool) -> void:
	_fullscreen = enabled
	_apply_fullscreen()
	_save()


func set_vsync(enabled: bool) -> void:
	_vsync = enabled
	_apply_vsync()
	_save()


func set_difficulty(value: int) -> void:
	_difficulty = clampi(value, 0, 3)
	_save()


func set_tutorial_completed(value: bool) -> void:
	_tutorial_completed = value
	_save()


func set_hotkey_binding(action: String, value: Variant) -> void:
	_hotkey_bindings[action] = value
	_save()


func _apply_all() -> void:
	_apply_bus_volume("Master", _master_volume)
	_apply_bus_volume("Music", _music_volume)
	_apply_bus_volume("SFX", _sfx_volume)
	_apply_bus_volume("Ambient", _ambient_volume)
	_apply_bus_volume("UI", _ui_volume)
	_apply_fullscreen()
	_apply_vsync()


func _apply_bus_volume(bus_name: String, linear: float) -> void:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(linear))


func _apply_fullscreen() -> void:
	if _fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _apply_vsync() -> void:
	if _vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _to_dict() -> Dictionary:
	return {
		"audio":
		{
			"master_volume": _master_volume,
			"music_volume": _music_volume,
			"sfx_volume": _sfx_volume,
			"ambient_volume": _ambient_volume,
			"ui_volume": _ui_volume,
		},
		"graphics":
		{
			"fullscreen": _fullscreen,
			"vsync": _vsync,
		},
		"gameplay":
		{
			"difficulty": _difficulty,
			"tutorial_completed": _tutorial_completed,
		},
		"hotkeys": _hotkey_bindings.duplicate(),
	}


func _from_dict(data: Dictionary) -> void:
	var audio: Dictionary = data.get("audio", {})
	_master_volume = clampf(float(audio.get("master_volume", 1.0)), 0.0, 1.0)
	_music_volume = clampf(float(audio.get("music_volume", 0.8)), 0.0, 1.0)
	_sfx_volume = clampf(float(audio.get("sfx_volume", 1.0)), 0.0, 1.0)
	_ambient_volume = clampf(float(audio.get("ambient_volume", 0.7)), 0.0, 1.0)
	_ui_volume = clampf(float(audio.get("ui_volume", 1.0)), 0.0, 1.0)

	var graphics: Dictionary = data.get("graphics", {})
	_fullscreen = bool(graphics.get("fullscreen", false))
	_vsync = bool(graphics.get("vsync", true))

	var gameplay: Dictionary = data.get("gameplay", {})
	_difficulty = clampi(int(gameplay.get("difficulty", 1)), 0, 3)
	_tutorial_completed = bool(gameplay.get("tutorial_completed", false))

	var hotkeys: Variant = data.get("hotkeys", {})
	if hotkeys is Dictionary:
		_hotkey_bindings = {}
		for key: String in hotkeys.keys():
			var val: Variant = hotkeys[key]
			if val is Dictionary:
				_hotkey_bindings[key] = {
					"keycode": int(val.get("keycode", 0)),
					"modifiers": int(val.get("modifiers", 0)),
				}
			else:
				_hotkey_bindings[key] = int(val)
	else:
		_hotkey_bindings = {}


func _save() -> void:
	var json_str := JSON.stringify(_to_dict(), "\t")
	var file := FileAccess.open(_config_path, FileAccess.WRITE)
	if file == null:
		push_warning(
			(
				"SettingsManager: Failed to save settings to %s: %s"
				% [_config_path, error_string(FileAccess.get_open_error())]
			)
		)
		return
	file.store_string(json_str)
	file.close()


func _load() -> void:
	if not FileAccess.file_exists(_config_path):
		_save()
		return
	var file := FileAccess.open(_config_path, FileAccess.READ)
	if file == null:
		push_warning("SettingsManager: Failed to open %s for reading" % _config_path)
		return
	var json_str := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_str)
	if parsed == null or not (parsed is Dictionary):
		push_warning("SettingsManager: Corrupt settings file %s, using defaults" % _config_path)
		_save()
		return
	_from_dict(parsed as Dictionary)


func _reset_defaults() -> void:
	_master_volume = 1.0
	_music_volume = 0.8
	_sfx_volume = 1.0
	_ambient_volume = 0.7
	_ui_volume = 1.0
	_fullscreen = false
	_vsync = true
	_difficulty = 1
	_tutorial_completed = false
	_hotkey_bindings = {}
