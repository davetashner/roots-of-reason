extends GdUnitTestSuite
## Tests for age_advancement_section.gd — age advancement UI section.

const SectionScript := preload("res://scripts/ui/age_advancement_section.gd")

const RMGuard := preload("res://tests/helpers/resource_manager_guard.gd")
const GMGuard := preload("res://tests/helpers/game_manager_guard.gd")

var _rm_guard: RefCounted
var _gm_guard: RefCounted


func before_test() -> void:
	_rm_guard = RMGuard.new()
	_gm_guard = GMGuard.new()
	GameManager.current_age = 0
	GameManager.is_paused = false
	GameManager.game_speed = 1.0


func after_test() -> void:
	_gm_guard.dispose()
	_rm_guard.dispose()


# -- Helpers --


func _create_section() -> VBoxContainer:
	var section := VBoxContainer.new()
	section.set_script(SectionScript)
	add_child(section)
	auto_free(section)
	return section


func _create_mock_advancement() -> Node:
	## Minimal mock that implements the methods age_advancement_section calls.
	var node := Node.new()
	node.set_meta("advancing", false)
	node.set_meta("progress", 0.0)
	node.set_meta("advance_target", 1)
	node.set_meta("missing_techs", [] as Array[String])
	node.set_meta("start_result", true)
	node.set_meta("cancelled", false)

	# Build a GDScript with the required methods
	var script := GDScript.new()
	script.source_code = """
extends Node

func is_advancing() -> bool:
	return get_meta("advancing")

func get_advance_progress() -> float:
	return get_meta("progress")

func get_advance_target() -> int:
	return get_meta("advance_target")

func get_advance_cost(age_index: int) -> Dictionary:
	if age_index == 1:
		return {0: 200, 1: 200, 2: 200}
	return {}

func get_advance_cost_raw(age_index: int) -> Dictionary:
	if age_index == 1:
		return {"food": 200, "wood": 200, "stone": 200}
	return {}

func get_missing_techs(player_id: int) -> Array[String]:
	return get_meta("missing_techs") as Array[String]

func start_advancement(player_id: int) -> bool:
	if get_meta("start_result"):
		set_meta("advancing", true)
	return get_meta("start_result")

func cancel_advancement(player_id: int) -> void:
	set_meta("cancelled", true)
	set_meta("advancing", false)
"""
	script.reload()
	node.set_script(script)
	add_child(node)
	auto_free(node)
	return node


func _create_mock_building(bname: String = "town_center", under_construction: bool = false) -> Node2D:
	var b := Node2D.new()
	b.set_meta("building_name", bname)
	b.set_meta("under_construction", under_construction)

	var script := GDScript.new()
	script.source_code = """
extends Node2D

var building_name: String:
	get: return get_meta("building_name")

var under_construction: bool:
	get: return get_meta("under_construction")
"""
	script.reload()
	b.set_script(script)
	add_child(b)
	auto_free(b)
	return b


# -- Initial state tests --


func test_starts_hidden() -> void:
	var section := _create_section()
	assert_bool(section.visible).is_false()


