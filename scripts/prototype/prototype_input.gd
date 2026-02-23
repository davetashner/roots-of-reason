extends Node
## Prototype input handler — selection, box-select, control groups, movement commands.

var _units: Array[Node] = []
var _box_selecting: bool = false
var _box_start: Vector2 = Vector2.ZERO
var _box_end: Vector2 = Vector2.ZERO
var _selection_rect_node: Node2D = null

var _max_selection_size: int = 40
var _double_tap_threshold_ms: int = 400
var _control_groups: Dictionary = {}
var _last_group_tap: Dictionary = {}
var _last_recalled_group: int = -1
var _camera: Camera2D = null


func _ready() -> void:
	_load_config()
	# Gather all units from parent scene
	_refresh_units()
	# Create a node for drawing selection box
	_selection_rect_node = Node2D.new()
	_selection_rect_node.z_index = 100
	_selection_rect_node.set_script(preload("res://scripts/prototype/selection_rect.gd"))
	add_child(_selection_rect_node)


func _load_config() -> void:
	var cfg: Dictionary = {}
	if Engine.has_singleton("DataLoader"):
		cfg = DataLoader.get_settings("selection")
	elif is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_settings"):
			cfg = dl.get_settings("selection")
	if cfg.is_empty():
		return
	_max_selection_size = int(cfg.get("max_selection_size", _max_selection_size))
	_double_tap_threshold_ms = int(cfg.get("double_tap_threshold_ms", _double_tap_threshold_ms))


func setup(camera: Camera2D) -> void:
	_camera = camera


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
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event as InputEventKey)


func _handle_key(key: InputEventKey) -> void:
	var keycode := key.keycode
	if keycode < KEY_0 or keycode > KEY_9:
		return
	var group_index: int = keycode - KEY_0
	if key.ctrl_pressed:
		_assign_control_group(group_index)
	else:
		_recall_control_group(group_index)


func _assign_control_group(group_index: int) -> void:
	var selected := _get_selected_units()
	if selected.size() > _max_selection_size:
		selected.resize(_max_selection_size)
	_control_groups[group_index] = selected


func _recall_control_group(group_index: int) -> void:
	_deselect_all()
	if not _control_groups.has(group_index):
		_last_recalled_group = group_index
		return
	# Filter out freed units
	var group: Array[Node] = []
	for unit in _control_groups[group_index]:
		if is_instance_valid(unit):
			group.append(unit)
	_control_groups[group_index] = group
	for unit in group:
		if unit.has_method("select"):
			unit.select()
	# Double-tap detection for camera centering
	var now := Time.get_ticks_msec()
	if _last_recalled_group == group_index and _last_group_tap.has(group_index):
		var elapsed: int = now - int(_last_group_tap[group_index])
		if elapsed <= _double_tap_threshold_ms and not group.is_empty():
			_center_camera_on_group(group_index)
	_last_group_tap[group_index] = now
	_last_recalled_group = group_index


func _center_camera_on_group(group_index: int) -> void:
	if _camera == null:
		return
	if not _control_groups.has(group_index):
		return
	var group: Array = _control_groups[group_index]
	if group.is_empty():
		return
	var centroid := Vector2.ZERO
	var count := 0
	for unit in group:
		if is_instance_valid(unit):
			centroid += unit.global_position
			count += 1
	if count > 0:
		_camera.position = centroid / count


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
				if Input.is_key_pressed(KEY_SHIFT):
					if clicked_unit.selected:
						clicked_unit.deselect()
					else:
						if get_selected_count() < _max_selection_size:
							clicked_unit.select()
				else:
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
		if "owner_id" in unit and unit.owner_id != 0:
			continue
		if unit.has_method("is_point_inside") and unit.is_point_inside(world_pos):
			return unit
	return null


func _deselect_all() -> void:
	for unit in _units:
		if is_instance_valid(unit) and unit.has_method("deselect"):
			unit.deselect()


func _get_selected_units() -> Array[Node]:
	var result: Array[Node] = []
	for unit in _units:
		if is_instance_valid(unit) and "selected" in unit and unit.selected:
			result.append(unit)
	return result


func get_active_group() -> int:
	return _last_recalled_group


func _move_selected(world_pos: Vector2) -> void:
	var selected: Array[Node] = []
	for unit in _units:
		if is_instance_valid(unit) and "selected" in unit and unit.selected:
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
	var count := get_selected_count()
	for unit in _units:
		if count >= _max_selection_size:
			break
		if "owner_id" in unit and unit.owner_id != 0:
			continue
		if rect.has_point(unit.global_position):
			if unit.has_method("select"):
				unit.select()
				count += 1


func _get_world_mouse(motion: InputEventMouseMotion) -> Vector2:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return motion.position
	return _screen_to_world(motion.position, camera)


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
		if is_instance_valid(unit) and "selected" in unit and unit.selected:
			count += 1
	return count


func save_state() -> Dictionary:
	# Build selected unit indices
	var selected_indices: Array[int] = []
	for i in _units.size():
		if "selected" in _units[i] and _units[i].selected:
			selected_indices.append(i)
	# Build control group data as index arrays
	var groups_data: Dictionary = {}
	for group_index in _control_groups:
		var indices: Array[int] = []
		for unit in _control_groups[group_index]:
			if is_instance_valid(unit):
				var idx := _units.find(unit)
				if idx >= 0:
					indices.append(idx)
		groups_data[str(group_index)] = indices
	return {
		"selected_indices": selected_indices,
		"control_groups": groups_data,
		"last_recalled_group": _last_recalled_group,
	}


func load_state(data: Dictionary) -> void:
	_deselect_all()
	_control_groups.clear()
	_last_recalled_group = int(data.get("last_recalled_group", -1))
	# Restore selected units
	var selected_indices: Array = data.get("selected_indices", [])
	for idx in selected_indices:
		var i := int(idx)
		if i >= 0 and i < _units.size() and _units[i].has_method("select"):
			_units[i].select()
	# Restore control groups
	var groups_data: Dictionary = data.get("control_groups", {})
	for key in groups_data:
		var group_index := int(key)
		var indices: Array = groups_data[key]
		var group: Array[Node] = []
		for idx in indices:
			var i := int(idx)
			if i >= 0 and i < _units.size():
				group.append(_units[i])
		_control_groups[group_index] = group
