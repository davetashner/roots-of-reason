extends GdUnitTestSuite
## Tests for scripts/ui/info_panel.gd — HP color thresholds and panel visibility.

const InfoPanelScript := preload("res://scripts/ui/info_panel.gd")


func _create_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_script(InfoPanelScript)
	add_child(panel)
	auto_free(panel)
	return panel


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
