extends Node2D
## Prototype building — isometric footprint-aware, targetable by right-click.
## entity_category is set at spawn based on owner_id.

@export var owner_id: int = 0
var entity_category: String = "own_building"
var building_name: String = ""
var footprint := Vector2i(1, 1)
var grid_pos := Vector2i.ZERO
var hp: int = 0
var max_hp: int = 0
var selected: bool = false


func get_entity_category() -> String:
	return entity_category


func select() -> void:
	selected = true
	queue_redraw()


func deselect() -> void:
	selected = false
	queue_redraw()


func is_point_inside(point: Vector2) -> bool:
	# Check if point falls within any footprint cell's isometric diamond
	var local_point := point - global_position
	for x in footprint.x:
		for y in footprint.y:
			var cell_center := IsoUtils.grid_to_screen(Vector2(x, y))
			var offset := local_point - cell_center
			# Isometric diamond test: |ox/hw| + |oy/hh| <= 1
			var nx := absf(offset.x) / IsoUtils.HALF_W
			var ny := absf(offset.y) / IsoUtils.HALF_H
			if nx + ny <= 1.0:
				return true
	return false


func _draw() -> void:
	var color: Color
	if owner_id == 0:
		color = Color(0.2, 0.5, 1.0)
	else:
		color = Color(0.8, 0.2, 0.2)
	# Draw isometric diamonds for each footprint cell
	for x in footprint.x:
		for y in footprint.y:
			var offset := IsoUtils.grid_to_screen(Vector2(x, y))
			_draw_iso_cell(offset, color)
	# Selection highlight
	if selected:
		_draw_selection_outline()


func _draw_iso_cell(offset: Vector2, color: Color) -> void:
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
	draw_colored_polygon(points, color)
	draw_line(points[0], points[1], color.darkened(0.3), 2.0)
	draw_line(points[1], points[2], color.darkened(0.3), 2.0)
	draw_line(points[2], points[3], color.darkened(0.3), 2.0)
	draw_line(points[3], points[0], color.darkened(0.3), 2.0)


func _draw_selection_outline() -> void:
	var hw := IsoUtils.HALF_W
	var hh := IsoUtils.HALF_H
	# Corners of the bounding iso region
	var top := IsoUtils.grid_to_screen(Vector2(0, 0)) + Vector2(0, -hh)
	var right := IsoUtils.grid_to_screen(Vector2(footprint.x - 1, 0)) + Vector2(hw, 0)
	var bottom := IsoUtils.grid_to_screen(Vector2(footprint.x - 1, footprint.y - 1)) + Vector2(0, hh)
	var left := IsoUtils.grid_to_screen(Vector2(0, footprint.y - 1)) + Vector2(-hw, 0)
	var highlight := Color(1.0, 1.0, 0.3, 0.8)
	draw_line(top, right, highlight, 2.0)
	draw_line(right, bottom, highlight, 2.0)
	draw_line(bottom, left, highlight, 2.0)
	draw_line(left, top, highlight, 2.0)
