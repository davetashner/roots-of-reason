extends GdUnitTestSuite
## Tests for debug_server.gd — HTTP debug server for dev tooling.

const DebugServerScript := preload("res://scripts/debug/debug_server.gd")


class MockUnit:
	extends Node2D
	var entity_category: String = "own_unit"
	var owner_id: int = 0
	var unit_category: String = "villager"
	var unit_type: String = "land"
	var hp: int = 50
	var max_hp: int = 50
	var selected: bool = false
	var _gather_state: int = 0
	var _gather_type: String = ""
	var _carried_amount: int = 0
	var _carry_capacity: int = 10
	var _combat_state: int = 0
	var _moving: bool = false


class MockResource:
	extends Node2D
	var entity_category: String = "resource_node"
	var resource_name: String = "forest"
	var resource_type: String = "wood"
	var current_yield: int = 150
	var total_yield: int = 200
	var grid_position: Vector2i = Vector2i(5, 10)


class MockBuilding:
	extends Node2D
	var entity_category: String = "own_building"
	var owner_id: int = 0
	var building_name: String = "barracks"
	var hp: int = 800
	var max_hp: int = 1000
	var is_drop_off: bool = false
	var drop_off_types: Array[String] = []
	var grid_pos: Vector2i = Vector2i(3, 7)
	var under_construction: bool = true
	var selected: bool = false


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


# -- parse_query_string tests --


func test_parse_query_string_empty() -> void:
	var result := DebugServerScript.parse_query_string("")
	assert_dict(result).is_empty()


func test_parse_query_string_single_param() -> void:
	var result := DebugServerScript.parse_query_string("category=unit")
	assert_str(result.get("category", "")).is_equal("unit")


func test_parse_query_string_multiple_params() -> void:
	var result := DebugServerScript.parse_query_string("category=unit&owner=0&type=villager")
	assert_str(result.get("category", "")).is_equal("unit")
	assert_str(result.get("owner", "")).is_equal("0")
	assert_str(result.get("type", "")).is_equal("villager")


func test_parse_query_string_no_value_skipped() -> void:
	var result := DebugServerScript.parse_query_string("novalue")
	assert_dict(result).is_empty()


# -- serialize_entity tests --


func test_serialize_entity_unit() -> void:
	var unit := MockUnit.new()
	auto_free(unit)
	unit.name = "TestUnit"
	var result := DebugServerScript.serialize_entity(unit)
	assert_str(result.get("name", "")).is_equal("TestUnit")
	assert_str(result.get("unit_category", "")).is_equal("villager")
	assert_int(int(result.get("owner_id", -1))).is_equal(0)
	assert_int(int(result.get("hp", -1))).is_equal(50)
	assert_str(result.get("action", "")).is_equal("idle")


func test_serialize_entity_resource() -> void:
	var res := MockResource.new()
	auto_free(res)
	res.name = "TreeNode"
	var result := DebugServerScript.serialize_entity(res)
	assert_str(result.get("entity_category", "")).is_equal("resource_node")
	assert_str(result.get("resource_name", "")).is_equal("forest")
	assert_str(result.get("resource_type", "")).is_equal("wood")
	assert_int(int(result.get("current_yield", 0))).is_equal(150)
	assert_int(int(result.get("total_yield", 0))).is_equal(200)
	var grid: Dictionary = result.get("grid_position", {})
	assert_int(int(grid.get("x", 0))).is_equal(5)
	assert_int(int(grid.get("y", 0))).is_equal(10)


func test_serialize_entity_building() -> void:
	var bldg := MockBuilding.new()
	auto_free(bldg)
	bldg.name = "Barracks"
	var result := DebugServerScript.serialize_entity(bldg)
	assert_str(result.get("building_name", "")).is_equal("barracks")
	assert_int(int(result.get("hp", 0))).is_equal(800)
	assert_bool(result.get("under_construction", false)).is_true()


