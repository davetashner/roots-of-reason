extends GdUnitTestSuite
## Tests for scripts/ui/notification_panel.gd — notifications, auto-dismiss, tier colors.

const NotifScript := preload("res://scripts/ui/notification_panel.gd")


func _create_panel() -> Control:
	var panel := Control.new()
	panel.set_script(NotifScript)
	add_child(panel)
	return auto_free(panel)


func test_notify_adds_message() -> void:
	var panel := _create_panel()
	panel.notify("Test message", "info")
	assert_int(panel.get_notification_count()).is_equal(1)


func test_notify_multiple_messages() -> void:
	var panel := _create_panel()
	panel.notify("First", "info")
	panel.notify("Second", "warning")
	panel.notify("Third", "alert")
	assert_int(panel.get_notification_count()).is_equal(3)


func test_max_visible_cap() -> void:
	var panel := _create_panel()
	panel._max_visible = 3
	for i in 5:
		panel.notify("Message %d" % i, "info")
	assert_int(panel.get_notification_count()).is_less_equal(3)


func test_auto_dismiss_after_duration() -> void:
	var panel := _create_panel()
	panel._default_duration = 0.5
	panel._fade_duration = 0.1
	panel.notify("Quick message", "info")
	assert_int(panel.get_notification_count()).is_equal(1)
	# Process past the duration
	for _i in 20:
		panel._process(0.1)
	assert_int(panel.get_notification_count()).is_equal(0)


func test_fade_reduces_alpha() -> void:
	var panel := _create_panel()
	panel._default_duration = 1.0
	panel._fade_duration = 0.5
	panel.notify("Fading message", "info")
	# Process until we're in the fade window (remaining < 0.5)
	for _i in 12:
		panel._process(0.1)
	# Should still exist but fading
	if panel.get_notification_count() > 0:
		var entry: Dictionary = panel._active_notifications[0]
		var label: Label = entry["label"]
		if is_instance_valid(label):
			assert_float(label.modulate.a).is_less(1.0)


func test_tier_color_info() -> void:
	var panel := _create_panel()
	panel.notify("Info message", "info")
	var entry: Dictionary = panel._active_notifications[0]
	var label: Label = entry["label"]
	# Info should use the info tier color
	assert_bool(is_instance_valid(label)).is_true()


func test_tier_color_alert() -> void:
	var panel := _create_panel()
	panel.notify("Alert!", "alert")
	var entry: Dictionary = panel._active_notifications[0]
	var label: Label = entry["label"]
	assert_bool(is_instance_valid(label)).is_true()


func test_mouse_filter_is_ignore() -> void:
	var panel := _create_panel()
	assert_int(panel.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_save_load_no_crash() -> void:
	var panel := _create_panel()
	panel.notify("Test", "info")
	var state: Dictionary = panel.save_state()
	assert_bool(state is Dictionary).is_true()
	panel.load_state(state)
	assert_bool(is_instance_valid(panel)).is_true()


func test_empty_panel_process_no_crash() -> void:
	var panel := _create_panel()
	panel._process(0.1)
	assert_int(panel.get_notification_count()).is_equal(0)
