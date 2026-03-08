extends GdUnitTestSuite
## Tests for progressive tech tree disclosure and opponent intel.

const TechTreeViewerScript := preload("res://scripts/ui/tech_tree_viewer.gd")
const TechManagerScript := preload("res://scripts/prototype/tech_manager.gd")

const RMGuard := preload("res://tests/helpers/resource_manager_guard.gd")
const GMGuard := preload("res://tests/helpers/game_manager_guard.gd")

var _rm_guard: RefCounted
var _gm_guard: RefCounted


func before_test() -> void:
	_rm_guard = RMGuard.new()
	_gm_guard = GMGuard.new()
	GameManager.current_age = 6
	GameManager.is_paused = false
	GameManager.game_speed = 1.0
	GameManager.player_civilizations = {}


func after_test() -> void:
	_gm_guard.dispose()
	_rm_guard.dispose()


func _give_resources(
	player_id: int,
	food: int = 0,
	wood: int = 0,
	stone: int = 0,
	gold: int = 0,
	knowledge: int = 0,
) -> void:
	(
		ResourceManager
		. init_player(
			player_id,
			{
				ResourceManager.ResourceType.FOOD: food,
				ResourceManager.ResourceType.WOOD: wood,
				ResourceManager.ResourceType.STONE: stone,
				ResourceManager.ResourceType.GOLD: gold,
				ResourceManager.ResourceType.KNOWLEDGE: knowledge,
			}
		)
	)


func _create_tech_manager() -> Node:
	var node := Node.new()
	node.set_script(TechManagerScript)
	add_child(node)
	auto_free(node)
	return node


func _create_viewer(tm: Node, player_id: int = 0) -> PanelContainer:
	var viewer := PanelContainer.new()
	viewer.name = "TechTreeViewer"
	viewer.set_script(TechTreeViewerScript)
	add_child(viewer)
	auto_free(viewer)
	viewer.setup(tm, player_id)
	return viewer


func _research_tech(tm: Node, player_id: int, tech_id: String) -> void:
	## Helper to fast-complete a tech research.
	_give_resources(player_id, 99999, 99999, 99999, 99999, 99999)
	tm.start_research(player_id, tech_id)
	tm._research_progress[player_id] = 99999.0
	tm._complete_research(player_id)


# -- Visibility rule tests --


func test_root_tech_always_visible() -> void:
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	# stone_tools has no prereqs — should be visible
	var vis: String = viewer.get_tech_visibility("stone_tools")
	assert_str(vis).is_equal("visible")


func test_researched_tech_always_visible() -> void:
	var tm := _create_tech_manager()
	_research_tech(tm, 0, "stone_tools")
	var viewer := _create_viewer(tm)
	var vis: String = viewer.get_tech_visibility("stone_tools")
	assert_str(vis).is_equal("visible")


func test_hidden_when_no_prereqs_researched() -> void:
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	# animal_husbandry requires stone_tools — nothing researched
	var vis: String = viewer.get_tech_visibility("animal_husbandry")
	assert_str(vis).is_equal("hidden")


func test_shadowed_when_partial_prereqs_researched() -> void:
	var tm := _create_tech_manager()
	# iron_working requires bronze_working — research bronze but not others
	_research_tech(tm, 0, "bronze_working")
	var viewer := _create_viewer(tm)
	# engineering requires mathematics — mathematics requires writing
	# compass requires trireme + mathematics — only one prereq done if we research
	# Let's check espionage: requires writing + iron_working
	# Research writing only (not iron_working)
	_research_tech(tm, 0, "writing")
	viewer.refresh()
	var vis: String = viewer.get_tech_visibility("espionage")
	assert_str(vis).is_equal("shadowed")


func test_visible_when_all_prereqs_researched() -> void:
	var tm := _create_tech_manager()
	# animal_husbandry requires stone_tools
	_research_tech(tm, 0, "stone_tools")
	var viewer := _create_viewer(tm)
	var vis: String = viewer.get_tech_visibility("animal_husbandry")
	assert_str(vis).is_equal("visible")


func test_civ_exclusive_hidden_for_wrong_civ() -> void:
	var tm := _create_tech_manager()
	# cuneiform_writing is mesopotamia-exclusive
	GameManager.set_player_civilization(0, "egypt")
	_research_tech(tm, 0, "writing")
	var viewer := _create_viewer(tm)
	var vis: String = viewer.get_tech_visibility("cuneiform_writing")
	assert_str(vis).is_equal("hidden")