func test_serialize_entity_empty_category_with_unit_category() -> void:
	var unit := MockUnit.new()
	auto_free(unit)
	unit.entity_category = ""
	unit.unit_category = "villager"
	var result := DebugServerScript.serialize_entity(unit)
	assert_str(result.get("entity_category", "")).is_equal("own_unit")
	assert_str(result.get("unit_category", "")).is_equal("villager")


func test_serialize_entity_empty_category_no_unit_category() -> void:
	var unit := MockUnit.new()
	auto_free(unit)
	unit.entity_category = ""
	unit.unit_category = ""
	var result := DebugServerScript.serialize_entity(unit)
	assert_dict(result).is_empty()


func test_serialize_entity_infers_enemy_unit() -> void:
	var unit := MockUnit.new()
	auto_free(unit)
	unit.entity_category = ""
	unit.owner_id = 1
	unit.unit_category = "archer"
	var result := DebugServerScript.serialize_entity(unit)
	assert_str(result.get("entity_category", "")).is_equal("enemy_unit")


func test_get_unit_action_idle() -> void:
	var unit := MockUnit.new()
	auto_free(unit)
	assert_str(DebugServerScript._get_unit_action(unit)).is_equal("idle")


func test_get_unit_action_gathering() -> void:
	var unit := MockUnit.new()
	auto_free(unit)
	unit._gather_state = 2
	assert_str(DebugServerScript._get_unit_action(unit)).is_equal("gathering")


func test_get_unit_action_attacking() -> void:
	var unit := MockUnit.new()
	auto_free(unit)
	unit._combat_state = 2
	assert_str(DebugServerScript._get_unit_action(unit)).is_equal("attacking")


func test_get_unit_action_moving() -> void:
	var unit := MockUnit.new()
	auto_free(unit)
	unit._moving = true
	assert_str(DebugServerScript._get_unit_action(unit)).is_equal("moving")


func test_matches_filters_no_filters() -> void:
	var data := {"entity_category": "unit", "owner_id": 0}
	assert_bool(DebugServerScript._matches_filters(data, {})).is_true()


func test_matches_filters_category_match() -> void:
	var data := {"entity_category": "resource_node"}
	assert_bool(DebugServerScript._matches_filters(data, {"category": "resource_node"})).is_true()


func test_matches_filters_category_mismatch() -> void:
	var data := {"entity_category": "own_building"}
	assert_bool(DebugServerScript._matches_filters(data, {"category": "resource_node"})).is_false()


func test_matches_filters_owner_match() -> void:
	var data := {"entity_category": "unit", "owner_id": 1}
	assert_bool(DebugServerScript._matches_filters(data, {"owner": "1"})).is_true()


func test_matches_filters_owner_mismatch() -> void:
	var data := {"entity_category": "unit", "owner_id": 0}
	assert_bool(DebugServerScript._matches_filters(data, {"owner": "1"})).is_false()


func test_matches_filters_type_unit_category() -> void:
	var data := {"entity_category": "own_unit", "unit_category": "villager"}
	assert_bool(DebugServerScript._matches_filters(data, {"type": "villager"})).is_true()


func test_matches_filters_type_resource_type() -> void:
	var data := {"entity_category": "resource_node", "resource_type": "wood"}
	assert_bool(DebugServerScript._matches_filters(data, {"type": "wood"})).is_true()


func test_matches_filters_type_mismatch() -> void:
	var data := {"entity_category": "own_unit", "unit_category": "archer"}
	assert_bool(DebugServerScript._matches_filters(data, {"type": "villager"})).is_false()


# -- parse_command_body spawn/teleport tests --


func test_parse_command_body_spawn() -> void:
	var result := DebugServerScript.parse_command_body(
		'{"action": "spawn", "type": "villager", "grid_x": 5, "grid_y": 5, "owner": 0}'
	)
	assert_str(result.get("action", "")).is_equal("spawn")
	var body: Dictionary = result.get("body", {})
	assert_str(str(body.get("type", ""))).is_equal("villager")
	assert_float(float(body.get("grid_x", 0))).is_equal(5.0)
	assert_float(float(body.get("grid_y", 0))).is_equal(5.0)