func test_mouse_filter_is_ignore() -> void:
	var section := _create_section()
	assert_int(section.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


# -- setup tests --


func test_setup_stores_references() -> void:
	var section := _create_section()
	var adv := _create_mock_advancement()
	section.setup(adv, 0)
	assert_object(section._age_advancement).is_same(adv)
	assert_int(section._player_id).is_equal(0)


func test_setup_with_player_id() -> void:
	var section := _create_section()
	var adv := _create_mock_advancement()
	section.setup(adv, 2)
	assert_int(section._player_id).is_equal(2)


# -- update_display visibility tests --


func test_hidden_when_no_advancement() -> void:
	var section := _create_section()
	var building := _create_mock_building()
	section.update_display(building)
	assert_bool(section.visible).is_false()


func test_hidden_for_non_town_center() -> void:
	var section := _create_section()
	var adv := _create_mock_advancement()
	section.setup(adv)
	var building := _create_mock_building("barracks")
	section.update_display(building)
	assert_bool(section.visible).is_false()


func test_hidden_for_under_construction() -> void:
	var section := _create_section()
	var adv := _create_mock_advancement()
	section.setup(adv)
	var building := _create_mock_building("town_center", true)
	section.update_display(building)
	assert_bool(section.visible).is_false()


func test_hidden_at_max_age() -> void:
	var section := _create_section()
	var adv := _create_mock_advancement()
	section.setup(adv)
	GameManager.current_age = AgeAdvancement.MAX_AGE
	var building := _create_mock_building()
	section.update_display(building)
	assert_bool(section.visible).is_false()


func test_visible_for_valid_town_center() -> void:
	var section := _create_section()
	var adv := _create_mock_advancement()
	section.setup(adv)
	(
		ResourceManager
		. init_player(
			0,
			{
				ResourceManager.ResourceType.FOOD: 200,
				ResourceManager.ResourceType.WOOD: 200,
				ResourceManager.ResourceType.STONE: 200,
			}
		)
	)
	var building := _create_mock_building()
	section.update_display(building)
	assert_bool(section.visible).is_true()


# -- update_display content tests --


func test_shows_advance_button_when_not_advancing() -> void:
	var section := _create_section()
	var adv := _create_mock_advancement()
	section.setup(adv)
	(
		ResourceManager
		. init_player(
			0,
			{
				ResourceManager.ResourceType.FOOD: 200,
				ResourceManager.ResourceType.WOOD: 200,
				ResourceManager.ResourceType.STONE: 200,
			}
		)
	)
	var building := _create_mock_building()
	section.update_display(building)
	assert_str(section._button.text).contains("Advance to")


func test_shows_cancel_button_when_advancing() -> void:
	var section := _create_section()
	var adv := _create_mock_advancement()
	adv.set_meta("advancing", true)
	adv.set_meta("progress", 0.5)
	section.setup(adv)
	var building := _create_mock_building()
	section.update_display(building)
	assert_str(section._button.text).is_equal("Cancel")
	assert_bool(section._progress_bar.visible).is_true()


func test_progress_bar_hidden_when_not_advancing() -> void:
	var section := _create_section()
	var adv := _create_mock_advancement()
	section.setup(adv)
	(
		ResourceManager
		. init_player(
			0,
			{
				ResourceManager.ResourceType.FOOD: 200,
				ResourceManager.ResourceType.WOOD: 200,
				ResourceManager.ResourceType.STONE: 200,
			}
		)
	)
	var building := _create_mock_building()
	section.update_display(building)
	assert_bool(section._progress_bar.visible).is_false()


func test_progress_bar_value_reflects_progress() -> void:
	var section := _create_section()
	var adv := _create_mock_advancement()
	adv.set_meta("advancing", true)
	adv.set_meta("progress", 0.75)
	section.setup(adv)
	var building := _create_mock_building()
	section.update_display(building)
	assert_float(section._progress_bar.value).is_equal_approx(75.0, 0.1)


func test_cost_label_shows_costs() -> void:
	var section := _create_section()
	var adv := _create_mock_advancement()
	section.setup(adv)
	(
		ResourceManager
		. init_player(
			0,
			{
				ResourceManager.ResourceType.FOOD: 200,
				ResourceManager.ResourceType.WOOD: 200,
				ResourceManager.ResourceType.STONE: 200,
			}
		)
	)
	var building := _create_mock_building()
	section.update_display(building)
	assert_str(section._cost_label.text).contains("Cost:")


func test_button_disabled_when_missing_techs() -> void:
	var section := _create_section()
	var adv := _create_mock_advancement()
	var missing: Array[String] = ["stone_tools"]
	adv.set_meta("missing_techs", missing)
	section.setup(adv)
	var building := _create_mock_building()
	section.update_display(building)
	assert_bool(section._button.disabled).is_true()
	assert_str(section._missing_label.text).contains("Need:")


func test_button_disabled_when_insufficient_resources() -> void:
	var section := _create_section()
	var adv := _create_mock_advancement()
	section.setup(adv)
	(
		ResourceManager
		. init_player(
			0,
			{
				ResourceManager.ResourceType.FOOD: 0,
				ResourceManager.ResourceType.WOOD: 0,
				ResourceManager.ResourceType.STONE: 0,
			}
		)
	)
	var building := _create_mock_building()
	section.update_display(building)
	assert_bool(section._button.disabled).is_true()
	assert_str(section._missing_label.text).contains("Not enough resources")


func test_button_enabled_when_can_advance() -> void:
	var section := _create_section()
	var adv := _create_mock_advancement()
	section.setup(adv)
	(
		ResourceManager
		. init_player(
			0,
			{
				ResourceManager.ResourceType.FOOD: 200,
				ResourceManager.ResourceType.WOOD: 200,
				ResourceManager.ResourceType.STONE: 200,
			}
		)
	)
	var building := _create_mock_building()
	section.update_display(building)
	assert_bool(section._button.disabled).is_false()
	assert_str(section._missing_label.text).is_equal("")


# -- button press tests --


func test_button_press_starts_advancement() -> void:
	var section := _create_section()
	var adv := _create_mock_advancement()
	section.setup(adv)
	section._on_button_pressed()
	assert_bool(adv.is_advancing()).is_true()


func test_button_press_cancels_when_advancing() -> void:
	var section := _create_section()
	var adv := _create_mock_advancement()
	adv.set_meta("advancing", true)
	section.setup(adv)
	section._on_button_pressed()
	assert_bool(adv.get_meta("cancelled")).is_true()


func test_button_press_noop_without_advancement() -> void:
	var section := _create_section()
	# No setup called — _age_advancement is null
	section._on_button_pressed()
	# Should not crash
	assert_bool(true).is_true()
