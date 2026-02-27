extends Node
## Prototype input handler — selection, box-select, control groups, context commands.

signal command_issued(units: Array[Node], command_type: String, target: Node, world_pos: Vector2)

const FormationManagerScript := preload("res://scripts/prototype/formation_manager.gd")

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
var _pathfinder: Node = null
var _target_detector: Node = null
var _cursor_overlay: Node = null
var _command_config: Dictionary = {}
var _attack_move_mode: bool = false
var _patrol_mode: bool = false
var _patrol_first_point: Vector2 = Vector2.ZERO
var _formation_manager: RefCounted = null
var _formation_type: int = 0  # FormationManager.FormationType.STAGGERED
var _river_overlay: Node = null


func _ready() -> void:
	_load_config()
	_load_command_config()
	_load_formation_config()
	# Gather all units from parent scene
	_refresh_units()
	# Create a node for drawing selection box
	_selection_rect_node = Node2D.new()
	_selection_rect_node.z_index = 100
	_selection_rect_node.set_script(preload("res://scripts/prototype/selection_rect.gd"))
	add_child(_selection_rect_node)


func _load_config() -> void:
	var cfg: Dictionary = GameUtils.dl_settings("selection")
	if cfg.is_empty():
		return
	_max_selection_size = int(cfg.get("max_selection_size", _max_selection_size))
	_double_tap_threshold_ms = int(cfg.get("double_tap_threshold_ms", _double_tap_threshold_ms))


func _load_command_config() -> void:
	var cfg: Dictionary = GameUtils.dl_settings("commands")
	if not cfg.is_empty():
		_command_config = cfg


func _load_formation_config() -> void:
	_formation_manager = FormationManagerScript.new()
	var cfg: Dictionary = GameUtils.dl_settings("formations")
	if cfg.is_empty():
		return
	_formation_manager.spacing = float(cfg.get("spacing", _formation_manager.spacing))
	_formation_manager.speed_sync = bool(cfg.get("speed_sync", true))
	var default_type: String = str(cfg.get("default_formation", "staggered"))
	_formation_type = FormationManagerScript.type_from_string(default_type)


func setup(
	camera: Camera2D,
	pathfinder: Node = null,
	target_detector: Node = null,
	cursor_overlay: Node = null,
) -> void:
	_camera = camera
	_pathfinder = pathfinder
	_target_detector = target_detector
	_cursor_overlay = cursor_overlay


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
	elif event is InputEventMouseMotion:
		if _box_selecting:
			_box_end = _get_world_mouse(event as InputEventMouseMotion)
			_update_selection_rect()
		else:
			_update_cursor_context(event as InputEventMouseMotion)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event as InputEventKey)


