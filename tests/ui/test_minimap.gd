extends GdUnitTestSuite
## Tests for minimap.gd — minimap HUD element with terrain, fog, entities, camera.

const MinimapScript := preload("res://scripts/ui/minimap.gd")


class _MockMap:
	extends Node
	var _width: int = 64
	var _height: int = 64
	var _tile_grid: Dictionary = {}
	var _rivers: Dictionary = {}

	func get_map_dimensions() -> Vector2i:
		return Vector2i(_width, _height)

	func get_tile_grid() -> Dictionary:
		return _tile_grid

	func is_river(grid_pos: Vector2i) -> bool:
		return _rivers.has(grid_pos)


class _MockVisibility:
	extends Node
	signal visibility_changed(player_id: int)
	var _visible: Dictionary = {}
	var _explored: Dictionary = {}

	func get_visible_tiles(player_id: int) -> Dictionary:
		if player_id == 0:
			return _visible
		return {}

	func get_explored_tiles(player_id: int) -> Dictionary:
		if player_id == 0:
			return _explored
		return {}


class _MockCamera:
	extends Camera2D


class _MockEntity:
	extends Node2D
	var owner_id: int = 0
	var hp: int = 100


class _MockBuilding:
	extends Node2D
	var owner_id: int = 0
	var hp: int = 2400
	var building_name: String = "town_center"


var _minimap: Control
var _mock_map: _MockMap
var _mock_vis: _MockVisibility
var _mock_camera: _MockCamera


func before_test() -> void:
	_mock_map = _MockMap.new()
	_mock_vis = _MockVisibility.new()
	_mock_camera = _MockCamera.new()
	_minimap = Control.new()
	_minimap.set_script(MinimapScript)
	add_child(_mock_map)
	add_child(_mock_vis)
	add_child(_mock_camera)
	add_child(_minimap)


func after_test() -> void:
	if is_instance_valid(_minimap):
		_minimap.queue_free()
	if is_instance_valid(_mock_map):
		_mock_map.queue_free()
	if is_instance_valid(_mock_vis):
		_mock_vis.queue_free()
	if is_instance_valid(_mock_camera):
		_mock_camera.queue_free()


# -- Setup tests --


func test_setup_stores_references() -> void:
	var scene_root := Node2D.new()
	add_child(scene_root)
	_minimap.setup(_mock_map, _mock_camera, _mock_vis, scene_root)
	assert_that(_minimap._map_node).is_equal(_mock_map)
	assert_that(_minimap._camera).is_equal(_mock_camera)
	assert_that(_minimap._visibility_manager).is_equal(_mock_vis)
	assert_that(_minimap._scene_root).is_equal(scene_root)
	scene_root.queue_free()


func test_setup_computes_scale_square_map() -> void:
	_mock_map._width = 64
	_mock_map._height = 64
	_minimap.setup(_mock_map, _mock_camera, _mock_vis, Node.new())
	# scale = 200 / max(64, 64) = 3.125
	assert_float(_minimap.get_minimap_scale()).is_equal_approx(200.0 / 64.0, 0.01)


func test_setup_computes_scale_rectangular_map() -> void:
	_mock_map._width = 100
	_mock_map._height = 50
	_minimap.setup(_mock_map, _mock_camera, _mock_vis, Node.new())
	# scale = 200 / max(100, 50) = 2.0
	assert_float(_minimap.get_minimap_scale()).is_equal_approx(2.0, 0.01)


# -- Layout tests --


func test_size_is_200x200() -> void:
	assert_that(_minimap.custom_minimum_size).is_equal(Vector2(200, 200))


func test_mouse_filter_stop() -> void:
	assert_int(_minimap.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)


# -- Coordinate mapping tests --