func test_civ_exclusive_hidden_until_all_prereqs_met() -> void:
	var tm := _create_tech_manager()
	# cuneiform_writing requires writing — don't research it
	GameManager.set_player_civilization(0, "mesopotamia")
	var viewer := _create_viewer(tm)
	var vis: String = viewer.get_tech_visibility("cuneiform_writing")
	assert_str(vis).is_equal("hidden")


func test_civ_exclusive_visible_with_correct_civ_and_prereqs() -> void:
	var tm := _create_tech_manager()
	GameManager.set_player_civilization(0, "mesopotamia")
	_research_tech(tm, 0, "writing")
	var viewer := _create_viewer(tm)
	var vis: String = viewer.get_tech_visibility("cuneiform_writing")
	assert_str(vis).is_equal("visible")


# -- Age gating tests --


func test_age_columns_hidden_beyond_lookahead() -> void:
	GameManager.current_age = 0  # Stone Age
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	# Default max_lookahead_ages = 1, so age 0 and 1 visible, age 2+ hidden
	var col_0: VBoxContainer = viewer.get_age_column(0)
	var col_1: VBoxContainer = viewer.get_age_column(1)
	var col_2: VBoxContainer = viewer.get_age_column(2)
	assert_bool(col_0.visible).is_true()
	assert_bool(col_1.visible).is_true()
	assert_bool(col_2.visible).is_false()


func test_age_columns_visible_within_lookahead() -> void:
	GameManager.current_age = 3  # Medieval
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	# Ages 0-4 should be visible (current=3, lookahead=1 → max=4)
	for i in range(5):
		var col: VBoxContainer = viewer.get_age_column(i)
		assert_bool(col.visible).is_true()
	# Age 5 should be hidden
	var col_5: VBoxContainer = viewer.get_age_column(5)
	assert_bool(col_5.visible).is_false()


func test_age_columns_update_after_age_advance() -> void:
	GameManager.current_age = 0
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	var col_2: VBoxContainer = viewer.get_age_column(2)
	assert_bool(col_2.visible).is_false()
	# Advance age and refresh
	GameManager.current_age = 1
	viewer.refresh()
	assert_bool(col_2.visible).is_true()


# -- Shadowed display tests --


func test_shadowed_tech_has_purple_border() -> void:
	var tm := _create_tech_manager()
	# espionage requires writing + iron_working — research only writing
	_research_tech(tm, 0, "writing")
	var viewer := _create_viewer(tm)
	var btn: Button = viewer.get_tech_button("espionage")
	var style: StyleBoxFlat = btn.get_theme_stylebox("normal") as StyleBoxFlat
	assert_object(style).is_not_null()
	assert_bool(style.border_color.is_equal_approx(Color("#9C27B0"))).is_true()


func test_shadowed_tooltip_hides_cost_shows_prereq_progress() -> void:
	var tm := _create_tech_manager()
	_research_tech(tm, 0, "writing")
	var viewer := _create_viewer(tm)
	var btn: Button = viewer.get_tech_button("espionage")
	var tooltip: String = btn.tooltip_text
	assert_str(tooltip).contains("UNDISCOVERED")
	assert_str(tooltip).contains("Writing (done)")
	assert_str(tooltip).contains("Iron Working (needed)")
	# Should NOT contain cost info
	assert_str(tooltip).not_contains("Cost:")


func test_shadowed_click_does_not_start_research() -> void:
	var tm := _create_tech_manager()
	_research_tech(tm, 0, "writing")
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	var viewer := _create_viewer(tm)
	# Manually trigger button press for a shadowed tech
	viewer._on_tech_button_pressed("espionage")
	var current: String = tm.get_current_research(0)
	assert_str(current).is_not_equal("espionage")


# -- Hidden button visibility --


func test_hidden_tech_button_not_visible() -> void:
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	# animal_husbandry requires stone_tools — hidden
	var btn: Button = viewer.get_tech_button("animal_husbandry")
	assert_bool(btn.visible).is_false()


func test_visible_tech_button_is_visible() -> void:
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	# stone_tools is a root tech — visible
	var btn: Button = viewer.get_tech_button("stone_tools")
	assert_bool(btn.visible).is_true()


# -- Opponent intel tests --


func test_opponent_toggle_hidden_initially() -> void:
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	assert_bool(viewer.is_opponent_research_unlocked()).is_false()
	assert_bool(viewer._opponent_toggle_btn.visible).is_false()


