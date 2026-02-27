extends GdUnitTestSuite
## Tests for SpatialIndex — grid-based spatial lookup.

const SpatialIndexScript := preload("res://scripts/prototype/spatial_index.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")


func _create_index(cell_size: float = 128.0) -> RefCounted:
	return SpatialIndexScript.new(cell_size)


func _create_entity(pos: Vector2) -> Node2D:
	var entity := Node2D.new()
	entity.position = pos
	entity.global_position = pos
	return auto_free(entity)


func _create_unit(pos: Vector2, pid: int = 0) -> Node2D:
	var unit := Node2D.new()
	unit.set_script(UnitScript)
	unit.position = pos
	unit.global_position = pos
	unit.owner_id = pid
	return auto_free(unit)


# -- Constants --


func test_default_cell_size() -> void:
	assert_float(SpatialIndexScript.DEFAULT_CELL_SIZE).is_equal(128.0)


# -- register_entity / unregister_entity --


func test_register_entity_adds_to_entities() -> void:
	var idx := _create_index()
	var e := _create_entity(Vector2(50, 50))
	idx.register_entity(e)
	assert_int(idx._entities.size()).is_equal(1)


func test_register_entity_idempotent() -> void:
	var idx := _create_index()
	var e := _create_entity(Vector2(50, 50))
	idx.register_entity(e)
	idx.register_entity(e)
	assert_int(idx._entities.size()).is_equal(1)


func test_unregister_entity_removes() -> void:
	var idx := _create_index()
	var e := _create_entity(Vector2(50, 50))
	idx.register_entity(e)
	idx.unregister_entity(e)
	assert_int(idx._entities.size()).is_equal(0)
	assert_int(idx._grid.size()).is_equal(0)
	assert_int(idx._entity_cells.size()).is_equal(0)


func test_unregister_unknown_entity_is_noop() -> void:
	var idx := _create_index()
	var e := _create_entity(Vector2(50, 50))
	idx.unregister_entity(e)
	assert_int(idx._entities.size()).is_equal(0)


func test_register_places_in_correct_cell() -> void:
	var idx := _create_index(128.0)
	var e := _create_entity(Vector2(200, 200))
	idx.register_entity(e)
	# 200 / 128 = 1.5625 -> floor = 1
	var expected_cell := Vector2i(1, 1)
	assert_vector(idx._entity_cells[e]).is_equal(expected_cell)


# -- update_position --


func test_update_position_moves_cell() -> void:
	var idx := _create_index(128.0)
	var e := _create_entity(Vector2(50, 50))
	idx.register_entity(e)
	var old_cell: Vector2i = idx._entity_cells[e]
	# Move to a different cell
	e.global_position = Vector2(300, 300)
	idx.update_position(e)
	var new_cell: Vector2i = idx._entity_cells[e]
	assert_bool(old_cell != new_cell).is_true()


func test_update_position_same_cell_noop() -> void:
	var idx := _create_index(128.0)
	var e := _create_entity(Vector2(50, 50))
	idx.register_entity(e)
	var old_cell: Vector2i = idx._entity_cells[e]
	e.global_position = Vector2(60, 60)
	idx.update_position(e)
	assert_vector(idx._entity_cells[e]).is_equal(old_cell)


func test_update_position_unregistered_is_noop() -> void:
	var idx := _create_index()
	var e := _create_entity(Vector2(50, 50))
	idx.update_position(e)
	assert_int(idx._entities.size()).is_equal(0)


# -- clear --


func test_clear_empties_all() -> void:
	var idx := _create_index()
	var e1 := _create_entity(Vector2(50, 50))
	var e2 := _create_entity(Vector2(300, 300))
	idx.register_entity(e1)
	idx.register_entity(e2)
	idx.clear()
	assert_int(idx._entities.size()).is_equal(0)
	assert_int(idx._grid.size()).is_equal(0)
	assert_int(idx._entity_cells.size()).is_equal(0)


# -- tick_positions --


func test_tick_positions_updates_moved_entities() -> void:
	var idx := _create_index(128.0)
	var e := _create_entity(Vector2(50, 50))
	idx.register_entity(e)
	var old_cell: Vector2i = idx._entity_cells[e]
	e.global_position = Vector2(500, 500)
	idx.tick_positions()
	assert_bool(idx._entity_cells[e] != old_cell).is_true()


func test_tick_positions_skips_stationary() -> void:
	var idx := _create_index(128.0)
	var e := _create_entity(Vector2(50, 50))
	idx.register_entity(e)
	var cell_before: Vector2i = idx._entity_cells[e]
	idx.tick_positions()
	assert_vector(idx._entity_cells[e]).is_equal(cell_before)


# -- get_entities_in_radius --


func test_get_entities_in_radius_finds_nearby() -> void:
	var idx := _create_index()
	var e := _create_entity(Vector2(100, 100))
	idx.register_entity(e)
	var results: Array = idx.get_entities_in_radius(Vector2(110, 100), 50.0)
	assert_int(results.size()).is_equal(1)
	assert_object(results[0]).is_same(e)


