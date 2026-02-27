extends GdUnitTestSuite
## Tests for singularity_cinematic_vfx.gd — cinematic sequence for AGI Core completion.

const VFXScript := preload("res://scripts/prototype/singularity_cinematic_vfx.gd")


func _create_vfx(
	scene_root: Node2D = null,
	camera: Camera2D = null,
) -> Node:
	if scene_root == null:
		scene_root = Node2D.new()
		add_child(scene_root)
		auto_free(scene_root)
	var node := Node.new()
	node.set_script(VFXScript)
	add_child(node)
	auto_free(node)
	node.setup(scene_root, camera)
	return node


# -- Config tests --


func test_config_loads_defaults_when_json_missing() -> void:
	## VFX should work with built-in defaults even if config file is absent.
	var vfx := _create_vfx()
	# Title text should be the hardcoded default
	assert_str(vfx._title_text).is_equal("The Singularity Has Been Achieved")
	assert_float(vfx._total_duration).is_equal_approx(6.0, 0.1)


func test_config_loads_from_json() -> void:
	## VFX should load values from singularity_cinematic.json.
	var vfx := _create_vfx()
	# These should match the JSON values (or defaults if JSON absent)
	assert_float(vfx._flash_duration).is_greater(0.0)
	assert_float(vfx._wave_max_radius).is_greater(0.0)


# -- Cinematic signal tests --


func test_play_cinematic_emits_cinematic_complete() -> void:
	## play_cinematic() must eventually emit cinematic_complete.
	var root := Node2D.new()
	add_child(root)
	auto_free(root)
	var vfx := _create_vfx(root)
	var signals_received: Array = []
	vfx.cinematic_complete.connect(func() -> void: signals_received.append(true))
	vfx.play_cinematic()
	# Wait long enough for the cinematic to complete
	await get_tree().create_timer(7.0).timeout
	assert_int(signals_received.size()).is_equal(1)


# -- Flash overlay tests --


func test_flash_overlay_uses_canvas_layer_100() -> void:
	## Screen flash should create a CanvasLayer at layer 100.
	var root := Node2D.new()
	add_child(root)
	auto_free(root)
	var vfx := _create_vfx(root)
	var before_count: int = root.get_child_count()
	vfx._play_screen_flash()
	var after_count: int = root.get_child_count()
	assert_int(after_count).is_greater(before_count)
	# Find the CanvasLayer
	var found_layer: bool = false
	for i in range(before_count, after_count):
		var child := root.get_child(i)
		if child is CanvasLayer and child.layer == 100:
			found_layer = true
			break
	assert_bool(found_layer).is_true()


# -- Energy wave tests --


func test_energy_wave_added_to_scene_root() -> void:
	## Energy wave node should be added as child of scene root.
	var root := Node2D.new()
	add_child(root)
	auto_free(root)
	var vfx := _create_vfx(root)
	var before_count: int = root.get_child_count()
	vfx._spawn_energy_wave()
	assert_int(root.get_child_count()).is_greater(before_count)


# -- Text overlay tests --


func test_title_text_contains_config_text() -> void:
	## Title label should contain the configured title text.
	var root := Node2D.new()
	add_child(root)
	auto_free(root)
	var vfx := _create_vfx(root)
	vfx._show_title_text()
	# Find the CinematicTitle label in the new CanvasLayer
	var found_title: bool = false
	for child in root.get_children():
		if child is CanvasLayer:
			var title := child.get_node_or_null("CinematicTitle")
			if title != null and title is Label:
				assert_str(title.text).is_equal(vfx._title_text)
				found_title = true
				break
	assert_bool(found_title).is_true()


# -- Cleanup tests --


func test_vfx_nodes_cleaned_up_after_cinematic() -> void:
	## All VFX nodes should be freed after cinematic completes.
	var root := Node2D.new()
	add_child(root)
	auto_free(root)
	var vfx := _create_vfx(root)
	vfx.play_cinematic()
	await get_tree().create_timer(7.0).timeout
	# All tracked VFX nodes should be cleaned up
	assert_int(vfx._vfx_nodes.size()).is_equal(0)


# -- Save/load tests --


func test_save_state_returns_empty_dict() -> void:
	var vfx := _create_vfx()
	var state: Dictionary = vfx.save_state()
	assert_bool(state.is_empty()).is_true()


# -- Setup tests --


func test_setup_stores_camera_and_scene_root() -> void:
	var root := Node2D.new()
	add_child(root)
	auto_free(root)
	var camera := Camera2D.new()
	add_child(camera)
	auto_free(camera)
	var vfx := _create_vfx(root, camera)
	assert_that(vfx._scene_root).is_same(root)
	assert_that(vfx._camera).is_same(camera)
