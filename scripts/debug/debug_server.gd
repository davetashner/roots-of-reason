extends Node
## Lightweight HTTP debug server for dev tooling (screenshot capture, status, commands).
## Only activates when --debug-server is passed via OS.get_cmdline_user_args().
## Listens on 127.0.0.1:9222, handles one request at a time.

const DEFAULT_PORT: int = 9222
const BIND_HOST: String = "127.0.0.1"
const MAX_REQUEST_SIZE: int = 4096
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const ResourceNodeScript := preload("res://scripts/prototype/prototype_resource_node.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")
## Known resource names that map to data/resources/*.json configs.
const RESOURCE_NAMES: Array[String] = [
	"tree",
	"stone_mine",
	"gold_mine",
	"berry_bush",
	"fish",
]

var _server: TCPServer = null
var _active: bool = false


func _ready() -> void:
	if not _should_activate():
		set_process(false)
		return
	_server = TCPServer.new()
	var err := _server.listen(DEFAULT_PORT, BIND_HOST)
	if err != OK:
		push_warning("DebugServer: failed to listen on %s:%d (error %d)" % [BIND_HOST, DEFAULT_PORT, err])
		set_process(false)
		return
	_active = true
	print("DebugServer: listening on %s:%d" % [BIND_HOST, DEFAULT_PORT])


func _process(_delta: float) -> void:
	if not _active:
		return
	if not _server.is_connection_available():
		return
	var peer: StreamPeerTCP = _server.take_connection()
	if peer == null:
		return
	_handle_connection(peer)


func _handle_connection(peer: StreamPeerTCP) -> void:
	# Read the HTTP request headers until we get a blank line.
	var request_data := ""
	var start_tick := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start_tick < 1000:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return
		var available := peer.get_available_bytes()
		if available <= 0:
			continue
		var chunk := peer.get_data(mini(available, MAX_REQUEST_SIZE))
		if chunk[0] != OK:
			return
		request_data += chunk[1].get_string_from_utf8()
		if "\r\n\r\n" in request_data or "\n\n" in request_data:
			break
		if request_data.length() >= MAX_REQUEST_SIZE:
			break
	if request_data.is_empty():
		return
	var parsed := _parse_request(request_data)
	var method: String = parsed.get("method", "")
	var path: String = parsed.get("path", "")
	var headers: Dictionary = parsed.get("headers", {})
	# Read POST body if Content-Length is present
	var body_text := ""
	if method == "POST":
		body_text = _read_body(peer, request_data, headers, start_tick)
	# Split path from query string
	var query_string := ""
	var base_path := path
	var qmark := path.find("?")
	if qmark >= 0:
		base_path = path.substr(0, qmark)
		query_string = path.substr(qmark + 1)
	if method == "GET" and base_path == "/ping":
		_send_json(peer, 200, {"status": "ok"})
	elif method == "GET" and base_path == "/screenshot":
		await _handle_screenshot(peer, query_string)
	elif method == "GET" and base_path == "/status":
		_handle_status(peer)
	elif method == "GET" and base_path == "/combat-log":
		_handle_combat_log(peer, query_string)
	elif method == "GET" and base_path == "/economy":
		_handle_economy(peer, query_string)
	elif method == "GET" and base_path == "/entities":
		_handle_entities(peer, query_string)
	elif method == "GET" and base_path == "/pathfinding":
		_handle_pathfinding(peer, query_string)
	elif method == "GET" and base_path == "/perf":
		_handle_perf(peer)
	elif method == "GET" and base_path == "/fow":
		_handle_fow(peer, query_string)
	elif method == "POST" and base_path == "/command":
		_handle_command(peer, body_text)
	else:
		_send_json(peer, 404, {"error": "not found", "path": path})
	peer.disconnect_from_host()


static func _read_body(peer: StreamPeerTCP, request_data: String, headers: Dictionary, start_tick: int) -> String:
	var content_length: int = int(headers.get("content-length", "0"))
	if content_length <= 0:
		return ""
	# Extract any body bytes already read after the header separator
	var body_text := ""
	var sep_idx := request_data.find("\r\n\r\n")
	if sep_idx >= 0:
		body_text = request_data.substr(sep_idx + 4)
	else:
		sep_idx = request_data.find("\n\n")
		if sep_idx >= 0:
			body_text = request_data.substr(sep_idx + 2)
	# Read remaining body bytes
	while body_text.length() < content_length and Time.get_ticks_msec() - start_tick < 2000:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var available := peer.get_available_bytes()
		if available <= 0:
			continue
		var chunk := peer.get_data(mini(available, MAX_REQUEST_SIZE))
		if chunk[0] != OK:
			break
		body_text += chunk[1].get_string_from_utf8()
	return body_text.substr(0, content_length)


static func _parse_request(raw: String) -> Dictionary:
	var lines := raw.split("\n")
	if lines.is_empty():
		return {}
	var request_line := lines[0].strip_edges()
	var parts := request_line.split(" ")
	if parts.size() < 2:
		return {}
	var headers: Dictionary = {}
	for i in range(1, lines.size()):
		var line := lines[i].strip_edges()
		if line.is_empty():
			break
		var colon_pos := line.find(":")
		if colon_pos > 0:
			var key := line.substr(0, colon_pos).strip_edges().to_lower()
			var value := line.substr(colon_pos + 1).strip_edges()
			headers[key] = value
	return {"method": parts[0], "path": parts[1], "headers": headers}


