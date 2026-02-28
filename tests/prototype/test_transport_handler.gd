extends GdUnitTestSuite
## Tests for transport_handler.gd — direct tests of the handler's embark, capacity,
## kill_passengers, save/load round-trip, and resolve logic.

const TransportHandlerScript := preload("res://scripts/prototype/transport_handler.gd")

var _mock_land_script: GDScript
var _mock_water_script: GDScript


func before() -> void:
	_mock_land_script = GDScript.new()
	_mock_land_script.source_code = (
		"extends Node2D\n"
		+ "var owner_id: int = 0\n"
		+ "var hp: int = 50\n"
		+ "var max_hp: int = 50\n"
		+ "var _is_dead: bool = false\n"
		+ 'var unit_type: String = "militia"\n'
		+ "var stats: RefCounted = null\n"
		+ "func _die() -> void:\n"
		+ "\t_is_dead = true\n"
	)
	_mock_land_script.reload()
	_mock_water_script = GDScript.new()
	_mock_water_script.source_code = (
		"extends Node2D\n"
		+ "var owner_id: int = 0\n"
		+ "var hp: int = 50\n"
		+ "var max_hp: int = 50\n"
		+ "var _is_dead: bool = false\n"
		+ 'var unit_type: String = "warship"\n'
		+ 'var movement_type: String = "water"\n'
		+ "var stats: RefCounted = null\n"
		+ "func _die() -> void:\n"
		+ "\t_is_dead = true\n"
	)
	_mock_water_script.reload()


func _create_handler(cap: int = 5) -> RefCounted:
	var h := TransportHandlerScript.new()
	h.capacity = cap
	h.config = {
		"load_time_per_unit": 1.0,
		"unload_time_per_unit": 1.0,
		"unload_spread_radius_tiles": 2,
	}
	return h


func _create_land_unit(unit_name: String = "") -> Node2D:
	var u := Node2D.new()
	u.set_script(_mock_land_script)
	if unit_name != "":
		u.name = unit_name
	add_child(u)
	auto_free(u)
	return u


func _create_water_unit() -> Node2D:
	var u := Node2D.new()
	u.set_script(_mock_water_script)
	add_child(u)
	auto_free(u)
	return u


# -- embark_unit --


func test_embark_unit_adds_to_load_queue() -> void:
	var h := _create_handler()
	var u := _create_land_unit()
	var result: bool = h.embark_unit(u)
	assert_bool(result).is_true()
	assert_int(h.load_queue.size()).is_equal(1)
	assert_int(h.embarked_units.size()).is_equal(0)


func test_embark_unit_moves_to_embarked_after_tick() -> void:
	var h := _create_handler()
	var u := _create_land_unit()
	h.embark_unit(u)
	h.tick(1.0, false)
	assert_int(h.load_queue.size()).is_equal(0)
	assert_int(h.embarked_units.size()).is_equal(1)
	assert_bool(u.visible).is_false()
	assert_bool(u.is_processing()).is_false()


func test_embark_unit_rejects_water_unit() -> void:
	var h := _create_handler()
	var u := _create_water_unit()
	var result: bool = h.embark_unit(u)
	assert_bool(result).is_false()
	assert_int(h.load_queue.size()).is_equal(0)


func test_embark_unit_rejects_duplicate() -> void:
	var h := _create_handler()
	var u := _create_land_unit()
	assert_bool(h.embark_unit(u)).is_true()
	assert_bool(h.embark_unit(u)).is_false()
	assert_int(h.load_queue.size()).is_equal(1)


func test_embark_unit_rejects_already_embarked() -> void:
	var h := _create_handler()
	var u := _create_land_unit()
	h.embark_unit(u)
	h.tick(1.0, false)
	assert_int(h.embarked_units.size()).is_equal(1)
	assert_bool(h.embark_unit(u)).is_false()


