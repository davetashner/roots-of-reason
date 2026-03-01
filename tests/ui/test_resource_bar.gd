extends GdUnitTestSuite
## Tests for scripts/ui/resource_bar.gd — resource bar HUD element.

const ResourceBarScript := preload("res://scripts/ui/resource_bar.gd")

const RMGuard := preload("res://tests/helpers/resource_manager_guard.gd")
const GMGuard := preload("res://tests/helpers/game_manager_guard.gd")

var _rm_guard: RefCounted
var _gm_guard: RefCounted


func before_test() -> void:
	_rm_guard = RMGuard.new()
	_gm_guard = GMGuard.new()


func after_test() -> void:
	_gm_guard.dispose()
	_rm_guard.dispose()


# --- format_amount tests ---


func test_format_amount_zero() -> void:
	assert_str(ResourceBarScript.format_amount(0)).is_equal("0")


func test_format_amount_hundreds() -> void:
	assert_str(ResourceBarScript.format_amount(500)).is_equal("500")


func test_format_amount_thousands() -> void:
	assert_str(ResourceBarScript.format_amount(1200)).is_equal("1.2k")


func test_format_amount_exact_thousand() -> void:
	assert_str(ResourceBarScript.format_amount(1000)).is_equal("1k")


func test_format_amount_large() -> void:
	assert_str(ResourceBarScript.format_amount(15300)).is_equal("15.3k")


func test_format_amount_negative() -> void:
	assert_str(ResourceBarScript.format_amount(-50)).is_equal("-50")


func test_format_amount_999() -> void:
	assert_str(ResourceBarScript.format_amount(999)).is_equal("999")


func test_format_amount_ten_thousand_even() -> void:
	assert_str(ResourceBarScript.format_amount(10000)).is_equal("10k")


# --- Scene tree tests ---


func _create_resource_bar() -> PanelContainer:
	(
		ResourceManager
		. init_player(
			0,
			{
				ResourceManager.ResourceType.FOOD: 200,
				ResourceManager.ResourceType.WOOD: 150,
				ResourceManager.ResourceType.STONE: 100,
				ResourceManager.ResourceType.GOLD: 50,
				ResourceManager.ResourceType.KNOWLEDGE: 0,
			}
		)
	)
	var bar := PanelContainer.new()
	bar.set_script(ResourceBarScript)
	add_child(bar)
	return auto_free(bar)


func test_initial_resource_labels_exist() -> void:
	var bar := _create_resource_bar()
	assert_int(bar._resource_labels.size()).is_equal(5)
	for res_name in ["Food", "Wood", "Stone", "Gold", "Knowledge"]:
		assert_bool(bar._resource_labels.has(res_name)).is_true()


func test_initial_food_label_value() -> void:
	var bar := _create_resource_bar()
	assert_str(bar._resource_labels["Food"].text).is_equal("200")


func test_initial_knowledge_label_value() -> void:
	var bar := _create_resource_bar()
	assert_str(bar._resource_labels["Knowledge"].text).is_equal("0")


func test_population_label_exists() -> void:
	var bar := _create_resource_bar()
	assert_object(bar._population_label).is_not_null()


func test_population_format() -> void:
	var bar := _create_resource_bar()
	bar.update_population(14, 20)
	assert_str(bar._population_label.text).is_equal("Pop: 14/20")


func test_age_display_stone() -> void:
	GameManager.current_age = 0
	var bar := _create_resource_bar()
	assert_str(bar._age_label.text).is_equal("Stone Age")


func test_age_display_bronze() -> void:
	GameManager.current_age = 1
	var bar := _create_resource_bar()
	bar.update_age()
	assert_str(bar._age_label.text).is_equal("Bronze Age")


func test_mouse_filter_is_ignore() -> void:
	var bar := _create_resource_bar()
	assert_int(bar.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_resource_update_via_signal() -> void:
	var bar := _create_resource_bar()
	ResourceManager.add_resource(0, ResourceManager.ResourceType.FOOD, 100)
	assert_str(bar._resource_labels["Food"].text).is_equal("300")


# --- Transit label tests ---


class MockRiverTransport:
	extends Node
	var _transit: Dictionary = {}

	func get_in_transit_resources(player_id: int) -> Dictionary:
		return _transit.get(player_id, {})


func test_transit_labels_exist() -> void:
	var bar := _create_resource_bar()
	assert_int(bar._transit_labels.size()).is_equal(5)
	for res_name in ["Food", "Wood", "Stone", "Gold", "Knowledge"]:
		assert_bool(bar._transit_labels.has(res_name)).is_true()


func test_transit_labels_initially_hidden() -> void:
	var bar := _create_resource_bar()
	for res_name in bar._transit_labels:
		var lbl: Label = bar._transit_labels[res_name]
		assert_bool(lbl.visible).is_false()


func _create_mock_transport(transit_data: Dictionary = {}) -> Node:
	var mock := MockRiverTransport.new()
	mock._transit = transit_data
	add_child(mock)
	auto_free(mock)
	return mock


func test_transit_labels_show_when_resources_in_transit() -> void:
	var bar := _create_resource_bar()
	var mock_transport := _create_mock_transport({0: {0: 25}})
	bar.setup_transit(mock_transport)
	bar._update_transit_labels()
	var food_transit: Label = bar._transit_labels["Food"]
	assert_bool(food_transit.visible).is_true()
	assert_str(food_transit.text).is_equal("(+25)")


func test_transit_labels_hidden_when_no_transit() -> void:
	var bar := _create_resource_bar()
	var mock_transport := _create_mock_transport({0: {}})
	bar.setup_transit(mock_transport)
	bar._update_transit_labels()
	var food_transit: Label = bar._transit_labels["Food"]
	assert_bool(food_transit.visible).is_false()


func test_transit_labels_format_thousands() -> void:
	var bar := _create_resource_bar()
	var mock_transport := _create_mock_transport({0: {1: 1500}})
	bar.setup_transit(mock_transport)
	bar._update_transit_labels()
	var wood_transit: Label = bar._transit_labels["Wood"]
	assert_str(wood_transit.text).is_equal("(+1.5k)")


func test_transit_null_safety() -> void:
	var bar := _create_resource_bar()
	# No river transport set — should not crash
	bar._update_transit_labels()
	assert_bool(is_instance_valid(bar)).is_true()