func _handle_screenshot(peer: StreamPeerTCP, query_string: String) -> void:
	var viewport := get_viewport()
	if viewport == null:
		_send_json(peer, 500, {"error": "no viewport"})
		return
	var params := parse_query_string(query_string)
	var annotate: bool = str(params.get("annotate", "false")) == "true"
	var overlay: CanvasLayer = null
	if annotate:
		overlay = _create_annotation_overlay()
		add_child(overlay)
		# Wait two frames: one for layout, one for draw
		await get_tree().process_frame
		await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	if overlay != null:
		overlay.queue_free()
	if image == null:
		_send_json(peer, 500, {"error": "failed to capture image"})
		return
	var png_data := image.save_png_to_buffer()
	if png_data.is_empty():
		_send_json(peer, 500, {"error": "failed to encode PNG"})
		return
	var header := "HTTP/1.1 200 OK\r\n"
	header += "Content-Type: image/png\r\n"
	header += "Content-Length: %d\r\n" % png_data.size()
	header += "Connection: close\r\n"
	header += "\r\n"
	peer.put_data(header.to_utf8_buffer())
	peer.put_data(png_data)


func _create_annotation_overlay() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 100
	var root := get_tree().current_scene
	if root == null:
		return layer
	var camera := _get_camera()
	var viewport := get_viewport()
	if viewport == null or camera == null:
		return layer
	var vp_size := Vector2(viewport.get_visible_rect().size)
	var cam_pos := camera.global_position
	var cam_zoom := camera.zoom
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 12
	for child: Node in root.get_children():
		if not (child is Node2D):
			continue
		if "entity_category" not in child:
			continue
		var entity := child as Node2D
		var screen_pos := _world_to_screen(entity.global_position, cam_pos, cam_zoom, vp_size)
		# Skip entities off-screen
		if screen_pos.x < -100 or screen_pos.x > vp_size.x + 100:
			continue
		if screen_pos.y < -100 or screen_pos.y > vp_size.y + 100:
			continue
		_add_entity_annotations(layer, entity, screen_pos, font, font_size)
	return layer


static func _world_to_screen(world_pos: Vector2, cam_pos: Vector2, cam_zoom: Vector2, vp_size: Vector2) -> Vector2:
	return (world_pos - cam_pos) * cam_zoom + vp_size / 2.0