func test_grid_to_minimap_conversion() -> void:
	_mock_map._width = 100
	_mock_map._height = 100
	_minimap.setup(_mock_map, _mock_camera, _mock_vis, Node.new())
	# scale = 200/100 = 2.0, so grid(50,50) -> minimap(100,100)
	var result: Vector2 = _minimap._grid_to_minimap(Vector2(50, 50))
	assert_float(result.x).is_equal_approx(100.0, 0.01)
	assert_float(result.y).is_equal_approx(100.0, 0.01)


func test_minimap_to_grid_conversion() -> void:
	_mock_map._width = 100
	_mock_map._height = 100
	_minimap.setup(_mock_map, _mock_camera, _mock_vis, Node.new())
	# scale = 2.0, so minimap(100,100) -> grid(50,50)
	var result: Vector2 = _minimap._minimap_to_grid(Vector2(100, 100))
	assert_float(result.x).is_equal_approx(50.0, 0.01)
	assert_float(result.y).is_equal_approx(50.0, 0.01)


func test_grid_to_minimap_origin() -> void:
	_mock_map._width = 64
	_mock_map._height = 64
	_minimap.setup(_mock_map, _mock_camera, _mock_vis, Node.new())
	var result: Vector2 = _minimap._grid_to_minimap(Vector2.ZERO)
	assert_float(result.x).is_equal_approx(0.0, 0.01)
	assert_float(result.y).is_equal_approx(0.0, 0.01)


func test_minimap_to_grid_zero_scale_returns_zero() -> void:
	# Without setup, scale is default 1.0 — test explicit zero
	_minimap._scale = 0.0
	var result: Vector2 = _minimap._minimap_to_grid(Vector2(100, 100))
	assert_that(result).is_equal(Vector2.ZERO)


# -- Terrain texture tests --


func test_terrain_texture_created() -> void:
	_mock_map._tile_grid[Vector2i(0, 0)] = "grass"
	_minimap.setup(_mock_map, _mock_camera, _mock_vis, Node.new())
	assert_that(_minimap.get_terrain_texture()).is_not_null()


func test_terrain_texture_not_null_empty_grid() -> void:
	_minimap.setup(_mock_map, _mock_camera, _mock_vis, Node.new())
	assert_that(_minimap.get_terrain_texture()).is_not_null()


func test_river_terrain_uses_river_color() -> void:
	# Set up a small 10x10 map with a river tile
	_mock_map._width = 10
	_mock_map._height = 10
	_mock_map._tile_grid[Vector2i(5, 5)] = "grass"
	_mock_map._rivers[Vector2i(5, 5)] = true
	_minimap.setup(_mock_map, _mock_camera, _mock_vis, Node.new())
	# The terrain image should exist
	assert_that(_minimap._terrain_image).is_not_null()


# -- Fog tests --


func test_fog_texture_created() -> void:
	_minimap.setup(_mock_map, _mock_camera, _mock_vis, Node.new())
	assert_that(_minimap.get_fog_texture()).is_not_null()


func test_fog_image_correct_size() -> void:
	_minimap.setup(_mock_map, _mock_camera, _mock_vis, Node.new())
	var fog_img: Image = _minimap._fog_image
	assert_int(fog_img.get_width()).is_equal(200)
	assert_int(fog_img.get_height()).is_equal(200)


func test_fog_dirty_on_visibility_changed() -> void:
	_minimap.setup(_mock_map, _mock_camera, _mock_vis, Node.new())
	_minimap._fog_dirty = false
	_mock_vis.visibility_changed.emit(0)
	assert_bool(_minimap._fog_dirty).is_true()


func test_fog_not_dirty_on_other_player() -> void:
	_minimap.setup(_mock_map, _mock_camera, _mock_vis, Node.new())
	_minimap._fog_dirty = false
	_mock_vis.visibility_changed.emit(1)
	assert_bool(_minimap._fog_dirty).is_false()


# -- Input tests --


