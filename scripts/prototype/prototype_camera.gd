extends Camera2D
## Prototype isometric camera with pan, zoom, edge-scroll, middle-mouse drag,
## bounds clamping, cursor-centered zoom, and save/load support.

var _pan_speed: float = 500.0
var _zoom_min: float = 0.5
var _zoom_max: float = 3.0
var _zoom_step: float = 0.1
var _zoom_lerp_weight: float = 8.0
var _edge_margin: int = 20

var _target_zoom: float = 1.0
var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _map_bounds: Rect2 = Rect2()
var _has_bounds: bool = false


func _ready() -> void:
	zoom = Vector2(1.0, 1.0)
	_target_zoom = 1.0
	_load_config()


func _load_config() -> void:
	var cfg: Dictionary = {}
	if Engine.has_singleton("DataLoader"):
		cfg = DataLoader.get_settings("camera")
	elif is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_settings"):
			cfg = dl.get_settings("camera")
	if cfg.is_empty():
		return
	_pan_speed = cfg.get("pan_speed", _pan_speed)
	_zoom_min = cfg.get("zoom_min", _zoom_min)
	_zoom_max = cfg.get("zoom_max", _zoom_max)
	_zoom_step = cfg.get("zoom_step", _zoom_step)
	_zoom_lerp_weight = cfg.get("zoom_lerp_weight", _zoom_lerp_weight)
	_edge_margin = int(cfg.get("edge_scroll_margin", _edge_margin))


func setup(map_bounds: Rect2) -> void:
	_map_bounds = map_bounds
	_has_bounds = true
	_clamp_to_bounds()


func _process(delta: float) -> void:
	_handle_keyboard_pan(delta)
	_handle_edge_scroll(delta)
	_smooth_zoom(delta)
	if _has_bounds:
		_clamp_to_bounds()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_toward_cursor(1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_toward_cursor(-1)
			MOUSE_BUTTON_MIDDLE:
				_dragging = mb.pressed
				_drag_start = mb.position
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		position -= motion.relative / zoom


func _zoom_toward_cursor(direction: int) -> void:
	var old_zoom := zoom.x
	_target_zoom = clampf(_target_zoom + direction * _zoom_step, _zoom_min, _zoom_max)
	# Cursor-centered zoom: shift position so world point under cursor stays put
	var vp := get_viewport()
	if vp == null:
		return
	var mouse_screen := vp.get_mouse_position()
	var vp_size := get_viewport_rect().size
	var offset_from_center := mouse_screen - vp_size * 0.5
	var world_offset_old := offset_from_center / old_zoom
	var world_offset_new := offset_from_center / _target_zoom
	position += world_offset_old - world_offset_new


func _handle_keyboard_pan(delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if direction != Vector2.ZERO:
		position += direction.normalized() * _pan_speed * delta / zoom.x


func _handle_edge_scroll(delta: float) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vp_size := get_viewport_rect().size
	var mouse_pos := vp.get_mouse_position()
	var direction := Vector2.ZERO
	if mouse_pos.x < _edge_margin:
		direction.x -= 1.0
	elif mouse_pos.x > vp_size.x - _edge_margin:
		direction.x += 1.0
	if mouse_pos.y < _edge_margin:
		direction.y -= 1.0
	elif mouse_pos.y > vp_size.y - _edge_margin:
		direction.y += 1.0
	if direction != Vector2.ZERO:
		position += direction.normalized() * _pan_speed * delta / zoom.x


func _smooth_zoom(delta: float) -> void:
	var current := zoom.x
	var new_zoom := lerpf(current, _target_zoom, _zoom_lerp_weight * delta)
	zoom = Vector2(new_zoom, new_zoom)


func _clamp_to_bounds() -> void:
	if not is_inside_tree():
		return
	var vp_size := get_viewport_rect().size
	var half_view := vp_size / (2.0 * zoom)
	var min_pos := Vector2(_map_bounds.position.x + half_view.x, _map_bounds.position.y + half_view.y)
	var max_pos := Vector2(_map_bounds.end.x - half_view.x, _map_bounds.end.y - half_view.y)
	# If map is smaller than viewport at this zoom, center on map
	if min_pos.x > max_pos.x:
		position.x = _map_bounds.position.x + _map_bounds.size.x * 0.5
	else:
		position.x = clampf(position.x, min_pos.x, max_pos.x)
	if min_pos.y > max_pos.y:
		position.y = _map_bounds.position.y + _map_bounds.size.y * 0.5
	else:
		position.y = clampf(position.y, min_pos.y, max_pos.y)


func get_world_mouse() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return position
	var mouse_screen := vp.get_mouse_position()
	var vp_size := get_viewport_rect().size
	var offset_from_center := mouse_screen - vp_size * 0.5
	return position + offset_from_center / zoom


func save_state() -> Dictionary:
	return {
		"position_x": position.x,
		"position_y": position.y,
		"zoom": zoom.x,
	}


func load_state(data: Dictionary) -> void:
	position.x = data.get("position_x", position.x)
	position.y = data.get("position_y", position.y)
	var z: float = data.get("zoom", zoom.x)
	_target_zoom = z
	zoom = Vector2(z, z)
