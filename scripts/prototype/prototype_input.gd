extends Node
## Prototype input handler — selection, box-select, movement commands.

var _units: Array[Node] = []
var _box_selecting: bool = false
var _box_start: Vector2 = Vector2.ZERO
var _box_end: Vector2 = Vector2.ZERO
var _selection_rect_node: Node2D = null


func _ready() -> void:
	# Gather all units from parent scene
	_refresh_units()
	# Create a node for drawing selection box
	_selection_rect_node = Node2D.new()
	_selection_rect_node.z_index = 100
	_selection_rect_node.set_script(preload("res://scripts/prototype/selection_rect.gd"))
	add_child(_selection_rect_node)


func _refresh_units() -> void:
	_units.clear()
	var parent := get_parent()
	if parent == null:
		return
	for child in parent.get_children():
		if child.has_method("select"):
			_units.append(child)


func register_unit(unit: Node) -> void:
	if unit not in _units:
		_units.append(unit)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _box_selecting:
		_box_end = _get_world_mouse(event as InputEventMouseMotion)
		_update_selection_rect()


func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return

	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			var world_pos := _screen_to_world(mb.position, camera)
			# Check if clicking a unit
			var clicked_unit := _unit_at(world_pos)
			if clicked_unit != null:
				if not Input.is_key_pressed(KEY_SHIFT):
					_deselect_all()
				clicked_unit.select()
			else:
				# Start box select
				_box_selecting = true
				_box_start = world_pos
				_box_end = world_pos
		else:
			# Release — finish box select
			if _box_selecting:
				_box_selecting = false
				_do_box_select()
				_clear_selection_rect()

	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		var world_pos := _screen_to_world(mb.position, camera)
		_move_selected(world_pos)


func _unit_at(world_pos: Vector2) -> Node:
	for unit in _units:
		if unit.has_method("is_point_inside") and unit.is_point_inside(world_pos):
			return unit
	return null


func _deselect_all() -> void:
	for unit in _units:
		if unit.has_method("deselect"):
			unit.deselect()


func _move_selected(world_pos: Vector2) -> void:
	var selected: Array[Node] = []
	for unit in _units:
		if "selected" in unit and unit.selected:
			selected.append(unit)
	if selected.is_empty():
		return
	# Spread units around target
	for i in selected.size():
		var offset := Vector2.ZERO
		if selected.size() > 1:
			var angle := TAU * i / selected.size()
			offset = Vector2(cos(angle), sin(angle)) * 20.0
		if selected[i].has_method("move_to"):
			selected[i].move_to(world_pos + offset)


func _do_box_select() -> void:
	var rect := Rect2(_box_start, _box_end - _box_start).abs()
	if rect.size.length() < 5.0:
		# Too small, treat as click-deselect
		if not Input.is_key_pressed(KEY_SHIFT):
			_deselect_all()
		return
	if not Input.is_key_pressed(KEY_SHIFT):
		_deselect_all()
	for unit in _units:
		if rect.has_point(unit.global_position):
			if unit.has_method("select"):
				unit.select()


func _screen_to_world(screen_pos: Vector2, camera: Camera2D) -> Vector2:
	var vp_size := camera.get_viewport_rect().size
	var offset := screen_pos - vp_size / 2.0
	return camera.position + offset / camera.zoom


func _update_selection_rect() -> void:
	if _selection_rect_node != null and _selection_rect_node.has_method("set_rect"):
		_selection_rect_node.set_rect(_box_start, _box_end)


func _clear_selection_rect() -> void:
	if _selection_rect_node != null and _selection_rect_node.has_method("clear_rect"):
		_selection_rect_node.clear_rect()


func get_selected_count() -> int:
	var count := 0
	for unit in _units:
		if "selected" in unit and unit.selected:
			count += 1
	return count