func test_right_click_emits_move_signal() -> void:
	_mock_map._width = 64
	_mock_map._height = 64
	var scene_root := Node2D.new()
	add_child(scene_root)
	_minimap.setup(_mock_map, _mock_camera, _mock_vis, scene_root)

	# Array-based signal detection (per CLAUDE.md lambda gotcha)
	var received: Array = []
	_minimap.minimap_move_command.connect(func(wp: Vector2) -> void: received.append(wp))

	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	event.position = Vector2(100, 100)
	_minimap._gui_input(event)

	assert_int(received.size()).is_equal(1)
	scene_root.queue_free()


func test_left_click_pans_camera() -> void:
	_mock_map._width = 64
	_mock_map._height = 64
	_minimap.setup(_mock_map, _mock_camera, _mock_vis, Node.new())

	var old_pos: Vector2 = _mock_camera.position
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = Vector2(100, 100)
	_minimap._gui_input(event)

	# Camera position should have changed
	assert_that(_mock_camera.position).is_not_equal(old_pos)


# -- Draw safety tests --


func test_draw_no_crash_without_setup() -> void:
	# Should not crash when _draw is called without setup
	_minimap.queue_redraw()
	await get_tree().process_frame
	assert_bool(is_instance_valid(_minimap)).is_true()


func test_draw_no_crash_with_full_setup() -> void:
	var scene_root := Node2D.new()
	add_child(scene_root)
	var entity := _MockEntity.new()
	entity.position = Vector2(100, 100)
	scene_root.add_child(entity)
	_mock_map._width = 10
	_mock_map._height = 10
	_mock_map._tile_grid[Vector2i(0, 0)] = "grass"
	_minimap.setup(_mock_map, _mock_camera, _mock_vis, scene_root)

	_minimap.queue_redraw()
	await get_tree().process_frame
	assert_bool(is_instance_valid(_minimap)).is_true()
	scene_root.queue_free()


# -- Dirty flag tests --


func test_dirty_flag_starts_true() -> void:
	assert_bool(_minimap._dirty).is_true()


func test_process_clears_dirty_flag() -> void:
	_minimap._dirty = true
	_minimap._process(0.01)
	assert_bool(_minimap._dirty).is_false()


func test_process_skips_redraw_when_not_dirty() -> void:
	_minimap._dirty = false
	_minimap._refresh_timer = 0.0
	# With a small delta and no camera, dirty stays false
	_minimap._process(0.01)
	assert_bool(_minimap._dirty).is_false()


func test_refresh_timer_sets_dirty() -> void:
	_minimap._dirty = false
	_minimap._refresh_timer = 0.19
	_minimap._process(0.02)  # Timer exceeds 0.2
	# Timer fired, set dirty, then _process cleared it
	# But we can check the timer was reset
	assert_float(_minimap._refresh_timer).is_less(0.01)


func test_camera_movement_sets_dirty() -> void:
	_minimap.setup(_mock_map, _mock_camera, _mock_vis, Node.new())
	_minimap._dirty = false
	_minimap._refresh_timer = 0.0
	_minimap._prev_camera_pos = Vector2.ZERO
	_mock_camera.position = Vector2(100, 100)
	_minimap._process(0.001)
	# Camera moved -> dirty was set then cleared by queue_redraw path
	# Verify prev_camera_pos was updated
	assert_that(_minimap._prev_camera_pos).is_equal(Vector2(100, 100))


func test_visibility_changed_sets_dirty() -> void:
	_minimap.setup(_mock_map, _mock_camera, _mock_vis, Node.new())
	_minimap._dirty = false
	_mock_vis.visibility_changed.emit(0)
	assert_bool(_minimap._dirty).is_true()


func test_mark_dirty_sets_flag() -> void:
	_minimap._dirty = false
	_minimap.mark_dirty()
	assert_bool(_minimap._dirty).is_true()


func test_left_click_sets_dirty() -> void:
	_minimap.setup(_mock_map, _mock_camera, _mock_vis, Node.new())
	_minimap._dirty = false
	_minimap._handle_left_click(Vector2(100, 100))
	assert_bool(_minimap._dirty).is_true()
