extends GdUnitTestSuite
## Tests for victory_screen.gd — victory/defeat overlay display.

const VictoryScreenScript := preload("res://scripts/ui/victory_screen.gd")

var _continue_count: int = 0
var _menu_count: int = 0
var _stats_count: int = 0


func _reset_counters() -> void:
	_continue_count = 0
	_menu_count = 0
	_stats_count = 0


func _on_continue() -> void:
	_continue_count += 1


func _on_menu() -> void:
	_menu_count += 1


func _on_stats() -> void:
	_stats_count += 1


func _create_screen() -> PanelContainer:
	var screen := PanelContainer.new()
	screen.name = "VictoryScreen"
	screen.set_script(VictoryScreenScript)
	add_child(screen)
	auto_free(screen)
	_reset_counters()
	screen.continue_pressed.connect(_on_continue)
	screen.menu_pressed.connect(_on_menu)
	screen.stats_pressed.connect(_on_stats)
	return screen


func test_screen_starts_hidden() -> void:
	var screen := _create_screen()
	assert_bool(screen.visible).is_false()


func test_show_victory_makes_visible() -> void:
	var screen := _create_screen()
	screen.show_victory("Military Conquest")
	assert_bool(screen.visible).is_true()


func test_show_defeat_makes_visible() -> void:
	var screen := _create_screen()
	screen.show_defeat("All Town Centers Lost")
	assert_bool(screen.visible).is_true()


func test_victory_title_text() -> void:
	var screen := _create_screen()
	screen.show_victory("Singularity Achieved")
	var title: Label = screen._title_label
	assert_str(title.text).is_equal("VICTORY")


func test_defeat_title_text() -> void:
	var screen := _create_screen()
	screen.show_defeat("All Town Centers Lost")
	var title: Label = screen._title_label
	assert_str(title.text).is_equal("DEFEAT")


func test_condition_label_text() -> void:
	var screen := _create_screen()
	screen.show_victory("Wonder Built")
	var cond: Label = screen._condition_label
	assert_str(cond.text).is_equal("Wonder Built")


func test_continue_button_hides_screen() -> void:
	var screen := _create_screen()
	screen.show_victory("Military Conquest")
	screen._on_continue_pressed()
	assert_bool(screen.visible).is_false()
	assert_int(_continue_count).is_equal(1)


func test_menu_button_emits_signal() -> void:
	var screen := _create_screen()
	screen.show_defeat("All Town Centers Lost")
	screen._on_menu_pressed()
	assert_int(_menu_count).is_equal(1)


func test_set_continue_enabled_false() -> void:
	var screen := _create_screen()
	screen.set_continue_enabled(false)
	assert_bool(screen._continue_btn.visible).is_false()


func test_stats_button_exists() -> void:
	var screen := _create_screen()
	assert_that(screen._stats_btn).is_not_null()
	assert_str(screen._stats_btn.text).is_equal("View Statistics")


func test_stats_button_emits_signal() -> void:
	var screen := _create_screen()
	screen.show_victory("Test")
	screen._on_stats_pressed()
	assert_int(_stats_count).is_equal(1)
