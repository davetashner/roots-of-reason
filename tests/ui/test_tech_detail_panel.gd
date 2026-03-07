extends GdUnitTestSuite
## Tests for the tech detail side panel in tech_tree_viewer.gd.
## Covers panel visibility, content population, state-driven button logic,
## the leads-to reverse dependency map, and close/ESC behaviour.

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


func _create_viewer(tm: Node) -> PanelContainer:
	var viewer := PanelContainer.new()
	viewer.name = "TechTreeViewer"
	viewer.set_script(TechTreeViewerScript)
	add_child(viewer)
	auto_free(viewer)
	viewer.setup(tm, 0)
	return viewer


func _research_tech(tm: Node, player_id: int, tech_id: String) -> void:
	## Fast-completes a tech for the given player.
	_give_resources(player_id, 99999, 99999, 99999, 99999, 99999)
	tm.start_research(player_id, tech_id)
	tm._research_progress[player_id] = 99999.0
	tm._complete_research(player_id)


func _get_detail_vbox(viewer: PanelContainer) -> VBoxContainer:
	## Convenience: returns the VBoxContainer inside the detail panel.
	var panel: PanelContainer = viewer.get_detail_panel()
	return panel.get_node("DetailScroll/DetailVBox") as VBoxContainer


# -- Panel startup --


func test_detail_panel_hidden_on_startup() -> void:
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	var panel: PanelContainer = viewer.get_detail_panel()
	assert_object(panel).is_not_null()
	assert_bool(panel.visible).is_false()


func test_detail_tech_id_empty_on_startup() -> void:
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	assert_str(viewer.get_detail_tech_id()).is_equal("")


# -- Clicking a tech button opens the panel --


func test_click_tech_shows_detail_panel() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	# stone_tools is a root tech — always visible
	viewer._on_tech_button_pressed("stone_tools")
	var panel: PanelContainer = viewer.get_detail_panel()
	assert_bool(panel.visible).is_true()


func test_click_tech_sets_detail_tech_id() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	viewer._on_tech_button_pressed("stone_tools")
	assert_str(viewer.get_detail_tech_id()).is_equal("stone_tools")


func test_click_hidden_tech_does_not_open_panel() -> void:
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	# animal_husbandry is hidden (prereq stone_tools not researched)
	viewer._on_tech_button_pressed("animal_husbandry")
	var panel: PanelContainer = viewer.get_detail_panel()
	assert_bool(panel.visible).is_false()


# -- Detail panel content: name --


func test_detail_panel_shows_tech_name() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	viewer._show_detail_panel("stone_tools")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var name_lbl: Label = vbox.get_node("DetailName") as Label
	assert_str(name_lbl.text).is_equal("Stone Tools")


func test_detail_panel_name_falls_back_to_id_for_unknown_tech() -> void:
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	# Pass an ID that has no entry in the tech cache
	viewer._show_detail_panel("nonexistent_tech")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var name_lbl: Label = vbox.get_node("DetailName") as Label
	assert_str(name_lbl.text).is_equal("nonexistent_tech")


# -- Detail panel content: description --


func test_detail_panel_shows_description() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	viewer._show_detail_panel("stone_tools")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var desc_lbl: Label = vbox.get_node("DetailDescription") as Label
	assert_str(desc_lbl.text).is_not_empty()
	assert_bool(desc_lbl.visible).is_true()


func test_detail_panel_description_hidden_when_empty() -> void:
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	# Use a nonexistent tech so the cache returns {} — no description field
	viewer._show_detail_panel("nonexistent_tech")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var desc_lbl: Label = vbox.get_node("DetailDescription") as Label
	assert_bool(desc_lbl.visible).is_false()


# -- Detail panel content: cost --


func test_detail_panel_shows_cost() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	# stone_tools costs food: 50
	viewer._show_detail_panel("stone_tools")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var cost_lbl: Label = vbox.get_node("DetailCost") as Label
	assert_bool(cost_lbl.visible).is_true()
	assert_str(cost_lbl.text).contains("Cost:")
	assert_str(cost_lbl.text).contains("Food")
	assert_str(cost_lbl.text).contains("50")


