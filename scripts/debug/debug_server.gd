extends Node
## Lightweight HTTP debug server for dev tooling (screenshot capture, status, commands).
## Only activates when --debug-server is passed via OS.get_cmdline_user_args().
## Listens on 127.0.0.1:9222, handles one request at a time.

const DEFAULT_PORT: int = 9222
const BIND_HOST: String = "127.0.0.1"
const MAX_REQUEST_SIZE: int = 4096

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
	if method == "GET" and path == "/ping":
		_send_json(peer, 200, {"status": "ok"})
	elif method == "GET" and path == "/screenshot":
		_handle_screenshot(peer)
	elif method == "GET" and path == "/status":
		_handle_status(peer)
	elif method == "POST" and path == "/command":
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


func _handle_screenshot(peer: StreamPeerTCP) -> void:
	var viewport := get_viewport()
	if viewport == null:
		_send_json(peer, 500, {"error": "no viewport"})
		return
	var image := viewport.get_texture().get_image()
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


func _handle_status(peer: StreamPeerTCP) -> void:
	var gm: Node = _get_manager("GameManager")
	var rm: Node = _get_manager("ResourceManager")
	var data: Dictionary = {}
	# Game state from GameManager
	if gm != null:
		data["game_time"] = gm.game_time
		data["game_speed"] = gm.game_speed
		data["is_paused"] = gm.is_paused
		data["current_age"] = gm.current_age
	else:
		data["game_time"] = 0.0
		data["game_speed"] = 1.0
		data["is_paused"] = false
		data["current_age"] = 0
	# Player 0 resources from ResourceManager
	data["player_resources"] = _get_player_resources(rm)
	# Unit counts by owner_id from scene tree
	data["unit_count"] = _get_unit_counts()
	# Camera position and zoom
	var cam_data := _get_camera_data()
	data["camera_position"] = cam_data["position"]
	data["camera_zoom"] = cam_data["zoom"]
	_send_json(peer, 200, data)


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
		_:
			_send_json(peer, 400, {"error": "unknown action", "action": action})


func _cmd_select_all(peer: StreamPeerTCP) -> void:
	var units := _get_player_units(0)
	var count := 0
	for unit: Node2D in units:
		if unit.has_method("select"):
			unit.select()
			count += 1
		elif "selected" in unit:
			unit.selected = true
			count += 1
	_send_json(peer, 200, {"action": "select-all", "selected": count})


func _cmd_right_click(peer: StreamPeerTCP, body: Dictionary) -> void:
	if not body.has("grid_x") or not body.has("grid_y"):
		_send_json(peer, 400, {"error": "right-click requires grid_x and grid_y"})
		return
	var grid_x: float = float(body["grid_x"])
	var grid_y: float = float(body["grid_y"])
	var world_pos := IsoUtils.grid_to_screen(Vector2(grid_x, grid_y))
	var units := _get_player_units(0)
	var moved := 0
	for unit: Node2D in units:
		if "selected" in unit and unit.selected and unit.has_method("move_to"):
			unit.move_to(world_pos)
			moved += 1
	_send_json(
		peer,
		200,
		{"action": "right-click", "grid_x": grid_x, "grid_y": grid_y, "moved": moved},
	)


func _cmd_camera_to(peer: StreamPeerTCP, body: Dictionary) -> void:
	if not body.has("grid_x") or not body.has("grid_y"):
		_send_json(peer, 400, {"error": "camera-to requires grid_x and grid_y"})
		return
	var grid_x: float = float(body["grid_x"])
	var grid_y: float = float(body["grid_y"])
	var world_pos := IsoUtils.grid_to_screen(Vector2(grid_x, grid_y))
	var camera := _get_camera()
	if camera != null:
		camera.global_position = world_pos
	_send_json(
		peer,
		200,
		{"action": "camera-to", "grid_x": grid_x, "grid_y": grid_y},
	)


func _cmd_speed(peer: StreamPeerTCP, body: Dictionary) -> void:
	if not body.has("value"):
		_send_json(peer, 400, {"error": "speed requires value"})
		return
	var speed_value: float = float(body["value"])
	var gm: Node = _get_manager("GameManager")
	if gm != null:
		gm.game_speed = speed_value
	_send_json(peer, 200, {"action": "speed", "value": speed_value})


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
	var camera := _get_camera()
	if camera != null:
		return {
			"position": {"x": camera.global_position.x, "y": camera.global_position.y},
			"zoom": {"x": camera.zoom.x, "y": camera.zoom.y},
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


func _exit_tree() -> void:
	if _server != null:
		_server.stop()
		_active = false


static func _should_activate() -> bool:
	return OS.get_cmdline_user_args().has("--debug-server")


## Build the response dictionary for /status (static, for testability).
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


## Parse a command body and validate the action field (static, for testability).
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
