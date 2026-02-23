extends Node2D
## Prototype unit — colored circle with direction indicator, click-to-select,
## right-click-to-move. Villagers can build construction sites.

const RADIUS: float = 12.0
const MOVE_SPEED: float = 150.0
const SELECTION_RING_RADIUS: float = 16.0

@export var unit_color: Color = Color(0.2, 0.4, 0.9)
@export var owner_id: int = 0
@export var unit_type: String = "land"
@export var entity_category: String = ""

var selected: bool = false
var _target_pos: Vector2 = Vector2.ZERO
var _moving: bool = false
var _path: Array[Vector2] = []
var _path_index: int = 0
var _facing: Vector2 = Vector2.RIGHT

var _build_target: Node2D = null
var _build_speed: float = 1.0
var _build_reach: float = 80.0
var _pending_build_target_name: String = ""


func _ready() -> void:
	_target_pos = position
	_load_build_config()


func _load_build_config() -> void:
	# Load build_speed from unit stats
	var unit_cfg: Dictionary = {}
	if Engine.has_singleton("DataLoader"):
		unit_cfg = DataLoader.get_unit_stats("villager")
	elif is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_unit_stats"):
			unit_cfg = dl.get_unit_stats("villager")
	if not unit_cfg.is_empty():
		_build_speed = float(unit_cfg.get("build_speed", _build_speed))
	# Load build_reach from construction settings
	var con_cfg: Dictionary = {}
	if Engine.has_singleton("DataLoader"):
		con_cfg = DataLoader.get_settings("construction")
	elif is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_settings"):
			con_cfg = dl.get_settings("construction")
	if not con_cfg.is_empty():
		_build_reach = float(con_cfg.get("build_reach", _build_reach))


func _process(delta: float) -> void:
	var game_delta := GameManager.get_game_delta(delta)
	if game_delta == 0.0:
		return
	if _moving:
		var dist := position.distance_to(_target_pos)
		if dist < 2.0:
			position = _target_pos
			# Advance to next waypoint if following a path
			if _path_index < _path.size() - 1:
				_path_index += 1
				_target_pos = _path[_path_index]
			else:
				_moving = false
				_path.clear()
				_path_index = 0
		else:
			var direction := (_target_pos - position).normalized()
			_facing = direction
			position = position.move_toward(_target_pos, MOVE_SPEED * game_delta)
		queue_redraw()
	_tick_build(game_delta)


func _tick_build(game_delta: float) -> void:
	if _build_target == null:
		return
	if not is_instance_valid(_build_target):
		_build_target = null
		return
	if not _build_target.under_construction:
		_build_target = null
		return
	var dist: float = position.distance_to(_build_target.global_position)
	if dist > _build_reach:
		return
	# Stop moving — we're in range
	_moving = false
	_path.clear()
	_path_index = 0
	# Apply build work: build_speed / build_time per second
	var build_time: float = _build_target._build_time
	var work: float = (_build_speed / build_time) * game_delta
	_build_target.apply_build_work(work)
	# Check if construction completed
	if not _build_target.under_construction:
		_build_target = null


func assign_build_target(building: Node2D) -> void:
	_build_target = building
	move_to(building.global_position)


func is_idle() -> bool:
	return not _moving and _build_target == null


func resolve_build_target(scene_root: Node) -> void:
	if _pending_build_target_name == "":
		return
	var target := scene_root.get_node_or_null(_pending_build_target_name)
	if target is Node2D:
		_build_target = target
	_pending_build_target_name = ""


func _draw() -> void:
	# Selection ring
	if selected:
		draw_arc(Vector2.ZERO, SELECTION_RING_RADIUS, 0, TAU, 32, Color(0.0, 1.0, 0.0, 0.8), 2.0)

	# Unit body
	draw_circle(Vector2.ZERO, RADIUS, unit_color)

	# Direction triangle (points toward facing direction)
	var dir := _facing
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
	_path.clear()
	_path_index = 0
	_target_pos = world_pos
	_moving = true
	queue_redraw()


func follow_path(waypoints: Array[Vector2]) -> void:
	if waypoints.is_empty():
		return
	_path = waypoints
	_path_index = 0
	_target_pos = _path[0]
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


func get_entity_category() -> String:
	if entity_category != "":
		return entity_category
	return "enemy_unit" if owner_id != 0 else ""


func save_state() -> Dictionary:
	var state := {
		"position_x": position.x,
		"position_y": position.y,
		"unit_type": unit_type,
	}
	if _build_target != null and is_instance_valid(_build_target):
		state["build_target_name"] = str(_build_target.name)
	return state


func load_state(data: Dictionary) -> void:
	position = Vector2(
		float(data.get("position_x", 0)),
		float(data.get("position_y", 0)),
	)
	unit_type = str(data.get("unit_type", "land"))
	_pending_build_target_name = str(data.get("build_target_name", ""))
