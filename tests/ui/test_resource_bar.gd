extends GdUnitTestSuite
## Tests for scripts/ui/resource_bar.gd — resource bar HUD element.

const ResourceBarScript := preload("res://scripts/ui/resource_bar.gd")

var _original_age: int
var _original_stockpiles: Dictionary


func before_test() -> void:
	_original_age = GameManager.current_age
	_original_stockpiles = ResourceManager._stockpiles.duplicate(true)


func after_test() -> void:
	GameManager.current_age = _original_age
	ResourceManager._stockpiles = _original_stockpiles


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
