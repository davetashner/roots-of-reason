extends GdUnitTestSuite
## Tests for game_lobby_screen.gd — pre-game lobby overlay.

const GameLobbyScreenScript := preload("res://scripts/ui/game_lobby_screen.gd")

var _emitted_settings: Dictionary = {}
var _back_pressed_count: int = 0


func _reset() -> void:
	_emitted_settings = {}
	_back_pressed_count = 0


func _on_start_game(settings: Dictionary) -> void:
	_emitted_settings = settings


func _on_back_pressed() -> void:
	_back_pressed_count += 1


func _create_screen() -> PanelContainer:
	var screen := PanelContainer.new()
	screen.name = "GameLobbyScreen"
	screen.set_script(GameLobbyScreenScript)
	add_child(screen)
	auto_free(screen)
	_reset()
	screen.start_game.connect(_on_start_game)
	screen.back_pressed.connect(_on_back_pressed)
	return screen


func test_screen_starts_hidden() -> void:
	var screen := _create_screen()
	assert_bool(screen.visible).is_false()


func test_show_screen_makes_visible() -> void:
	var screen := _create_screen()
	screen.show_screen()
	assert_bool(screen.visible).is_true()


func test_hide_screen_hides() -> void:
	var screen := _create_screen()
	screen.show_screen()
	screen.hide_screen()
	assert_bool(screen.visible).is_false()


func test_difficulty_options_match_json() -> void:
	var screen := _create_screen()
	assert_int(screen._difficulty_picker.item_count).is_equal(4)
	assert_array(screen._difficulty_keys).contains(["easy", "normal", "hard", "expert"])


func test_difficulty_default_is_normal() -> void:
	var screen := _create_screen()
	var selected_idx: int = screen._difficulty_picker.selected
	assert_str(screen._difficulty_keys[selected_idx]).is_equal("normal")


func test_map_size_options_present() -> void:
	var screen := _create_screen()
	assert_int(screen._map_size_picker.item_count).is_greater(0)
	assert_bool(screen._map_size_keys.has("dev")).is_true()


func test_three_civ_cards_created() -> void:
	var screen := _create_screen()
	assert_int(screen._cards.size()).is_equal(3)
	assert_bool(screen._cards.has("mesopotamia")).is_true()
	assert_bool(screen._cards.has("rome")).is_true()
	assert_bool(screen._cards.has("polynesia")).is_true()


func test_start_button_disabled_initially() -> void:
	var screen := _create_screen()
	assert_bool(screen._start_btn.disabled).is_true()


func test_start_enabled_after_civ_selection() -> void:
	var screen := _create_screen()
	screen._select_civ("mesopotamia")
	assert_bool(screen._start_btn.disabled).is_false()


func test_start_emits_settings_dict() -> void:
	var screen := _create_screen()
	screen._select_civ("rome")
	screen._on_start_pressed()
	assert_str(_emitted_settings.get("player_civ", "")).is_equal("rome")
	assert_str(_emitted_settings.get("difficulty", "")).is_not_empty()
	assert_str(_emitted_settings.get("map_size", "")).is_not_empty()
	assert_str(_emitted_settings.get("ai_civ", "")).is_not_empty()


func test_ai_random_excludes_player_civ() -> void:
	var screen := _create_screen()
	screen._select_civ("mesopotamia")
	# Run multiple times to verify exclusion
	for i in 20:
		var ai_civ: String = screen._resolve_ai_civ()
		assert_str(ai_civ).is_not_equal("mesopotamia")


func test_back_button_emits_signal_and_hides() -> void:
	var screen := _create_screen()
	screen.show_screen()
	screen._on_back_pressed()
	assert_int(_back_pressed_count).is_equal(1)
	assert_bool(screen.visible).is_false()


func test_card_highlight_on_selection() -> void:
	var screen := _create_screen()
	screen._select_civ("rome")
	var rome_style: Variant = screen._cards["rome"].get_theme_stylebox("panel")
	var expected_style: Variant = screen._card_styles["rome"]["selected"]
	assert_object(rome_style).is_same(expected_style)
	# Other cards should have normal style
	var meso_style: Variant = screen._cards["mesopotamia"].get_theme_stylebox("panel")
	var meso_normal: Variant = screen._card_styles["mesopotamia"]["normal"]
	assert_object(meso_style).is_same(meso_normal)


func test_ai_picker_has_random_option() -> void:
	var screen := _create_screen()
	assert_str(screen._ai_picker.get_item_text(0)).is_equal("Random")