func test_get_entities_in_radius_excludes_far() -> void:
	var idx := _create_index()
	var e := _create_entity(Vector2(1000, 1000))
	idx.register_entity(e)
	var results: Array = idx.get_entities_in_radius(Vector2(0, 0), 50.0)
	assert_int(results.size()).is_equal(0)


func test_get_entities_in_radius_empty_index() -> void:
	var idx := _create_index()
	var results: Array = idx.get_entities_in_radius(Vector2(0, 0), 100.0)
	assert_int(results.size()).is_equal(0)


func test_get_entities_in_radius_boundary() -> void:
	var idx := _create_index()
	var e := _create_entity(Vector2(50, 0))
	idx.register_entity(e)
	# Exactly at radius boundary — distance is 50, radius is 50
	var results: Array = idx.get_entities_in_radius(Vector2(0, 0), 50.0)
	assert_int(results.size()).is_equal(1)


func test_get_entities_in_radius_just_outside() -> void:
	var idx := _create_index()
	var e := _create_entity(Vector2(51, 0))
	idx.register_entity(e)
	var results: Array = idx.get_entities_in_radius(Vector2(0, 0), 50.0)
	assert_int(results.size()).is_equal(0)


func test_get_entities_in_radius_multiple() -> void:
	var idx := _create_index()
	var e1 := _create_entity(Vector2(10, 10))
	var e2 := _create_entity(Vector2(20, 20))
	var e3 := _create_entity(Vector2(5000, 5000))
	idx.register_entity(e1)
	idx.register_entity(e2)
	idx.register_entity(e3)
	var results: Array = idx.get_entities_in_radius(Vector2(15, 15), 100.0)
	assert_int(results.size()).is_equal(2)


func test_get_entities_in_radius_skips_freed() -> void:
	var idx := _create_index()
	var e1 := _create_entity(Vector2(10, 10))
	var e2 := _create_entity(Vector2(20, 20))
	idx.register_entity(e1)
	idx.register_entity(e2)
	e1.free()
	var results: Array = idx.get_entities_in_radius(Vector2(15, 15), 100.0)
	assert_int(results.size()).is_equal(1)
	assert_object(results[0]).is_same(e2)


# -- get_nearest --


func test_get_nearest_returns_closest() -> void:
	var idx := _create_index()
	var far := _create_entity(Vector2(100, 0))
	var near := _create_entity(Vector2(20, 0))
	idx.register_entity(far)
	idx.register_entity(near)
	var result: Variant = idx.get_nearest(Vector2(0, 0), 200.0)
	assert_object(result).is_same(near)


func test_get_nearest_returns_null_empty() -> void:
	var idx := _create_index()
	var result: Variant = idx.get_nearest(Vector2(0, 0), 100.0)
	assert_object(result).is_null()


func test_get_nearest_returns_null_out_of_range() -> void:
	var idx := _create_index()
	var e := _create_entity(Vector2(500, 500))
	idx.register_entity(e)
	var result: Variant = idx.get_nearest(Vector2(0, 0), 50.0)
	assert_object(result).is_null()


func test_get_nearest_skips_freed() -> void:
	var idx := _create_index()
	var e1 := _create_entity(Vector2(10, 0))
	var e2 := _create_entity(Vector2(50, 0))
	idx.register_entity(e1)
	idx.register_entity(e2)
	e1.free()
	var result: Variant = idx.get_nearest(Vector2(0, 0), 200.0)
	assert_object(result).is_same(e2)


# -- get_all_matching --


func test_get_all_matching_no_filter_returns_all() -> void:
	var idx := _create_index()
	var e1 := _create_entity(Vector2(10, 10))
	var e2 := _create_entity(Vector2(5000, 5000))
	idx.register_entity(e1)
	idx.register_entity(e2)
	var results: Array = idx.get_all_matching()
	assert_int(results.size()).is_equal(2)


func test_get_all_matching_empty_index() -> void:
	var idx := _create_index()
	var results: Array = idx.get_all_matching()
	assert_int(results.size()).is_equal(0)


# -- Filter: owner_id --


func test_filter_owner_id() -> void:
	var idx := _create_index()
	var u0 := _create_unit(Vector2(10, 10), 0)
	var u1 := _create_unit(Vector2(20, 20), 1)
	idx.register_entity(u0)
	idx.register_entity(u1)
	var results: Array = idx.get_entities_in_radius(Vector2(15, 15), 500.0, {"owner_id": 1})
	assert_int(results.size()).is_equal(1)
	assert_object(results[0]).is_same(u1)


# -- Filter: entity_category --


func test_filter_entity_category() -> void:
	var idx := _create_index()
	var u1 := _create_unit(Vector2(10, 10))
	u1.entity_category = "resource_node"
	var u2 := _create_unit(Vector2(20, 20))
	u2.entity_category = "military"
	idx.register_entity(u1)
	idx.register_entity(u2)
	var results: Array = idx.get_entities_in_radius(Vector2(15, 15), 500.0, {"entity_category": "resource_node"})
	assert_int(results.size()).is_equal(1)
	assert_object(results[0]).is_same(u1)


