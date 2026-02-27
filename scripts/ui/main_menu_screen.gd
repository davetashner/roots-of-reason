extends Control
## Main menu screen — entry point for the game.
## Shows title, single player, settings, credits, and quit buttons.

const GameLobbyScreenScript := preload("res://scripts/ui/game_lobby_screen.gd")
const SettingsPanelScript := preload("res://scripts/ui/settings_panel.gd")

var _lobby: PanelContainer = null
var _settings_panel: PanelContainer = null
var _credits_panel: PanelContainer = null
var _button_vbox: VBoxContainer = null


func _ready() -> void:
	_reset_state()
	_build_ui()


func _reset_state() -> void:
	GameManager.reset_game_state()
	ResourceManager.reset()
	CivBonusManager.reset()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Background
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.04, 0.04, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Center container
	var center := VBoxContainer.new()
	center.name = "CenterVBox"
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.size = Vector2(400, 500)
	center.position = Vector2(-200, -250)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 16)
	add_child(center)

	# Title
	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "Roots of Reason"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	center.add_child(title)

	# Subtitle
	var subtitle := Label.new()
	subtitle.name = "SubtitleLabel"
	subtitle.text = "The Path to Singularity"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	center.add_child(subtitle)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	center.add_child(spacer)

	# Buttons
	_button_vbox = VBoxContainer.new()
	_button_vbox.name = "ButtonVBox"
	_button_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_button_vbox.add_theme_constant_override("separation", 12)
	center.add_child(_button_vbox)

	_add_menu_button("SinglePlayerButton", "Single Player", _on_single_player_pressed)
	_add_menu_button("SettingsButton", "Settings", _on_settings_pressed)
	_add_menu_button("CreditsButton", "Credits", _on_credits_pressed)
	_add_menu_button("QuitButton", "Quit", _on_quit_pressed)

	# Lobby overlay (CanvasLayer 10)
	var lobby_layer := CanvasLayer.new()
	lobby_layer.name = "LobbyLayer"
	lobby_layer.layer = 10
	add_child(lobby_layer)
	_lobby = PanelContainer.new()
	_lobby.name = "GameLobbyScreen"
	_lobby.set_script(GameLobbyScreenScript)
	lobby_layer.add_child(_lobby)
	_lobby.start_game.connect(_on_lobby_start_game)
	_lobby.back_pressed.connect(_on_lobby_back)

	# Settings panel
	_settings_panel = PanelContainer.new()
	_settings_panel.name = "SettingsPanel"
	_settings_panel.visible = false
	_settings_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var settings_style := StyleBoxFlat.new()
	settings_style.bg_color = Color(0.05, 0.05, 0.1, 0.95)
	_settings_panel.add_theme_stylebox_override("panel", settings_style)
	var settings_center := CenterContainer.new()
	settings_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_panel.add_child(settings_center)
	var settings_vbox := VBoxContainer.new()
	settings_vbox.set_script(SettingsPanelScript)
	settings_center.add_child(settings_vbox)
	settings_vbox.build(func() -> void: _settings_panel.visible = false)
	add_child(_settings_panel)

	# Credits placeholder
	_credits_panel = _build_placeholder_panel("CreditsPanel", "Credits — Coming Soon")
	add_child(_credits_panel)


func _add_menu_button(btn_name: String, text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.name = btn_name
	btn.text = text
	btn.custom_minimum_size = Vector2(260, 50)
	btn.pressed.connect(callback)
	_button_vbox.add_child(btn)
	return btn


func _build_placeholder_panel(panel_name: String, text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.95)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.size = Vector2(400, 200)
	vbox.position = Vector2(-200, -100)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(label)

	var back_btn := Button.new()
	back_btn.name = "BackButton"
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(120, 40)
	back_btn.pressed.connect(func() -> void: panel.visible = false)
	vbox.add_child(back_btn)

	return panel


func _on_single_player_pressed() -> void:
	_lobby.show_screen()


func _on_settings_pressed() -> void:
	_settings_panel.visible = true


func _on_credits_pressed() -> void:
	_credits_panel.visible = true


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_lobby_start_game(settings: Dictionary) -> void:
	# Write settings to GameManager
	var difficulty: String = settings.get("difficulty", "normal")
	GameManager.ai_difficulty = difficulty
	var player_civ: String = settings.get("player_civ", "")
	var ai_civ: String = settings.get("ai_civ", "")
	if player_civ != "":
		GameManager.set_player_civilization(0, player_civ)
	if ai_civ != "":
		GameManager.set_player_civilization(1, ai_civ)
	get_tree().change_scene_to_file("res://scenes/prototype/prototype_main.tscn")


func _on_lobby_back() -> void:
	_lobby.hide_screen()
