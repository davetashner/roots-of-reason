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