func test_opponent_toggle_shown_after_espionage_researched() -> void:
	var tm := _create_tech_manager()
	# Research prereqs then espionage
	_research_tech(tm, 0, "writing")
	_research_tech(tm, 0, "bronze_working")
	_research_tech(tm, 0, "iron_working")
	_research_tech(tm, 0, "espionage")
	var viewer := _create_viewer(tm)
	assert_bool(viewer.is_opponent_research_unlocked()).is_true()
	assert_bool(viewer._opponent_toggle_btn.visible).is_true()


func test_opponent_toggle_shows_panel() -> void:
	var tm := _create_tech_manager()
	_research_tech(tm, 0, "writing")
	_research_tech(tm, 0, "bronze_working")
	_research_tech(tm, 0, "iron_working")
	_research_tech(tm, 0, "espionage")
	var viewer := _create_viewer(tm)
	assert_bool(viewer._opponent_panel.visible).is_false()
	viewer._on_opponent_toggle()
	assert_bool(viewer._opponent_panel.visible).is_true()
	assert_bool(viewer.is_showing_opponent()).is_true()


func test_opponent_panel_shows_no_active_research() -> void:
	var tm := _create_tech_manager()
	_research_tech(tm, 0, "writing")
	_research_tech(tm, 0, "bronze_working")
	_research_tech(tm, 0, "iron_working")
	_research_tech(tm, 0, "espionage")
	var viewer := _create_viewer(tm)
	viewer._on_opponent_toggle()
	var vbox: VBoxContainer = viewer._opponent_panel.get_node("OpponentVBox")
	var research_lbl: Label = vbox.get_node("OpponentResearch")
	assert_str(research_lbl.text).is_equal("No active research")


func test_opponent_panel_shows_current_research() -> void:
	var tm := _create_tech_manager()
	# Setup player 0 with espionage
	_research_tech(tm, 0, "writing")
	_research_tech(tm, 0, "bronze_working")
	_research_tech(tm, 0, "iron_working")
	_research_tech(tm, 0, "espionage")
	# Start AI (player 1) research
	_give_resources(1, 99999, 99999, 99999, 99999, 99999)
	tm.start_research(1, "stone_tools")
	var viewer := _create_viewer(tm)
	viewer._on_opponent_toggle()
	var vbox: VBoxContainer = viewer._opponent_panel.get_node("OpponentVBox")
	var research_lbl: Label = vbox.get_node("OpponentResearch")
	assert_str(research_lbl.text).contains("Stone Tools")
	var progress_bar: ProgressBar = vbox.get_node("OpponentProgress")
	assert_bool(progress_bar.visible).is_true()


func test_opponent_panel_hides_when_toggled_off() -> void:
	var tm := _create_tech_manager()
	_research_tech(tm, 0, "writing")
	_research_tech(tm, 0, "bronze_working")
	_research_tech(tm, 0, "iron_working")
	_research_tech(tm, 0, "espionage")
	var viewer := _create_viewer(tm)
	viewer._on_opponent_toggle()
	assert_bool(viewer._opponent_panel.visible).is_true()
	viewer._on_opponent_toggle()
	assert_bool(viewer._opponent_panel.visible).is_false()


# -- Config-driven tests --


func test_max_lookahead_zero_hides_next_age() -> void:
	GameManager.current_age = 0
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	# Override config to zero lookahead
	viewer._visibility_config["max_lookahead_ages"] = 0
	viewer.refresh()
	var col_0: VBoxContainer = viewer.get_age_column(0)
	var col_1: VBoxContainer = viewer.get_age_column(1)
	assert_bool(col_0.visible).is_true()
	assert_bool(col_1.visible).is_false()


func test_show_shadowed_false_hides_shadowed_techs() -> void:
	var tm := _create_tech_manager()
	# espionage requires writing + iron_working — research only writing
	_research_tech(tm, 0, "writing")
	var viewer := _create_viewer(tm)
	# Override config to hide shadowed techs
	viewer._visibility_config["show_shadowed_techs"] = false
	viewer.refresh()
	var btn: Button = viewer.get_tech_button("espionage")
	assert_bool(btn.visible).is_false()


# -- Espionage unlocks via signal --


func test_espionage_signal_unlocks_opponent_button() -> void:
	var tm := _create_tech_manager()
	_research_tech(tm, 0, "writing")
	_research_tech(tm, 0, "bronze_working")
	_research_tech(tm, 0, "iron_working")
	var viewer := _create_viewer(tm)
	assert_bool(viewer._opponent_toggle_btn.visible).is_false()
	# Now research espionage — signal should trigger unlock check
	_research_tech(tm, 0, "espionage")
	assert_bool(viewer._opponent_toggle_btn.visible).is_true()
