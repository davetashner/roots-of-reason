extends GdUnitTestSuite
## Tests for pause_menu.gd

const PauseMenuScript := preload("res://scripts/ui/pause_menu.gd")

var _menu: PanelContainer
var _original_paused: bool


func before_test() -> void:
	_original_paused = GameManager.is_paused
	_menu = PanelContainer.new()
	_menu.set_script(PauseMenuScript)
	add_child(_menu)
	# Wait for _ready to fire
	await get_tree().process_frame


func after_test() -> void:
	GameManager.is_paused = _original_paused
	if is_instance_valid(_menu):
		_menu.queue_free()


func test_menu_starts_hidden() -> void:
	assert_bool(_menu.visible).is_false()


func test_show_menu_makes_visible_and_pauses() -> void:
	_menu.show_menu()
	assert_bool(_menu.visible).is_true()
	assert_bool(GameManager.is_paused).is_true()


func test_hide_menu_makes_invisible_and_resumes() -> void:
	_menu.show_menu()
	_menu.hide_menu()
	assert_bool(_menu.visible).is_false()
	assert_bool(GameManager.is_paused).is_false()


func test_resume_button_hides_menu() -> void:
	_menu.show_menu()
	var resume_btn := _find_button("ResumeButton")
	assert_object(resume_btn).is_not_null()
	resume_btn.pressed.emit()
	assert_bool(_menu.visible).is_false()


func test_main_panel_has_six_buttons() -> void:
	var main_panel: VBoxContainer = _menu._main_vbox
	assert_object(main_panel).is_not_null()
	var button_count := 0
	for child in main_panel.get_children():
		if child is Button:
			button_count += 1
	assert_int(button_count).is_equal(6)


func test_save_panel_toggles_on() -> void:
	_menu.show_menu()
	var save_btn := _find_button("SaveButton")
	assert_object(save_btn).is_not_null()
	save_btn.pressed.emit()
	assert_bool(_menu._save_panel.visible).is_true()
	assert_bool(_menu._main_vbox.visible).is_false()


func test_load_panel_toggles_on() -> void:
	_menu.show_menu()
	var load_btn := _find_button("LoadButton")
	assert_object(load_btn).is_not_null()
	load_btn.pressed.emit()
	assert_bool(_menu._load_panel.visible).is_true()
	assert_bool(_menu._main_vbox.visible).is_false()


func test_settings_panel_toggles_on() -> void:
	_menu.show_menu()
	var settings_btn := _find_button("SettingsButton")
	assert_object(settings_btn).is_not_null()
	settings_btn.pressed.emit()
	assert_bool(_menu._settings_panel.visible).is_true()
	assert_bool(_menu._main_vbox.visible).is_false()


func test_resumed_signal_emitted() -> void:
	var signal_emitted := [false]
	_menu.resumed.connect(func() -> void: signal_emitted[0] = true)
	_menu.show_menu()
	var resume_btn := _find_button("ResumeButton")
	resume_btn.pressed.emit()
	assert_bool(signal_emitted[0]).is_true()


func test_quit_to_menu_signal_emitted() -> void:
	var signal_emitted := [false]
	_menu.quit_to_menu.connect(func() -> void: signal_emitted[0] = true)
	_menu.show_menu()
	var btn := _find_button("QuitMenuButton")
	btn.pressed.emit()
	assert_bool(signal_emitted[0]).is_true()


func test_quit_to_desktop_signal_emitted() -> void:
	var signal_emitted := [false]
	_menu.quit_to_desktop.connect(func() -> void: signal_emitted[0] = true)
	_menu.show_menu()
	var btn := _find_button("QuitDesktopButton")
	btn.pressed.emit()
	assert_bool(signal_emitted[0]).is_true()


func _find_button(button_name: String) -> Button:
	return _find_child_recursive(_menu, button_name) as Button


func _find_child_recursive(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var result := _find_child_recursive(child, target_name)
		if result != null:
			return result
	return null