func _handle_key(key: InputEventKey) -> void:
	var keycode := key.keycode
	# Attack-move mode
	if keycode == KEY_A:
		_attack_move_mode = true
		_patrol_mode = false
		_patrol_first_point = Vector2.ZERO
		if _cursor_overlay != null and _cursor_overlay.has_method("update_command"):
			_cursor_overlay.update_command("attack_move", _command_config.get("cursor_labels", {}))
		return
	# Patrol mode
	if keycode == KEY_P:
		if not _patrol_mode:
			_patrol_mode = true
			_attack_move_mode = false
			_patrol_first_point = Vector2.ZERO
			if _cursor_overlay != null and _cursor_overlay.has_method("update_command"):
				_cursor_overlay.update_command("patrol", _command_config.get("cursor_labels", {}))
		return
	# River overlay toggle
	if keycode == KEY_R:
		if _river_overlay != null and _river_overlay.has_method("toggle"):
			_river_overlay.toggle()
		return
	# Escape cancels modes
	if keycode == KEY_ESCAPE:
		_attack_move_mode = false
		_patrol_mode = false
		_patrol_first_point = Vector2.ZERO
		if _cursor_overlay != null and _cursor_overlay.has_method("clear"):
			_cursor_overlay.clear()
		return
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
			# Attack-move mode: issue attack-move to click position
			if _attack_move_mode:
				_attack_move_mode = false
				var selected := _get_selected_units()
				_show_click_marker(world_pos, "attack_move")
				for unit in selected:
					if unit.has_method("attack_move_to"):
						unit.attack_move_to(world_pos)
				if _cursor_overlay != null and _cursor_overlay.has_method("clear"):
					_cursor_overlay.clear()
				return
			# Patrol mode: set two points
			if _patrol_mode:
				var selected := _get_selected_units()
				if _patrol_first_point == Vector2.ZERO:
					_patrol_first_point = world_pos
					_show_click_marker(world_pos, "patrol")
				else:
					_show_click_marker(world_pos, "patrol")
					for unit in selected:
						if unit.has_method("patrol_between"):
							unit.patrol_between(_patrol_first_point, world_pos)
					_patrol_mode = false
					_patrol_first_point = Vector2.ZERO
					if _cursor_overlay != null and _cursor_overlay.has_method("clear"):
						_cursor_overlay.clear()
				return
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
		_issue_context_command(world_pos)


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
	var selected := _get_selected_units()
	selected = _filter_barges(selected)
	if selected.is_empty():
		return
	_show_click_marker(world_pos)
	# Compute formation offsets
	var first_pos: Vector2 = (selected[0] as Node2D).global_position
	var facing: Vector2 = (world_pos - first_pos).normalized()
	if facing.length() < 0.1:
		facing = Vector2.RIGHT
	var fm: RefCounted = _formation_manager
	if fm == null:
		fm = FormationManagerScript.new()
	var offsets: Array[Vector2] = fm.get_offsets(_formation_type, selected.size(), facing)
	# Compute formation speed and apply
	if fm.speed_sync and selected.size() > 1:
		var group_speed: float = fm.get_formation_speed(selected)
		for unit in selected:
			if unit.has_method("set_formation_speed"):
				unit.set_formation_speed(group_speed)
	# Assign units to nearest slot (greedy)
	var slot_positions: Array[Vector2] = []
	for offset in offsets:
		slot_positions.append(world_pos + offset)
	var assignments: Array[Vector2] = _assign_slots(selected, slot_positions)
	# Move each unit to its assigned slot
	if _pathfinder != null and _pathfinder.has_method("find_path_world"):
		for i in selected.size():
			var dest: Vector2 = assignments[i]
			var unit_pos: Vector2 = (selected[i] as Node2D).global_position
			var path: Array[Vector2] = _pathfinder.find_path_world(unit_pos, dest)
			if path.size() > 0 and selected[i].has_method("follow_path"):
				selected[i].follow_path(path)
			elif selected[i].has_method("move_to"):
				selected[i].move_to(dest)
		return
	# Fallback: direct movement
	for i in selected.size():
		if selected[i].has_method("move_to"):
			selected[i].move_to(assignments[i])


func _assign_slots(units: Array[Node], slots: Array[Vector2]) -> Array[Vector2]:
	## Greedy nearest-neighbor slot assignment to minimize total distance.
	var result: Array[Vector2] = []
	result.resize(units.size())
	var used: Array[bool] = []
	used.resize(slots.size())
	for i in used.size():
		used[i] = false
	for i in units.size():
		var best_idx := 0
		var best_dist := INF
		var unit_pos: Vector2 = (units[i] as Node2D).global_position
		for j in slots.size():
			if used[j]:
				continue
			var dist: float = unit_pos.distance_to(slots[j])
			if dist < best_dist:
				best_dist = dist
				best_idx = j
		used[best_idx] = true
		result[i] = slots[best_idx]
	return result