func test_detail_panel_cost_hidden_for_unknown_tech() -> void:
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	viewer._show_detail_panel("nonexistent_tech")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var cost_lbl: Label = vbox.get_node("DetailCost") as Label
	assert_bool(cost_lbl.visible).is_false()


func test_detail_panel_cost_shows_multiple_resources() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	var viewer := _create_viewer(tm)
	# basket_weaving costs food: 75, wood: 25
	viewer._show_detail_panel("basket_weaving")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var cost_lbl: Label = vbox.get_node("DetailCost") as Label
	assert_bool(cost_lbl.visible).is_true()
	assert_str(cost_lbl.text).contains("Food")
	assert_str(cost_lbl.text).contains("Wood")


# -- Detail panel content: effects --


func test_detail_panel_shows_effects() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	# stone_tools has effects: {economic_bonus: {gather_rate: 0.1}}
	viewer._show_detail_panel("stone_tools")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var effects_lbl: Label = vbox.get_node("DetailEffects") as Label
	var effects_header: Label = vbox.get_node("DetailEffectsHeader") as Label
	assert_bool(effects_header.visible).is_true()
	assert_bool(effects_lbl.visible).is_true()
	assert_str(effects_lbl.text).is_not_empty()


func test_detail_panel_effects_hidden_for_tech_with_no_effects() -> void:
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	# Use nonexistent tech — no effects in cache
	viewer._show_detail_panel("nonexistent_tech")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var effects_lbl: Label = vbox.get_node("DetailEffects") as Label
	var effects_header: Label = vbox.get_node("DetailEffectsHeader") as Label
	assert_bool(effects_header.visible).is_false()
	assert_bool(effects_lbl.visible).is_false()


# -- Detail panel content: prerequisites --


func test_detail_panel_shows_prerequisites() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	var viewer := _create_viewer(tm)
	# animal_husbandry requires stone_tools; open panel directly (bypass visibility)
	viewer._show_detail_panel("animal_husbandry")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var prereq_header: Label = vbox.get_node("DetailPrereqHeader") as Label
	var prereq_lbl: Label = vbox.get_node("DetailPrereqs") as Label
	assert_bool(prereq_header.visible).is_true()
	assert_bool(prereq_lbl.visible).is_true()
	assert_str(prereq_lbl.text).contains("Stone Tools")


func test_detail_panel_prereq_shows_done_marker_when_researched() -> void:
	var tm := _create_tech_manager()
	_research_tech(tm, 0, "stone_tools")
	var viewer := _create_viewer(tm)
	viewer._show_detail_panel("animal_husbandry")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var prereq_lbl: Label = vbox.get_node("DetailPrereqs") as Label
	assert_str(prereq_lbl.text).contains("(done)")


func test_detail_panel_prereq_shows_needed_marker_when_not_researched() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 0)
	var viewer := _create_viewer(tm)
	viewer._show_detail_panel("animal_husbandry")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var prereq_lbl: Label = vbox.get_node("DetailPrereqs") as Label
	assert_str(prereq_lbl.text).contains("(needed)")


func test_detail_panel_prereqs_hidden_for_root_tech() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	# stone_tools has no prerequisites
	viewer._show_detail_panel("stone_tools")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var prereq_header: Label = vbox.get_node("DetailPrereqHeader") as Label
	var prereq_lbl: Label = vbox.get_node("DetailPrereqs") as Label
	assert_bool(prereq_header.visible).is_false()
	assert_bool(prereq_lbl.visible).is_false()


# -- Detail panel content: leads-to --


func test_detail_panel_shows_leads_to() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	# stone_tools leads to animal_husbandry and basket_weaving (among others)
	viewer._show_detail_panel("stone_tools")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var leads_header: Label = vbox.get_node("DetailLeadsToHeader") as Label
	var leads_lbl: Label = vbox.get_node("DetailLeadsTo") as Label
	assert_bool(leads_header.visible).is_true()
	assert_bool(leads_lbl.visible).is_true()
	assert_str(leads_lbl.text).is_not_empty()


