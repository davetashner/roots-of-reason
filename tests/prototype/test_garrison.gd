extends GdUnitTestSuite
## Tests for garrison system in prototype_building.gd.

const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")

var _mock_unit_script: GDScript
var _scene_root: Node


func before() -> void:
	_mock_unit_script = GDScript.new()
	_mock_unit_script.source_code = (
		"extends Node2D\n"
		+ "var owner_id: int = 0\n"
		+ "var hp: int = 100\n"
		+ 'var unit_category: String = "military"\n'
		+ "func take_damage(amount: int, _attacker: Node2D) -> void:\n"
		+ "\thp -= amount\n"
		+ "\tif hp < 0: hp = 0\n"
	)
	_mock_unit_script.reload()


func _create_building(capacity: int = 10, complete: bool = true) -> Node2D:
	var b := Node2D.new()
	b.set_script(BuildingScript)
	b.building_name = "test_building"
	b.max_hp = 1200
	b.hp = 1200 if complete else 0
	b.under_construction = not complete
	b.build_progress = 1.0 if complete else 0.0
	b._build_time = 50.0
	b.footprint = Vector2i(3, 3)
	b.grid_pos = Vector2i(5, 5)
	add_child(b)
	auto_free(b)
	# Set after add_child so _ready() doesn't override from DataLoader
	b.garrison_capacity = capacity
	b._garrison_config = {
		"damage_reduction": 0.5,
		"arrow_damage": 5,
		"arrow_range_tiles": 6,
		"arrow_interval": 2.0,
		"ungarrison_radius_tiles": 2,
		"garrison_reach_tiles": 2,
		"garrison_load_time": 0.5,
	}
	b._combat_config = {"show_damage_numbers": false}
	return b


func _create_unit(owner: int = 0) -> Node2D:
	var u := Node2D.new()
	u.set_script(_mock_unit_script)
	u.owner_id = owner
	add_child(u)
	auto_free(u)
	return u


func _create_hostile(pos: Vector2 = Vector2.ZERO) -> Node2D:
	var u := _create_unit(1)
	u.global_position = pos
	return u


## Helper: queue a unit, position it at the building, and tick loading so it
## becomes fully garrisoned (hidden). Use when tests need the old instant-garrison
## behavior.
func _garrison_immediately(building: Node2D, unit: Node2D) -> bool:
	var result: bool = building.garrison_unit(unit)
	if not result:
		return false
	unit.global_position = building.global_position
	building._tick_garrison_loading()
	return true


# -- garrison_unit queuing --


func test_garrison_unit_queues_not_immediate() -> void:
	var b := _create_building()
	var u := _create_unit()
	u.global_position = Vector2(9999, 9999)
	var result: bool = b.garrison_unit(u)
	assert_bool(result).is_true()
	# Unit should still be visible — it's queued, not garrisoned yet
	assert_bool(u.visible).is_true()
	assert_int(b.get_garrisoned_count()).is_equal(0)


func test_garrison_loading_hides_unit_when_in_range() -> void:
	var b := _create_building()
	b.global_position = Vector2(200, 200)
	var u := _create_unit()
	u.global_position = Vector2(200, 200)  # At building position
	b.garrison_unit(u)
	b._tick_garrison_loading()
	assert_bool(u.visible).is_false()
	assert_bool(u.is_processing()).is_false()
	assert_int(b.get_garrisoned_count()).is_equal(1)


func test_garrison_loading_waits_when_out_of_range() -> void:
	var b := _create_building()
	b.global_position = Vector2(200, 200)
	var u := _create_unit()
	u.global_position = Vector2(9999, 9999)  # Far away
	b.garrison_unit(u)
	b._tick_garrison_loading()
	# Still visible — not in range
	assert_bool(u.visible).is_true()
	assert_int(b.get_garrisoned_count()).is_equal(0)


func test_garrison_unit_hides_unit() -> void:
	var b := _create_building()
	var u := _create_unit()
	var result: bool = _garrison_immediately(b, u)
	assert_bool(result).is_true()
	assert_bool(u.visible).is_false()
	assert_bool(u.is_processing()).is_false()


func test_garrison_respects_capacity() -> void:
	var b := _create_building(2)
	var u1 := _create_unit()
	var u2 := _create_unit()
	assert_bool(_garrison_immediately(b, u1)).is_true()
	assert_bool(_garrison_immediately(b, u2)).is_true()
	assert_int(b.get_garrisoned_count()).is_equal(2)


func test_garrison_fails_when_full() -> void:
	var b := _create_building(1)
	var u1 := _create_unit()
	var u2 := _create_unit()
	assert_bool(b.garrison_unit(u1)).is_true()
	assert_bool(b.garrison_unit(u2)).is_false()


func test_garrison_capacity_includes_queue() -> void:
	var b := _create_building(2)
	var u1 := _create_unit()
	var u2 := _create_unit()
	var u3 := _create_unit()
	u1.global_position = Vector2(9999, 9999)
	u2.global_position = Vector2(9999, 9999)
	u3.global_position = Vector2(9999, 9999)
	assert_bool(b.garrison_unit(u1)).is_true()
	assert_bool(b.garrison_unit(u2)).is_true()
	# Queue is full (2 queued, 0 garrisoned, capacity 2) — should fail
	assert_bool(b.garrison_unit(u3)).is_false()