func _issue_context_command(world_pos: Vector2) -> void:
	var selected := _get_selected_units()
	selected = _filter_barges(selected)
	if selected.is_empty():
		return
	var target: Node = null
	if _target_detector != null and _target_detector.has_method("detect"):
		target = _target_detector.detect(world_pos)
	var category := CommandResolver.get_target_category(target)
	var unit_type := CommandResolver.get_primary_unit_type(selected)
	var cmd := CommandResolver.resolve(unit_type, category, _command_config.get("command_table", {}))
	# Shift+right-click on wild fauna with villager → feed
	if Input.is_key_pressed(KEY_SHIFT) and category == "wild_fauna" and unit_type == "villager":
		cmd = "feed"
	command_issued.emit(selected, cmd, target, world_pos)
	_show_click_marker(world_pos, cmd)
	if cmd == "feed" and target != null:
		for unit in selected:
			if unit.has_method("assign_feed_target"):
				unit.assign_feed_target(target)
	elif cmd == "build" and target != null and target.has_method("apply_build_work"):
		for unit in selected:
			if unit.has_method("assign_build_target"):
				unit.assign_build_target(target)
	elif cmd == "gather" and target != null:
		for unit in selected:
			if unit.has_method("assign_gather_target"):
				unit.assign_gather_target(target)
	elif cmd == "garrison" and target != null and target.has_method("garrison_unit"):
		for unit in selected:
			if unit is Node2D:
				target.garrison_unit(unit)
	elif cmd == "embark" and target != null and target.has_method("embark_unit"):
		for unit in selected:
			if unit is Node2D:
				unit.move_to(target.global_position)
				target.embark_unit(unit)
	elif target == null and _has_transport_with_passengers(selected):
		# Transports with passengers right-clicking ground → disembark
		for unit in selected:
			if unit.has_method("disembark_all") and unit.get_embarked_count() > 0:
				unit.disembark_all(world_pos)
			elif unit.has_method("move_to"):
				unit.move_to(world_pos)
	else:
		_move_selected(world_pos)


func _resolve_command_at(world_pos: Vector2) -> String:
	var selected := _get_selected_units()
	if selected.is_empty():
		return ""
	var target: Node = null
	if _target_detector != null and _target_detector.has_method("detect"):
		target = _target_detector.detect(world_pos)
	var category := CommandResolver.get_target_category(target)
	var unit_type := CommandResolver.get_primary_unit_type(selected)
	var cmd := CommandResolver.resolve(unit_type, category, _command_config.get("command_table", {}))
	# Shift+right-click on wild fauna with villager → feed
	if Input.is_key_pressed(KEY_SHIFT) and category == "wild_fauna" and unit_type == "villager":
		cmd = "feed"
	return cmd


func _update_cursor_context(motion: InputEventMouseMotion) -> void:
	if _cursor_overlay == null:
		return
	var selected := _get_selected_units()
	if selected.is_empty():
		if _cursor_overlay.has_method("clear"):
			_cursor_overlay.clear()
		return
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	var world_pos := _screen_to_world(motion.position, camera)
	var cmd := _resolve_command_at(world_pos)
	if cmd != "" and _cursor_overlay.has_method("update_command"):
		_cursor_overlay.update_command(cmd, _command_config.get("cursor_labels", {}))


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


func _filter_barges(units: Array[Node]) -> Array[Node]:
	## Remove barges and auto-trading units from a unit list — they cannot
	## receive manual move/context commands.
	var result: Array[Node] = []
	for unit in units:
		if "entity_category" in unit:
			var cat: String = unit.entity_category
			if cat == "own_barge" or cat == "enemy_barge":
				continue
		# Filter out trade carts and merchant ships (driven by TradeCartAI)
		if "unit_type" in unit:
			var utype: String = unit.unit_type
			if utype == "trade_cart" or utype == "merchant_ship":
				continue
		result.append(unit)
	return result


func _has_transport_with_passengers(units: Array[Node]) -> bool:
	for unit in units:
		if unit.has_method("get_embarked_count") and unit.get_embarked_count() > 0:
			return true
	return false


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


func _show_click_marker(world_pos: Vector2, command_type: String = "move") -> void:
	var parent := get_parent()
	if parent == null:
		return
	var marker := _ClickMarker.new()
	marker.position = world_pos
	marker.z_index = 99
	var colors: Dictionary = _command_config.get("click_marker_colors", {})
	if colors.has(command_type):
		var c: Array = colors[command_type]
		marker.marker_color = Color(c[0], c[1], c[2], c[3])
	parent.add_child(marker)


class _ClickMarker:
	extends Node2D
	const DURATION: float = 0.5
	var marker_color: Color = Color(1, 1, 0, 1)
	var _elapsed: float = 0.0

	func _process(delta: float) -> void:
		_elapsed += delta
		if _elapsed >= DURATION:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t := _elapsed / DURATION
		var radius := 8.0 + t * 12.0
		var alpha := 1.0 - t
		var color := Color(marker_color.r, marker_color.g, marker_color.b, alpha)
		draw_arc(Vector2.ZERO, radius, 0, TAU, 16, color, 2.0)
