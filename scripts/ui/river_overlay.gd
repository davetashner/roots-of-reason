extends Node2D
## River transport overlay — draws flow arrows on river tiles when toggled.
## Color-coded: green flows toward player base, red away, yellow perpendicular.

var _map_node: Node = null
var _player_base_pos: Vector2i = Vector2i.ZERO
var _visible: bool = false

# Config (loaded from JSON)
var _arrow_length: float = 20.0
var _arrow_width: float = 2.0
var _arrow_head_size: float = 6.0
var _tile_highlight_alpha: float = 0.15
var _color_toward: Color = Color(0.2, 0.9, 0.2, 0.7)
var _color_away: Color = Color(0.9, 0.2, 0.2, 0.7)
var _color_perpendicular: Color = Color(0.9, 0.9, 0.2, 0.7)


func _ready() -> void:
	_load_config()
	visible = false


func _load_config() -> void:
	var cfg: Dictionary = GameUtils.dl_settings("river_overlay")
	if cfg.is_empty():
		return
	_arrow_length = float(cfg.get("arrow_length", _arrow_length))
	_arrow_width = float(cfg.get("arrow_width", _arrow_width))
	_arrow_head_size = float(cfg.get("arrow_head_size", _arrow_head_size))
	_tile_highlight_alpha = float(cfg.get("tile_highlight_alpha", _tile_highlight_alpha))
	_color_toward = _color_from_array(cfg.get("color_toward", []), _color_toward)
	_color_away = _color_from_array(cfg.get("color_away", []), _color_away)
	_color_perpendicular = _color_from_array(cfg.get("color_perpendicular", []), _color_perpendicular)


static func _color_from_array(arr: Array, fallback: Color) -> Color:
	if arr.size() == 4:
		return Color(arr[0], arr[1], arr[2], arr[3])
	return fallback


func setup(map_node: Node, player_base_pos: Vector2i) -> void:
	_map_node = map_node
	_player_base_pos = player_base_pos


func toggle() -> void:
	_visible = not _visible
	visible = _visible
	if _visible:
		queue_redraw()


func is_overlay_visible() -> bool:
	return _visible


func classify_flow(flow: Vector2i, river_pos: Vector2i) -> String:
	## Classify whether the flow direction moves toward, away, or perpendicular to the player base.
	if flow == Vector2i.ZERO:
		return "perpendicular"
	var to_base: Vector2 = Vector2(_player_base_pos - river_pos).normalized()
	var flow_dir: Vector2 = Vector2(flow).normalized()
	var dot: float = to_base.dot(flow_dir)
	if dot > 0.3:
		return "toward"
	if dot < -0.3:
		return "away"
	return "perpendicular"


func _get_flow_color(classification: String) -> Color:
	match classification:
		"toward":
			return _color_toward
		"away":
			return _color_away
	return _color_perpendicular


func _draw() -> void:
	if not _visible or _map_node == null:
		return
	if not _map_node.has_method("get_river_tiles"):
		return
	var river_tiles: Array = _map_node.get_river_tiles()
	for tile in river_tiles:
		var pos: Vector2i = tile as Vector2i
		var flow: Vector2i = _map_node.get_flow_direction(pos)
		var screen_pos: Vector2 = IsoUtils.grid_to_screen(Vector2(pos)) - position
		# Tile highlight
		draw_circle(screen_pos, 8.0, Color(0.3, 0.6, 1.0, _tile_highlight_alpha))
		# Flow arrow
		if flow != Vector2i.ZERO:
			var classification: String = classify_flow(flow, pos)
			var color: Color = _get_flow_color(classification)
			var flow_screen: Vector2 = Vector2(flow).normalized() * _arrow_length
			var arrow_end: Vector2 = screen_pos + flow_screen * 0.5
			var arrow_start: Vector2 = screen_pos - flow_screen * 0.5
			draw_line(arrow_start, arrow_end, color, _arrow_width)
			# Arrow head
			var perp: Vector2 = Vector2(-flow_screen.y, flow_screen.x).normalized() * _arrow_head_size
			var head_base: Vector2 = arrow_end - flow_screen.normalized() * _arrow_head_size
			draw_colored_polygon(
				PackedVector2Array([arrow_end, head_base + perp, head_base - perp]),
				color,
			)
