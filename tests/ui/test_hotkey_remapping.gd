extends GdUnitTestSuite
## Tests for hotkey_remapping.gd — hotkey rebinding UI.

const HotkeyRemappingScript := preload("res://scripts/ui/hotkey_remapping.gd")

var _saved_bindings: Dictionary = {}


func before() -> void:
	_saved_bindings = SettingsManager.get_hotkey_bindings()


func before_test() -> void:
	# Clear all hotkey bindings so each test starts from defaults
	_clear_all_hotkey_bindings()


func after() -> void:
	# Restore original bindings
	for action: String in _saved_bindings:
		SettingsManager.set_hotkey_binding(action, _saved_bindings[action])
	# Clear any bindings added during tests
	var current := SettingsManager.get_hotkey_bindings()
	for action: String in current:
		if not _saved_bindings.has(action):
			SettingsManager.set_hotkey_binding(action, {})


func _clear_all_hotkey_bindings() -> void:
	var current := SettingsManager.get_hotkey_bindings()
	for action: String in current:
		SettingsManager.set_hotkey_binding(action, {})
	# Force internal dict to empty
	SettingsManager._hotkey_bindings = {}


func _create_section() -> VBoxContainer:
	var section := VBoxContainer.new()
	section.set_script(HotkeyRemappingScript)
	add_child(section)
	section.build()
	auto_free(section)
	return section


func test_has_hotkey_buttons_for_all_actions() -> void:
	var section := _create_section()
	for entry: Dictionary in HotkeyRemappingScript.BINDABLE_ACTIONS:
		var action: String = entry["action"]
		var btn := section.find_child("HotkeyBtn_" + action, true, false)
		assert_object(btn).is_not_null()
		assert_object(btn).is_instanceof(Button)


func test_has_reset_button() -> void:
	var section := _create_section()
	var btn := section.find_child("ResetHotkeysButton", true, false)
	assert_object(btn).is_not_null()
	assert_object(btn).is_instanceof(Button)


func test_has_conflict_dialog() -> void:
	var section := _create_section()
	var dialog := section.find_child("HotkeyConflictDialog", true, false)
	assert_object(dialog).is_not_null()
	assert_object(dialog).is_instanceof(ConfirmationDialog)


func test_default_display_text_for_camera_pan_up() -> void:
	var section := _create_section()
	var btn: Button = section.find_child("HotkeyBtn_camera_pan_up", true, false)
	assert_str(btn.text).is_equal("W")


func test_default_display_text_with_modifier() -> void:
	var section := _create_section()
	var btn: Button = section.find_child("HotkeyBtn_select_all_military", true, false)
	assert_str(btn.text).is_equal("Ctrl+A")


func test_clicking_button_shows_press_a_key() -> void:
	var section := _create_section()
	var btn: Button = section.find_child("HotkeyBtn_camera_pan_up", true, false)
	btn.pressed.emit()
	assert_str(btn.text).is_equal("Press a key...")
	assert_bool(section.is_awaiting_rebind()).is_true()
	assert_str(section.get_awaiting_action()).is_equal("camera_pan_up")


func test_rebind_updates_binding() -> void:
	var section := _create_section()
	var btn: Button = section.find_child("HotkeyBtn_camera_pan_up", true, false)
	# Start rebind
	btn.pressed.emit()
	# Simulate key press (T key)
	var key_event := InputEventKey.new()
	key_event.keycode = KEY_T
	key_event.pressed = true
	section._input(key_event)
	# Verify button text updated
	assert_str(btn.text).is_equal("T")
	# Verify persisted
	var binding: Dictionary = section.get_binding("camera_pan_up")
	assert_int(binding["keycode"]).is_equal(KEY_T)
	assert_int(binding["modifiers"]).is_equal(0)


func test_rebind_with_modifier() -> void:
	var section := _create_section()
	var btn: Button = section.find_child("HotkeyBtn_build_menu", true, false)
	btn.pressed.emit()
	var key_event := InputEventKey.new()
	key_event.keycode = KEY_F
	key_event.pressed = true
	key_event.ctrl_pressed = true
	section._input(key_event)
	assert_str(btn.text).is_equal("Ctrl+F")
	var binding: Dictionary = section.get_binding("build_menu")
	assert_int(binding["keycode"]).is_equal(KEY_F)
	assert_int(binding["modifiers"]).is_equal(KEY_MASK_CTRL)


func test_escape_cancels_rebind() -> void:
	var section := _create_section()
	var btn: Button = section.find_child("HotkeyBtn_camera_pan_up", true, false)
	var original_text := btn.text
	btn.pressed.emit()
	assert_str(btn.text).is_equal("Press a key...")
	# Press Escape
	var esc_event := InputEventKey.new()
	esc_event.keycode = KEY_ESCAPE
	esc_event.pressed = true
	section._input(esc_event)
	assert_str(btn.text).is_equal(original_text)
	assert_bool(section.is_awaiting_rebind()).is_false()


