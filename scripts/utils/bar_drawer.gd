class_name BarDrawer
## Static utility for drawing rectangular bars (HP, progress, etc.) via CanvasItem.draw_* calls.


## Draw a filled bar with background, fill, and optional border.
## [param ci]: The CanvasItem doing the drawing (typically `self` from _draw()).
## [param pos]: Top-left corner of the bar in local coordinates.
## [param size]: Width and height of the bar.
## [param fill_ratio]: 0.0–1.0 how much of the bar is filled.
## [param fill_color]: Color for the filled portion.
## [param bg_color]: Color for the background rectangle.
## [param border_color]: If non-transparent, draws a 1px border. Pass Color.TRANSPARENT to skip.
static func draw_bar(
	ci: CanvasItem,
	pos: Vector2,
	size: Vector2,
	fill_ratio: float,
	fill_color: Color,
	bg_color: Color = Color(0.1, 0.1, 0.1, 0.8),
	border_color: Color = Color(1, 1, 1, 0.5),
) -> void:
	var rect := Rect2(pos, size)
	ci.draw_rect(rect, bg_color)
	ci.draw_rect(Rect2(pos, Vector2(size.x * clampf(fill_ratio, 0.0, 1.0), size.y)), fill_color)
	if border_color.a > 0.0:
		ci.draw_rect(rect, border_color, false)