func test_detail_panel_leads_to_hidden_for_leaf_tech() -> void:
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	# Verify that a tech with no entries in the leads-to map hides the section.
	# We find such a tech by checking the leads_to map directly.
	var leaf_id: String = ""
	for tech_id: String in viewer._tech_cache:
		if viewer.get_leads_to(tech_id).is_empty():
			leaf_id = tech_id
			break
	assert_str(leaf_id).is_not_empty()  # sanity: tree must have at least one leaf
	viewer._show_detail_panel(leaf_id)
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var leads_header: Label = vbox.get_node("DetailLeadsToHeader") as Label
	assert_bool(leads_header.visible).is_false()


# -- Research button visibility --


func test_research_button_visible_when_available() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	# stone_tools is available (no prereqs, have enough food)
	viewer._show_detail_panel("stone_tools")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var research_btn: Button = vbox.get_node("DetailResearchBtn") as Button
	assert_bool(research_btn.visible).is_true()


func test_research_button_hidden_when_locked() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 0)
	var viewer := _create_viewer(tm)
	# animal_husbandry prereqs not met — state is "locked"
	viewer._show_detail_panel("animal_husbandry")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var research_btn: Button = vbox.get_node("DetailResearchBtn") as Button
	assert_bool(research_btn.visible).is_false()


func test_research_button_hidden_when_unaffordable() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 0)
	var viewer := _create_viewer(tm)
	# stone_tools has no prereqs but costs 50 food — state is "unaffordable"
	viewer._show_detail_panel("stone_tools")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var research_btn: Button = vbox.get_node("DetailResearchBtn") as Button
	assert_bool(research_btn.visible).is_false()


func test_research_button_hidden_when_already_researched() -> void:
	var tm := _create_tech_manager()
	_research_tech(tm, 0, "stone_tools")
	var viewer := _create_viewer(tm)
	viewer._show_detail_panel("stone_tools")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var research_btn: Button = vbox.get_node("DetailResearchBtn") as Button
	assert_bool(research_btn.visible).is_false()


# -- Research button starts research --


func test_research_button_starts_research() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	viewer._show_detail_panel("stone_tools")
	# Trigger the research button handler directly
	viewer._on_detail_research_pressed("stone_tools")
	var current: String = tm.get_current_research(0)
	assert_str(current).is_equal("stone_tools")


func test_research_button_refreshes_panel_state_after_starting() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	viewer._show_detail_panel("stone_tools")
	viewer._on_detail_research_pressed("stone_tools")
	# After starting research the state changes to "researching"/in-progress;
	# the research button should no longer be visible (state is no longer "available")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var research_btn: Button = vbox.get_node("DetailResearchBtn") as Button
	assert_bool(research_btn.visible).is_false()


func test_research_button_does_nothing_without_tech_manager() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	viewer._show_detail_panel("stone_tools")
	viewer._tech_manager = null
	# Should not crash
	viewer._on_detail_research_pressed("stone_tools")


func test_research_button_does_nothing_when_no_tech_selected() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	# Do not call _show_detail_panel — pass empty string
	viewer._on_detail_research_pressed("")
	var current: String = tm.get_current_research(0)
	assert_str(current).is_equal("")


# -- Status label text --


func test_detail_panel_status_shows_available() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	viewer._show_detail_panel("stone_tools")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var status_lbl: Label = vbox.get_node("DetailStatus") as Label
	assert_str(status_lbl.text).is_equal("AVAILABLE")


func test_detail_panel_status_shows_researched() -> void:
	var tm := _create_tech_manager()
	_research_tech(tm, 0, "stone_tools")
	var viewer := _create_viewer(tm)
	viewer._show_detail_panel("stone_tools")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var status_lbl: Label = vbox.get_node("DetailStatus") as Label
	assert_str(status_lbl.text).is_equal("RESEARCHED")


