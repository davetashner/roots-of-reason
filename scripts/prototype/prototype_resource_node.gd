extends Node2D
## Prototype resource node — green diamond, targetable by right-click.

const SIZE: float = 10.0

var entity_category: String = "resource_node"


func get_entity_category() -> String:
	return entity_category


func is_point_inside(point: Vector2) -> bool:
	return point.distance_to(global_position) <= SIZE * 2.0


func _draw() -> void:
	var points := PackedVector2Array(
		[
			Vector2(0, -SIZE),
			Vector2(SIZE, 0),
			Vector2(0, SIZE),
			Vector2(-SIZE, 0),
		]
	)
	draw_colored_polygon(points, Color(0.2, 0.8, 0.2))
	draw_polyline(points + PackedVector2Array([points[0]]), Color(0.1, 0.5, 0.1), 2.0)
