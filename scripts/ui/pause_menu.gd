extends PanelContainer
## In-game pause menu overlay.
## Provides Resume, Save, Load, Settings, Quit to Menu, and Quit to Desktop.

signal resumed
signal quit_to_menu
signal quit_to_desktop

var _main_vbox: VBoxContainer = null
var _save_panel: VBoxContainer = null
var _load_panel: VBoxContainer = null
var _settings_panel: VBoxContainer = null
var _save_slot_buttons: Array[Button] = []
var _load_slot_buttons: Array[Button] = []
var _selected_save_slot: int = -1
var _selected_load_slot: int = -1
var _save_confirm_btn: Button = null
var _load_confirm_btn: Button = null
var _save_status_label: Label = null
var _load_status_label: Label = null


func _ready() -> void:
	visible = false
	_build_ui()


func show_menu() -> void:
	visible = true
	_show_main_panel()
	GameManager.pause()


func hide_menu() -> void:
	visible = false
	GameManager.resume()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	add_theme_stylebox_override("panel", style)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.custom_minimum_size = Vector2(400, 0)
	center.add_child(outer_vbox)

	_main_vbox = VBoxContainer.new()
	_main_vbox.name = "MainPanel"
	outer_vbox.add_child(_main_vbox)
	_build_main_panel(_main_vbox)

	_save_panel = VBoxContainer.new()
	_save_panel.name = "SavePanel"
	_save_panel.visible = false
	outer_vbox.add_child(_save_panel)
	_build_save_panel(_save_panel)

	_load_panel = VBoxContainer.new()
	_load_panel.name = "LoadPanel"
	_load_panel.visible = false
	outer_vbox.add_child(_load_panel)
	_build_load_panel(_load_panel)

	_settings_panel = VBoxContainer.new()
	_settings_panel.name = "SettingsPanel"
	_settings_panel.visible = false
	outer_vbox.add_child(_settings_panel)
	_build_settings_panel(_settings_panel)


