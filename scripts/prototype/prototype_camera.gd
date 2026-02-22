extends Camera2D
## Prototype isometric camera with pan, zoom, edge-scroll, and middle-mouse drag.

const PAN_SPEED: float = 500.0
const ZOOM_MIN: float = 0.5
const ZOOM_MAX: float = 3.0
const ZOOM_STEP: float = 0.1
const ZOOM_LERP_WEIGHT: float = 8.0
const EDGE_MARGIN: int = 20

var _target_zoom: float = 1.0
var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO


func _ready() -> void:
	zoom = Vector2(1.0, 1.0)
	_target_zoom = 1.0


func _process(delta: float) -> void:
	_handle_keyboard_pan(delta)
	_handle_edge_scroll(delta)
	_smooth_zoom(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_target_zoom = clampf(_target_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			MOUSE_BUTTON_WHEEL_DOWN:
				_target_zoom = clampf(_target_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			MOUSE_BUTTON_MIDDLE:
				_dragging = mb.pressed
				_drag_start = mb.position
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		position -= motion.relative / zoom


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
		position += direction.normalized() * PAN_SPEED * delta / zoom.x


func _handle_edge_scroll(delta: float) -> void:
	var vp_size := get_viewport_rect().size
	var mouse_pos := get_viewport().get_mouse_position()
	var direction := Vector2.ZERO
	if mouse_pos.x < EDGE_MARGIN:
		direction.x -= 1.0
	elif mouse_pos.x > vp_size.x - EDGE_MARGIN:
		direction.x += 1.0
	if mouse_pos.y < EDGE_MARGIN:
		direction.y -= 1.0
	elif mouse_pos.y > vp_size.y - EDGE_MARGIN:
		direction.y += 1.0
	if direction != Vector2.ZERO:
		position += direction.normalized() * PAN_SPEED * delta / zoom.x


func _smooth_zoom(delta: float) -> void:
	var current := zoom.x
	var new_zoom := lerpf(current, _target_zoom, ZOOM_LERP_WEIGHT * delta)
	zoom = Vector2(new_zoom, new_zoom)
