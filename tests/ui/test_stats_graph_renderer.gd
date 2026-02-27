extends GdUnitTestSuite
## Tests for stats_graph_renderer.gd — custom chart control.

const RendererScript := preload("res://scripts/ui/stats_graph_renderer.gd")


func _create_renderer() -> Control:
	var renderer := Control.new()
	renderer.name = "StatsGraphRenderer"
	renderer.set_script(RendererScript)
	renderer.size = Vector2(600, 250)
	add_child(renderer)
	auto_free(renderer)
	return renderer


func test_default_state_no_crash() -> void:
	var renderer := _create_renderer()
	# Force a draw — should not crash with empty data
	renderer.queue_redraw()
	await get_tree().process_frame
	assert_that(renderer).is_not_null()


func test_set_data_stores_series() -> void:
	var renderer := _create_renderer()
	var series: Array = [
		{"label": "Player", "color": Color.BLUE, "values": [10.0, 20.0, 30.0]},
		{"label": "AI", "color": Color.RED, "values": [5.0, 15.0, 25.0]},
	]
	renderer.set_data(series, ["0:30", "1:00", "1:30"], "Score")
	assert_that(renderer.get_series().size()).is_equal(2)


func test_chart_type_switching() -> void:
	var renderer := _create_renderer()
	var series: Array = [
		{"label": "P1", "color": Color.BLUE, "values": [10.0, 20.0]},
	]
	renderer.set_data(series, ["A", "B"], "Val", RendererScript.ChartType.BAR)
	assert_that(renderer._chart_type).is_equal(RendererScript.ChartType.BAR)
	renderer.set_chart_type(RendererScript.ChartType.LINE)
	assert_that(renderer._chart_type).is_equal(RendererScript.ChartType.LINE)


func test_minimum_size() -> void:
	var renderer := _create_renderer()
	var min_size: Vector2 = renderer._get_minimum_size()
	assert_that(min_size.x).is_greater_equal(100.0)
	assert_that(min_size.y).is_greater_equal(100.0)