func _build_main_panel(parent: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	parent.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	parent.add_child(spacer)

	var buttons_data := [
		["ResumeButton", "Resume", _on_resume_pressed],
		["SaveButton", "Save Game", _on_save_pressed],
		["LoadButton", "Load Game", _on_load_pressed],
		["SettingsButton", "Settings", _on_settings_pressed],
		["QuitMenuButton", "Quit to Menu", _on_quit_menu_pressed],
		["QuitDesktopButton", "Quit to Desktop", _on_quit_desktop_pressed],
	]
	for data: Array in buttons_data:
		var btn := Button.new()
		btn.name = data[0]
		btn.text = data[1]
		btn.custom_minimum_size = Vector2(300, 40)
		btn.pressed.connect(data[2])
		parent.add_child(btn)


func _build_save_panel(parent: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "Save Game"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	parent.add_child(title)

	var note := Label.new()
	note.text = "(Autoload state only)"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	parent.add_child(note)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	parent.add_child(spacer)

	_save_slot_buttons.clear()
	for i in SaveManager.MAX_SLOTS:
		var btn := Button.new()
		btn.name = "SaveSlot_%d" % i
		btn.custom_minimum_size = Vector2(300, 36)
		btn.pressed.connect(_on_save_slot_selected.bind(i))
		parent.add_child(btn)
		_save_slot_buttons.append(btn)

	var btn_spacer := Control.new()
	btn_spacer.custom_minimum_size = Vector2(0, 10)
	parent.add_child(btn_spacer)

	_save_status_label = Label.new()
	_save_status_label.name = "SaveStatusLabel"
	_save_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_status_label.text = ""
	parent.add_child(_save_status_label)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(hbox)

	_save_confirm_btn = Button.new()
	_save_confirm_btn.name = "SaveConfirmButton"
	_save_confirm_btn.text = "Save"
	_save_confirm_btn.custom_minimum_size = Vector2(120, 36)
	_save_confirm_btn.disabled = true
	_save_confirm_btn.pressed.connect(_on_save_confirm)
	hbox.add_child(_save_confirm_btn)

	var hbox_spacer := Control.new()
	hbox_spacer.custom_minimum_size = Vector2(10, 0)
	hbox.add_child(hbox_spacer)

	var back_btn := Button.new()
	back_btn.name = "SaveBackButton"
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(120, 36)
	back_btn.pressed.connect(_show_main_panel)
	hbox.add_child(back_btn)


func _build_load_panel(parent: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "Load Game"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	parent.add_child(title)

	var note := Label.new()
	note.text = "(Autoload state only)"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	parent.add_child(note)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	parent.add_child(spacer)

	_load_slot_buttons.clear()
	for i in SaveManager.MAX_SLOTS:
		var btn := Button.new()
		btn.name = "LoadSlot_%d" % i
		btn.custom_minimum_size = Vector2(300, 36)
		btn.pressed.connect(_on_load_slot_selected.bind(i))
		parent.add_child(btn)
		_load_slot_buttons.append(btn)

	var btn_spacer := Control.new()
	btn_spacer.custom_minimum_size = Vector2(0, 10)
	parent.add_child(btn_spacer)

	_load_status_label = Label.new()
	_load_status_label.name = "LoadStatusLabel"
	_load_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_load_status_label.text = ""
	parent.add_child(_load_status_label)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(hbox)

	_load_confirm_btn = Button.new()
	_load_confirm_btn.name = "LoadConfirmButton"
	_load_confirm_btn.text = "Load"
	_load_confirm_btn.custom_minimum_size = Vector2(120, 36)
	_load_confirm_btn.disabled = true
	_load_confirm_btn.pressed.connect(_on_load_confirm)
	hbox.add_child(_load_confirm_btn)

	var hbox_spacer := Control.new()
	hbox_spacer.custom_minimum_size = Vector2(10, 0)
	hbox.add_child(hbox_spacer)

	var back_btn := Button.new()
	back_btn.name = "LoadBackButton"
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(120, 36)
	back_btn.pressed.connect(_show_main_panel)
	hbox.add_child(back_btn)


func _build_settings_panel(parent: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	parent.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	parent.add_child(spacer)

	var placeholder := Label.new()
	placeholder.text = "Coming Soon"
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.add_theme_font_size_override("font_size", 20)
	placeholder.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	parent.add_child(placeholder)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	parent.add_child(spacer2)

	var back_btn := Button.new()
	back_btn.name = "SettingsBackButton"
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(300, 40)
	back_btn.pressed.connect(_show_main_panel)
	parent.add_child(back_btn)


func _show_main_panel() -> void:
	_main_vbox.visible = true
	_save_panel.visible = false
	_load_panel.visible = false
	_settings_panel.visible = false


func _on_resume_pressed() -> void:
	hide_menu()
	resumed.emit()


func _on_save_pressed() -> void:
	_main_vbox.visible = false
	_save_panel.visible = true
	_selected_save_slot = -1
	_save_confirm_btn.disabled = true
	_save_status_label.text = ""
	_refresh_save_slots()


func _on_load_pressed() -> void:
	_main_vbox.visible = false
	_load_panel.visible = true
	_selected_load_slot = -1
	_load_confirm_btn.disabled = true
	_load_status_label.text = ""
	_refresh_load_slots()


func _on_settings_pressed() -> void:
	_main_vbox.visible = false
	_settings_panel.visible = true


func _on_quit_menu_pressed() -> void:
	quit_to_menu.emit()


func _on_quit_desktop_pressed() -> void:
	quit_to_desktop.emit()


func _on_save_slot_selected(slot: int) -> void:
	_selected_save_slot = slot
	_save_confirm_btn.disabled = false
	_save_status_label.text = ""
	# Highlight selected slot
	for i in _save_slot_buttons.size():
		_save_slot_buttons[i].add_theme_color_override("font_color", Color.WHITE if i == slot else Color(0.8, 0.8, 0.8))


func _on_load_slot_selected(slot: int) -> void:
	var info := SaveManager.get_save_info(slot)
	if not info.get("exists", false):
		return
	_selected_load_slot = slot
	_load_confirm_btn.disabled = false
	_load_status_label.text = ""
	for i in _load_slot_buttons.size():
		_load_slot_buttons[i].add_theme_color_override("font_color", Color.WHITE if i == slot else Color(0.8, 0.8, 0.8))


func _on_save_confirm() -> void:
	if _selected_save_slot < 0:
		return
	var ok := SaveManager.save_game(_selected_save_slot)
	if ok:
		_save_status_label.text = "Saved to slot %d" % (_selected_save_slot + 1)
		_save_status_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	else:
		_save_status_label.text = "Save failed!"
		_save_status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	_refresh_save_slots()


func _on_load_confirm() -> void:
	if _selected_load_slot < 0:
		return
	var data := SaveManager.load_game(_selected_load_slot)
	if data.is_empty():
		_load_status_label.text = "Load failed!"
		_load_status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		return
	SaveManager.apply_loaded_state(data)
	_load_status_label.text = "Loaded slot %d" % (_selected_load_slot + 1)
	_load_status_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))


func _refresh_save_slots() -> void:
	for i in SaveManager.MAX_SLOTS:
		var info := SaveManager.get_save_info(i)
		if info.get("exists", false):
			var ts: float = info.get("timestamp", 0.0)
			var dt := Time.get_datetime_dict_from_unix_time(int(ts))
			var time_str := (
				"%04d-%02d-%02d %02d:%02d"
				% [
					dt.get("year", 0),
					dt.get("month", 0),
					dt.get("day", 0),
					dt.get("hour", 0),
					dt.get("minute", 0),
				]
			)
			_save_slot_buttons[i].text = (
				"Slot %d: %s — %s (%s)"
				% [
					i + 1,
					info.get("civ_name", "?"),
					info.get("age_name", "?"),
					time_str,
				]
			)
		else:
			_save_slot_buttons[i].text = "Slot %d: Empty" % (i + 1)


func _refresh_load_slots() -> void:
	for i in SaveManager.MAX_SLOTS:
		var info := SaveManager.get_save_info(i)
		if info.get("exists", false):
			var ts: float = info.get("timestamp", 0.0)
			var dt := Time.get_datetime_dict_from_unix_time(int(ts))
			var time_str := (
				"%04d-%02d-%02d %02d:%02d"
				% [
					dt.get("year", 0),
					dt.get("month", 0),
					dt.get("day", 0),
					dt.get("hour", 0),
					dt.get("minute", 0),
				]
			)
			_load_slot_buttons[i].text = (
				"Slot %d: %s — %s (%s)"
				% [
					i + 1,
					info.get("civ_name", "?"),
					info.get("age_name", "?"),
					time_str,
				]
			)
		else:
			_load_slot_buttons[i].text = "Slot %d: Empty" % (i + 1)
			_load_slot_buttons[i].disabled = true
