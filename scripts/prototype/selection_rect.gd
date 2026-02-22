extends Node2D
## Draws a selection rectangle overlay.

var _start: Vector2 = Vector2.ZERO
var _end: Vector2 = Vector2.ZERO
var _visible: bool = false


func set_rect(start: Vector2, end: Vector2) -> void:
	_start = start
	_end = end
	_visible = true
	queue_redraw()


func clear_rect() -> void:
	_visible = false
	queue_redraw()


func _draw() -> void:
	if not _visible:
		return
	var rect := Rect2(_start, _end - _start).abs()
	draw_rect(rect, Color(0.2, 0.8, 0.2, 0.15), true)
	draw_rect(rect, Color(0.2, 0.8, 0.2, 0.6), false, 1.0)
