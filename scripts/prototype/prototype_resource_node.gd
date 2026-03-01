extends Node2D
## Prototype resource node — typed, depletable resource with gather support.
## Supports optional regeneration (e.g. trees regrow after depletion).

signal depleted(node: Node2D)
signal regen_started(node: Node2D)

const SIZE: float = 10.0

var entity_category: String = "resource_node"
## Logical grid cell where this resource was placed (before visual cluster offset).
## Used for pathfinding so villagers navigate to the walkable tile, not the
## offset screen position which may map to an adjacent impassable tile.
var grid_position: Vector2i = Vector2i.ZERO
var resource_name: String = ""
var resource_type: String = ""
var total_yield: int = 0
var current_yield: int = 0
var regenerates: bool = false
var regen_rate: float = 0.0
var regen_delay: float = 0.0
var variant_index: int = 0
var _regen_accum: float = 0.0
var _regen_delay_timer: float = 0.0
var _is_regrowing: bool = false
var _node_color: Color = Color(0.2, 0.8, 0.2)
var _sprite: Sprite2D = null
var _sprite_textures: Dictionary = {}  # state_name -> Texture2D
var _sprite_scales: Dictionary = {}  # state_name -> float (per-state scale override)
var _half_threshold: float = 0.5
var _sprite_offset_y: float = 0.0


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
	_setup_sprite(cfg)
	queue_redraw()


func _setup_sprite(cfg: Dictionary) -> void:
	var sprite_cfg: Dictionary = cfg.get("sprite", {})
	if sprite_cfg.is_empty():
		return
	var base_path: String = str(sprite_cfg.get("base_path", ""))
	var states: Dictionary = sprite_cfg.get("states", {})
	if base_path.is_empty() or states.is_empty():
		return
	# Load textures — each state value is either a single filename or an array
	for state_name: String in states:
		var value = states[state_name]
		var file_name: String = ""
		if value is Array:
			var files: Array = value
			if files.is_empty():
				continue
			file_name = str(files[variant_index % files.size()])
		else:
			file_name = str(value)
		var full_path: String = base_path + "/" + file_name
		if ResourceLoader.exists(full_path):
			_sprite_textures[state_name] = load(full_path)
	if _sprite_textures.is_empty():
		return
	_half_threshold = float(sprite_cfg.get("half_threshold", 0.5))
	_sprite_offset_y = float(sprite_cfg.get("offset_y", 0.0))
	var scales: Dictionary = sprite_cfg.get("scales", {})
	for state_name_s: String in scales:
		_sprite_scales[state_name_s] = float(scales[state_name_s])
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.position.y = _sprite_offset_y
	add_child(_sprite)
	_update_sprite()


func _update_sprite() -> void:
	if _sprite == null:
		return
	var state: String = "full"
	if _is_regrowing or current_yield <= 0:
		state = "stump"
	elif total_yield > 0 and float(current_yield) / float(total_yield) <= _half_threshold:
		state = "half"
	if _sprite_textures.has(state):
		_sprite.texture = _sprite_textures[state]
	elif _sprite_textures.has("full"):
		_sprite.texture = _sprite_textures["full"]
	var s: float = _sprite_scales.get(state, 1.0)
	_sprite.scale = Vector2(s, s)


func _load_resource_config(res_name: String) -> Dictionary:
	if Engine.has_singleton("DataLoader"):
		return DataLoader.get_resource_data(res_name)
	if is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_resource_data"):
			return dl.get_resource_data(res_name)
	return {}


func is_harvestable() -> bool:
	if current_yield <= 0:
		return false
	if _is_regrowing:
		return false
	return true


func apply_gather_work(amount: float) -> int:
	if not is_harvestable():
		return 0
	var gathered := mini(int(amount), current_yield)
	current_yield -= gathered
	_update_sprite()
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
	if not _is_regrowing:
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
		if current_yield >= total_yield and _is_regrowing:
			_is_regrowing = false
		_update_sprite()
		queue_redraw()


func get_entity_category() -> String:
	return entity_category


func is_point_inside(point: Vector2) -> bool:
	return point.distance_to(global_position) <= SIZE * 2.0


func _draw() -> void:
	if _sprite != null:
		return
	var color := _node_color
	if _is_regrowing:
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
		"variant_index": variant_index,
		"grid_position_x": grid_position.x,
		"grid_position_y": grid_position.y,
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
	variant_index = int(data.get("variant_index", 0))
	grid_position = Vector2i(
		int(data.get("grid_position_x", 0)),
		int(data.get("grid_position_y", 0)),
	)
	# Reload config for color and regen properties
	var cfg: Dictionary = _load_resource_config(resource_name)
	if not cfg.is_empty():
		var c: Array = cfg.get("color", [0.2, 0.8, 0.2])
		_node_color = Color(c[0], c[1], c[2])
		regenerates = bool(cfg.get("regenerates", false))
		regen_rate = float(cfg.get("regen_rate", 0.0))
		regen_delay = float(cfg.get("regen_delay", 0.0))
		_setup_sprite(cfg)
	queue_redraw()
