extends GdUnitTestSuite
## Tests for pandemic_vfx.gd — save/load round-trip and visual feedback.

const VFXScript := preload("res://scripts/prototype/pandemic_vfx.gd")


func _create_vfx(
	scene_root: Node2D = null,
	camera: Camera2D = null,
	notif: Control = null,
) -> Node:
	if scene_root == null:
		scene_root = Node2D.new()
		add_child(scene_root)
		auto_free(scene_root)
	var node := Node.new()
	node.set_script(VFXScript)
	add_child(node)
	auto_free(node)
	node.setup(scene_root, camera, notif)
	return node


# -- Save/load tests --


func test_save_state_returns_dictionary() -> void:
	var vfx := _create_vfx()
	var state: Dictionary = vfx.save_state()
	assert_that(state).is_not_null()
	assert_bool(state is Dictionary).is_true()


func test_save_state_returns_empty_dict() -> void:
	var vfx := _create_vfx()
	var state: Dictionary = vfx.save_state()
	assert_bool(state.is_empty()).is_true()


func test_load_state_round_trip_preserves_state() -> void:
	var vfx := _create_vfx()
	var saved: Dictionary = vfx.save_state()
	var vfx2 := _create_vfx()
	vfx2.load_state(saved)
	var restored: Dictionary = vfx2.save_state()
	assert_dict(restored).is_equal(saved)


func test_load_state_with_empty_dict() -> void:
	var vfx := _create_vfx()
	vfx.load_state({})
	var state: Dictionary = vfx.save_state()
	assert_bool(state.is_empty()).is_true()


func test_load_state_with_unknown_keys() -> void:
	## load_state should not crash when given unexpected keys.
	var vfx := _create_vfx()
	vfx.load_state({"unknown_key": 42, "another": "value"})
	var state: Dictionary = vfx.save_state()
	assert_bool(state.is_empty()).is_true()


# -- Setup tests --


func test_setup_stores_scene_root() -> void:
	var root := Node2D.new()
	add_child(root)
	auto_free(root)
	var vfx := _create_vfx(root)
	assert_that(vfx._scene_root).is_same(root)


func test_setup_stores_camera() -> void:
	var root := Node2D.new()
	add_child(root)
	auto_free(root)
	var camera := Camera2D.new()
	add_child(camera)
	auto_free(camera)
	var vfx := _create_vfx(root, camera)
	assert_that(vfx._camera).is_same(camera)
