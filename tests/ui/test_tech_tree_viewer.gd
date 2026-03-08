extends GdUnitTestSuite
## Tests for tech_tree_viewer.gd — in-game tech tree UI overlay.

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


# -- Basic setup tests --


func test_viewer_starts_hidden() -> void:
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	assert_bool(viewer.visible).is_false()


func test_viewer_creates_tech_buttons() -> void:
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	# Should have created a button for every tech in tech_tree.json
	var count: int = viewer.get_tech_button_count()
	assert_int(count).is_greater(0)
	# Spot-check a known tech
	var btn: Button = viewer.get_tech_button("stone_tools")
	assert_object(btn).is_not_null()
	assert_str(btn.text).is_equal("Stone Tools")


func test_toggle_visible_shows_and_hides() -> void:
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	assert_bool(viewer.visible).is_false()
	viewer.toggle_visible()
	assert_bool(viewer.visible).is_true()
	viewer.toggle_visible()
	assert_bool(viewer.visible).is_false()


# -- Color state tests --


func test_researched_tech_shows_gold_style() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	# Research stone_tools manually
	tm.start_research(0, "stone_tools")
	# Fast-complete: simulate enough progress
	tm._research_progress[0] = 9999.0
	tm._complete_research(0)
	var viewer := _create_viewer(tm)
	var btn: Button = viewer.get_tech_button("stone_tools")
	var style: StyleBoxFlat = btn.get_theme_stylebox("normal") as StyleBoxFlat
	# Gold border = COLOR_RESEARCHED = #FFD700
	assert_object(style).is_not_null()
	assert_bool(style.border_color.is_equal_approx(Color("#FFD700"))).is_true()


func test_available_tech_shows_green_style() -> void:
	var tm := _create_tech_manager()
	# stone_tools: age 0, no prereqs, costs 50 food — give enough
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	var btn: Button = viewer.get_tech_button("stone_tools")
	var style: StyleBoxFlat = btn.get_theme_stylebox("normal") as StyleBoxFlat
	assert_object(style).is_not_null()
	assert_bool(style.border_color.is_equal_approx(Color("#4CAF50"))).is_true()


func test_locked_tech_shows_gray_style() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 0)
	# animal_husbandry requires stone_tools — not researched, so locked
	var viewer := _create_viewer(tm)
	var btn: Button = viewer.get_tech_button("animal_husbandry")
	var style: StyleBoxFlat = btn.get_theme_stylebox("normal") as StyleBoxFlat
	assert_object(style).is_not_null()
	assert_bool(style.border_color.is_equal_approx(Color("#666666"))).is_true()


func test_unaffordable_tech_shows_blue_style() -> void:
	var tm := _create_tech_manager()
	# Give zero resources so prereqs-met techs that cost resources are unaffordable
	_give_resources(0, 0)
	# stone_tools: age 0, no prereqs, costs 50 food — prereqs met but can't afford
	var viewer := _create_viewer(tm)
	var btn: Button = viewer.get_tech_button("stone_tools")
	var style: StyleBoxFlat = btn.get_theme_stylebox("normal") as StyleBoxFlat
	assert_object(style).is_not_null()
	assert_bool(style.border_color.is_equal_approx(Color("#2196F3"))).is_true()


# -- Tooltip tests --


func test_tooltip_contains_cost_info() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	var btn: Button = viewer.get_tech_button("stone_tools")
	var tooltip: String = btn.tooltip_text
	assert_str(tooltip).contains("Cost:")
	assert_str(tooltip).contains("Food")


func test_tooltip_contains_prereq_info() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 0)
	# Research stone_tools so animal_husbandry becomes visible with full tooltip
	_give_resources(0, 1000)
	tm.start_research(0, "stone_tools")
	tm._research_progress[0] = 9999.0
	tm._complete_research(0)
	_give_resources(0, 0)
	var viewer := _create_viewer(tm)
	# animal_husbandry requires stone_tools (now researched) — visible with prereq info
	var btn: Button = viewer.get_tech_button("animal_husbandry")
	var tooltip: String = btn.tooltip_text
	assert_str(tooltip).contains("Requires:")
	assert_str(tooltip).contains("Stone Tools")


func test_tooltip_contains_research_time() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	var btn: Button = viewer.get_tech_button("stone_tools")
	var tooltip: String = btn.tooltip_text
	# stone_tools has research_time 25
	assert_str(tooltip).contains("Time: 25s")


# -- Close button test --


func test_close_button_hides_viewer() -> void:
	var tm := _create_tech_manager()
	var viewer := _create_viewer(tm)
	viewer.toggle_visible()
	assert_bool(viewer.visible).is_true()
	viewer._on_close_pressed()
	assert_bool(viewer.visible).is_false()


# -- Refresh on signal --


func test_refresh_updates_after_research() -> void:
	var tm := _create_tech_manager()
	_give_resources(0, 1000)
	var viewer := _create_viewer(tm)
	# stone_tools starts as available (green)
	var btn: Button = viewer.get_tech_button("stone_tools")
	var style_before: StyleBoxFlat = btn.get_theme_stylebox("normal") as StyleBoxFlat
	assert_bool(style_before.border_color.is_equal_approx(Color("#4CAF50"))).is_true()
	# Research stone_tools
	tm.start_research(0, "stone_tools")
	tm._research_progress[0] = 9999.0
	tm._complete_research(0)
	# Refresh was auto-triggered via signal — check button is now gold
	var style_after: StyleBoxFlat = btn.get_theme_stylebox("normal") as StyleBoxFlat
	assert_bool(style_after.border_color.is_equal_approx(Color("#FFD700"))).is_true()
