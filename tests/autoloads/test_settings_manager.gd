extends GdUnitTestSuite
## Tests for settings_manager.gd — audio/display/gameplay settings with JSON persistence.

const TEST_CONFIG_PATH := "user://test_settings.json"


func before_test() -> void:
	SettingsManager._config_path = TEST_CONFIG_PATH
	SettingsManager._reset_defaults()


func after_test() -> void:
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	SettingsManager._config_path = SettingsManager.SETTINGS_PATH
	SettingsManager._reset_defaults()


func test_default_master_volume() -> void:
	assert_float(SettingsManager.get_master_volume()).is_equal(1.0)


func test_default_music_volume() -> void:
	assert_float(SettingsManager.get_music_volume()).is_equal(0.8)


func test_default_sfx_volume() -> void:
	assert_float(SettingsManager.get_sfx_volume()).is_equal(1.0)


func test_default_ambient_volume() -> void:
	assert_float(SettingsManager.get_ambient_volume()).is_equal(0.7)


func test_default_ui_volume() -> void:
	assert_float(SettingsManager.get_ui_volume()).is_equal(1.0)


func test_default_fullscreen() -> void:
	assert_bool(SettingsManager.is_fullscreen()).is_false()


func test_default_vsync() -> void:
	assert_bool(SettingsManager.is_vsync()).is_true()


func test_default_difficulty() -> void:
	assert_int(SettingsManager.get_difficulty()).is_equal(1)


func test_default_tutorial_completed() -> void:
	assert_bool(SettingsManager.is_tutorial_completed()).is_false()


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


func test_set_ambient_volume_roundtrip() -> void:
	SettingsManager.set_ambient_volume(0.35)
	assert_float(SettingsManager.get_ambient_volume()).is_equal_approx(0.35, 0.01)


func test_set_ui_volume_roundtrip() -> void:
	SettingsManager.set_ui_volume(0.65)
	assert_float(SettingsManager.get_ui_volume()).is_equal_approx(0.65, 0.01)


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


func test_set_difficulty_roundtrip() -> void:
	SettingsManager.set_difficulty(2)
	assert_int(SettingsManager.get_difficulty()).is_equal(2)


func test_set_difficulty_clamps() -> void:
	SettingsManager.set_difficulty(10)
	assert_int(SettingsManager.get_difficulty()).is_equal(3)
	SettingsManager.set_difficulty(-1)
	assert_int(SettingsManager.get_difficulty()).is_equal(0)


func test_set_tutorial_completed() -> void:
	SettingsManager.set_tutorial_completed(true)
	assert_bool(SettingsManager.is_tutorial_completed()).is_true()


func test_set_hotkey_binding() -> void:
	SettingsManager.set_hotkey_binding("move_up", 87)
	var bindings := SettingsManager.get_hotkey_bindings()
	assert_int(int(bindings.get("move_up", 0))).is_equal(87)


func test_save_and_reload_volume() -> void:
	SettingsManager.set_master_volume(0.33)
	SettingsManager.set_music_volume(0.55)
	SettingsManager.set_sfx_volume(0.77)
	SettingsManager.set_ambient_volume(0.45)
	SettingsManager.set_ui_volume(0.62)
	SettingsManager.set_fullscreen(true)
	SettingsManager.set_vsync(false)
	SettingsManager.set_difficulty(2)
	SettingsManager.set_tutorial_completed(true)
	SettingsManager.set_hotkey_binding("attack", 65)
	# Reset in-memory values to defaults
	SettingsManager._reset_defaults()
	# Verify defaults are active
	assert_float(SettingsManager.get_master_volume()).is_equal(1.0)
	# Reload from file
	SettingsManager._load()
	assert_float(SettingsManager.get_master_volume()).is_equal_approx(0.33, 0.01)
	assert_float(SettingsManager.get_music_volume()).is_equal_approx(0.55, 0.01)
	assert_float(SettingsManager.get_sfx_volume()).is_equal_approx(0.77, 0.01)
	assert_float(SettingsManager.get_ambient_volume()).is_equal_approx(0.45, 0.01)
	assert_float(SettingsManager.get_ui_volume()).is_equal_approx(0.62, 0.01)
	assert_bool(SettingsManager.is_fullscreen()).is_true()
	assert_bool(SettingsManager.is_vsync()).is_false()
	assert_int(SettingsManager.get_difficulty()).is_equal(2)
	assert_bool(SettingsManager.is_tutorial_completed()).is_true()
	var bindings := SettingsManager.get_hotkey_bindings()
	assert_int(int(bindings.get("attack", 0))).is_equal(65)


func test_missing_file_creates_defaults() -> void:
	# Ensure no file exists
	if FileAccess.file_exists(TEST_CONFIG_PATH):
		DirAccess.remove_absolute(TEST_CONFIG_PATH)
	# Load with no file — should create defaults file
	SettingsManager._load()
	assert_float(SettingsManager.get_master_volume()).is_equal(1.0)
	assert_float(SettingsManager.get_music_volume()).is_equal(0.8)
	assert_float(SettingsManager.get_sfx_volume()).is_equal(1.0)
	assert_float(SettingsManager.get_ambient_volume()).is_equal(0.7)
	assert_float(SettingsManager.get_ui_volume()).is_equal(1.0)
	assert_bool(SettingsManager.is_fullscreen()).is_false()
	assert_bool(SettingsManager.is_vsync()).is_true()
	assert_int(SettingsManager.get_difficulty()).is_equal(1)
	assert_bool(SettingsManager.is_tutorial_completed()).is_false()
	# File should now exist with defaults
	assert_bool(FileAccess.file_exists(TEST_CONFIG_PATH)).is_true()


func test_corrupt_file_recovers() -> void:
	# Write corrupt JSON to file
	var file := FileAccess.open(TEST_CONFIG_PATH, FileAccess.WRITE)
	file.store_string("{{not valid json!!!")
	file.close()
	# Load should recover gracefully with defaults
	SettingsManager._load()
	assert_float(SettingsManager.get_master_volume()).is_equal(1.0)
	assert_float(SettingsManager.get_music_volume()).is_equal(0.8)
	assert_float(SettingsManager.get_sfx_volume()).is_equal(1.0)
	assert_float(SettingsManager.get_ambient_volume()).is_equal(0.7)
	assert_float(SettingsManager.get_ui_volume()).is_equal(1.0)
	assert_bool(SettingsManager.is_fullscreen()).is_false()
	assert_bool(SettingsManager.is_vsync()).is_true()
	assert_int(SettingsManager.get_difficulty()).is_equal(1)
	assert_bool(SettingsManager.is_tutorial_completed()).is_false()


func test_persistence_roundtrip() -> void:
	SettingsManager.set_master_volume(0.33)
	SettingsManager.set_music_volume(0.55)
	SettingsManager.set_sfx_volume(0.77)
	SettingsManager.set_fullscreen(true)
	SettingsManager.set_vsync(false)
	# Reset in-memory values
	SettingsManager._reset_defaults()
	# Reload from file
	SettingsManager._load()
	assert_float(SettingsManager.get_master_volume()).is_equal_approx(0.33, 0.01)
	assert_float(SettingsManager.get_music_volume()).is_equal_approx(0.55, 0.01)
	assert_float(SettingsManager.get_sfx_volume()).is_equal_approx(0.77, 0.01)
	assert_bool(SettingsManager.is_fullscreen()).is_true()
	assert_bool(SettingsManager.is_vsync()).is_false()
