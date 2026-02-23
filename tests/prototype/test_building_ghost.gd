extends GdUnitTestSuite
## Tests for building_ghost.gd — visual ghost preview node.

const GhostScript := preload("res://scripts/prototype/building_ghost.gd")


func _create_ghost() -> Node2D:
	var ghost := Node2D.new()
	ghost.set_script(GhostScript)
	return auto_free(ghost)


func test_setup_stores_footprint() -> void:
	var ghost := _create_ghost()
	ghost.setup(Vector2i(3, 3))
	assert_object(ghost._footprint).is_equal(Vector2i(3, 3))


func test_setup_stores_footprint_2x2() -> void:
	var ghost := _create_ghost()
	ghost.setup(Vector2i(2, 2))
	assert_object(ghost._footprint).is_equal(Vector2i(2, 2))


func test_default_is_valid() -> void:
	var ghost := _create_ghost()
	assert_bool(ghost._is_valid).is_true()


func test_set_valid_false() -> void:
	var ghost := _create_ghost()
	ghost.set_valid(false)
	assert_bool(ghost._is_valid).is_false()


func test_set_valid_true() -> void:
	var ghost := _create_ghost()
	ghost.set_valid(false)
	ghost.set_valid(true)
	assert_bool(ghost._is_valid).is_true()
