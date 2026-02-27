extends GdUnitTestSuite
## Tests for settings_manager.gd — audio/display settings with persistence.

const TEST_CONFIG_PATH := "user://test_settings.cfg"


func before_test() -> void:
	SettingsManager._config_path = TEST_CONFIG_PATH
	SettingsManager._master_volume = 1.0
	SettingsManager._music_volume = 0.8
	SettingsManager._sfx_volume = 1.0
	SettingsManager._fullscreen = false
	SettingsManager._vsync = true


func after_test() -> void:
	DirAccess.remove_absolute(TEST_CONFIG_PATH)
	SettingsManager._config_path = SettingsManager.SETTINGS_PATH
	SettingsManager._master_volume = 1.0
	SettingsManager._music_volume = 0.8
	SettingsManager._sfx_volume = 1.0
	SettingsManager._fullscreen = false
	SettingsManager._vsync = true


func test_default_master_volume() -> void:
	assert_float(SettingsManager.get_master_volume()).is_equal(1.0)


func test_default_music_volume() -> void:
	assert_float(SettingsManager.get_music_volume()).is_equal(0.8)


func test_default_sfx_volume() -> void:
	assert_float(SettingsManager.get_sfx_volume()).is_equal(1.0)


func test_default_fullscreen() -> void:
	assert_bool(SettingsManager.is_fullscreen()).is_false()


func test_default_vsync() -> void:
	assert_bool(SettingsManager.is_vsync()).is_true()


func test_set_master_volume_clamps_above() -> void:
	SettingsManager.set_master_volume(1.5)
	assert_float(SettingsManager.get_master_volume()).is_equal(1.0)


func test_set_master_volume_clamps_below() -> void:
	SettingsManager.set_master_volume(-0.5)
	assert_float(SettingsManager.get_master_volume()).is_equal(0.0)


func test_set_music_volume_roundtrip() -> void:
	SettingsManager.set_music_volume(0.42)
	assert_float(SettingsManager.get_music_volume()).is_equal_approx(0.42, 0.01)


func test_set_sfx_volume_roundtrip() -> void:
	SettingsManager.set_sfx_volume(0.77)
	assert_float(SettingsManager.get_sfx_volume()).is_equal_approx(0.77, 0.01)


func test_set_fullscreen_roundtrip() -> void:
	SettingsManager.set_fullscreen(true)
	assert_bool(SettingsManager.is_fullscreen()).is_true()
	SettingsManager.set_fullscreen(false)
	assert_bool(SettingsManager.is_fullscreen()).is_false()


func test_set_vsync_roundtrip() -> void:
	SettingsManager.set_vsync(false)
	assert_bool(SettingsManager.is_vsync()).is_false()
	SettingsManager.set_vsync(true)
	assert_bool(SettingsManager.is_vsync()).is_true()


func test_persistence_roundtrip() -> void:
	SettingsManager.set_master_volume(0.33)
	SettingsManager.set_music_volume(0.55)
	SettingsManager.set_sfx_volume(0.77)
	SettingsManager.set_fullscreen(true)
	SettingsManager.set_vsync(false)
	# Reset in-memory values
	SettingsManager._master_volume = 1.0
	SettingsManager._music_volume = 0.8
	SettingsManager._sfx_volume = 1.0
	SettingsManager._fullscreen = false
	SettingsManager._vsync = true
	# Reload from file
	SettingsManager._load()
	assert_float(SettingsManager.get_master_volume()).is_equal_approx(0.33, 0.01)
	assert_float(SettingsManager.get_music_volume()).is_equal_approx(0.55, 0.01)
	assert_float(SettingsManager.get_sfx_volume()).is_equal_approx(0.77, 0.01)
	assert_bool(SettingsManager.is_fullscreen()).is_true()
	assert_bool(SettingsManager.is_vsync()).is_false()
