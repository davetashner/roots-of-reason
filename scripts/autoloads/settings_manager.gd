extends Node
## Manages game settings with ConfigFile-backed persistence.
## Controls audio bus volumes, fullscreen, and vsync.

const SETTINGS_PATH := "user://settings.cfg"

var _master_volume: float = 1.0
var _music_volume: float = 0.8
var _sfx_volume: float = 1.0
var _fullscreen: bool = false
var _vsync: bool = true
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


func is_fullscreen() -> bool:
	return _fullscreen


func is_vsync() -> bool:
	return _vsync


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


func set_fullscreen(enabled: bool) -> void:
	_fullscreen = enabled
	_apply_fullscreen()
	_save()


func set_vsync(enabled: bool) -> void:
	_vsync = enabled
	_apply_vsync()
	_save()


func _apply_all() -> void:
	_apply_bus_volume("Master", _master_volume)
	_apply_bus_volume("Music", _music_volume)
	_apply_bus_volume("SFX", _sfx_volume)
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


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", _master_volume)
	config.set_value("audio", "music_volume", _music_volume)
	config.set_value("audio", "sfx_volume", _sfx_volume)
	config.set_value("display", "fullscreen", _fullscreen)
	config.set_value("display", "vsync", _vsync)
	config.save(_config_path)


func _load() -> void:
	var config := ConfigFile.new()
	var err := config.load(_config_path)
	if err != OK:
		return
	_master_volume = clampf(config.get_value("audio", "master_volume", 1.0), 0.0, 1.0)
	_music_volume = clampf(config.get_value("audio", "music_volume", 0.8), 0.0, 1.0)
	_sfx_volume = clampf(config.get_value("audio", "sfx_volume", 1.0), 0.0, 1.0)
	_fullscreen = config.get_value("display", "fullscreen", false)
	_vsync = config.get_value("display", "vsync", true)