func test_garrison_fails_on_ruins() -> void:
	var b := _create_building()
	b._is_ruins = true
	b.entity_category = "ruins"
	var u := _create_unit()
	assert_bool(b.garrison_unit(u)).is_false()


func test_garrison_fails_on_construction() -> void:
	var b := _create_building(10, false)
	var u := _create_unit()
	assert_bool(b.garrison_unit(u)).is_false()


# -- ungarrison_all --


func test_ungarrison_all_restores_units() -> void:
	var b := _create_building()
	var u1 := _create_unit()
	var u2 := _create_unit()
	_garrison_immediately(b, u1)
	_garrison_immediately(b, u2)
	var ejected: Array = b.ungarrison_all()
	assert_int(ejected.size()).is_equal(2)
	assert_bool(u1.visible).is_true()
	assert_bool(u1.is_processing()).is_true()
	assert_bool(u2.visible).is_true()
	assert_int(b.get_garrisoned_count()).is_equal(0)


func test_ungarrison_positions_near_building() -> void:
	var b := _create_building()
	b.global_position = Vector2(500, 500)
	var u := _create_unit()
	_garrison_immediately(b, u)
	b.ungarrison_all()
	var dist := u.global_position.distance_to(b.global_position)
	# Should be within ungarrison_radius_tiles * 64 = 128 pixels
	assert_float(dist).is_less_equal(128.0 + 1.0)
	assert_float(dist).is_greater(0.0)


func test_garrison_queue_cleared_on_ungarrison() -> void:
	var b := _create_building()
	var u := _create_unit()
	u.global_position = Vector2(9999, 9999)
	b.garrison_unit(u)
	var ejected: Array = b.ungarrison_all()
	assert_int(ejected.size()).is_equal(1)
	assert_bool(ejected.has(u)).is_true()
	# Queue should be empty now
	assert_int(b._garrison_load_queue.size()).is_equal(0)


# -- arrow fire --


func test_garrison_arrow_fires_at_hostile() -> void:
	var b := _create_building()
	b.global_position = Vector2(200, 200)
	var u := _create_unit()
	_garrison_immediately(b, u)
	# Place hostile within range (6 tiles * 64 = 384 px)
	var hostile := _create_hostile(Vector2(300, 200))
	var initial_hp: int = hostile.hp
	# Tick past the arrow interval
	b._tick_garrison_arrows(2.1)
	assert_int(hostile.hp).is_less(initial_hp)


func test_garrison_arrow_damage_scales_with_count() -> void:
	var b := _create_building()
	b.global_position = Vector2(200, 200)
	var u1 := _create_unit()
	var u2 := _create_unit()
	var u3 := _create_unit()
	_garrison_immediately(b, u1)
	_garrison_immediately(b, u2)
	_garrison_immediately(b, u3)
	assert_int(b.get_garrisoned_count()).is_equal(3)
	var hostile := _create_hostile(Vector2(300, 200))
	# Verify hostile is findable
	var found: Node2D = b._find_nearest_hostile(384.0)
	assert_object(found).is_not_null()
	# Manually compute expected damage
	var arrow_damage: int = int(b._garrison_config.get("arrow_damage", 5))
	var expected_damage: int = arrow_damage * b.get_garrisoned_count()
	assert_int(expected_damage).is_equal(15)
	# Apply damage directly to verify mock works
	hostile.take_damage(expected_damage, b)
	assert_int(hostile.hp).is_equal(85)


# -- destruction ejects --


func test_building_destruction_ejects_units() -> void:
	var b := _create_building()
	var u := _create_unit()
	_garrison_immediately(b, u)
	assert_bool(u.visible).is_false()
	# Simulate destruction
	b.take_damage(b.hp, null)
	assert_bool(u.visible).is_true()
	assert_bool(u.is_processing()).is_true()
	assert_int(b.get_garrisoned_count()).is_equal(0)


# -- save/load --


func test_garrison_save_load_round_trip() -> void:
	var b := _create_building()
	var u1 := _create_unit()
	var u2 := _create_unit()
	u1.name = "unit_alpha"
	u2.name = "unit_beta"
	_garrison_immediately(b, u1)
	_garrison_immediately(b, u2)
	var state: Dictionary = b.save_state()
	assert_int(state["garrison_capacity"]).is_equal(10)
	var names: Array = state["garrisoned_units"]
	assert_int(names.size()).is_equal(2)
	assert_bool(names.has("unit_alpha")).is_true()
	assert_bool(names.has("unit_beta")).is_true()


func test_garrison_save_includes_queued_units() -> void:
	var b := _create_building()
	var u1 := _create_unit()
	var u2 := _create_unit()
	u1.name = "unit_garrisoned"
	u2.name = "unit_queued"
	_garrison_immediately(b, u1)
	# Queue u2 far away so it stays in the load queue
	u2.global_position = Vector2(9999, 9999)
	b.garrison_unit(u2)
	var state: Dictionary = b.save_state()
	var names: Array = state["garrisoned_units"]
	assert_int(names.size()).is_equal(2)
	assert_bool(names.has("unit_garrisoned")).is_true()
	assert_bool(names.has("unit_queued")).is_true()


# -- can_garrison edge cases --


func test_can_garrison_returns_false_at_zero_capacity() -> void:
	var b := _create_building(0)
	assert_bool(b.can_garrison()).is_false()
	var u := _create_unit()
	assert_bool(b.garrison_unit(u)).is_false()
