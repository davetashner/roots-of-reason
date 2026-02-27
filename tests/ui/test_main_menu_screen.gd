extends GdUnitTestSuite
## Tests for main_menu_screen.gd — main menu entry point.

const MainMenuScreenScript := preload("res://scripts/ui/main_menu_screen.gd")


func _create_menu() -> Control:
	var menu := Control.new()
	menu.name = "MainMenu"
	menu.set_script(MainMenuScreenScript)
	add_child(menu)
	auto_free(menu)
	return menu


func test_menu_has_four_buttons() -> void:
	var menu := _create_menu()
	var btn_vbox: VBoxContainer = menu._button_vbox
	assert_int(btn_vbox.get_child_count()).is_equal(4)


func test_button_names() -> void:
	var menu := _create_menu()
	var btn_vbox: VBoxContainer = menu._button_vbox
	var names: Array[String] = []
	for child in btn_vbox.get_children():
		names.append(child.name)
	assert_array(names).contains(["SinglePlayerButton", "SettingsButton", "CreditsButton", "QuitButton"])


func test_single_player_shows_lobby() -> void:
	var menu := _create_menu()
	assert_bool(menu._lobby.visible).is_false()
	menu._on_single_player_pressed()
	assert_bool(menu._lobby.visible).is_true()


func test_settings_shows_panel() -> void:
	var menu := _create_menu()
	assert_bool(menu._settings_panel.visible).is_false()
	menu._on_settings_pressed()
	assert_bool(menu._settings_panel.visible).is_true()


func test_credits_shows_placeholder() -> void:
	var menu := _create_menu()
	assert_bool(menu._credits_panel.visible).is_false()
	menu._on_credits_pressed()
	assert_bool(menu._credits_panel.visible).is_true()


func test_lobby_back_hides_lobby() -> void:
	var menu := _create_menu()
	menu._on_single_player_pressed()
	assert_bool(menu._lobby.visible).is_true()
	menu._on_lobby_back()
	assert_bool(menu._lobby.visible).is_false()


func test_reset_state_clears_game_manager() -> void:
	GameManager.game_time = 100.0
	GameManager.set_player_civilization(0, "rome")
	var menu := _create_menu()
	# _ready() calls _reset_state() which clears game state
	assert_object(menu).is_not_null()
	assert_float(GameManager.game_time).is_equal(0.0)
	assert_str(GameManager.get_player_civilization(0)).is_equal("")