# -- Filter: unit_type --


func test_filter_unit_type() -> void:
	var idx := _create_index()
	var u1 := _create_unit(Vector2(10, 10))
	u1.unit_type = "archer"
	var u2 := _create_unit(Vector2(20, 20))
	u2.unit_type = "cavalry"
	idx.register_entity(u1)
	idx.register_entity(u2)
	var results: Array = idx.get_entities_in_radius(Vector2(15, 15), 500.0, {"unit_type": "archer"})
	assert_int(results.size()).is_equal(1)
	assert_object(results[0]).is_same(u1)


# -- Filter: exclude --


func test_filter_exclude() -> void:
	var idx := _create_index()
	var e1 := _create_entity(Vector2(10, 10))
	var e2 := _create_entity(Vector2(20, 20))
	idx.register_entity(e1)
	idx.register_entity(e2)
	var results: Array = idx.get_entities_in_radius(Vector2(15, 15), 500.0, {"exclude": e1})
	assert_int(results.size()).is_equal(1)
	assert_object(results[0]).is_same(e2)


# -- Filter: predicate --


func test_filter_predicate() -> void:
	var idx := _create_index()
	var e1 := _create_entity(Vector2(10, 10))
	var e2 := _create_entity(Vector2(20, 20))
	idx.register_entity(e1)
	idx.register_entity(e2)
	# Predicate: only entities at x > 15
	var pred := func(entity: Node) -> bool: return entity.global_position.x > 15
	var results: Array = idx.get_entities_in_radius(Vector2(15, 15), 500.0, {"predicate": pred})
	assert_int(results.size()).is_equal(1)
	assert_object(results[0]).is_same(e2)


# -- Filter: alive --


func test_filter_alive_excludes_dead() -> void:
	var idx := _create_index()
	var alive_unit := _create_unit(Vector2(10, 10))
	alive_unit.hp = 50
	alive_unit.max_hp = 100
	var dead_unit := _create_unit(Vector2(20, 20))
	dead_unit.hp = 0
	dead_unit.max_hp = 100
	idx.register_entity(alive_unit)
	idx.register_entity(dead_unit)
	var results: Array = idx.get_entities_in_radius(Vector2(15, 15), 500.0, {"alive": true})
	assert_int(results.size()).is_equal(1)
	assert_object(results[0]).is_same(alive_unit)


# -- get_nearest with filter --


func test_get_nearest_with_filter() -> void:
	var idx := _create_index()
	var u0 := _create_unit(Vector2(10, 0), 0)
	var u1 := _create_unit(Vector2(50, 0), 1)
	idx.register_entity(u0)
	idx.register_entity(u1)
	# Nearest with owner_id=1 should skip u0 even though it's closer
	var result: Variant = idx.get_nearest(Vector2(0, 0), 500.0, {"owner_id": 1})
	assert_object(result).is_same(u1)


# -- get_all_matching with filter --


func test_get_all_matching_with_filter() -> void:
	var idx := _create_index()
	var u0 := _create_unit(Vector2(10, 10), 0)
	var u1 := _create_unit(Vector2(5000, 5000), 1)
	idx.register_entity(u0)
	idx.register_entity(u1)
	var results: Array = idx.get_all_matching({"owner_id": 0})
	assert_int(results.size()).is_equal(1)
	assert_object(results[0]).is_same(u0)


# -- Custom cell size --


func test_custom_cell_size() -> void:
	var idx := _create_index(64.0)
	assert_float(idx._cell_size).is_equal(64.0)
	var e := _create_entity(Vector2(100, 100))
	idx.register_entity(e)
	# 100 / 64 = 1.5625 -> floor = 1
	assert_vector(idx._entity_cells[e]).is_equal(Vector2i(1, 1))


# -- Negative coordinates --


func test_negative_positions() -> void:
	var idx := _create_index(128.0)
	var e := _create_entity(Vector2(-200, -200))
	idx.register_entity(e)
	# -200 / 128 = -1.5625 -> floor = -2
	assert_vector(idx._entity_cells[e]).is_equal(Vector2i(-2, -2))
	var results: Array = idx.get_entities_in_radius(Vector2(-200, -200), 50.0)
	assert_int(results.size()).is_equal(1)


# -- Cross-cell radius query --


func test_radius_spans_multiple_cells() -> void:
	var idx := _create_index(128.0)
	# Place entities in different cells
	var e1 := _create_entity(Vector2(10, 10))
	var e2 := _create_entity(Vector2(200, 200))
	var e3 := _create_entity(Vector2(400, 400))
	idx.register_entity(e1)
	idx.register_entity(e2)
	idx.register_entity(e3)
	# Query centered at 100,100 with radius 250 — should get e1 and e2
	var results: Array = idx.get_entities_in_radius(Vector2(100, 100), 250.0)
	assert_int(results.size()).is_equal(2)
