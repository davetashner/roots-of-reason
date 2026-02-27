extends GdUnitTestSuite
## Tests for settings_panel.gd — reusable settings UI panel.

const SettingsPanelScript := preload("res://scripts/ui/settings_panel.gd")


func _create_panel(back_callback: Callable = func() -> void: pass) -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.set_script(SettingsPanelScript)
	add_child(panel)
	panel.build(back_callback)
	auto_free(panel)
	return panel


func test_has_master_slider() -> void:
	var panel := _create_panel()
	var slider := panel.find_child("MasterSlider", true, false)
	assert_object(slider).is_not_null()
	assert_object(slider).is_instanceof(HSlider)


func test_has_music_slider() -> void:
	var panel := _create_panel()
	var slider := panel.find_child("MusicSlider", true, false)
	assert_object(slider).is_not_null()
	assert_object(slider).is_instanceof(HSlider)


func test_has_sfx_slider() -> void:
	var panel := _create_panel()
	var slider := panel.find_child("SFXSlider", true, false)
	assert_object(slider).is_not_null()
	assert_object(slider).is_instanceof(HSlider)


func test_has_fullscreen_check() -> void:
	var panel := _create_panel()
	var check := panel.find_child("FullscreenCheck", true, false)
	assert_object(check).is_not_null()
	assert_object(check).is_instanceof(CheckButton)


func test_has_vsync_check() -> void:
	var panel := _create_panel()
	var check := panel.find_child("VsyncCheck", true, false)
	assert_object(check).is_not_null()
	assert_object(check).is_instanceof(CheckButton)


func test_has_back_button() -> void:
	var panel := _create_panel()
	var btn := panel.find_child("SettingsBackButton", true, false)
	assert_object(btn).is_not_null()
	assert_object(btn).is_instanceof(Button)


func test_initial_values_match_settings_manager() -> void:
	var panel := _create_panel()
	var master_slider: HSlider = panel.find_child("MasterSlider", true, false)
	var music_slider: HSlider = panel.find_child("MusicSlider", true, false)
	var sfx_slider: HSlider = panel.find_child("SFXSlider", true, false)
	var fs_check: CheckButton = panel.find_child("FullscreenCheck", true, false)
	var vs_check: CheckButton = panel.find_child("VsyncCheck", true, false)
	assert_float(master_slider.value).is_equal_approx(SettingsManager.get_master_volume(), 0.01)
	assert_float(music_slider.value).is_equal_approx(SettingsManager.get_music_volume(), 0.01)
	assert_float(sfx_slider.value).is_equal_approx(SettingsManager.get_sfx_volume(), 0.01)
	assert_bool(fs_check.button_pressed).is_equal(SettingsManager.is_fullscreen())
	assert_bool(vs_check.button_pressed).is_equal(SettingsManager.is_vsync())


func test_back_button_fires_callback() -> void:
	var called := [false]
	var panel := _create_panel(func() -> void: called[0] = true)
	var btn: Button = panel.find_child("SettingsBackButton", true, false)
	btn.pressed.emit()
	assert_bool(called[0]).is_true()


func test_slider_change_updates_settings_manager() -> void:
	var old_volume := SettingsManager.get_master_volume()
	var panel := _create_panel()
	var slider: HSlider = panel.find_child("MasterSlider", true, false)
	slider.value = 0.42
	assert_float(SettingsManager.get_master_volume()).is_equal_approx(0.42, 0.01)
	# Restore
	SettingsManager.set_master_volume(old_volume)
