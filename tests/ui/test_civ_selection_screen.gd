extends GdUnitTestSuite
## Tests for civ_selection_screen.gd — civilization selection overlay.

const CivSelectionScreenScript := preload("res://scripts/ui/civ_selection_screen.gd")

var _selected_player: String = ""
var _selected_ai: String = ""


func _reset() -> void:
	_selected_player = ""
	_selected_ai = ""


func _on_civ_selected(player_civ: String, ai_civ: String) -> void:
	_selected_player = player_civ
	_selected_ai = ai_civ


func _create_screen() -> PanelContainer:
	var screen := PanelContainer.new()
	screen.name = "CivSelectionScreen"
	screen.set_script(CivSelectionScreenScript)
	add_child(screen)
	auto_free(screen)
	_reset()
	screen.civ_selected.connect(_on_civ_selected)
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


func test_three_civ_cards_created() -> void:
	var screen := _create_screen()
	assert_int(screen._cards.size()).is_equal(3)
	assert_bool(screen._cards.has("mesopotamia")).is_true()
	assert_bool(screen._cards.has("rome")).is_true()
	assert_bool(screen._cards.has("polynesia")).is_true()


func test_start_button_disabled_initially() -> void:
	var screen := _create_screen()
	assert_bool(screen._start_btn.disabled).is_true()


func test_selecting_civ_enables_start() -> void:
	var screen := _create_screen()
	screen._select_civ("rome")
	assert_bool(screen._start_btn.disabled).is_false()
	assert_str(screen.get_selected_civ()).is_equal("rome")


func test_selecting_different_civ_updates_selection() -> void:
	var screen := _create_screen()
	screen._select_civ("mesopotamia")
	assert_str(screen.get_selected_civ()).is_equal("mesopotamia")
	screen._select_civ("polynesia")
	assert_str(screen.get_selected_civ()).is_equal("polynesia")


func test_selected_card_gets_highlight_style() -> void:
	var screen := _create_screen()
	screen._select_civ("rome")
	var rome_card: PanelContainer = screen._cards["rome"]
	var rome_style := rome_card.get_theme_stylebox("panel")
	var expected_style: StyleBox = screen._card_styles["rome"]["selected"]
	assert_object(rome_style).is_same(expected_style)
	# Other cards should have normal style
	var meso_card: PanelContainer = screen._cards["mesopotamia"]
	var meso_style := meso_card.get_theme_stylebox("panel")
	var meso_normal: StyleBox = screen._card_styles["mesopotamia"]["normal"]
	assert_object(meso_style).is_same(meso_normal)


func test_start_emits_signal_with_correct_civs() -> void:
	var screen := _create_screen()
	screen.show_screen()
	screen._select_civ("mesopotamia")
	# Set AI picker to explicit civ (index 2 = rome, since sorted: meso=1, poly=2, rome=3)
	# Find the rome index
	var rome_idx := -1
	for i in screen._ai_picker.item_count:
		if screen._ai_picker.get_item_text(i) == "Rome":
			rome_idx = i
			break
	assert_int(rome_idx).is_greater(0)
	screen._ai_picker.select(rome_idx)
	screen._on_start_pressed()
	assert_str(_selected_player).is_equal("mesopotamia")
	assert_str(_selected_ai).is_equal("rome")


func test_start_hides_screen() -> void:
	var screen := _create_screen()
	screen.show_screen()
	screen._select_civ("polynesia")
	screen._on_start_pressed()
	assert_bool(screen.visible).is_false()


func test_ai_random_picks_non_player_civ() -> void:
	var screen := _create_screen()
	screen._select_civ("rome")
	# AI picker defaults to "Random" (index 0)
	var ai_civ: String = screen._resolve_ai_civ()
	assert_str(ai_civ).is_not_equal("rome")
	assert_bool(ai_civ != "").is_true()


func test_ai_explicit_pick_same_as_player_falls_back_to_random() -> void:
	var screen := _create_screen()
	screen._select_civ("mesopotamia")
	# Find mesopotamia index in AI picker
	var meso_idx := -1
	for i in screen._ai_picker.item_count:
		if screen._ai_picker.get_item_text(i) == "Mesopotamia":
			meso_idx = i
			break
	assert_int(meso_idx).is_greater(0)
	screen._ai_picker.select(meso_idx)
	var ai_civ: String = screen._resolve_ai_civ()
	# Should not be the same as player
	assert_str(ai_civ).is_not_equal("mesopotamia")


func test_ai_picker_has_random_plus_all_civs() -> void:
	var screen := _create_screen()
	# First item should be "Random"
	assert_str(screen._ai_picker.get_item_text(0)).is_equal("Random")
	# Should have 4 total items (Random + 3 civs)
	assert_int(screen._ai_picker.item_count).is_equal(4)


func test_card_displays_civ_name() -> void:
	var screen := _create_screen()
	var rome_card: PanelContainer = screen._cards["rome"]
	# Find the name label (second child of the VBox inside card)
	var vbox: VBoxContainer = rome_card.get_child(0)
	# Banner is child 0, name label is child 1
	var name_label: Label = vbox.get_child(1) as Label
	assert_str(name_label.text).is_equal("Rome")


func test_card_displays_unique_building() -> void:
	var screen := _create_screen()
	var meso_card: PanelContainer = screen._cards["mesopotamia"]
	var vbox: VBoxContainer = meso_card.get_child(0)
	var bld_label: Label = _find_child_by_name(vbox, "UniqueBuildingLabel") as Label
	assert_object(bld_label).is_not_null()
	assert_str(bld_label.text).contains("Ziggurat")


func test_card_displays_unique_unit() -> void:
	var screen := _create_screen()
	var rome_card: PanelContainer = screen._cards["rome"]
	var vbox: VBoxContainer = rome_card.get_child(0)
	var unit_label: Label = _find_child_by_name(vbox, "UniqueUnitLabel") as Label
	assert_object(unit_label).is_not_null()
	assert_str(unit_label.text).contains("Legionnaire")


func test_start_does_nothing_without_selection() -> void:
	var screen := _create_screen()
	screen.show_screen()
	screen._on_start_pressed()
	assert_str(_selected_player).is_equal("")
	assert_bool(screen.visible).is_true()


func test_get_all_civ_ids_returns_three() -> void:
	var ids: Array = DataLoader.get_all_civ_ids()
	assert_int(ids.size()).is_equal(3)
	assert_bool(ids.has("mesopotamia")).is_true()
	assert_bool(ids.has("rome")).is_true()
	assert_bool(ids.has("polynesia")).is_true()


func test_get_all_civ_ids_sorted() -> void:
	var ids: Array = DataLoader.get_all_civ_ids()
	assert_str(ids[0] as String).is_equal("mesopotamia")
	assert_str(ids[1] as String).is_equal("polynesia")
	assert_str(ids[2] as String).is_equal("rome")


func _find_child_by_name(parent: Node, child_name: String) -> Node:
	for child in parent.get_children():
		if child.name == child_name:
			return child
		var found := _find_child_by_name(child, child_name)
		if found != null:
			return found
	return null