func test_conflict_detection_shows_dialog() -> void:
	var section := _create_section()
	# Rebind camera_pan_up to KEY_S (which is camera_pan_down's default)
	var btn: Button = section.find_child("HotkeyBtn_camera_pan_up", true, false)
	btn.pressed.emit()
	var key_event := InputEventKey.new()
	key_event.keycode = KEY_S  # Conflicts with camera_pan_down
	key_event.pressed = true
	section._input(key_event)
	# Dialog should be visible
	var dialog: ConfirmationDialog = section.find_child("HotkeyConflictDialog", true, false)
	assert_bool(dialog.visible).is_true()
	# Still in rebind mode (waiting for dialog resolution)
	assert_bool(section.is_awaiting_rebind()).is_true()


func test_conflict_swap_updates_both_bindings() -> void:
	var section := _create_section()
	# Rebind camera_pan_up (W) to S (conflicts with camera_pan_down)
	var up_btn: Button = section.find_child("HotkeyBtn_camera_pan_up", true, false)
	var down_btn: Button = section.find_child("HotkeyBtn_camera_pan_down", true, false)
	up_btn.pressed.emit()
	var key_event := InputEventKey.new()
	key_event.keycode = KEY_S
	key_event.pressed = true
	section._input(key_event)
	# Confirm swap
	var dialog: ConfirmationDialog = section.find_child("HotkeyConflictDialog", true, false)
	dialog.confirmed.emit()
	# camera_pan_up should now be S, camera_pan_down should now be W
	assert_str(up_btn.text).is_equal("S")
	assert_str(down_btn.text).is_equal("W")


func test_conflict_cancel_restores_original() -> void:
	var section := _create_section()
	var btn: Button = section.find_child("HotkeyBtn_camera_pan_up", true, false)
	btn.pressed.emit()
	var key_event := InputEventKey.new()
	key_event.keycode = KEY_S
	key_event.pressed = true
	section._input(key_event)
	# Cancel conflict
	var dialog: ConfirmationDialog = section.find_child("HotkeyConflictDialog", true, false)
	dialog.canceled.emit()
	assert_str(btn.text).is_equal("W")
	assert_bool(section.is_awaiting_rebind()).is_false()


func test_reset_to_defaults() -> void:
	var section := _create_section()
	# First rebind camera_pan_up to T
	var btn: Button = section.find_child("HotkeyBtn_camera_pan_up", true, false)
	btn.pressed.emit()
	var key_event := InputEventKey.new()
	key_event.keycode = KEY_T
	key_event.pressed = true
	section._input(key_event)
	assert_str(btn.text).is_equal("T")
	# Reset
	var reset_btn: Button = section.find_child("ResetHotkeysButton", true, false)
	reset_btn.pressed.emit()
	# Should be back to W
	assert_str(btn.text).is_equal("W")
	var binding: Dictionary = section.get_binding("camera_pan_up")
	assert_int(binding["keycode"]).is_equal(KEY_W)


func test_keycode_to_string_plain() -> void:
	var text := HotkeyRemappingScript._keycode_to_string(KEY_W, 0)
	assert_str(text).is_equal("W")


func test_keycode_to_string_with_ctrl() -> void:
	var text := HotkeyRemappingScript._keycode_to_string(KEY_A, KEY_MASK_CTRL)
	assert_str(text).is_equal("Ctrl+A")


func test_keycode_to_string_with_shift_alt() -> void:
	var text := HotkeyRemappingScript._keycode_to_string(KEY_F, KEY_MASK_SHIFT | KEY_MASK_ALT)
	assert_str(text).is_equal("Shift+Alt+F")


func test_bare_modifier_key_ignored_during_rebind() -> void:
	var section := _create_section()
	var btn: Button = section.find_child("HotkeyBtn_camera_pan_up", true, false)
	btn.pressed.emit()
	# Press bare Ctrl key — should stay in rebind mode
	var ctrl_event := InputEventKey.new()
	ctrl_event.keycode = KEY_CTRL
	ctrl_event.pressed = true
	section._input(ctrl_event)
	assert_str(btn.text).is_equal("Press a key...")
	assert_bool(section.is_awaiting_rebind()).is_true()


func test_rebind_signals_emitted() -> void:
	var section := _create_section()
	var started_actions: Array = []
	var completed_actions: Array = []
	section.rebind_started.connect(func(action: String) -> void: started_actions.append(action))
	section.rebind_completed.connect(func(action: String, _k: int, _m: int) -> void: completed_actions.append(action))
	var btn: Button = section.find_child("HotkeyBtn_build_menu", true, false)
	btn.pressed.emit()
	assert_array(started_actions).contains(["build_menu"])
	var key_event := InputEventKey.new()
	key_event.keycode = KEY_N
	key_event.pressed = true
	section._input(key_event)
	assert_array(completed_actions).contains(["build_menu"])


func test_no_conflict_when_same_action() -> void:
	# Rebinding an action to its own current key should not trigger conflict
	var section := _create_section()
	var btn: Button = section.find_child("HotkeyBtn_camera_pan_up", true, false)
	btn.pressed.emit()
	var key_event := InputEventKey.new()
	key_event.keycode = KEY_W  # Same as default
	key_event.pressed = true
	section._input(key_event)
	assert_str(btn.text).is_equal("W")
	assert_bool(section.is_awaiting_rebind()).is_false()
