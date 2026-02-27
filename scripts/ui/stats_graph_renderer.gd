extends Control
## Custom drawing control for line charts and bar charts in post-game stats.

enum ChartType { LINE, BAR }

var _chart_type: ChartType = ChartType.LINE
var _series: Array = []  # Array of {label: String, color: Color, values: Array[float]}
var _x_labels: Array = []
var _y_label: String = ""
var _grid_color: Color = Color(0.2, 0.2, 0.2)
var _axis_color: Color = Color(0.53, 0.53, 0.53)
var _line_width: float = 2.0
var _padding := Vector2(50, 30)
var _legend_height: float = 25.0


func set_data(
	series: Array, x_labels: Array = [], y_label: String = "", chart_type: ChartType = ChartType.LINE
) -> void:
	_series = series
	_x_labels = x_labels
	_y_label = y_label
	_chart_type = chart_type
	queue_redraw()


func set_chart_type(chart_type: ChartType) -> void:
	_chart_type = chart_type
	queue_redraw()


func set_grid_color(c: Color) -> void:
	_grid_color = c
	queue_redraw()


func set_axis_color(c: Color) -> void:
	_axis_color = c
	queue_redraw()


func set_line_width(w: float) -> void:
	_line_width = w
	queue_redraw()


func get_series() -> Array:
	return _series


func _get_minimum_size() -> Vector2:
	return Vector2(200, 150)


func _draw() -> void:
	if _series.is_empty():
		return

	var chart_rect := _get_chart_rect()
	_draw_grid(chart_rect)
	_draw_axes(chart_rect)

	match _chart_type:
		ChartType.LINE:
			_draw_line_chart(chart_rect)
		ChartType.BAR:
			_draw_bar_chart(chart_rect)

	_draw_legend(chart_rect)


func _get_chart_rect() -> Rect2:
	var s := size
	return Rect2(
		_padding.x,
		_padding.y,
		s.x - _padding.x * 2,
		s.y - _padding.y * 2 - _legend_height,
	)


func _get_max_value() -> float:
	var max_val := 0.0
	for s: Dictionary in _series:
		var values: Array = s.get("values", [])
		for v: float in values:
			max_val = maxf(max_val, v)
	return max_val if max_val > 0.0 else 1.0


func _get_max_point_count() -> int:
	var max_count := 0
	for s: Dictionary in _series:
		var values: Array = s.get("values", [])
		max_count = maxi(max_count, values.size())
	return max_count


func _draw_grid(rect: Rect2) -> void:
	var grid_lines := 4
	for i in range(grid_lines + 1):
		var y: float = rect.position.y + rect.size.y * (float(i) / grid_lines)
		draw_line(
			Vector2(rect.position.x, y),
			Vector2(rect.position.x + rect.size.x, y),
			_grid_color,
			1.0,
		)


func _draw_axes(rect: Rect2) -> void:
	# Y axis
	draw_line(rect.position, Vector2(rect.position.x, rect.end.y), _axis_color, 1.5)
	# X axis
	draw_line(Vector2(rect.position.x, rect.end.y), rect.end, _axis_color, 1.5)

	# Y axis labels
	var max_val := _get_max_value()
	var grid_lines := 4
	var font := ThemeDB.fallback_font
	var font_size := 10
	for i in range(grid_lines + 1):
		var val: float = max_val * (1.0 - float(i) / grid_lines)
		var y: float = rect.position.y + rect.size.y * (float(i) / grid_lines)
		var label := _format_number(val)
		draw_string(
			font,
			Vector2(rect.position.x - 45, y + 4),
			label,
			HORIZONTAL_ALIGNMENT_RIGHT,
			40,
			font_size,
			_axis_color,
		)

	# X axis labels
	if not _x_labels.is_empty():
		var x_count := _x_labels.size()
		for i in range(x_count):
			var x: float = rect.position.x + rect.size.x * (float(i) / maxf(x_count - 1, 1))
			draw_string(
				font,
				Vector2(x - 15, rect.end.y + 14),
				str(_x_labels[i]),
				HORIZONTAL_ALIGNMENT_CENTER,
				30,
				font_size,
				_axis_color,
			)


func _draw_line_chart(rect: Rect2) -> void:
	var max_val := _get_max_value()
	for s: Dictionary in _series:
		var values: Array = s.get("values", [])
		var color: Color = s.get("color", Color.WHITE)
		if values.size() < 2:
			continue
		var points := PackedVector2Array()
		for i in range(values.size()):
			var x: float = rect.position.x + rect.size.x * (float(i) / (values.size() - 1))
			var y: float = rect.end.y - rect.size.y * (float(values[i]) / max_val)
			points.append(Vector2(x, y))
		draw_polyline(points, color, _line_width, true)


func _draw_bar_chart(rect: Rect2) -> void:
	var max_val := _get_max_value()
	var num_groups := _get_max_point_count()
	if num_groups == 0:
		return
	var num_series := _series.size()
	var group_width: float = rect.size.x / num_groups
	var bar_width: float = (group_width * 0.7) / maxf(num_series, 1)
	var gap: float = group_width * 0.15

	for si in range(num_series):
		var s: Dictionary = _series[si]
		var values: Array = s.get("values", [])
		var color: Color = s.get("color", Color.WHITE)
		for vi in range(values.size()):
			var bar_height: float = rect.size.y * (float(values[vi]) / max_val)
			var x: float = rect.position.x + group_width * vi + gap + bar_width * si
			var y: float = rect.end.y - bar_height
			draw_rect(Rect2(x, y, bar_width, bar_height), color)


func _draw_legend(rect: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var font_size := 11
	var x: float = rect.position.x
	var y: float = rect.end.y + _legend_height + 5
	for s: Dictionary in _series:
		var color: Color = s.get("color", Color.WHITE)
		var label: String = s.get("label", "")
		draw_rect(Rect2(x, y - 8, 12, 12), color)
		draw_string(font, Vector2(x + 16, y + 2), label, HORIZONTAL_ALIGNMENT_LEFT, 200, font_size, Color.WHITE)
		x += label.length() * 7 + 40


func _format_number(val: float) -> String:
	if val >= 1000:
		return "%dk" % int(val / 1000)
	return str(int(val))