func test_embark_fails_with_zero_capacity() -> void:
	var h := _create_handler(0)
	var u := _create_land_unit()
	assert_bool(h.embark_unit(u)).is_false()


# -- capacity --


func test_capacity_respects_limit() -> void:
	var h := _create_handler(2)
	var u1 := _create_land_unit()
	var u2 := _create_land_unit()
	var u3 := _create_land_unit()
	assert_bool(h.embark_unit(u1)).is_true()
	assert_bool(h.embark_unit(u2)).is_true()
	assert_bool(h.embark_unit(u3)).is_false()


func test_capacity_counts_queue_and_embarked() -> void:
	var h := _create_handler(2)
	var u1 := _create_land_unit()
	var u2 := _create_land_unit()
	h.embark_unit(u1)
	h.tick(1.0, false)
	assert_int(h.embarked_units.size()).is_equal(1)
	assert_int(h.load_queue.size()).is_equal(0)
	h.embark_unit(u2)
	assert_int(h.get_count()).is_equal(2)
	var u3 := _create_land_unit()
	assert_bool(h.embark_unit(u3)).is_false()


func test_can_embark_false_when_full() -> void:
	var h := _create_handler(1)
	assert_bool(h.can_embark()).is_true()
	var u := _create_land_unit()
	h.embark_unit(u)
	assert_bool(h.can_embark()).is_false()


func test_can_embark_false_at_zero_capacity() -> void:
	var h := _create_handler(0)
	assert_bool(h.can_embark()).is_false()


# -- kill_passengers --


func test_kill_passengers_kills_embarked() -> void:
	var h := _create_handler()
	var u1 := _create_land_unit()
	var u2 := _create_land_unit()
	h.embark_unit(u1)
	h.embark_unit(u2)
	h.tick(1.0, false)
	h.tick(1.0, false)
	assert_int(h.embarked_units.size()).is_equal(2)
	h.kill_passengers()
	assert_int(u1.hp).is_equal(0)
	assert_bool(u1._is_dead).is_true()
	assert_int(u2.hp).is_equal(0)
	assert_bool(u2._is_dead).is_true()
	assert_int(h.embarked_units.size()).is_equal(0)


func test_kill_passengers_kills_load_queue() -> void:
	var h := _create_handler()
	var u := _create_land_unit()
	h.embark_unit(u)
	assert_int(h.load_queue.size()).is_equal(1)
	h.kill_passengers()
	assert_int(u.hp).is_equal(0)
	assert_bool(u._is_dead).is_true()
	assert_int(h.load_queue.size()).is_equal(0)


func test_kill_passengers_clears_both_lists() -> void:
	var h := _create_handler(5)
	var u_queued := _create_land_unit()
	var u_embarked := _create_land_unit()
	h.embark_unit(u_embarked)
	h.tick(1.0, false)
	h.embark_unit(u_queued)
	assert_int(h.embarked_units.size()).is_equal(1)
	assert_int(h.load_queue.size()).is_equal(1)
	h.kill_passengers()
	assert_int(h.embarked_units.size()).is_equal(0)
	assert_int(h.load_queue.size()).is_equal(0)
	assert_int(u_embarked.hp).is_equal(0)
	assert_int(u_queued.hp).is_equal(0)


func test_kill_passengers_restores_visibility() -> void:
	var h := _create_handler()
	var u := _create_land_unit()
	h.embark_unit(u)
	h.tick(1.0, false)
	assert_bool(u.visible).is_false()
	h.kill_passengers()
	assert_bool(u.visible).is_true()


# -- save/load round-trip --


func test_save_state_records_unit_names() -> void:
	var h := _create_handler()
	var u1 := _create_land_unit("soldier_a")
	var u2 := _create_land_unit("soldier_b")
	h.embark_unit(u1)
	h.embark_unit(u2)
	h.tick(1.0, false)
	h.tick(1.0, false)
	var state: Dictionary = h.save_state()
	var names: Array = state["embarked_unit_names"]
	assert_int(names.size()).is_equal(2)
	assert_bool(names.has("soldier_a")).is_true()
	assert_bool(names.has("soldier_b")).is_true()


