extends Node2D
## Prototype unit — colored circle with direction indicator, click-to-select,
## right-click-to-move.

const RADIUS: float = 12.0
const MOVE_SPEED: float = 150.0
const SELECTION_RING_RADIUS: float = 16.0

@export var unit_color: Color = Color(0.2, 0.4, 0.9)

var selected: bool = false
var _target_pos: Vector2 = Vector2.ZERO
var _moving: bool = false


func _ready() -> void:
	_target_pos = position


func _process(delta: float) -> void:
	if _moving:
		var dist := position.distance_to(_target_pos)
		if dist < 2.0:
			position = _target_pos
			_moving = false
		else:
			position = position.move_toward(_target_pos, MOVE_SPEED * delta)
		queue_redraw()


func _draw() -> void:
	# Selection ring
	if selected:
		draw_arc(Vector2.ZERO, SELECTION_RING_RADIUS, 0, TAU, 32, Color(0.0, 1.0, 0.0, 0.8), 2.0)

	# Unit body
	draw_circle(Vector2.ZERO, RADIUS, unit_color)

	# Direction triangle (points toward target if moving, else right)
	var dir := Vector2.RIGHT
	if _moving:
		dir = ((_target_pos - position).normalized() if _target_pos.distance_to(position) > 1.0 else Vector2.RIGHT)
	var tip := dir * (RADIUS + 4.0)
	var left := dir.rotated(2.5) * RADIUS * 0.5
	var right := dir.rotated(-2.5) * RADIUS * 0.5
	draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(1, 1, 1, 0.9))

	# Movement target indicator
	if _moving:
		var local_target := _target_pos - position
		draw_circle(local_target, 3.0, Color(1, 1, 0, 0.6))
		draw_arc(local_target, 6.0, 0, TAU, 16, Color(1, 1, 0, 0.4), 1.0)


func move_to(world_pos: Vector2) -> void:
	_target_pos = world_pos
	_moving = true
	queue_redraw()


func select() -> void:
	selected = true
	queue_redraw()


func deselect() -> void:
	selected = false
	queue_redraw()


func is_point_inside(point: Vector2) -> bool:
	return point.distance_to(global_position) <= RADIUS * 1.5
