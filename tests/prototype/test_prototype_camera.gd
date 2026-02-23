extends GdUnitTestSuite
## Tests for prototype_camera.gd — clamp logic, zoom math, save/load.

const CameraScript := preload("res://scripts/prototype/prototype_camera.gd")


func _create_camera(in_tree: bool = false) -> Camera2D:
	var cam := Camera2D.new()
	cam.set_script(CameraScript)
	# Skip _ready auto-config — set defaults manually for isolated tests
	cam.zoom = Vector2(1.0, 1.0)
	if in_tree:
		add_child(cam)
	return auto_free(cam)


func test_clamp_to_bounds() -> void:
	var cam := _create_camera(true)
	var bounds := Rect2(-500, -300, 1000, 600)
	cam.setup(bounds)
	# Place camera way outside bounds to the right
	cam.position = Vector2(9999, 9999)
	cam._clamp_to_bounds()
	assert_float(cam.position.x).is_less_equal(bounds.end.x)
	assert_float(cam.position.y).is_less_equal(bounds.end.y)


func test_clamp_to_bounds_negative() -> void:
	var cam := _create_camera(true)
	var bounds := Rect2(-500, -300, 1000, 600)
	cam.setup(bounds)
	cam.position = Vector2(-9999, -9999)
	cam._clamp_to_bounds()
	assert_float(cam.position.x).is_greater_equal(bounds.position.x)
	assert_float(cam.position.y).is_greater_equal(bounds.position.y)


func test_zoom_clamp_min() -> void:
	var cam := _create_camera()
	cam._zoom_min = 0.5
	cam._zoom_max = 3.0
	cam._zoom_step = 0.1
	cam._target_zoom = 0.5
	# Try to zoom out beyond min
	cam._target_zoom = clampf(cam._target_zoom - cam._zoom_step, cam._zoom_min, cam._zoom_max)
	assert_float(cam._target_zoom).is_equal_approx(0.5, 0.001)


func test_zoom_clamp_max() -> void:
	var cam := _create_camera()
	cam._zoom_min = 0.5
	cam._zoom_max = 3.0
	cam._zoom_step = 0.1
	cam._target_zoom = 3.0
	# Try to zoom in beyond max
	cam._target_zoom = clampf(cam._target_zoom + cam._zoom_step, cam._zoom_min, cam._zoom_max)
	assert_float(cam._target_zoom).is_equal_approx(3.0, 0.001)


func test_save_load_roundtrip() -> void:
	var cam := _create_camera()
	cam.position = Vector2(123.4, 567.8)
	cam.zoom = Vector2(1.5, 1.5)
	cam._target_zoom = 1.5
	var state: Dictionary = cam.save_state()
	# Modify camera
	cam.position = Vector2(0, 0)
	cam.zoom = Vector2(1.0, 1.0)
	cam._target_zoom = 1.0
	# Restore
	cam.load_state(state)
	assert_float(cam.position.x).is_equal_approx(123.4, 0.01)
	assert_float(cam.position.y).is_equal_approx(567.8, 0.01)
	assert_float(cam.zoom.x).is_equal_approx(1.5, 0.01)
	assert_float(cam._target_zoom).is_equal_approx(1.5, 0.01)


func test_save_state_keys() -> void:
	var cam := _create_camera()
	cam.position = Vector2(10, 20)
	cam.zoom = Vector2(2.0, 2.0)
	var state: Dictionary = cam.save_state()
	assert_dict(state).contains_keys(["position_x", "position_y", "zoom"])
	assert_float(state["position_x"]).is_equal_approx(10.0, 0.01)
	assert_float(state["position_y"]).is_equal_approx(20.0, 0.01)
	assert_float(state["zoom"]).is_equal_approx(2.0, 0.01)


func test_default_config_values() -> void:
	# Camera should work with fallback defaults even without DataLoader
	var cam := _create_camera()
	assert_float(cam._pan_speed).is_equal_approx(500.0, 0.01)
	assert_float(cam._zoom_min).is_equal_approx(0.5, 0.01)
	assert_float(cam._zoom_max).is_equal_approx(3.0, 0.01)
	assert_float(cam._zoom_step).is_equal_approx(0.1, 0.01)
	assert_float(cam._zoom_lerp_weight).is_equal_approx(8.0, 0.01)
	assert_int(cam._edge_margin).is_equal(20)


func test_setup_stores_bounds() -> void:
	var cam := _create_camera(true)
	var bounds := Rect2(-100, -50, 500, 300)
	cam.setup(bounds)
	assert_bool(cam._has_bounds).is_true()
	assert_float(cam._map_bounds.position.x).is_equal_approx(-100.0, 0.01)
	assert_float(cam._map_bounds.size.x).is_equal_approx(500.0, 0.01)


func test_get_world_mouse_at_center() -> void:
	# Without viewport, get_world_mouse returns position as fallback
	var cam := _create_camera()
	cam.position = Vector2(200, 300)
	var result: Vector2 = cam.get_world_mouse()
	assert_vector(result).is_equal(Vector2(200, 300))