func test_save_state_records_unloading_flag() -> void:
	var h := _create_handler()
	h.is_unloading = true
	h.pending_disembark_pos = Vector2(100.0, 200.0)
	var state: Dictionary = h.save_state()
	assert_bool(state["is_unloading"]).is_true()
	assert_float(float(state["pending_disembark_pos_x"])).is_equal_approx(100.0, 0.01)
	assert_float(float(state["pending_disembark_pos_y"])).is_equal_approx(200.0, 0.01)


func test_load_state_restores_pending_names() -> void:
	var state: Dictionary = {
		"embarked_unit_names": ["alpha", "bravo"],
		"is_unloading": false,
		"pending_disembark_pos_x": 0.0,
		"pending_disembark_pos_y": 0.0,
	}
	var h := _create_handler()
	h.load_state(state)
	assert_int(h.pending_names.size()).is_equal(2)
	assert_str(h.pending_names[0]).is_equal("alpha")
	assert_str(h.pending_names[1]).is_equal("bravo")


func test_load_state_restores_disembark_pos() -> void:
	var state: Dictionary = {
		"embarked_unit_names": [],
		"is_unloading": true,
		"pending_disembark_pos_x": 300.0,
		"pending_disembark_pos_y": 450.0,
	}
	var h := _create_handler()
	h.load_state(state)
	assert_bool(h.is_unloading).is_true()
	assert_float(h.pending_disembark_pos.x).is_equal_approx(300.0, 0.01)
	assert_float(h.pending_disembark_pos.y).is_equal_approx(450.0, 0.01)


func test_save_load_round_trip() -> void:
	var h := _create_handler()
	var u1 := _create_land_unit("trooper_1")
	var u2 := _create_land_unit("trooper_2")
	h.embark_unit(u1)
	h.embark_unit(u2)
	h.tick(1.0, false)
	h.tick(1.0, false)
	h.is_unloading = true
	h.pending_disembark_pos = Vector2(150.0, 250.0)

	var state: Dictionary = h.save_state()

	var h2 := _create_handler()
	h2.load_state(state)
	assert_int(h2.pending_names.size()).is_equal(2)
	assert_bool(h2.is_unloading).is_true()
	assert_float(h2.pending_disembark_pos.x).is_equal_approx(150.0, 0.01)
	assert_float(h2.pending_disembark_pos.y).is_equal_approx(250.0, 0.01)

	# Resolve pending names against scene tree
	h2.resolve(self)
	assert_int(h2.embarked_units.size()).is_equal(2)
	assert_int(h2.pending_names.size()).is_equal(0)
	assert_bool(u1.visible).is_false()
	assert_bool(u2.visible).is_false()


# -- resolve --


func test_resolve_finds_units_in_scene_tree() -> void:
	var h := _create_handler()
	var u := _create_land_unit("recon_unit")
	h.pending_names.append("recon_unit")
	h.resolve(self)
	assert_int(h.embarked_units.size()).is_equal(1)
	assert_bool(u.visible).is_false()
	assert_int(h.pending_names.size()).is_equal(0)


func test_resolve_skips_missing_units() -> void:
	var h := _create_handler()
	h.pending_names.append("nonexistent_unit")
	h.resolve(self)
	assert_int(h.embarked_units.size()).is_equal(0)
	assert_int(h.pending_names.size()).is_equal(0)


# -- get_count --


func test_get_count_returns_combined_total() -> void:
	var h := _create_handler(5)
	var u1 := _create_land_unit()
	var u2 := _create_land_unit()
	h.embark_unit(u1)
	h.tick(1.0, false)
	h.embark_unit(u2)
	assert_int(h.get_count()).is_equal(2)
	assert_int(h.embarked_units.size()).is_equal(1)
	assert_int(h.load_queue.size()).is_equal(1)
