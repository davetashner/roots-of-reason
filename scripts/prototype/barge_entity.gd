class_name BargeEntity
extends Node2D
## Visual barge entity that moves along river tiles carrying resources.
## Resources are in the stockpile immediately when deposited; if the barge is
## destroyed in transit, the carried amount is deducted from the stockpile.

signal destroyed(barge: Node2D)
signal arrived(barge: Node2D)

var carried_resources: Dictionary = {}  # ResourceType (int) -> amount (int)
var total_carried: int = 0
var owner_id: int = 0
var hp: int = 15
var max_hp: int = 15
var speed: float = 180.0
var river_path: Array[Vector2i] = []  # pre-computed path of river tiles
var path_index: int = 0
var entity_category: String = "own_barge"

var _visual_size: float = 24.0
var _arrived: bool = false
var _destroyed: bool = false


func _process(delta: float) -> void:
	if _arrived or _destroyed:
		return
	if river_path.is_empty() or path_index >= river_path.size():
		_arrive()
		return
	var target_pos := IsoUtils.grid_to_screen(Vector2(river_path[path_index]))
	var direction := target_pos - position
	var distance := direction.length()
	var step := speed * delta
	if step >= distance:
		position = target_pos
		path_index += 1
		if path_index >= river_path.size():
			_arrive()
	else:
		position += direction.normalized() * step


func _arrive() -> void:
	if _arrived:
		return
	_arrived = true
	arrived.emit(self)


func take_damage(amount: int) -> void:
	if _destroyed:
		return
	hp -= amount
	if hp <= 0:
		hp = 0
		_destroyed = true
		destroyed.emit(self)


func get_entity_category() -> String:
	return entity_category


func _draw() -> void:
	var half := _visual_size / 2.0
	# Draw a small diamond shape for the barge
	var points := PackedVector2Array(
		[
			Vector2(0, -half),
			Vector2(half, 0),
			Vector2(0, half),
			Vector2(-half, 0),
		]
	)
	var color := Color(0.6, 0.4, 0.2) if owner_id == 0 else Color(0.8, 0.3, 0.3)
	draw_colored_polygon(points, color)
	# Border
	var border_color := Color(0.3, 0.2, 0.1)
	draw_line(points[0], points[1], border_color, 1.5)
	draw_line(points[1], points[2], border_color, 1.5)
	draw_line(points[2], points[3], border_color, 1.5)
	draw_line(points[3], points[0], border_color, 1.5)


func save_state() -> Dictionary:
	var resources_out: Dictionary = {}
	for res_type: int in carried_resources:
		resources_out[str(res_type)] = carried_resources[res_type]
	var path_out: Array = []
	for pos: Vector2i in river_path:
		path_out.append([pos.x, pos.y])
	return {
		"carried_resources": resources_out,
		"total_carried": total_carried,
		"owner_id": owner_id,
		"hp": hp,
		"max_hp": max_hp,
		"speed": speed,
		"river_path": path_out,
		"path_index": path_index,
		"position": [position.x, position.y],
		"arrived": _arrived,
		"destroyed": _destroyed,
	}


func load_state(data: Dictionary) -> void:
	carried_resources.clear()
	var res_data: Dictionary = data.get("carried_resources", {})
	for key: String in res_data:
		carried_resources[int(key)] = int(res_data[key])
	total_carried = int(data.get("total_carried", 0))
	owner_id = int(data.get("owner_id", 0))
	hp = int(data.get("hp", max_hp))
	max_hp = int(data.get("max_hp", max_hp))
	speed = float(data.get("speed", speed))
	river_path.clear()
	var path_data: Array = data.get("river_path", [])
	for entry in path_data:
		var arr: Array = entry
		river_path.append(Vector2i(int(arr[0]), int(arr[1])))
	path_index = int(data.get("path_index", 0))
	var pos_arr: Array = data.get("position", [0.0, 0.0])
	position = Vector2(float(pos_arr[0]), float(pos_arr[1]))
	_arrived = bool(data.get("arrived", false))
	_destroyed = bool(data.get("destroyed", false))
	entity_category = "own_barge" if owner_id == 0 else "enemy_barge"
	queue_redraw()