static func _make_label(text: String, pos: Vector2, font: Font, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	return lbl


func _add_entity_annotations(
	layer: CanvasLayer,
	entity: Node2D,
	screen_pos: Vector2,
	font: Font,
	font_size: int,
) -> void:
	var cat: String = _infer_entity_category(entity)
	if cat == "":
		return
	var is_unit := "unit_category" in entity and str(entity.unit_category) != ""
	var is_building := "building_name" in entity and str(entity.building_name) != ""
	var is_resource := cat == "resource_node"
	if bool(entity.selected) if "selected" in entity else false:
		var hl := ColorRect.new()
		hl.color = Color(0, 1, 0, 0.3)
		hl.size = Vector2(60, 60)
		hl.position = screen_pos - Vector2(30, 50)
		layer.add_child(hl)
	var name_text := entity.name
	if is_building:
		name_text = str(entity.building_name)
	elif is_resource:
		name_text = str(entity.resource_name) if "resource_name" in entity else entity.name
	layer.add_child(_make_label(name_text, screen_pos - Vector2(30, 55), font, font_size, Color.WHITE))
	if (is_unit or is_building) and "hp" in entity and "max_hp" in entity:
		var hp_val: int = int(entity.hp)
		var max_val: int = int(entity.max_hp)
		if max_val > 0:
			var ratio: float = clampf(float(hp_val) / float(max_val), 0.0, 1.0)
			var bg := ColorRect.new()
			bg.color = Color(0.2, 0.2, 0.2, 0.8)
			bg.size = Vector2(50, 4)
			bg.position = screen_pos - Vector2(25, 40)
			layer.add_child(bg)
			var fg := ColorRect.new()
			if ratio > 0.6:
				fg.color = Color(0, 0.8, 0, 0.9)
			elif ratio > 0.3:
				fg.color = Color(0.9, 0.8, 0, 0.9)
			else:
				fg.color = Color(0.9, 0.1, 0, 0.9)
			fg.size = Vector2(50.0 * ratio, 4)
			fg.position = screen_pos - Vector2(25, 40)
			layer.add_child(fg)
	if is_unit:
		var st := _get_unit_action(entity)
		var gtype: String = str(entity._gather_type) if "_gather_type" in entity else ""
		if gtype != "" and st in ["gathering", "moving_to_resource"]:
			st += " " + gtype
		var carried: int = int(entity._carried_amount) if "_carried_amount" in entity else 0
		if carried > 0:
			st += " (carrying %d %s)" % [carried, gtype]
		layer.add_child(_make_label(st, screen_pos - Vector2(30, 30), font, 10, Color(0.9, 0.9, 0.5)))
	if is_resource and "current_yield" in entity and "total_yield" in entity:
		var yt := "%d/%d" % [int(entity.current_yield), int(entity.total_yield)]
		layer.add_child(_make_label(yt, screen_pos - Vector2(20, 30), font, 10, Color(0.5, 0.9, 0.9)))


func _handle_status(peer: StreamPeerTCP) -> void:
	var gm: Node = _get_manager("GameManager")
	var rm: Node = _get_manager("ResourceManager")
	var cd := _get_camera_data()
	_send_json(
		peer,
		200,
		{
			"game_time": float(gm.game_time) if gm != null else 0.0,
			"game_speed": float(gm.game_speed) if gm != null else 1.0,
			"is_paused": bool(gm.is_paused) if gm != null else false,
			"current_age": int(gm.current_age) if gm != null else 0,
			"player_resources": _get_player_resources(rm),
			"unit_count": _get_unit_counts(),
			"camera_position": cd["position"],
			"camera_zoom": cd["zoom"],
		}
	)


func _handle_combat_log(peer: StreamPeerTCP, query_string: String) -> void:
	var params := parse_query_string(query_string)
	var evts := CombatLogger.get_events(int(params.get("limit", "50")))
	var gm: Node = _get_manager("GameManager")
	_send_json(
		peer,
		200,
		{
			"events": evts,
			"count": evts.size(),
			"capacity": CombatLogger.get_capacity(),
			"total_logged": CombatLogger.get_total_logged(),
			"game_time": float(gm.game_time) if gm != null else 0.0,
		}
	)


func _handle_economy(peer: StreamPeerTCP, query_string: String) -> void:
	var params := parse_query_string(query_string)
	var pid: int = int(params.get("player", "0"))
	var gm: Node = _get_manager("GameManager")
	var rm: Node = _get_manager("ResourceManager")
	var vd := EconomyLogger.get_villager_allocation(get_tree().current_scene, pid)
	_send_json(
		peer,
		200,
		{
			"game_time": float(gm.game_time) if gm != null else 0.0,
			"player_id": pid,
			"player_resources": _get_player_resources(rm) if rm != null else {},
			"gather_rates": EconomyLogger.get_gather_rates(pid),
			"deposits_per_second": EconomyLogger.get_deposits_per_second(pid),
			"villager_allocation": vd["allocation"],
			"idle_villagers": vd["idle_count"],
			"total_villagers": vd["total"],
			"recent_deposits": EconomyLogger.get_events(int(params.get("limit", "20"))),
			"total_deposits": EconomyLogger.get_total_logged(),
			"gather_multiplier": rm.get_gather_multiplier(pid) if rm != null else 1.0,
			"corruption_rate": rm.get_corruption_rate(pid) if rm != null else 0.0,
		}
	)


func _handle_command(peer: StreamPeerTCP, body_text: String) -> void:
	if body_text.is_empty():
		_send_json(peer, 400, {"error": "empty request body"})
		return
	var parsed: Variant = JSON.parse_string(body_text)
	if parsed == null or not (parsed is Dictionary):
		_send_json(peer, 400, {"error": "invalid JSON"})
		return
	var body: Dictionary = parsed
	var action: String = str(body.get("action", ""))
	if action.is_empty():
		_send_json(peer, 400, {"error": "missing action field"})
		return
	match action:
		"select-all":
			_cmd_select_all(peer)
		"right-click":
			_cmd_right_click(peer, body)
		"camera-to":
			_cmd_camera_to(peer, body)
		"speed":
			_cmd_speed(peer, body)
		"pause":
			_cmd_pause(peer)
		"unpause":
			_cmd_unpause(peer)
		"gather":
			_cmd_gather(peer, body)
		"spawn":
			_cmd_spawn(peer, body)
		"teleport":
			_cmd_teleport(peer, body)
		"place-building":
			_cmd_place_building(peer, body)
		"zoom":
			_cmd_zoom(peer, body)
		"stop":
			_cmd_stop(peer, body)
		"reset":
			_cmd_reset(peer)
		"set-resources":
			_cmd_set_resources(peer, body)
		"save":
			_cmd_save(peer, body)
		"load":
			_cmd_load(peer, body)
		_:
			_send_json(peer, 400, {"error": "unknown action", "action": action})


func _cmd_select_all(peer: StreamPeerTCP) -> void:
	var count := 0
	for u: Node2D in _get_player_units(0):
		if u.has_method("select"):
			u.select()
			count += 1
		elif "selected" in u:
			u.selected = true
			count += 1
	_send_json(peer, 200, {"action": "select-all", "selected": count})


func _cmd_right_click(peer: StreamPeerTCP, body: Dictionary) -> void:
	if not body.has("grid_x") or not body.has("grid_y"):
		_send_json(peer, 400, {"error": "right-click requires grid_x and grid_y"})
		return
	var gx: float = float(body["grid_x"])
	var gy: float = float(body["grid_y"])
	var wp := IsoUtils.grid_to_screen(Vector2(gx, gy))
	var moved := 0
	for u: Node2D in _get_player_units(0):
		if "selected" in u and u.selected and u.has_method("move_to"):
			u.move_to(wp)
			moved += 1
	_send_json(peer, 200, {"action": "right-click", "grid_x": gx, "grid_y": gy, "moved": moved})


func _cmd_camera_to(peer: StreamPeerTCP, body: Dictionary) -> void:
	if not body.has("grid_x") or not body.has("grid_y"):
		_send_json(peer, 400, {"error": "camera-to requires grid_x and grid_y"})
		return
	var gx: float = float(body["grid_x"])
	var gy: float = float(body["grid_y"])
	var wp := IsoUtils.grid_to_screen(Vector2(gx, gy))
	var camera := _get_camera()
	if camera != null:
		camera.global_position = wp
	_send_json(peer, 200, {"action": "camera-to", "grid_x": gx, "grid_y": gy})


func _cmd_speed(peer: StreamPeerTCP, body: Dictionary) -> void:
	if not body.has("value"):
		_send_json(peer, 400, {"error": "speed requires value"})
		return
	var sv: float = float(body["value"])
	var gm: Node = _get_manager("GameManager")
	if gm != null:
		gm.game_speed = sv
	_send_json(peer, 200, {"action": "speed", "value": sv})


func _cmd_pause(peer: StreamPeerTCP) -> void:
	var gm: Node = _get_manager("GameManager")
	if gm != null and gm.has_method("pause"):
		gm.pause()
	_send_json(peer, 200, {"action": "pause"})


func _cmd_unpause(peer: StreamPeerTCP) -> void:
	var gm: Node = _get_manager("GameManager")
	if gm != null and gm.has_method("resume"):
		gm.resume()
	_send_json(peer, 200, {"action": "unpause"})


func _cmd_gather(peer: StreamPeerTCP, body: Dictionary) -> void:
	if not body.has("grid_x") or not body.has("grid_y"):
		_send_json(peer, 400, {"error": "gather requires grid_x and grid_y"})
		return
	var wp := IsoUtils.grid_to_screen(Vector2(float(body["grid_x"]), float(body["grid_y"])))
	var target: Node2D = _find_nearest_resource(wp)
	if target == null:
		_send_json(peer, 200, {"action": "gather", "error": "no resource node found near position"})
		return
	var gatherers: Array[Node2D] = []
	for u: Node2D in _get_player_units(0):
		if "selected" in u and u.selected and u.has_method("assign_gather_target"):
			gatherers.append(u)
	var offsets: Array[Vector2] = _gather_offsets(target, gatherers.size())
	for i in gatherers.size():
		gatherers[i].assign_gather_target(target, offsets[i] if i < offsets.size() else Vector2.ZERO)
	_send_json(peer, 200, {"action": "gather", "target": str(target.name), "gathering": gatherers.size()})


func _find_nearest_resource(world_pos: Vector2) -> Node2D:
	var root := get_tree().current_scene
	if root == null:
		return null
	var best: Node2D = null
	var best_dist := INF
	for child: Node in root.get_children():
		if "entity_category" not in child:
			continue
		if str(child.entity_category) != "resource_node":
			continue
		if "current_yield" in child and int(child.current_yield) <= 0:
			continue
		if child is Node2D:
			var dist: float = world_pos.distance_to(child.global_position)
			if dist < best_dist:
				best_dist = dist
				best = child as Node2D
	return best


func _gather_offsets(target: Node2D, count: int) -> Array[Vector2]:
	## Compute formation offsets around a gather target so units spread out.
	if count <= 1:
		return [Vector2.ZERO]
	var root := get_tree().current_scene
	if root == null or "_pathfinder" not in root or root._pathfinder == null:
		var zeros: Array[Vector2] = []
		zeros.resize(count)
		zeros.fill(Vector2.ZERO)
		return zeros
	var nav_pos: Vector2 = target.global_position
	if "grid_position" in target and target.grid_position != Vector2i.ZERO:
		nav_pos = IsoUtils.grid_to_screen(Vector2(target.grid_position))
	var center := IsoUtils.snap_to_grid(nav_pos)
	var cells: Array[Vector2i] = root._pathfinder.get_formation_targets(center, count)
	var result: Array[Vector2] = []
	for cell in cells:
		result.append(IsoUtils.grid_to_screen(Vector2(cell)) - nav_pos)
	while result.size() < count:
		result.append(Vector2.ZERO)
	return result


static func _get_player_resources(rm: Node) -> Dictionary:
	if rm == null:
		return {}
	var result: Dictionary = {}
	# ResourceManager uses enum keys internally; iterate RESOURCE_KEYS to get string names
	if "RESOURCE_KEYS" in rm:
		for res_type: Variant in rm.RESOURCE_KEYS:
			var key: String = rm.RESOURCE_KEYS[res_type]
			result[key] = rm.get_amount(0, res_type)
	return result


func _get_unit_counts() -> Dictionary:
	var counts: Dictionary = {}
	var root := get_tree().current_scene
	if root == null:
		return counts
	for child: Node in root.get_children():
		if "entity_category" not in child or "owner_id" not in child:
			continue
		# Units have unit_category or entity_category containing "unit"
		var is_unit := false
		if "unit_category" in child and str(child.unit_category) != "":
			is_unit = true
		elif str(child.entity_category).ends_with("_unit") or str(child.entity_category) == "unit":
			is_unit = true
		elif child.has_method("move_to") and child.has_method("select"):
			is_unit = true
		if is_unit:
			var oid: int = int(child.owner_id)
			var key := str(oid)
			counts[key] = int(counts.get(key, 0)) + 1
	return counts


func _get_player_units(player_id: int) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var root := get_tree().current_scene
	if root == null:
		return result
	for child: Node in root.get_children():
		if "owner_id" not in child:
			continue
		if int(child.owner_id) != player_id:
			continue
		if not (child is Node2D):
			continue
		# Check if it's a unit (has move_to or unit_category)
		var is_unit := false
		if "unit_category" in child and str(child.unit_category) != "":
			is_unit = true
		elif child.has_method("move_to"):
			is_unit = true
		if is_unit:
			result.append(child as Node2D)
	return result


func _get_camera_data() -> Dictionary:
	var c := _get_camera()
	if c != null:
		return {
			"position": {"x": c.global_position.x, "y": c.global_position.y}, "zoom": {"x": c.zoom.x, "y": c.zoom.y}
		}
	return {"position": {"x": 0.0, "y": 0.0}, "zoom": {"x": 1.0, "y": 1.0}}


func _get_camera() -> Camera2D:
	var viewport := get_viewport()
	if viewport == null:
		return null
	# Try to find any Camera2D in the scene
	var camera := viewport.get_camera_2d()
	return camera


func _get_manager(autoload_name: String) -> Node:
	var tree := Engine.get_main_loop()
	if tree == null:
		return null
	return tree.root.get_node_or_null(autoload_name)


static func _send_json(peer: StreamPeerTCP, status_code: int, data: Dictionary) -> void:
	var status_text := "OK" if status_code == 200 else "Error"
	if status_code == 400:
		status_text = "Bad Request"
	elif status_code == 404:
		status_text = "Not Found"
	elif status_code == 500:
		status_text = "Internal Server Error"
	var body := JSON.stringify(data)
	var header := "HTTP/1.1 %d %s\r\n" % [status_code, status_text]
	header += "Content-Type: application/json\r\n"
	header += "Content-Length: %d\r\n" % body.length()
	header += "Connection: close\r\n"
	header += "\r\n"
	peer.put_data(header.to_utf8_buffer())
	peer.put_data(body.to_utf8_buffer())


func _handle_entities(peer: StreamPeerTCP, query_string: String) -> void:
	var params := parse_query_string(query_string)
	var verbose: bool = str(params.get("verbose", "false")) == "true"
	var entities: Array[Dictionary] = []
	var root := get_tree().current_scene
	if root != null:
		for child: Node in root.get_children():
			if not (child is Node2D):
				continue
			if "entity_category" not in child:
				continue
			var data: Dictionary
			if verbose:
				data = serialize_entity_verbose(child as Node2D)
			else:
				data = serialize_entity(child as Node2D)
			if data.is_empty():
				continue
			if not _matches_filters(data, params):
				continue
			entities.append(data)
	_send_json(peer, 200, {"entities": entities, "count": entities.size()})


static func _matches_filters(data: Dictionary, params: Dictionary) -> bool:
	if params.has("category"):
		var cat: String = params["category"]
		if str(data.get("entity_category", "")) != cat:
			return false
	if params.has("type"):
		var t: String = params["type"]
		# Match against resource_type, unit_category, or building_name
		var match_found := false
		if str(data.get("resource_type", "")) == t:
			match_found = true
		elif str(data.get("unit_category", "")) == t:
			match_found = true
		elif str(data.get("building_name", "")) == t:
			match_found = true
		if not match_found:
			return false
	if params.has("owner"):
		var owner_val: int = int(params["owner"])
		if not data.has("owner_id"):
			return false
		if int(data["owner_id"]) != owner_val:
			return false
	return true


static func _infer_entity_category(entity: Node2D) -> String:
	var cat: String = str(entity.get("entity_category")) if "entity_category" in entity else ""
	if cat == "" and "unit_category" in entity and str(entity.unit_category) != "":
		var oid: int = int(entity.owner_id) if "owner_id" in entity else 0
		cat = "own_unit" if oid == 0 else "enemy_unit"
	return cat


static func serialize_entity(entity: Node2D) -> Dictionary:
	var cat: String = _infer_entity_category(entity)
	if cat == "":
		return {}
	var r: Dictionary = {
		"name": entity.name,
		"entity_category": cat,
		"position": {"x": entity.global_position.x, "y": entity.global_position.y},
	}
	if "owner_id" in entity:
		r["owner_id"] = int(entity.owner_id)
	if "unit_category" in entity and str(entity.unit_category) != "":
		r["unit_category"] = str(entity.unit_category)
		r["unit_type"] = str(entity.get("unit_type")) if "unit_type" in entity else "land"
		r["hp"] = int(entity.hp) if "hp" in entity else 0
		r["max_hp"] = int(entity.max_hp) if "max_hp" in entity else 0
		r["selected"] = bool(entity.selected) if "selected" in entity else false
		r["gather_state"] = int(entity._gather_state) if "_gather_state" in entity else 0
		r["gather_type"] = str(entity._gather_type) if "_gather_type" in entity else ""
		r["carried_amount"] = int(entity._carried_amount) if "_carried_amount" in entity else 0
		r["carry_capacity"] = int(entity._carry_capacity) if "_carry_capacity" in entity else 0
		r["combat_state"] = int(entity._combat_state) if "_combat_state" in entity else 0
		r["action"] = _get_unit_action(entity)
	if "building_name" in entity and str(entity.building_name) != "":
		r["building_name"] = str(entity.building_name)
		r["hp"] = int(entity.hp) if "hp" in entity else 0
		r["max_hp"] = int(entity.max_hp) if "max_hp" in entity else 0
		r["is_drop_off"] = bool(entity.is_drop_off) if "is_drop_off" in entity else false
		if "drop_off_types" in entity:
			var types: Array[String] = []
			for t: Variant in entity.drop_off_types:
				types.append(str(t))
			r["drop_off_types"] = types
		if "grid_pos" in entity:
			r["grid_position"] = {"x": entity.grid_pos.x, "y": entity.grid_pos.y}
		r["under_construction"] = bool(entity.under_construction) if "under_construction" in entity else false
		r["selected"] = bool(entity.selected) if "selected" in entity else false
	if cat == "resource_node":
		r["resource_type"] = str(entity.resource_type) if "resource_type" in entity else ""
		r["resource_name"] = str(entity.resource_name) if "resource_name" in entity else ""
		r["current_yield"] = int(entity.current_yield) if "current_yield" in entity else 0
		r["total_yield"] = int(entity.total_yield) if "total_yield" in entity else 0
		if "grid_position" in entity:
			r["grid_position"] = {"x": entity.grid_position.x, "y": entity.grid_position.y}
	return r


static func _get_unit_action(entity: Node2D) -> String:
	# Determine high-level action from state
	var combat_state: int = int(entity._combat_state) if "_combat_state" in entity else 0
	if combat_state != 0:
		match combat_state:
			1:
				return "pursuing"
			2:
				return "attacking"
			3:
				return "attack_moving"
			4:
				return "patrolling"
	var gather_state: int = int(entity._gather_state) if "_gather_state" in entity else 0
	if gather_state != 0:
		match gather_state:
			1:
				return "moving_to_resource"
			2:
				return "gathering"
			3:
				return "moving_to_drop_off"
			4:
				return "depositing"
	if "_moving" in entity and entity._moving:
		return "moving"
	return "idle"


static func parse_query_string(qs: String) -> Dictionary:
	var result: Dictionary = {}
	if qs.is_empty():
		return result
	var pairs := qs.split("&")
	for pair: String in pairs:
		var eq := pair.find("=")
		if eq < 0:
			continue
		var key := pair.substr(0, eq).strip_edges()
		var value := pair.substr(eq + 1).strip_edges()
		if not key.is_empty():
			result[key] = value
	return result


func _cmd_spawn(peer: StreamPeerTCP, body: Dictionary) -> void:
	if not body.has("type"):
		_send_json(peer, 400, {"error": "spawn requires type field"})
		return
	if not body.has("grid_x") or not body.has("grid_y"):
		_send_json(peer, 400, {"error": "spawn requires grid_x and grid_y"})
		return
	var spawn_type: String = str(body["type"])
	var gx: float = float(body["grid_x"])
	var gy: float = float(body["grid_y"])
	var gp := Vector2i(int(gx), int(gy))
	var wp := IsoUtils.grid_to_screen(Vector2(gx, gy))
	var root := get_tree().current_scene
	if root == null:
		_send_json(peer, 500, {"error": "no active scene"})
		return
	if spawn_type in RESOURCE_NAMES:
		var node := _spawn_resource(root, spawn_type, gp, wp)
		if node == null:
			_send_json(peer, 500, {"error": "failed to spawn resource", "type": spawn_type})
			return
		_send_json(
			peer,
			200,
			{
				"action": "spawn",
				"entity": "resource",
				"type": spawn_type,
				"name": node.name,
				"grid_x": gx,
				"grid_y": gy,
			}
		)
	else:
		var oid: int = int(body.get("owner", 0))
		var node := _spawn_unit(root, spawn_type, oid, gp, wp)
		if node == null:
			_send_json(peer, 500, {"error": "failed to spawn unit", "type": spawn_type})
			return
		_send_json(
			peer,
			200,
			{
				"action": "spawn",
				"entity": "unit",
				"type": spawn_type,
				"name": node.name,
				"owner": oid,
				"grid_x": gx,
				"grid_y": gy,
			}
		)


func _spawn_unit(root: Node, unit_type: String, oid: int, _grid_pos: Vector2i, wp: Vector2) -> Node2D:
	var u := Node2D.new()
	u.name = "DebugUnit_%d" % root.get_child_count()
	u.set_script(UnitScript)
	u.unit_type = unit_type
	u.owner_id = oid
	u.position = wp
	if oid == 1:
		u.unit_color = Color(0.9, 0.2, 0.2)
	root.add_child(u)
	u._scene_root = root
	if "_pathfinder" in root:
		u._pathfinder = root._pathfinder
	if "_visibility_manager" in root and root._visibility_manager != null:
		u._visibility_manager = root._visibility_manager
	if "_war_survival" in root and root._war_survival != null:
		u._war_survival = root._war_survival
	if "_input_handler" in root and root._input_handler != null:
		if root._input_handler.has_method("register_unit"):
			root._input_handler.register_unit(u)
	if "_target_detector" in root and root._target_detector != null:
		root._target_detector.register_entity(u)
	if "_population_manager" in root and root._population_manager != null:
		root._population_manager.register_unit(u, oid)
	if "_entity_registry" in root:
		root._entity_registry.register(u)
	if u.has_signal("unit_died") and root.has_method("_on_unit_died"):
		u.unit_died.connect(root._on_unit_died)
	return u


func _spawn_resource(root: Node, res_name: String, gp: Vector2i, wp: Vector2) -> Node2D:
	var rn := Node2D.new()
	rn.name = "DebugResource_%s_%d" % [res_name, root.get_child_count()]
	rn.set_script(ResourceNodeScript)
	rn.position = wp
	rn.grid_position = gp
	rn.z_index = 2
	root.add_child(rn)
	rn.setup(res_name)
	if rn.has_signal("depleted") and root.has_method("_on_resource_depleted"):
		rn.depleted.connect(root._on_resource_depleted)
	if "_target_detector" in root and root._target_detector != null:
		root._target_detector.register_entity(rn)
	return rn


func _cmd_teleport(peer: StreamPeerTCP, body: Dictionary) -> void:
	if not body.has("grid_x") or not body.has("grid_y"):
		_send_json(peer, 400, {"error": "teleport requires grid_x and grid_y"})
		return
	var gx: float = float(body["grid_x"])
	var gy: float = float(body["grid_y"])
	var wp := IsoUtils.grid_to_screen(Vector2(gx, gy))
	var moved := 0
	for u: Node2D in _get_player_units(0):
		if "selected" in u and u.selected:
			u.global_position = wp
			if "_moving" in u:
				u._moving = false
			if "_path" in u:
				u._path.clear()
			moved += 1
	_send_json(peer, 200, {"action": "teleport", "grid_x": gx, "grid_y": gy, "moved": moved})


func _cmd_zoom(peer: StreamPeerTCP, body: Dictionary) -> void:
	if not body.has("value"):
		_send_json(peer, 400, {"error": "zoom requires value"})
		return
	var zv: float = float(body["value"])
	var cam := _get_camera()
	if cam != null:
		cam.zoom = Vector2(zv, zv)
	_send_json(peer, 200, {"action": "zoom", "value": zv})


func _cmd_place_building(peer: StreamPeerTCP, body: Dictionary) -> void:
	if not body.has("building_name"):
		_send_json(peer, 400, {"error": "place-building requires building_name"})
		return
	if not body.has("grid_x") or not body.has("grid_y"):
		_send_json(peer, 400, {"error": "place-building requires grid_x and grid_y"})
		return
	var bn: String = str(body["building_name"])
	var gx: int = int(body["grid_x"])
	var gy: int = int(body["grid_y"])
	var gp := Vector2i(gx, gy)
	var oid: int = int(body.get("owner", 0))
	var built: bool = str(body.get("built", "true")) != "false"
	var root := get_tree().current_scene
	if root == null:
		_send_json(peer, 500, {"error": "no active scene"})
		return
	var st: Dictionary = DataLoader.get_building_stats(bn)
	if st.is_empty():
		_send_json(peer, 400, {"error": "unknown building", "building_name": bn})
		return
	var mhp: int = int(st.get("hp", 100))
	var fp_arr: Array = st.get("footprint", [1, 1])
	var fp := Vector2i(int(fp_arr[0]), int(fp_arr[1]))
	var b := Node2D.new()
	b.name = "Building_%s_%d_%d" % [bn, gx, gy]
	b.set_script(BuildingScript)
	b.position = IsoUtils.grid_to_screen(Vector2(gp))
	b.owner_id = oid
	b.building_name = bn
	b.footprint = fp
	b.grid_pos = gp
	b.max_hp = mhp
	b.entity_category = "own_building" if oid == 0 else "enemy_building"
	if built:
		b.hp = mhp
		b.under_construction = false
		b.build_progress = 1.0
	else:
		b.hp = 0
		b.under_construction = true
		b.build_progress = 0.0
		b._build_time = float(st.get("build_time", 25))
	root.add_child(b)
	if "_target_detector" in root and root._target_detector != null:
		root._target_detector.register_entity(b)
	if "_population_manager" in root and root._population_manager != null:
		root._population_manager.register_building(b, oid)
	if "_entity_registry" in root:
		root._entity_registry.register(b)
	if b.has_signal("building_destroyed") and root.has_method("_on_building_destroyed"):
		b.building_destroyed.connect(root._on_building_destroyed)
	if "_pathfinder" in root and root._pathfinder != null:
		for cell: Vector2i in BuildingValidator.get_footprint_cells(gp, fp):
			root._pathfinder.set_cell_solid(cell, true)
	_send_json(
		peer,
		200,
		{
			"action": "place-building",
			"building_name": bn,
			"grid_x": gx,
			"grid_y": gy,
			"owner": oid,
			"built": built,
		}
	)


func _cmd_stop(peer: StreamPeerTCP, body: Dictionary) -> void:
	var ids: Array = body.get("unit_ids", []) as Array
	var units: Array[Node2D] = []
	if ids.is_empty():
		for u: Node2D in _get_player_units(0):
			if "selected" in u and u.selected:
				units.append(u)
	else:
		var root := get_tree().current_scene
		if root != null:
			for uid: Variant in ids:
				var n := root.get_node_or_null(NodePath(str(uid)))
				if n is Node2D:
					units.append(n as Node2D)
	var stopped := 0
	for u: Node2D in units:
		if u.has_method("_cancel_combat"):
			u._cancel_combat()
		if u.has_method("_cancel_gather"):
			u._cancel_gather()
		if u.has_method("_cancel_feed"):
			u._cancel_feed()
		if "_moving" in u:
			u._moving = false
		if "_path" in u:
			u._path.clear()
		if "_build_target" in u:
			u._build_target = null
		if "_pending_build_target_name" in u:
			u._pending_build_target_name = ""
		stopped += 1
	_send_json(peer, 200, {"action": "stop", "stopped": stopped})


func _cmd_reset(peer: StreamPeerTCP) -> void:
	_send_json(peer, 200, {"action": "reset", "status": "reloading"})
	get_tree().call_deferred("reload_current_scene")


func _cmd_set_resources(peer: StreamPeerTCP, body: Dictionary) -> void:
	var rm: Node = _get_manager("ResourceManager")
	if rm == null:
		_send_json(peer, 500, {"error": "ResourceManager not available"})
		return
	var ktt: Dictionary = {}
	for rt: Variant in rm.RESOURCE_KEYS:
		ktt[rm.RESOURCE_KEYS[rt]] = rt
	var updated: Dictionary = {}
	for key: String in ktt:
		if body.has(key):
			var amt: int = int(body[key])
			rm.set_resource(0, ktt[key], amt)
			updated[key] = amt
	_send_json(peer, 200, {"action": "set-resources", "resources": _get_player_resources(rm), "updated": updated})


func _cmd_save(peer: StreamPeerTCP, body: Dictionary) -> void:
	var slot: String = str(body.get("slot", "debug_scenario"))
	var sm: Node = _get_manager("SaveManager")
	if sm == null:
		_send_json(peer, 500, {"error": "SaveManager not available"})
		return
	var sp := "user://saves/debug_%s.json" % slot
	sm._ensure_save_dir()
	var data := {
		"version": sm.SAVE_VERSION,
		"timestamp": Time.get_unix_time_from_system(),
		"game_manager": GameManager.save_state(),
		"resource_manager": ResourceManager.save_state(),
		"civ_bonus_manager": CivBonusManager.save_state(),
	}
	if sm._scene_provider != null and sm._scene_provider.has_method("save_state"):
		data["scene"] = sm._scene_provider.save_state()
	var f := FileAccess.open(sp, FileAccess.WRITE)
	if f == null:
		_send_json(peer, 500, {"error": "failed to write save file", "path": sp})
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	_send_json(peer, 200, {"action": "save", "slot": slot, "path": sp})


func _cmd_load(peer: StreamPeerTCP, body: Dictionary) -> void:
	var slot: String = str(body.get("slot", "debug_scenario"))
	var sm: Node = _get_manager("SaveManager")
	if sm == null:
		_send_json(peer, 500, {"error": "SaveManager not available"})
		return
	var sp := "user://saves/debug_%s.json" % slot
	if not FileAccess.file_exists(sp):
		_send_json(peer, 400, {"error": "save file not found", "slot": slot, "path": sp})
		return
	var f := FileAccess.open(sp, FileAccess.READ)
	if f == null:
		_send_json(peer, 500, {"error": "failed to read save file", "path": sp})
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed == null or not (parsed is Dictionary):
		_send_json(peer, 500, {"error": "failed to parse save file", "path": sp})
		return
	_send_json(peer, 200, {"action": "load", "slot": slot, "status": "loading"})
	sm.call_deferred("apply_loaded_state", parsed as Dictionary)


func _handle_pathfinding(peer: StreamPeerTCP, query_string: String) -> void:
	var root := get_tree().current_scene
	if root == null or "_pathfinder" not in root or root._pathfinder == null:
		_send_json(peer, 200, {"error": "pathfinder not available"})
		return
	var pf: Node = root._pathfinder
	var ms: int = int(pf._map_size)
	var solid_cells: Array[Dictionary] = []
	if pf._astar != null:
		for x in ms:
			for y in ms:
				if pf._astar.is_point_solid(Vector2i(x, y)):
					solid_cells.append({"x": x, "y": y})
	var result: Dictionary = {
		"map_size": ms,
		"solid_cell_count": solid_cells.size(),
		"solid_cells": solid_cells,
	}
	var params := parse_query_string(query_string)
	if params.has("unit"):
		var un: String = params["unit"]
		var node: Node = root.get_node_or_null(NodePath(un))
		if node != null and "_path" in node:
			var wps: Array[Dictionary] = []
			for wp: Vector2 in node._path:
				wps.append({"x": wp.x, "y": wp.y})
			result["unit_path"] = {"name": un, "waypoints": wps}
		else:
			result["unit_path"] = {"name": un, "error": "not found or no path"}
	_send_json(peer, 200, result)


func _handle_perf(peer: StreamPeerTCP) -> void:
	var ec: Dictionary = {"unit": 0, "building": 0, "resource_node": 0}
	var root := get_tree().current_scene
	if root != null:
		for child: Node in root.get_children():
			if "entity_category" not in child:
				continue
			var cat: String = str(child.entity_category)
			if "unit" in cat or ("unit_category" in child and str(child.unit_category) != ""):
				ec["unit"] = int(ec["unit"]) + 1
			elif "building" in cat:
				ec["building"] = int(ec["building"]) + 1
			elif cat == "resource_node":
				ec["resource_node"] = int(ec["resource_node"]) + 1
	var pm := Performance.get_monitor
	_send_json(
		peer,
		200,
		{
			"fps": pm.call(Performance.TIME_FPS),
			"frame_time_ms": pm.call(Performance.TIME_PROCESS) * 1000.0,
			"physics_time_ms": pm.call(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			"memory_static_bytes": int(pm.call(Performance.MEMORY_STATIC)),
			"orphan_node_count": int(pm.call(Performance.OBJECT_ORPHAN_NODE_COUNT)),
			"total_node_count": int(pm.call(Performance.OBJECT_NODE_COUNT)),
			"entity_counts": ec,
		}
	)


func _handle_fow(peer: StreamPeerTCP, query_string: String) -> void:
	var root := get_tree().current_scene
	if root == null or "_visibility_manager" not in root or root._visibility_manager == null:
		_send_json(peer, 200, {"error": "visibility_manager not available"})
		return
	var vm: Node = root._visibility_manager
	var params := parse_query_string(query_string)
	var pid: int = int(params.get("player", "0"))
	var map_w: int = int(vm._map_width)
	var map_h: int = int(vm._map_height)
	var total: int = map_w * map_h
	var vis: Dictionary = vm.get_visible_tiles(pid)
	var exp: Dictionary = vm.get_explored_tiles(pid)
	var pv: float = (float(vis.size()) / float(total) * 100.0) if total > 0 else 0.0
	var pe: float = (float(exp.size()) / float(total) * 100.0) if total > 0 else 0.0
	var los_src: Array[Dictionary] = []
	for child: Node in root.get_children():
		if not (child is Node2D):
			continue
		if "owner_id" not in child or int(child.owner_id) != pid:
			continue
		if ("unit_category" in child and str(child.unit_category) != "") or child.has_method("move_to"):
			var pos := (child as Node2D).global_position
			los_src.append({"name": child.name, "position": {"x": pos.x, "y": pos.y}})
	_send_json(
		peer,
		200,
		{
			"player_id": pid,
			"map_width": map_w,
			"map_height": map_h,
			"total_tiles": total,
			"visible_tile_count": vis.size(),
			"explored_tile_count": exp.size(),
			"percent_visible": snapped(pv, 0.01),
			"percent_explored": snapped(pe, 0.01),
			"los_source_count": los_src.size(),
			"los_sources": los_src,
		}
	)


static func serialize_entity_verbose(entity: Node2D) -> Dictionary:
	## Extended entity serialization with component state detail.
	var base := serialize_entity(entity)
	if base.is_empty():
		return base
	if not ("unit_category" in entity and str(entity.unit_category) != ""):
		return base
	# Gather detail
	var gd: Dictionary = {}
	var gt: Node2D = entity._gather_target if "_gather_target" in entity else null
	if gt != null and is_instance_valid(gt):
		gd["target_name"] = gt.name
		gd["target_position"] = {"x": gt.global_position.x, "y": gt.global_position.y}
	gd["gather_rate_multiplier"] = float(entity._gather_rate_multiplier) if "_gather_rate_multiplier" in entity else 1.0
	gd["gather_reach"] = float(entity._gather_reach) if "_gather_reach" in entity else 80.0
	gd["drop_off_reach"] = float(entity._drop_off_reach) if "_drop_off_reach" in entity else 80.0
	var dot: Node2D = entity._drop_off_target if "_drop_off_target" in entity else null
	if dot != null and is_instance_valid(dot):
		gd["drop_off_target_name"] = dot.name
	base["gather_detail"] = gd
	# Combat detail
	var cd: Dictionary = {}
	cd["stance"] = int(entity._stance) if "_stance" in entity else 0
	var ct: Node2D = entity._combat_target if "_combat_target" in entity else null
	if ct != null and is_instance_valid(ct):
		cd["target_name"] = ct.name
		cd["target_position"] = {"x": ct.global_position.x, "y": ct.global_position.y}
	cd["attack_cooldown"] = float(entity._attack_cooldown) if "_attack_cooldown" in entity else 0.0
	base["combat_detail"] = cd
	var bt: Node2D = entity._build_target if "_build_target" in entity else null
	if bt != null and is_instance_valid(bt):
		base["build_target"] = bt.name
	if "_path" in entity:
		base["path_length"] = entity._path.size()
	base["is_dead"] = bool(entity._is_dead) if "_is_dead" in entity else false
	return base


func _exit_tree() -> void:
	if _server != null:
		_server.stop()
		_active = false


static func _should_activate() -> bool:
	return OS.get_cmdline_user_args().has("--debug-server")


## Build /status response (static, for testability).
static func build_status_response(
	game_time: float,
	game_speed: float,
	is_paused: bool,
	current_age: int,
	player_resources: Dictionary,
	unit_count: Dictionary,
	camera_position: Dictionary,
	camera_zoom: Dictionary,
) -> Dictionary:
	return {
		"game_time": game_time,
		"game_speed": game_speed,
		"is_paused": is_paused,
		"current_age": current_age,
		"player_resources": player_resources,
		"unit_count": unit_count,
		"camera_position": camera_position,
		"camera_zoom": camera_zoom,
	}


## Parse command body and validate action field (static, for testability).
static func parse_command_body(body_text: String) -> Dictionary:
	if body_text.is_empty():
		return {"error": "empty request body"}
	var parsed: Variant = JSON.parse_string(body_text)
	if parsed == null or not (parsed is Dictionary):
		return {"error": "invalid JSON"}
	var body: Dictionary = parsed
	var action: String = str(body.get("action", ""))
	if action.is_empty():
		return {"error": "missing action field"}
	return {"action": action, "body": body}
