extends GdUnitTestSuite
## Tests for scripts/ui/info_panel.gd — HP color thresholds, panel visibility,
## and resource node hover display.

const InfoPanelScript := preload("res://scripts/ui/info_panel.gd")
const ResourceNodeScript := preload("res://scripts/prototype/prototype_resource_node.gd")


func _create_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_script(InfoPanelScript)
	add_child(panel)
	auto_free(panel)
	return panel


func _create_resource_node(
	res_name: String = "gold_mine", res_type: String = "gold", yield_amt: int = 800, regen: bool = false
) -> Node2D:
	var n := Node2D.new()
	n.set_script(ResourceNodeScript)
	n.resource_name = res_name
	n.resource_type = res_type
	n.total_yield = yield_amt
	n.current_yield = yield_amt
	n.regenerates = regen
	add_child(n)
	auto_free(n)
	return n


# -- _get_hp_color --


func test_hp_color_full_health_is_green() -> void:
	var panel := _create_panel()
	var color: Color = panel._get_hp_color(1.0)
	# Green channel should dominate
	assert_float(color.g).is_greater(0.7)
	assert_float(color.r).is_less(0.3)


func test_hp_color_half_health_is_yellow() -> void:
	var panel := _create_panel()
	var color: Color = panel._get_hp_color(0.5)
	# Yellow: both red and green high
	assert_float(color.r).is_greater(0.7)
	assert_float(color.g).is_greater(0.7)


func test_hp_color_low_health_is_red() -> void:
	var panel := _create_panel()
	var color: Color = panel._get_hp_color(0.2)
	# Red channel should dominate
	assert_float(color.r).is_greater(0.7)
	assert_float(color.g).is_less(0.3)


func test_hp_color_zero_is_red() -> void:
	var panel := _create_panel()
	var color: Color = panel._get_hp_color(0.0)
	assert_float(color.r).is_greater(0.7)
	assert_float(color.g).is_less(0.3)


# -- clear / visibility --


func test_clear_hides_panel() -> void:
	var panel := _create_panel()
	panel.visible = true
	panel.clear()
	assert_bool(panel.visible).is_false()


func test_initial_state_is_hidden() -> void:
	var panel := _create_panel()
	assert_bool(panel.visible).is_false()


# -- show_resource_node --


func test_show_resource_node_makes_panel_visible() -> void:
	var panel := _create_panel()
	var node := _create_resource_node()
	panel.show_resource_node(node)
	assert_bool(panel.visible).is_true()


func test_show_resource_node_displays_correct_name() -> void:
	var panel := _create_panel()
	var node := _create_resource_node("gold_mine", "gold")
	panel.show_resource_node(node)
	assert_str(panel._name_label.text).is_equal("Gold Mine")


func test_show_resource_node_displays_regen_status() -> void:
	var panel := _create_panel()
	var node := _create_resource_node("tree", "wood", 200, true)
	panel.show_resource_node(node)
	assert_str(panel._stats_label.text).contains("Regenerates")


func test_show_resource_node_displays_regrowing_status() -> void:
	var panel := _create_panel()
	var node := _create_resource_node("tree", "wood", 200, true)
	node._is_regrowing = true
	node.current_yield = 0
	panel.show_resource_node(node)
	assert_str(panel._stats_label.text).contains("Regrowing")


func test_show_resource_node_yield_bar_ratio() -> void:
	var panel := _create_panel()
	var node := _create_resource_node("gold_mine", "gold", 800)
	node.current_yield = 400
	panel.show_resource_node(node)
	assert_str(panel._hp_label.text).is_equal("Yield: 400/800")


func test_show_resource_node_no_regen_text_for_non_regen() -> void:
	var panel := _create_panel()
	var node := _create_resource_node("gold_mine", "gold", 800, false)
	panel.show_resource_node(node)
	assert_str(panel._stats_label.text).is_equal("Gold")
