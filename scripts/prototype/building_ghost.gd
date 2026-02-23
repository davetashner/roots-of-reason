extends Node2D
## Visual-only ghost preview for building placement.
## Draws isometric diamonds for each footprint cell with green/red tint.

const VALID_COLOR := Color(0.2, 0.8, 0.2, 0.4)
const INVALID_COLOR := Color(0.8, 0.2, 0.2, 0.4)
const OUTLINE_ALPHA := 0.7

var _footprint := Vector2i(1, 1)
var _is_valid := true


func setup(footprint_size: Vector2i) -> void:
	_footprint = footprint_size
	queue_redraw()


func set_valid(valid: bool) -> void:
	if _is_valid != valid:
		_is_valid = valid
		queue_redraw()


func _draw() -> void:
	var fill_color := VALID_COLOR if _is_valid else INVALID_COLOR
	var outline_color := Color(fill_color, OUTLINE_ALPHA)
	for x in _footprint.x:
		for y in _footprint.y:
			var offset := IsoUtils.grid_to_screen(Vector2(x, y))
			_draw_iso_diamond(offset, fill_color, outline_color)


func _draw_iso_diamond(offset: Vector2, fill: Color, outline: Color) -> void:
	var hw := IsoUtils.HALF_W
	var hh := IsoUtils.HALF_H
	var points := PackedVector2Array(
		[
			offset + Vector2(0, -hh),
			offset + Vector2(hw, 0),
			offset + Vector2(0, hh),
			offset + Vector2(-hw, 0),
		]
	)
	draw_colored_polygon(points, fill)
	# Draw outline
	for i in points.size():
		draw_line(points[i], points[(i + 1) % points.size()], outline, 2.0)
