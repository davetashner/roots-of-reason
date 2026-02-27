extends Node2D
## Prototype resource node — typed, depletable resource with gather support.
## Supports optional regeneration (e.g. trees regrow after depletion).

signal depleted(node: Node2D)
signal regen_started(node: Node2D)

const SIZE: float = 10.0

var entity_category: String = "resource_node"
var resource_name: String = ""
var resource_type: String = ""
var total_yield: int = 0
var current_yield: int = 0
var regenerates: bool = false
var regen_rate: float = 0.0
var regen_delay: float = 0.0
var _regen_accum: float = 0.0
var _regen_delay_timer: float = 0.0
var _is_regrowing: bool = false
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
	regenerates = bool(cfg.get("regenerates", false))
	regen_rate = float(cfg.get("regen_rate", 0.0))
	regen_delay = float(cfg.get("regen_delay", 0.0))
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
		if regenerates:
			_is_regrowing = true
			_regen_delay_timer = 0.0
			_regen_accum = 0.0
			regen_started.emit(self)
		else:
			depleted.emit(self)
	return gathered


func _process(delta: float) -> void:
	if not regenerates:
		return
	if current_yield >= total_yield:
		return
	if not _is_regrowing and current_yield > 0:
		# Partially gathered but not fully depleted — still regen
		pass
	elif not _is_regrowing:
		return
	var game_delta := GameUtils.get_game_delta(delta)
	if game_delta <= 0.0:
		return
	# Handle delay before regen starts
	var regen_delta := game_delta
	if _is_regrowing and _regen_delay_timer < regen_delay:
		_regen_delay_timer += game_delta
		if _regen_delay_timer < regen_delay:
			return
		# Use remaining time after delay for regen
		regen_delta = _regen_delay_timer - regen_delay
	# Accumulate regen
	_regen_accum += regen_rate * regen_delta
	var restore := int(_regen_accum)
	if restore > 0:
		_regen_accum -= float(restore)
		current_yield = mini(current_yield + restore, total_yield)
		if current_yield > 0 and _is_regrowing:
			_is_regrowing = false
		queue_redraw()


func get_entity_category() -> String:
	return entity_category


func is_point_inside(point: Vector2) -> bool:
	return point.distance_to(global_position) <= SIZE * 2.0


func _draw() -> void:
	var color := _node_color
	if _is_regrowing and current_yield <= 0:
		# Stump visual — faded outline only
		var stump_pts := PackedVector2Array(
			[
				Vector2(0, -SIZE),
				Vector2(SIZE, 0),
				Vector2(0, SIZE),
				Vector2(-SIZE, 0),
			]
		)
		var stump_color := Color(_node_color, 0.4).darkened(0.3)
		draw_polyline(stump_pts + PackedVector2Array([stump_pts[0]]), stump_color, 2.0)
		return
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
		"is_regrowing": _is_regrowing,
		"regen_delay_timer": _regen_delay_timer,
		"regen_accum": _regen_accum,
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
	_is_regrowing = bool(data.get("is_regrowing", false))
	_regen_delay_timer = float(data.get("regen_delay_timer", 0.0))
	_regen_accum = float(data.get("regen_accum", 0.0))
	# Reload config for color and regen properties
	var cfg: Dictionary = _load_resource_config(resource_name)
	if not cfg.is_empty():
		var c: Array = cfg.get("color", [0.2, 0.8, 0.2])
		_node_color = Color(c[0], c[1], c[2])
		regenerates = bool(cfg.get("regenerates", false))
		regen_rate = float(cfg.get("regen_rate", 0.0))
		regen_delay = float(cfg.get("regen_delay", 0.0))
	queue_redraw()