func test_detail_panel_status_shows_locked() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 0)
	var viewer := _create_viewer(tm)
	# animal_husbandry prereqs not met
	viewer._show_detail_panel("animal_husbandry")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var status_lbl: Label = vbox.get_node("DetailStatus") as Label
	assert_str(status_lbl.text).is_equal("LOCKED")


func test_detail_panel_status_shows_need_resources() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 0)
	var viewer := _create_viewer(tm)
	# stone_tools: no prereqs but can't afford
	viewer._show_detail_panel("stone_tools")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var status_lbl: Label = vbox.get_node("DetailStatus") as Label
	assert_str(status_lbl.text).is_equal("NEED RESOURCES")


# -- Research time label --


func test_detail_panel_shows_research_time() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	# stone_tools research_time is 25
	viewer._show_detail_panel("stone_tools")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var time_lbl: Label = vbox.get_node("DetailTime") as Label
	assert_bool(time_lbl.visible).is_true()
	assert_str(time_lbl.text).contains("25")
	assert_str(time_lbl.text).contains("s")


# -- Leads-to map --


func test_leads_to_map_built_correctly() -> void:
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	# stone_tools is a prereq for animal_husbandry and basket_weaving
	var leads_to: Array = viewer.get_leads_to("stone_tools")
	assert_bool(leads_to.has("animal_husbandry")).is_true()
	assert_bool(leads_to.has("basket_weaving")).is_true()


func test_leads_to_map_empty_for_leaf_tech() -> void:
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	# Find a tech with no entries in the leads-to map and verify the accessor
	var leaf_id: String = ""
	for tech_id: String in viewer._tech_cache:
		if viewer.get_leads_to(tech_id).is_empty():
			leaf_id = tech_id
			break
	assert_str(leaf_id).is_not_empty()
	var leads_to: Array = viewer.get_leads_to(leaf_id)
	assert_int(leads_to.size()).is_equal(0)


func test_leads_to_map_empty_for_unknown_tech() -> void:
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	var leads_to: Array = viewer.get_leads_to("does_not_exist")
	assert_int(leads_to.size()).is_equal(0)


func test_leads_to_map_includes_all_dependents() -> void:
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	# writing has 10 dependents per the JSON analysis — verify count is > 1
	var leads_to: Array = viewer.get_leads_to("writing")
	assert_int(leads_to.size()).is_greater(1)


# -- Closing the detail panel --


func test_close_detail_panel_hides_panel() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	viewer._show_detail_panel("stone_tools")
	assert_bool(viewer.get_detail_panel().visible).is_true()
	viewer._hide_detail_panel()
	assert_bool(viewer.get_detail_panel().visible).is_false()


func test_close_detail_panel_resets_tech_id() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	viewer._show_detail_panel("stone_tools")
	assert_str(viewer.get_detail_tech_id()).is_equal("stone_tools")
	viewer._hide_detail_panel()
	assert_str(viewer.get_detail_tech_id()).is_equal("")


func test_detail_close_button_calls_hide() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	viewer._show_detail_panel("stone_tools")
	# Activate the close button inside the detail panel
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var close_btn: Button = vbox.get_node("DetailCloseRow/DetailCloseBtn") as Button
	close_btn.pressed.emit()
	assert_bool(viewer.get_detail_panel().visible).is_false()
	assert_str(viewer.get_detail_tech_id()).is_equal("")


# -- Switching between techs --


func test_opening_second_tech_updates_name_label() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	var viewer := _create_viewer(tm)
	viewer._show_detail_panel("stone_tools")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var name_lbl: Label = vbox.get_node("DetailName") as Label
	assert_str(name_lbl.text).is_equal("Stone Tools")
	# Switch to a second root tech
	viewer._show_detail_panel("fire_mastery")
	assert_str(name_lbl.text).is_equal("Fire Mastery")
	assert_str(viewer.get_detail_tech_id()).is_equal("fire_mastery")


