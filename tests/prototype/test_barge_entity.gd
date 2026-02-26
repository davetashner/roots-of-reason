extends GdUnitTestSuite
## Tests for barge_entity.gd — barge movement, damage, selection, visuals, and save/load.

const BargeScript := preload("res://scripts/prototype/barge_entity.gd")

var _signal_count: int = 0


func _reset_counter() -> void:
	_signal_count = 0


func _increment_counter(_barge: Node2D) -> void:
	_signal_count += 1


func _create_barge(path: Array[Vector2i] = []) -> Node2D:
	var barge := Node2D.new()
	barge.set_script(BargeScript)
	barge.owner_id = 0
	barge.hp = 15
	barge.max_hp = 15
	barge.speed = 180.0
	barge.river_path = path
	barge.path_index = 0
	# Disable Godot auto-processing so we control _process manually in tests
	barge.set_process(false)
	add_child(barge)
	auto_free(barge)
	return barge


func test_barge_moves_along_path() -> void:
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var barge := _create_barge(path)
	barge.position = IsoUtils.grid_to_screen(Vector2(0, 0))
	for _i in 100:
		barge._process(0.05)
	# Should have progressed along the path
	assert_int(barge.path_index).is_greater(0)


func test_barge_emits_arrived_at_end() -> void:
	_reset_counter()
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var barge := _create_barge(path)
	barge.position = IsoUtils.grid_to_screen(Vector2(0, 0))
	barge.speed = 10000.0
	barge.arrived.connect(_increment_counter)
	for _i in 20:
		barge._process(0.1)
	assert_int(_signal_count).is_equal(1)


func test_take_damage_reduces_hp() -> void:
	var barge := _create_barge()
	barge.hp = 15
	barge.take_damage(5)
	assert_int(barge.hp).is_equal(10)


func test_barge_destroyed_at_zero_hp() -> void:
	_reset_counter()
	var barge := _create_barge()
	barge.hp = 15
	barge.destroyed.connect(_increment_counter)
	barge.take_damage(15)
	assert_int(barge.hp).is_equal(0)
	assert_int(_signal_count).is_equal(1)


func test_barge_draw_does_not_crash() -> void:
	var barge := _create_barge()
	barge.queue_redraw()
	assert_bool(is_instance_valid(barge)).is_true()


func test_save_load_state() -> void:
	var path: Array[Vector2i] = [Vector2i(3, 4), Vector2i(4, 4)]
	var barge := _create_barge(path)
	barge.owner_id = 1
	barge.hp = 10
	barge.max_hp = 15
	barge.carried_resources = {0: 5, 1: 3}
	barge.total_carried = 8
	barge.path_index = 1
	barge.position = Vector2(100.0, 50.0)
	barge.selected = true
	var state: Dictionary = barge.save_state()
	var barge2 := _create_barge()
	barge2.load_state(state)
	assert_int(barge2.owner_id).is_equal(1)
	assert_int(barge2.hp).is_equal(10)
	assert_int(barge2.max_hp).is_equal(15)
	assert_int(barge2.total_carried).is_equal(8)
	assert_int(barge2.path_index).is_equal(1)
	assert_int(barge2.river_path.size()).is_equal(2)
	assert_float(barge2.position.x).is_equal_approx(100.0, 0.01)
	assert_float(barge2.position.y).is_equal_approx(50.0, 0.01)
	assert_int(barge2.carried_resources.get(0, 0)).is_equal(5)
	assert_int(barge2.carried_resources.get(1, 0)).is_equal(3)
	assert_bool(barge2.selected).is_true()


# --- Selection tests ---


func test_select_sets_selected_true() -> void:
	var barge := _create_barge()
	assert_bool(barge.selected).is_false()
	barge.select()
	assert_bool(barge.selected).is_true()


func test_deselect_sets_selected_false() -> void:
	var barge := _create_barge()
	barge.select()
	barge.deselect()
	assert_bool(barge.selected).is_false()


func test_is_point_inside_near_center() -> void:
	var barge := _create_barge()
	barge.position = Vector2(100, 100)
	# Point within selection ring radius (default 18)
	assert_bool(barge.is_point_inside(Vector2(110, 100))).is_true()


func test_is_point_inside_far_away() -> void:
	var barge := _create_barge()
	barge.position = Vector2(100, 100)
	# Point far outside selection ring
	assert_bool(barge.is_point_inside(Vector2(200, 200))).is_false()


# --- Damage flash tests ---


func test_damage_flash_timer_set_on_damage() -> void:
	var barge := _create_barge()
	barge.take_damage(3)
	assert_float(barge._damage_flash_timer).is_greater(0.0)


func test_damage_flash_timer_decreases() -> void:
	var barge := _create_barge()
	barge.take_damage(3)
	var initial_timer: float = barge._damage_flash_timer
	barge._process(0.1)
	assert_float(barge._damage_flash_timer).is_less(initial_timer)


# --- Wake trail tests ---


func test_wake_trail_grows_during_movement() -> void:
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	var barge := _create_barge(path)
	barge.position = IsoUtils.grid_to_screen(Vector2(0, 0))
	for _i in 30:
		barge._process(0.05)
	assert_int(barge._wake_positions.size()).is_greater(0)


func test_wake_trail_capped_at_max_length() -> void:
	var path: Array[Vector2i] = []
	for i in 20:
		path.append(Vector2i(i, 0))
	var barge := _create_barge(path)
	barge.position = IsoUtils.grid_to_screen(Vector2(0, 0))
	barge.speed = 5000.0
	for _i in 200:
		barge._process(0.05)
	assert_int(barge._wake_positions.size()).is_less_equal(barge._wake_trail_length)


# --- Draw with selection ring ---


func test_draw_with_selection_ring_no_crash() -> void:
	var barge := _create_barge()
	barge.selected = true
	barge.carried_resources = {0: 5, 1: 3}
	barge.queue_redraw()
	assert_bool(is_instance_valid(barge)).is_true()


# --- Entity category ---


func test_entity_category_default_own_barge() -> void:
	var barge := _create_barge()
	assert_str(barge.entity_category).is_equal("own_barge")


func test_entity_category_enemy_on_load() -> void:
	var barge := _create_barge()
	barge.load_state({"owner_id": 1})
	assert_str(barge.entity_category).is_equal("enemy_barge")
