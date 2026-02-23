extends Node2D
## Prototype resource node — typed, depletable resource with gather support.

signal depleted(node: Node2D)

const SIZE: float = 10.0

var entity_category: String = "resource_node"
var resource_name: String = ""
var resource_type: String = ""
var total_yield: int = 0
var current_yield: int = 0
var _node_color: Color = Color(0.2, 0.8, 0.2)


func setup(res_name: String) -> void:
	resource_name = res_name
	var cfg: Dictionary = _load_resource_config(res_name)
	if cfg.is_empty():
		return
	resource_type = str(cfg.get("resource_type", ""))
	total_yield = int(cfg.get("total_yield", 0))
	current_yield = total_yield
	var c: Array = cfg.get("color", [0.2, 0.8, 0.2])
	_node_color = Color(c[0], c[1], c[2])
	queue_redraw()


func _load_resource_config(res_name: String) -> Dictionary:
	if Engine.has_singleton("DataLoader"):
		return DataLoader.get_resource_data(res_name)
	if is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_resource_data"):
			return dl.get_resource_data(res_name)
	return {}


func apply_gather_work(amount: float) -> int:
	if current_yield <= 0:
		return 0
	var gathered := mini(int(amount), current_yield)
	current_yield -= gathered
	queue_redraw()
	if current_yield <= 0:
		depleted.emit(self)
	return gathered


func get_entity_category() -> String:
	return entity_category


func is_point_inside(point: Vector2) -> bool:
	return point.distance_to(global_position) <= SIZE * 2.0


func _draw() -> void:
	var color := _node_color
	if total_yield > 0 and current_yield > 0:
		var ratio := float(current_yield) / float(total_yield)
		color.a = clampf(0.3 + 0.7 * ratio, 0.3, 1.0)
	var points := PackedVector2Array(
		[
			Vector2(0, -SIZE),
			Vector2(SIZE, 0),
			Vector2(0, SIZE),
			Vector2(-SIZE, 0),
		]
	)
	draw_colored_polygon(points, color)
	var outline_color := Color(color, 1.0).darkened(0.3)
	draw_polyline(points + PackedVector2Array([points[0]]), outline_color, 2.0)


func save_state() -> Dictionary:
	return {
		"resource_name": resource_name,
		"resource_type": resource_type,
		"total_yield": total_yield,
		"current_yield": current_yield,
		"position_x": position.x,
		"position_y": position.y,
	}


func load_state(data: Dictionary) -> void:
	resource_name = str(data.get("resource_name", ""))
	resource_type = str(data.get("resource_type", ""))
	total_yield = int(data.get("total_yield", 0))
	current_yield = int(data.get("current_yield", 0))
	position = Vector2(
		float(data.get("position_x", 0)),
		float(data.get("position_y", 0)),
	)
	# Reload color from config
	var cfg: Dictionary = _load_resource_config(resource_name)
	if not cfg.is_empty():
		var c: Array = cfg.get("color", [0.2, 0.8, 0.2])
		_node_color = Color(c[0], c[1], c[2])
	queue_redraw()
