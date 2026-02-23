extends GdUnitTestSuite
## Tests for prototype_input.gd — selection, control groups, context commands, save/load.

const InputScript := preload("res://scripts/prototype/prototype_input.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const DetectorScript := preload("res://scripts/prototype/target_detector.gd")
const ResourceScript := preload("res://scripts/prototype/prototype_resource_node.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")

var _context_table: Dictionary = {
	"default":
	{
		"enemy_unit": "attack",
		"enemy_building": "attack",
		"own_building": "garrison",
		"resource_node": "move",
	},
	"villager":
	{
		"enemy_unit": "attack",
		"enemy_building": "attack",
		"own_building": "garrison",
		"resource_node": "gather",
	},
}


func _create_handler() -> Node:
	var handler := Node.new()
	handler.set_script(InputScript)
	# Prevent _ready from preloading selection_rect (no scene tree needed)
	handler._max_selection_size = 40
	handler._double_tap_threshold_ms = 400
	return auto_free(handler)


func _create_unit(pos: Vector2, unit_owner: int = 0) -> Node2D:
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.position = pos
	unit.owner_id = unit_owner
	return auto_free(unit)


func _register_units(handler: Node, units: Array) -> void:
	for unit in units:
		handler.register_unit(unit)


# -- Box select geometry --


func test_box_select_geometry() -> void:
	var handler := _create_handler()
	var u1 := _create_unit(Vector2(50, 50))
	var u2 := _create_unit(Vector2(60, 60))
	var u3 := _create_unit(Vector2(200, 200))
	var u4 := _create_unit(Vector2(300, 300))
	_register_units(handler, [u1, u2, u3, u4])
	# Simulate box select covering u1 and u2
	handler._box_start = Vector2(40, 40)
	handler._box_end = Vector2(70, 70)
	handler._do_box_select()
	assert_bool(u1.selected).is_true()
	assert_bool(u2.selected).is_true()
	assert_bool(u3.selected).is_false()
	assert_bool(u4.selected).is_false()
	assert_int(handler.get_selected_count()).is_equal(2)


func test_box_select_small_rect_deselects() -> void:
	var handler := _create_handler()
	var u1 := _create_unit(Vector2(50, 50))
	_register_units(handler, [u1])
	u1.select()
	assert_bool(u1.selected).is_true()
	# Tiny drag — should deselect
	handler._box_start = Vector2(100, 100)
	handler._box_end = Vector2(102, 102)
	handler._do_box_select()
	assert_bool(u1.selected).is_false()


# -- Shift+click toggle --


func test_shift_click_toggle_on() -> void:
	var handler := _create_handler()
	var u1 := _create_unit(Vector2(50, 50))
	_register_units(handler, [u1])
	assert_bool(u1.selected).is_false()
	u1.select()
	assert_bool(u1.selected).is_true()


func test_shift_click_toggle_off() -> void:
	var handler := _create_handler()
	var u1 := _create_unit(Vector2(50, 50))
	_register_units(handler, [u1])
	u1.select()
	assert_bool(u1.selected).is_true()
	u1.deselect()
	assert_bool(u1.selected).is_false()


# -- Control groups --


func test_control_group_assign_recall() -> void:
	var handler := _create_handler()
	var u1 := _create_unit(Vector2(10, 10))
	var u2 := _create_unit(Vector2(20, 20))
	var u3 := _create_unit(Vector2(30, 30))
	_register_units(handler, [u1, u2, u3])
	# Select u1 and u2
	u1.select()
	u2.select()
	# Assign to group 1
	handler._assign_control_group(1)
	# Deselect all
	handler._deselect_all()
	assert_int(handler.get_selected_count()).is_equal(0)
	# Recall group 1
	handler._recall_control_group(1)
	assert_bool(u1.selected).is_true()
	assert_bool(u2.selected).is_true()
	assert_bool(u3.selected).is_false()
	assert_int(handler.get_selected_count()).is_equal(2)


func test_control_group_overwrite() -> void:
	var handler := _create_handler()
	var u1 := _create_unit(Vector2(10, 10))
	var u2 := _create_unit(Vector2(20, 20))
	_register_units(handler, [u1, u2])
	# Assign u1 to group 1
	u1.select()
	handler._assign_control_group(1)
	handler._deselect_all()
	# Reassign group 1 to u2
	u2.select()
	handler._assign_control_group(1)
	handler._deselect_all()
	# Recall — should only have u2
	handler._recall_control_group(1)
	assert_bool(u1.selected).is_false()
	assert_bool(u2.selected).is_true()


func test_control_group_empty_recall() -> void:
	var handler := _create_handler()
	var u1 := _create_unit(Vector2(10, 10))
	_register_units(handler, [u1])
	u1.select()
	# Recall an unassigned group — no crash, deselects current
	handler._recall_control_group(5)
	assert_int(handler.get_selected_count()).is_equal(0)


func test_control_group_stale_unit() -> void:
	var handler := _create_handler()
	var u1 := _create_unit(Vector2(10, 10))
	var u2 := _create_unit(Vector2(20, 20))
	_register_units(handler, [u1, u2])
	u1.select()
	u2.select()
	handler._assign_control_group(2)
	handler._deselect_all()
	# Free u1 to simulate unit death
	u1.queue_free()
	await get_tree().process_frame
	# Recall group 2 — only u2 should remain
	handler._recall_control_group(2)
	assert_bool(u2.selected).is_true()
	assert_int(handler.get_selected_count()).is_equal(1)


# -- Max selection size --


func test_max_selection_size() -> void:
	var handler := _create_handler()
	handler._max_selection_size = 3
	var units: Array = []
	for i in 5:
		var u := _create_unit(Vector2(10 + i * 10, 10 + i * 10))
		units.append(u)
	_register_units(handler, units)
	# Box select all 5
	handler._box_start = Vector2(0, 0)
	handler._box_end = Vector2(200, 200)
	handler._do_box_select()
	assert_int(handler.get_selected_count()).is_equal(3)


# -- Owner filter --


func test_owner_filter_skips_enemy() -> void:
	var handler := _create_handler()
	var u1 := _create_unit(Vector2(50, 50), 0)
	var u2 := _create_unit(Vector2(60, 60), 1)
	var u3 := _create_unit(Vector2(70, 70), 0)
	_register_units(handler, [u1, u2, u3])
	# Box select all
	handler._box_start = Vector2(40, 40)
	handler._box_end = Vector2(80, 80)
	handler._do_box_select()
	assert_bool(u1.selected).is_true()
	assert_bool(u2.selected).is_false()
	assert_bool(u3.selected).is_true()
	assert_int(handler.get_selected_count()).is_equal(2)


# -- Save / Load --


func test_save_load_roundtrip() -> void:
	var handler := _create_handler()
	var u1 := _create_unit(Vector2(10, 10))
	var u2 := _create_unit(Vector2(20, 20))
	var u3 := _create_unit(Vector2(30, 30))
	_register_units(handler, [u1, u2, u3])
	# Select u1, u3 and assign group 1
	u1.select()
	u3.select()
	handler._assign_control_group(1)
	var state: Dictionary = handler.save_state()
	# Clear everything
	handler._deselect_all()
	handler._control_groups.clear()
	assert_int(handler.get_selected_count()).is_equal(0)
	# Restore
	handler.load_state(state)
	assert_bool(u1.selected).is_true()
	assert_bool(u2.selected).is_false()
	assert_bool(u3.selected).is_true()
	# Verify control group restored
	handler._deselect_all()
	handler._recall_control_group(1)
	assert_bool(u1.selected).is_true()
	assert_bool(u3.selected).is_true()


func test_save_state_keys() -> void:
	var handler := _create_handler()
	var u1 := _create_unit(Vector2(10, 10))
	_register_units(handler, [u1])
	u1.select()
	var state: Dictionary = handler.save_state()
	assert_dict(state).contains_keys(["selected_indices", "control_groups", "last_recalled_group"])


# -- Config defaults --


func test_config_defaults() -> void:
	var handler := _create_handler()
	assert_int(handler._max_selection_size).is_equal(40)
	assert_int(handler._double_tap_threshold_ms).is_equal(400)


# -- Selection helpers --


func test_get_selected_count() -> void:
	var handler := _create_handler()
	var u1 := _create_unit(Vector2(10, 10))
	var u2 := _create_unit(Vector2(20, 20))
	var u3 := _create_unit(Vector2(30, 30))
	_register_units(handler, [u1, u2, u3])
	u1.select()
	u3.select()
	assert_int(handler.get_selected_count()).is_equal(2)


func test_deselect_all() -> void:
	var handler := _create_handler()
	var u1 := _create_unit(Vector2(10, 10))
	var u2 := _create_unit(Vector2(20, 20))
	_register_units(handler, [u1, u2])
	u1.select()
	u2.select()
	assert_int(handler.get_selected_count()).is_equal(2)
	handler._deselect_all()
	assert_int(handler.get_selected_count()).is_equal(0)
	assert_bool(u1.selected).is_false()
	assert_bool(u2.selected).is_false()


# -- Context commands --


func _create_detector() -> Node:
	var detector := Node.new()
	detector.set_script(DetectorScript)
	return auto_free(detector)


func _setup_context_handler(command_table: Dictionary) -> Node:
	var handler := _create_handler()
	var detector := _create_detector()
	handler._target_detector = detector
	handler._command_config = {"command_table": command_table}
	return handler


func test_context_command_resolve_attack() -> void:
	var handler := _setup_context_handler(_context_table)
	var unit := _create_unit(Vector2(50, 50))
	_register_units(handler, [unit])
	unit.select()
	var enemy := _create_unit(Vector2(100, 100), 1)
	handler._target_detector.register_entity(enemy)
	var cmd: String = handler._resolve_command_at(Vector2(105, 100))
	assert_str(cmd).is_equal("attack")


func test_context_command_resolve_move() -> void:
	var handler := _setup_context_handler(_context_table)
	var unit := _create_unit(Vector2(50, 50))
	_register_units(handler, [unit])
	unit.select()
	var cmd: String = handler._resolve_command_at(Vector2(500, 500))
	assert_str(cmd).is_equal("move")


func test_context_command_resolve_gather() -> void:
	var handler := _setup_context_handler(_context_table)
	var unit := _create_unit(Vector2(50, 50))
	unit.unit_type = "villager"
	_register_units(handler, [unit])
	unit.select()
	var resource := Node2D.new()
	resource.set_script(ResourceScript)
	resource.position = Vector2(200, 200)
	resource.global_position = Vector2(200, 200)
	auto_free(resource)
	handler._target_detector.register_entity(resource)
	var cmd: String = handler._resolve_command_at(Vector2(205, 200))
	assert_str(cmd).is_equal("gather")


func test_context_command_resolve_garrison() -> void:
	var handler := _setup_context_handler(_context_table)
	var unit := _create_unit(Vector2(50, 50))
	_register_units(handler, [unit])
	unit.select()
	var building := Node2D.new()
	building.set_script(BuildingScript)
	building.position = Vector2(300, 300)
	building.global_position = Vector2(300, 300)
	building.owner_id = 0
	auto_free(building)
	handler._target_detector.register_entity(building)
	var cmd: String = handler._resolve_command_at(Vector2(305, 300))
	assert_str(cmd).is_equal("garrison")
