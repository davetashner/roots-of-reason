extends Node2D
## Prototype building — colored rectangle, targetable by right-click.
## entity_category is set at spawn based on owner_id.

const SIZE: Vector2 = Vector2(20, 20)

@export var owner_id: int = 0
var entity_category: String = "own_building"


func get_entity_category() -> String:
	return entity_category


func is_point_inside(point: Vector2) -> bool:
	return point.distance_to(global_position) <= SIZE.x * 1.5


func _draw() -> void:
	var color: Color
	if owner_id == 0:
		color = Color(0.2, 0.5, 1.0)
	else:
		color = Color(0.8, 0.2, 0.2)
	var rect := Rect2(-SIZE / 2.0, SIZE)
	draw_rect(rect, color)
	draw_rect(rect, color.darkened(0.3), false, 2.0)
