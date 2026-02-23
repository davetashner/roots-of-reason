extends Node2D
## Prototype building — isometric footprint-aware, targetable by right-click.
## Supports construction state: starts translucent, built by villagers over time.

signal construction_complete(building: Node2D)

@export var owner_id: int = 0
var entity_category: String = "own_building"
var building_name: String = ""
var footprint := Vector2i(1, 1)
var grid_pos := Vector2i.ZERO
var hp: int = 0
var max_hp: int = 0
var selected: bool = false

var under_construction: bool = false
var build_progress: float = 0.0
var _build_time: float = 1.0

var _construction_alpha: float = 0.4
var _bar_width: float = 40.0
var _bar_height: float = 5.0
var _bar_offset_y: float = -30.0


func _ready() -> void:
	_load_construction_config()


func _load_construction_config() -> void:
	var cfg: Dictionary = {}
	if Engine.has_singleton("DataLoader"):
		cfg = DataLoader.get_settings("construction")
	elif is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_settings"):
			cfg = dl.get_settings("construction")
	if cfg.is_empty():
		return
	_construction_alpha = float(cfg.get("construction_alpha", _construction_alpha))
	_bar_width = float(cfg.get("progress_bar_width", _bar_width))
	_bar_height = float(cfg.get("progress_bar_height", _bar_height))
	_bar_offset_y = float(cfg.get("progress_bar_offset_y", _bar_offset_y))


func get_entity_category() -> String:
	if under_construction:
		return "construction_site"
	return entity_category


func apply_build_work(amount: float) -> void:
	if not under_construction:
		return
	build_progress = clampf(build_progress + amount, 0.0, 1.0)
	hp = int(build_progress * max_hp)
	queue_redraw()
	if build_progress >= 1.0 - 0.001:
		_complete_construction()


func _complete_construction() -> void:
	under_construction = false
	hp = max_hp
	build_progress = 1.0
	queue_redraw()
	construction_complete.emit(self)


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
	if under_construction:
		color.a = _construction_alpha
	# Draw isometric diamonds for each footprint cell
	for x in footprint.x:
		for y in footprint.y:
			var offset := IsoUtils.grid_to_screen(Vector2(x, y))
			_draw_iso_cell(offset, color)
	# Selection highlight
	if selected:
		_draw_selection_outline()
	# Progress bar during construction
	if under_construction:
		_draw_progress_bar()


func _draw_progress_bar() -> void:
	var bar_x := -_bar_width / 2.0
	var bar_y := _bar_offset_y
	# Background
	draw_rect(Rect2(bar_x, bar_y, _bar_width, _bar_height), Color(0.1, 0.1, 0.1, 0.8))
	# Fill
	var fill_width := _bar_width * build_progress
	draw_rect(Rect2(bar_x, bar_y, fill_width, _bar_height), Color(0.2, 0.8, 0.2, 0.9))
	# Border
	draw_rect(Rect2(bar_x, bar_y, _bar_width, _bar_height), Color(1, 1, 1, 0.5), false)


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
	var line_color := Color(color, 1.0).darkened(0.3)
	draw_line(points[0], points[1], line_color, 2.0)
	draw_line(points[1], points[2], line_color, 2.0)
	draw_line(points[2], points[3], line_color, 2.0)
	draw_line(points[3], points[0], line_color, 2.0)


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


func save_state() -> Dictionary:
	return {
		"building_name": building_name,
		"grid_pos": [grid_pos.x, grid_pos.y],
		"owner_id": owner_id,
		"hp": hp,
		"max_hp": max_hp,
		"under_construction": under_construction,
		"build_progress": build_progress,
		"build_time": _build_time,
	}


func load_state(data: Dictionary) -> void:
	building_name = str(data.get("building_name", ""))
	var pos_arr: Array = data.get("grid_pos", [0, 0])
	grid_pos = Vector2i(int(pos_arr[0]), int(pos_arr[1]))
	owner_id = int(data.get("owner_id", 0))
	hp = int(data.get("hp", 0))
	max_hp = int(data.get("max_hp", 0))
	under_construction = bool(data.get("under_construction", false))
	build_progress = float(data.get("build_progress", 0.0))
	_build_time = float(data.get("build_time", 1.0))
	queue_redraw()
