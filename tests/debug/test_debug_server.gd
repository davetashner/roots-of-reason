extends GdUnitTestSuite
## Tests for debug_server.gd — HTTP debug server for dev tooling.

const DebugServerScript := preload("res://scripts/debug/debug_server.gd")


func test_should_activate_returns_false_without_flag() -> void:
	# _should_activate is static so we can call it directly.
	# In the test runner, --debug-server is not passed.
	assert_bool(DebugServerScript._should_activate()).is_false()


func test_parse_request_get_ping() -> void:
	var result := DebugServerScript._parse_request("GET /ping HTTP/1.1\r\nHost: localhost\r\n\r\n")
	assert_str(result.get("method", "")).is_equal("GET")
	assert_str(result.get("path", "")).is_equal("/ping")


func test_parse_request_get_screenshot() -> void:
	var result := DebugServerScript._parse_request("GET /screenshot HTTP/1.1\r\n\r\n")
	assert_str(result.get("method", "")).is_equal("GET")
	assert_str(result.get("path", "")).is_equal("/screenshot")


func test_parse_request_empty_string() -> void:
	var result := DebugServerScript._parse_request("")
	assert_dict(result).is_empty()


func test_parse_request_malformed() -> void:
	var result := DebugServerScript._parse_request("GARBAGE")
	assert_dict(result).is_empty()


func test_parse_request_post_method() -> void:
	var result := DebugServerScript._parse_request("POST /command HTTP/1.1\r\n\r\n")
	assert_str(result.get("method", "")).is_equal("POST")
	assert_str(result.get("path", "")).is_equal("/command")


func test_parse_request_extracts_headers() -> void:
	var raw := "POST /command HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 42\r\n\r\n"
	var result := DebugServerScript._parse_request(raw)
	var headers: Dictionary = result.get("headers", {})
	assert_str(headers.get("content-type", "")).is_equal("application/json")
	assert_str(headers.get("content-length", "")).is_equal("42")


func test_parse_request_headers_case_insensitive() -> void:
	var raw := "GET /status HTTP/1.1\r\nHost: Localhost\r\nACCEPT: text/html\r\n\r\n"
	var result := DebugServerScript._parse_request(raw)
	var headers: Dictionary = result.get("headers", {})
	assert_str(headers.get("host", "")).is_equal("Localhost")
	assert_str(headers.get("accept", "")).is_equal("text/html")


func test_parse_request_get_status() -> void:
	var result := DebugServerScript._parse_request("GET /status HTTP/1.1\r\n\r\n")
	assert_str(result.get("method", "")).is_equal("GET")
	assert_str(result.get("path", "")).is_equal("/status")


func test_server_inactive_by_default() -> void:
	var server := DebugServerScript.new()
	auto_free(server)
	# Before _ready, _active should be false
	assert_bool(server._active).is_false()


func test_server_no_listening_without_flag() -> void:
	var server := DebugServerScript.new()
	add_child(server)
	# _ready should have run but not activated (no --debug-server flag)
	assert_bool(server._active).is_false()
	assert_object(server._server).is_null()
	server.queue_free()


# -- build_status_response tests --


func test_build_status_response_has_all_keys() -> void:
	var result := DebugServerScript.build_status_response(
		10.5, 2.0, false, 1, {"food": 100, "wood": 200}, {"0": 5}, {"x": 0.0, "y": 0.0}, {"x": 1.0, "y": 1.0}
	)
	assert_float(result["game_time"]).is_equal(10.5)
	assert_float(result["game_speed"]).is_equal(2.0)
	assert_bool(result["is_paused"]).is_false()
	assert_int(result["current_age"]).is_equal(1)
	assert_dict(result["player_resources"]).has_size(2)
	assert_dict(result["unit_count"]).has_size(1)
	assert_dict(result["camera_position"]).contains_key_value("x", 0.0)
	assert_dict(result["camera_zoom"]).contains_key_value("x", 1.0)


func test_build_status_response_paused() -> void:
	var result := DebugServerScript.build_status_response(
		0.0, 1.0, true, 0, {}, {}, {"x": 0.0, "y": 0.0}, {"x": 1.0, "y": 1.0}
	)
	assert_bool(result["is_paused"]).is_true()


# -- parse_command_body tests --


func test_parse_command_body_empty() -> void:
	var result := DebugServerScript.parse_command_body("")
	assert_str(result.get("error", "")).is_equal("empty request body")


func test_parse_command_body_invalid_json() -> void:
	var result := DebugServerScript.parse_command_body("{not json")
	assert_str(result.get("error", "")).is_equal("invalid JSON")


func test_parse_command_body_missing_action() -> void:
	var result := DebugServerScript.parse_command_body('{"foo": "bar"}')
	assert_str(result.get("error", "")).is_equal("missing action field")


func test_parse_command_body_select_all() -> void:
	var result := DebugServerScript.parse_command_body('{"action": "select-all"}')
	assert_str(result.get("action", "")).is_equal("select-all")
	assert_dict(result).contains_keys(["action", "body"])


func test_parse_command_body_right_click() -> void:
	var result := DebugServerScript.parse_command_body('{"action": "right-click", "grid_x": 10, "grid_y": 20}')
	assert_str(result.get("action", "")).is_equal("right-click")
	var body: Dictionary = result.get("body", {})
	assert_float(float(body.get("grid_x", 0))).is_equal(10.0)
	assert_float(float(body.get("grid_y", 0))).is_equal(20.0)


func test_parse_command_body_camera_to() -> void:
	var result := DebugServerScript.parse_command_body('{"action": "camera-to", "grid_x": 5, "grid_y": 8}')
	assert_str(result.get("action", "")).is_equal("camera-to")


func test_parse_command_body_speed() -> void:
	var result := DebugServerScript.parse_command_body('{"action": "speed", "value": 2.0}')
	assert_str(result.get("action", "")).is_equal("speed")
	var body: Dictionary = result.get("body", {})
	assert_float(float(body.get("value", 0))).is_equal(2.0)


func test_parse_command_body_pause() -> void:
	var result := DebugServerScript.parse_command_body('{"action": "pause"}')
	assert_str(result.get("action", "")).is_equal("pause")


func test_parse_command_body_unpause() -> void:
	var result := DebugServerScript.parse_command_body('{"action": "unpause"}')
	assert_str(result.get("action", "")).is_equal("unpause")


func test_parse_command_body_non_dict_json() -> void:
	var result := DebugServerScript.parse_command_body('"just a string"')
	assert_str(result.get("error", "")).is_equal("invalid JSON")


func test_parse_command_body_array_json() -> void:
	var result := DebugServerScript.parse_command_body("[1, 2, 3]")
	assert_str(result.get("error", "")).is_equal("invalid JSON")