# -- Buildings / units unlocked (aceo.13) --


func test_detail_panel_shows_unlocked_buildings() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	# stone_tools has unlock_buildings: ["mining_camp"]
	viewer._show_detail_panel("stone_tools")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var unlocks_header: Label = vbox.get_node("DetailUnlocksHeader") as Label
	var unlocks_lbl: Label = vbox.get_node("DetailUnlocks") as Label
	assert_bool(unlocks_header.visible).is_true()
	assert_bool(unlocks_lbl.visible).is_true()
	assert_str(unlocks_lbl.text).contains("Mining Camp")


func test_detail_panel_shows_unlocked_units() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 99999, 99999, 99999, 99999, 99999)
	var viewer := _create_viewer(tm)
	# bronze_working has unlock_buildings: ["barracks"], unlock_units: ["infantry"]
	viewer._show_detail_panel("bronze_working")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var unlocks_lbl: Label = vbox.get_node("DetailUnlocks") as Label
	assert_bool(unlocks_lbl.visible).is_true()
	assert_str(unlocks_lbl.text).contains("Infantry")
	assert_str(unlocks_lbl.text).contains("Barracks")


func test_detail_panel_unlocks_hidden_when_none() -> void:
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	# fire_mastery has no unlock_buildings or unlock_units
	viewer._show_detail_panel("fire_mastery")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var unlocks_header: Label = vbox.get_node("DetailUnlocksHeader") as Label
	var unlocks_lbl: Label = vbox.get_node("DetailUnlocks") as Label
	assert_bool(unlocks_header.visible).is_false()
	assert_bool(unlocks_lbl.visible).is_false()


func test_unlocks_not_in_benefits_section() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	# stone_tools has unlock_buildings in effects — should NOT appear in Benefits
	viewer._show_detail_panel("stone_tools")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var effects_lbl: Label = vbox.get_node("DetailEffects") as Label
	assert_str(effects_lbl.text).not_contains("Unlock Buildings")
	assert_str(effects_lbl.text).not_contains("Unlock Units")


# -- Percentage formatting (aceo.14) --


func test_decimal_fraction_formatted_as_percentage() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	# stone_tools has effects: {economic_bonus: {gather_rate: 0.1}}
	viewer._show_detail_panel("stone_tools")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var effects_lbl: Label = vbox.get_node("DetailEffects") as Label
	assert_str(effects_lbl.text).contains("10%")
	assert_str(effects_lbl.text).not_contains("0.1")


# -- Progress bar (aceo.15) --


func test_progress_bar_hidden_when_not_researching() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	viewer._show_detail_panel("stone_tools")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var progress_bar: ProgressBar = vbox.get_node("DetailProgressBar") as ProgressBar
	assert_bool(progress_bar.visible).is_false()


func test_progress_bar_visible_when_researching() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	tm.start_research(0, "stone_tools")
	viewer._show_detail_panel("stone_tools")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var progress_bar: ProgressBar = vbox.get_node("DetailProgressBar") as ProgressBar
	assert_bool(progress_bar.visible).is_true()


func test_progress_bar_reflects_progress_ratio() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	tm.start_research(0, "stone_tools")
	# Simulate partial progress
	tm._research_progress[0] = 12.5
	viewer._show_detail_panel("stone_tools")
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var progress_bar: ProgressBar = vbox.get_node("DetailProgressBar") as ProgressBar
	assert_float(progress_bar.value).is_greater(0.0)


func test_update_progress_updates_bar() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	tm.start_research(0, "stone_tools")
	viewer._show_detail_panel("stone_tools")
	var panel: PanelContainer = viewer.get_detail_panel()
	panel.update_progress(0.75)
	var vbox: VBoxContainer = _get_detail_vbox(viewer)
	var progress_bar: ProgressBar = vbox.get_node("DetailProgressBar") as ProgressBar
	assert_float(progress_bar.value).is_equal_approx(75.0, 0.1)
