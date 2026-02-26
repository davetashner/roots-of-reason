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
var selected: bool = false

var _visual_size: float = 24.0
var _arrived: bool = false
var _destroyed: bool = false

# Visual config (loaded from JSON)
var _flag_height: float = 12.0
var _flag_width: float = 8.0
var _wake_trail_length: int = 5
var _damage_flash_duration: float = 0.3
var _damage_flash_color: Color = Color(1.0, 0.3, 0.3, 0.8)
var _selection_ring_radius: float = 18.0

# Runtime visual state
var _wake_positions: Array[Vector2] = []
var _damage_flash_timer: float = 0.0


func _ready() -> void:
	_load_visual_config()


func _load_visual_config() -> void:
	var cfg := _load_settings("river_transport")
	_flag_height = float(cfg.get("flag_height", _flag_height))
	_flag_width = float(cfg.get("flag_width", _flag_width))
	_wake_trail_length = int(cfg.get("wake_trail_length", _wake_trail_length))
	_damage_flash_duration = float(cfg.get("damage_flash_duration", _damage_flash_duration))
	var flash_arr: Array = cfg.get("damage_flash_color", [])
	if flash_arr.size() == 4:
		_damage_flash_color = Color(flash_arr[0], flash_arr[1], flash_arr[2], flash_arr[3])
	_selection_ring_radius = float(cfg.get("selection_ring_radius", _selection_ring_radius))


func _load_settings(settings_name: String) -> Dictionary:
	if is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_settings"):
			return dl.get_settings(settings_name)
	var path := "res://data/settings/%s.json" % settings_name
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	if json.data is Dictionary:
		return json.data
	return {}


func _process(delta: float) -> void:
	# Damage flash countdown
	if _damage_flash_timer > 0.0:
		_damage_flash_timer -= delta
		if _damage_flash_timer <= 0.0:
			_damage_flash_timer = 0.0
		queue_redraw()
	if _arrived or _destroyed:
		return
	if river_path.is_empty() or path_index >= river_path.size():
		_arrive()
		return
	# Record wake trail
	_wake_positions.append(position)
	if _wake_positions.size() > _wake_trail_length:
		_wake_positions.remove_at(0)
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
	queue_redraw()


func _arrive() -> void:
	if _arrived:
		return
	_arrived = true
	arrived.emit(self)


func take_damage(amount: int) -> void:
	if _destroyed:
		return
	hp -= amount
	_damage_flash_timer = _damage_flash_duration
	queue_redraw()
	if hp <= 0:
		hp = 0
		_destroyed = true
		destroyed.emit(self)


func select() -> void:
	selected = true
	queue_redraw()


func deselect() -> void:
	selected = false
	queue_redraw()


func is_point_inside(world_pos: Vector2) -> bool:
	var dist: float = world_pos.distance_to(global_position)
	return dist <= _selection_ring_radius


func get_entity_category() -> String:
	return entity_category


func _draw() -> void:
	var half := _visual_size / 2.0
	# Wake trail
	for i in _wake_positions.size():
		var wake_pos: Vector2 = _wake_positions[i] - position
		var alpha: float = float(i + 1) / float(_wake_positions.size() + 1) * 0.3
		var wake_radius: float = 3.0 + float(i) * 0.5
		draw_circle(wake_pos, wake_radius, Color(0.6, 0.8, 1.0, alpha))
	# Barge diamond shape
	var points := PackedVector2Array(
		[
			Vector2(0, -half),
			Vector2(half, 0),
			Vector2(0, half),
			Vector2(-half, 0),
		]
	)
	var body_color: Color
	if _damage_flash_timer > 0.0:
		body_color = _damage_flash_color
	elif owner_id == 0:
		body_color = Color(0.6, 0.4, 0.2)
	else:
		body_color = Color(0.8, 0.3, 0.3)
	draw_colored_polygon(points, body_color)
	# Border
	var border_color := Color(0.3, 0.2, 0.1)
	draw_line(points[0], points[1], border_color, 1.5)
	draw_line(points[1], points[2], border_color, 1.5)
	draw_line(points[2], points[3], border_color, 1.5)
	draw_line(points[3], points[0], border_color, 1.5)
	# Player flag
	var flag_color := Color(0.2, 0.5, 1.0) if owner_id == 0 else Color(0.9, 0.2, 0.2)
	var flag_base := Vector2(0, -half)
	var flag_top := flag_base + Vector2(0, -_flag_height)
	draw_line(flag_base, flag_top, Color(0.3, 0.2, 0.1), 1.0)
	var flag_rect := Rect2(flag_top, Vector2(_flag_width, _flag_height * 0.5))
	draw_rect(flag_rect, flag_color)
	# Resource cargo indicator (small dots for each resource type)
	var res_index := 0
	for res_type: int in carried_resources:
		if carried_resources[res_type] <= 0:
			continue
		var dot_x: float = -half * 0.4 + res_index * 6.0
		var dot_pos := Vector2(dot_x, 0)
		var dot_color := _get_resource_dot_color(res_type)
		draw_circle(dot_pos, 2.5, dot_color)
		res_index += 1
	# Selection ring
	if selected:
		var ring_color := Color(0.2, 1.0, 0.2, 0.7)
		draw_arc(Vector2.ZERO, _selection_ring_radius, 0, TAU, 24, ring_color, 1.5)


func _get_resource_dot_color(res_type: int) -> Color:
	match res_type:
		0:
			return Color(0.9, 0.3, 0.3)  # Food
		1:
			return Color(0.4, 0.7, 0.2)  # Wood
		2:
			return Color(0.6, 0.6, 0.6)  # Stone
		3:
			return Color(0.9, 0.8, 0.1)  # Gold
		4:
			return Color(0.3, 0.5, 0.9)  # Knowledge
	return Color(0.7, 0.7, 0.7)


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
		"selected": selected,
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
	selected = bool(data.get("selected", false))
	entity_category = "own_barge" if owner_id == 0 else "enemy_barge"
	queue_redraw()
