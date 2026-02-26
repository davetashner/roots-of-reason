extends GdUnitTestSuite
## Tests for scripts/ui/river_overlay.gd — flow arrows, toggle, classification.

const OverlayScript := preload("res://scripts/ui/river_overlay.gd")


func _create_overlay() -> Node2D:
	var overlay := Node2D.new()
	overlay.set_script(OverlayScript)
	add_child(overlay)
	return auto_free(overlay)


func test_initial_state_hidden() -> void:
	var overlay := _create_overlay()
	assert_bool(overlay.visible).is_false()
	assert_bool(overlay.is_overlay_visible()).is_false()


func test_toggle_makes_visible() -> void:
	var overlay := _create_overlay()
	overlay.toggle()
	assert_bool(overlay.is_overlay_visible()).is_true()
	assert_bool(overlay.visible).is_true()


func test_toggle_twice_hides() -> void:
	var overlay := _create_overlay()
	overlay.toggle()
	overlay.toggle()
	assert_bool(overlay.is_overlay_visible()).is_false()
	assert_bool(overlay.visible).is_false()


func test_classify_flow_toward_base() -> void:
	var overlay := _create_overlay()
	overlay._player_base_pos = Vector2i(0, 0)
	# Flow going toward (0,0) from (5,5) — flow direction (-1,-1)
	var result: String = overlay.classify_flow(Vector2i(-1, -1), Vector2i(5, 5))
	assert_str(result).is_equal("toward")


func test_classify_flow_away_from_base() -> void:
	var overlay := _create_overlay()
	overlay._player_base_pos = Vector2i(0, 0)
	# Flow going away from (0,0) from (5,5) — flow direction (1,1)
	var result: String = overlay.classify_flow(Vector2i(1, 1), Vector2i(5, 5))
	assert_str(result).is_equal("away")


func test_classify_flow_perpendicular() -> void:
	var overlay := _create_overlay()
	overlay._player_base_pos = Vector2i(0, 0)
	# Flow perpendicular to direction toward base — from (5,0) going (0,1)
	var result: String = overlay.classify_flow(Vector2i(0, 1), Vector2i(5, 0))
	assert_str(result).is_equal("perpendicular")


func test_classify_flow_zero_is_perpendicular() -> void:
	var overlay := _create_overlay()
	overlay._player_base_pos = Vector2i(0, 0)
	var result: String = overlay.classify_flow(Vector2i(0, 0), Vector2i(5, 5))
	assert_str(result).is_equal("perpendicular")


func test_draw_no_crash_without_map() -> void:
	var overlay := _create_overlay()
	overlay.toggle()
	overlay.queue_redraw()
	assert_bool(is_instance_valid(overlay)).is_true()


func test_draw_no_crash_with_mock_map() -> void:
	var overlay := _create_overlay()
	var mock_map := _MockMap.new()
	mock_map._river_tiles = [Vector2i(3, 3), Vector2i(3, 4)]
	mock_map._flow_dirs = {Vector2i(3, 3): Vector2i(0, 1), Vector2i(3, 4): Vector2i.ZERO}
	add_child(mock_map)
	auto_free(mock_map)
	overlay.setup(mock_map, Vector2i(0, 0))
	overlay.toggle()
	overlay.queue_redraw()
	assert_bool(is_instance_valid(overlay)).is_true()


func test_setup_stores_references() -> void:
	var overlay := _create_overlay()
	var mock_map := _MockMap.new()
	add_child(mock_map)
	auto_free(mock_map)
	overlay.setup(mock_map, Vector2i(5, 5))
	assert_bool(overlay._map_node == mock_map).is_true()
	assert_bool(overlay._player_base_pos == Vector2i(5, 5)).is_true()


class _MockMap:
	extends Node
	var _river_tiles: Array = []
	var _flow_dirs: Dictionary = {}

	func get_river_tiles() -> Array:
		return _river_tiles

	func get_flow_direction(pos: Vector2i) -> Vector2i:
		return _flow_dirs.get(pos, Vector2i.ZERO)