func test_parse_command_body_spawn_resource() -> void:
	var result := DebugServerScript.parse_command_body('{"action": "spawn", "type": "tree", "grid_x": 8, "grid_y": 8}')
	assert_str(result.get("action", "")).is_equal("spawn")
	var body: Dictionary = result.get("body", {})
	assert_str(str(body.get("type", ""))).is_equal("tree")


func test_parse_command_body_teleport() -> void:
	var result := DebugServerScript.parse_command_body('{"action": "teleport", "grid_x": 10, "grid_y": 15}')
	assert_str(result.get("action", "")).is_equal("teleport")
	var body: Dictionary = result.get("body", {})
	assert_float(float(body.get("grid_x", 0))).is_equal(10.0)
	assert_float(float(body.get("grid_y", 0))).is_equal(15.0)


func test_resource_names_contains_tree() -> void:
	assert_bool("tree" in DebugServerScript.RESOURCE_NAMES).is_true()


func test_resource_names_contains_gold_mine() -> void:
	assert_bool("gold_mine" in DebugServerScript.RESOURCE_NAMES).is_true()


func test_resource_names_does_not_contain_villager() -> void:
	assert_bool("villager" in DebugServerScript.RESOURCE_NAMES).is_false()


# -- world_to_screen tests --


func test_world_to_screen_center() -> void:
	var cam_pos := Vector2(100, 100)
	var cam_zoom := Vector2(1, 1)
	var vp_size := Vector2(800, 600)
	# Entity at camera position should be at viewport center
	var result := DebugServerScript._world_to_screen(Vector2(100, 100), cam_pos, cam_zoom, vp_size)
	assert_float(result.x).is_equal(400.0)
	assert_float(result.y).is_equal(300.0)


func test_world_to_screen_offset() -> void:
	var cam_pos := Vector2(0, 0)
	var cam_zoom := Vector2(1, 1)
	var vp_size := Vector2(800, 600)
	var result := DebugServerScript._world_to_screen(Vector2(50, 30), cam_pos, cam_zoom, vp_size)
	assert_float(result.x).is_equal(450.0)
	assert_float(result.y).is_equal(330.0)


func test_world_to_screen_zoom() -> void:
	var cam_pos := Vector2(0, 0)
	var cam_zoom := Vector2(2, 2)
	var vp_size := Vector2(800, 600)
	var result := DebugServerScript._world_to_screen(Vector2(50, 30), cam_pos, cam_zoom, vp_size)
	# (50-0)*2 + 400 = 500, (30-0)*2 + 300 = 360
	assert_float(result.x).is_equal(500.0)
	assert_float(result.y).is_equal(360.0)


# -- screenshot query string tests --


func test_parse_command_body_stop() -> void:
	var result := DebugServerScript.parse_command_body('{"action": "stop"}')
	assert_str(result.get("action", "")).is_equal("stop")
	assert_dict(result).contains_keys(["action", "body"])


func test_parse_command_body_stop_with_unit_ids() -> void:
	var result := DebugServerScript.parse_command_body('{"action": "stop", "unit_ids": ["Unit1", "Unit2"]}')
	assert_str(result.get("action", "")).is_equal("stop")
	var body: Dictionary = result.get("body", {})
	var ids: Array = body.get("unit_ids", []) as Array
	assert_int(ids.size()).is_equal(2)


func test_parse_request_screenshot_with_annotate() -> void:
	var result := DebugServerScript._parse_request("GET /screenshot?annotate=true HTTP/1.1\r\n\r\n")
	assert_str(result.get("method", "")).is_equal("GET")
	assert_str(result.get("path", "")).is_equal("/screenshot?annotate=true")
