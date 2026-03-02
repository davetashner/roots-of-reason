extends VBoxContainer
## Reusable settings panel with audio sliders and display toggles.
## Used by both main menu and pause menu.

const HotkeyRemappingScript := preload("res://scripts/ui/hotkey_remapping.gd")


func build(back_callback: Callable) -> void:
	add_theme_constant_override("separation", 12)
	custom_minimum_size = Vector2(400, 0)

	# Title
	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	add_child(title)

	# Audio section header
	var audio_label := Label.new()
	audio_label.text = "Audio"
	audio_label.add_theme_font_size_override("font_size", 20)
	audio_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	add_child(audio_label)

	# Volume sliders
	_add_slider_row("MasterSlider", "Master Volume", SettingsManager.get_master_volume(), _on_master_changed)
	_add_slider_row("MusicSlider", "Music Volume", SettingsManager.get_music_volume(), _on_music_changed)
	_add_slider_row("SFXSlider", "SFX Volume", SettingsManager.get_sfx_volume(), _on_sfx_changed)

	# Display section header
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	add_child(spacer)

	var display_label := Label.new()
	display_label.text = "Display"
	display_label.add_theme_font_size_override("font_size", 20)
	display_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	add_child(display_label)

	# Fullscreen checkbox
	_add_check_row("FullscreenCheck", "Fullscreen", SettingsManager.is_fullscreen(), _on_fullscreen_toggled)
	_add_check_row("VsyncCheck", "VSync", SettingsManager.is_vsync(), _on_vsync_toggled)

	# Hotkey section
	var hotkey_spacer := Control.new()
	hotkey_spacer.custom_minimum_size = Vector2(0, 8)
	add_child(hotkey_spacer)

	var hotkey_section := VBoxContainer.new()
	hotkey_section.set_script(HotkeyRemappingScript)
	add_child(hotkey_section)
	hotkey_section.build()

	# Back button
	var btn_spacer := Control.new()
	btn_spacer.custom_minimum_size = Vector2(0, 12)
	add_child(btn_spacer)

	var back_btn := Button.new()
	back_btn.name = "SettingsBackButton"
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(300, 40)
	back_btn.pressed.connect(back_callback)
	add_child(back_btn)


func _add_slider_row(slider_name: String, label_text: String, initial: float, callback: Callable) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	add_child(hbox)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(140, 0)
	hbox.add_child(label)

	var slider := HSlider.new()
	slider.name = slider_name
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = initial
	slider.custom_minimum_size = Vector2(180, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(slider)

	var pct_label := Label.new()
	pct_label.name = slider_name + "Pct"
	pct_label.text = "%d%%" % int(initial * 100)
	pct_label.custom_minimum_size = Vector2(50, 0)
	pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(pct_label)

	slider.value_changed.connect(
		func(value: float) -> void:
			pct_label.text = "%d%%" % int(value * 100)
			callback.call(value)
	)


func _add_check_row(check_name: String, label_text: String, initial: bool, callback: Callable) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	add_child(hbox)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(140, 0)
	hbox.add_child(label)

	var check := CheckButton.new()
	check.name = check_name
	check.button_pressed = initial
	check.toggled.connect(callback)
	hbox.add_child(check)


func _on_master_changed(value: float) -> void:
	SettingsManager.set_master_volume(value)


func _on_music_changed(value: float) -> void:
	SettingsManager.set_music_volume(value)


func _on_sfx_changed(value: float) -> void:
	SettingsManager.set_sfx_volume(value)


func _on_fullscreen_toggled(enabled: bool) -> void:
	SettingsManager.set_fullscreen(enabled)


func _on_vsync_toggled(enabled: bool) -> void:
	SettingsManager.set_vsync(enabled)
