extends Node
## Lightweight HTTP debug server for dev tooling (screenshot capture, etc.).
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
	# Read the HTTP request line-by-line until we get a blank line.
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
	if method == "GET" and path == "/ping":
		_send_json(peer, 200, {"status": "ok"})
	elif method == "GET" and path == "/screenshot":
		_handle_screenshot(peer)
	else:
		_send_json(peer, 404, {"error": "not found", "path": path})
	peer.disconnect_from_host()


static func _parse_request(raw: String) -> Dictionary:
	var lines := raw.split("\n")
	if lines.is_empty():
		return {}
	var request_line := lines[0].strip_edges()
	var parts := request_line.split(" ")
	if parts.size() < 2:
		return {}
	return {"method": parts[0], "path": parts[1]}


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


static func _send_json(peer: StreamPeerTCP, status_code: int, data: Dictionary) -> void:
	var status_text := "OK" if status_code == 200 else "Error"
	if status_code == 404:
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
