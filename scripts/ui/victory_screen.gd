extends PanelContainer
## Victory/Defeat overlay screen.
## Shows outcome text with condition label and action buttons.

signal continue_pressed
signal menu_pressed

var _title_label: Label = null
var _condition_label: Label = null
var _continue_btn: Button = null
var _menu_btn: Button = null
var _vbox: VBoxContainer = null


func _ready() -> void:
	visible = false
	_build_ui()


func _build_ui() -> void:
	# Full-screen semi-transparent overlay
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	add_theme_stylebox_override("panel", style)

	_vbox = VBoxContainer.new()
	_vbox.name = "VBox"
	_vbox.set_anchors_preset(Control.PRESET_CENTER)
	_vbox.size = Vector2(400, 300)
	_vbox.position = Vector2(-200, -150)
	_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_vbox)

	# Spacer top
	var spacer_top := Control.new()
	spacer_top.custom_minimum_size = Vector2(0, 40)
	_vbox.add_child(spacer_top)

	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 48)
	_vbox.add_child(_title_label)

	# Spacer between title and condition
	var spacer_mid := Control.new()
	spacer_mid.custom_minimum_size = Vector2(0, 20)
	_vbox.add_child(spacer_mid)

	_condition_label = Label.new()
	_condition_label.name = "ConditionLabel"
	_condition_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_condition_label.add_theme_font_size_override("font_size", 24)
	_vbox.add_child(_condition_label)

	# Spacer before buttons
	var spacer_btns := Control.new()
	spacer_btns.custom_minimum_size = Vector2(0, 40)
	_vbox.add_child(spacer_btns)

	var btn_hbox := HBoxContainer.new()
	btn_hbox.name = "ButtonRow"
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_vbox.add_child(btn_hbox)

	_continue_btn = Button.new()
	_continue_btn.name = "ContinueButton"
	_continue_btn.text = "Continue Playing"
	_continue_btn.custom_minimum_size = Vector2(160, 40)
	_continue_btn.pressed.connect(_on_continue_pressed)
	btn_hbox.add_child(_continue_btn)

	var btn_spacer := Control.new()
	btn_spacer.custom_minimum_size = Vector2(20, 0)
	btn_hbox.add_child(btn_spacer)

	_menu_btn = Button.new()
	_menu_btn.name = "MenuButton"
	_menu_btn.text = "Return to Menu"
	_menu_btn.custom_minimum_size = Vector2(160, 40)
	_menu_btn.pressed.connect(_on_menu_pressed)
	btn_hbox.add_child(_menu_btn)


func show_victory(condition_label: String) -> void:
	_title_label.text = "VICTORY"
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	_condition_label.text = condition_label
	visible = true


func show_defeat(condition_label: String) -> void:
	_title_label.text = "DEFEAT"
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
	_condition_label.text = condition_label
	visible = true


func set_continue_enabled(enabled: bool) -> void:
	if _continue_btn != null:
		_continue_btn.visible = enabled


func _on_continue_pressed() -> void:
	visible = false
	continue_pressed.emit()


func _on_menu_pressed() -> void:
	menu_pressed.emit()
	print("Return to menu requested (not yet implemented)")
