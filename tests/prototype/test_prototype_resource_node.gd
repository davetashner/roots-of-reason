extends GdUnitTestSuite
## Tests for prototype_resource_node.gd — yield math, depletion, regen, save/load.

const ResourceNodeScript := preload("res://scripts/prototype/prototype_resource_node.gd")


func _create_node(res_type: String = "food", yield_amt: int = 100) -> Node2D:
	var n := Node2D.new()
	n.set_script(ResourceNodeScript)
	n.resource_name = "berry_bush"
	n.resource_type = res_type
	n.total_yield = yield_amt
	n.current_yield = yield_amt
	add_child(n)
	auto_free(n)
	return n


func _create_regen_node(yield_amt: int = 100, rate: float = 1.0, delay: float = 0.0) -> Node2D:
	var n := _create_node("wood", yield_amt)
	n.resource_name = "tree"
	n.regenerates = true
	n.regen_rate = rate
	n.regen_delay = delay
	return n


# -- apply_gather_work --


func test_apply_gather_work_reduces_yield() -> void:
	var n := _create_node("food", 100)
	var gathered: int = n.apply_gather_work(5.0)
	assert_int(gathered).is_equal(5)
	assert_int(n.current_yield).is_equal(95)


func test_apply_gather_work_clamps_to_remaining() -> void:
	var n := _create_node("food", 3)
	var gathered: int = n.apply_gather_work(10.0)
	assert_int(gathered).is_equal(3)
	assert_int(n.current_yield).is_equal(0)


func test_apply_gather_work_returns_zero_when_depleted() -> void:
	var n := _create_node("food", 0)
	var gathered: int = n.apply_gather_work(5.0)
	assert_int(gathered).is_equal(0)


func test_apply_gather_work_emits_depleted() -> void:
	var n := _create_node("food", 5)
	var monitor := monitor_signals(n)
	n.apply_gather_work(5.0)
	await assert_signal(monitor).is_emitted("depleted", [n])


func test_apply_gather_work_no_signal_when_not_empty() -> void:
	var n := _create_node("food", 10)
	var monitor := monitor_signals(n)
	n.apply_gather_work(3.0)
	await assert_signal(monitor).is_not_emitted("depleted")


func test_apply_gather_work_truncates_float() -> void:
	var n := _create_node("food", 100)
	# 2.9 truncates to 2
	var gathered: int = n.apply_gather_work(2.9)
	assert_int(gathered).is_equal(2)
	assert_int(n.current_yield).is_equal(98)


# -- Regen property defaults --


func test_regenerates_defaults_false() -> void:
	var n := _create_node("food", 100)
	assert_bool(n.regenerates).is_false()
	assert_float(n.regen_rate).is_equal(0.0)
	assert_float(n.regen_delay).is_equal(0.0)


# -- Regen signal behavior --


func test_regen_node_emits_regen_started_not_depleted() -> void:
	var n := _create_regen_node(5)
	var monitor := monitor_signals(n)
	n.apply_gather_work(5.0)
	await assert_signal(monitor).is_emitted("regen_started", [n])
	await assert_signal(monitor).is_not_emitted("depleted")


func test_non_regen_node_emits_depleted_not_regen_started() -> void:
	var n := _create_node("food", 5)
	var monitor := monitor_signals(n)
	n.apply_gather_work(5.0)
	await assert_signal(monitor).is_emitted("depleted", [n])
	await assert_signal(monitor).is_not_emitted("regen_started")


func test_regen_node_sets_is_regrowing() -> void:
	var n := _create_regen_node(5)
	n.apply_gather_work(5.0)
	assert_bool(n._is_regrowing).is_true()
	assert_int(n.current_yield).is_equal(0)


# -- Regen delay --


func test_regen_delay_prevents_early_restore() -> void:
	var n := _create_regen_node(5, 10.0, 5.0)
	n.apply_gather_work(5.0)
	assert_int(n.current_yield).is_equal(0)
	# Process with small delta — should still be in delay
	n._process(1.0)
	assert_int(n.current_yield).is_equal(0)
	assert_bool(n._is_regrowing).is_true()


func test_regen_starts_after_delay() -> void:
	var n := _create_regen_node(5, 10.0, 2.0)
	n.apply_gather_work(5.0)
	# Process past the delay
	n._process(3.0)
	# Now yield should have been restored (10.0 rate * 1.0 remaining delta = 10)
	assert_int(n.current_yield).is_greater(0)


# -- Regen accumulator --


func test_regen_accumulator_restores_yield() -> void:
	var n := _create_regen_node(100, 2.0, 0.0)
	n.apply_gather_work(100.0)
	# Process 1 second — should restore 2 yield
	n._process(1.0)
	assert_int(n.current_yield).is_equal(2)


func test_regen_yield_caps_at_total() -> void:
	var n := _create_regen_node(10, 100.0, 0.0)
	n.current_yield = 8
	n.regenerates = true
	n._is_regrowing = false
	# Process — should cap at total_yield
	n._process(1.0)
	assert_int(n.current_yield).is_equal(10)


func test_is_regrowing_clears_when_yield_positive() -> void:
	var n := _create_regen_node(100, 5.0, 0.0)
	n.apply_gather_work(100.0)
	assert_bool(n._is_regrowing).is_true()
	# Process enough to get yield > 0
	n._process(1.0)
	assert_int(n.current_yield).is_greater(0)
	assert_bool(n._is_regrowing).is_false()


# -- save_state / load_state --


func test_save_state_includes_all_fields() -> void:
	var n := _create_node("food", 100)
	n.position = Vector2(50, 75)
	n.apply_gather_work(10.0)
	var state: Dictionary = n.save_state()
	assert_str(state["resource_name"]).is_equal("berry_bush")
	assert_str(state["resource_type"]).is_equal("food")
	assert_int(int(state["total_yield"])).is_equal(100)
	assert_int(int(state["current_yield"])).is_equal(90)
	assert_float(float(state["position_x"])).is_equal_approx(50.0, 0.01)
	assert_float(float(state["position_y"])).is_equal_approx(75.0, 0.01)


func test_save_load_round_trip() -> void:
	var n := _create_node("wood", 200)
	n.resource_name = "tree"
	n.position = Vector2(30, 40)
	n.apply_gather_work(50.0)
	var state: Dictionary = n.save_state()
	var n2 := _create_node()
	n2.load_state(state)
	assert_str(n2.resource_name).is_equal("tree")
	assert_str(n2.resource_type).is_equal("wood")
	assert_int(n2.total_yield).is_equal(200)
	assert_int(n2.current_yield).is_equal(150)
	assert_float(n2.position.x).is_equal_approx(30.0, 0.01)
	assert_float(n2.position.y).is_equal_approx(40.0, 0.01)


func test_save_state_includes_regen_fields() -> void:
	var n := _create_regen_node(100, 2.0, 5.0)
	n.apply_gather_work(100.0)
	n._regen_delay_timer = 3.0
	n._regen_accum = 0.5
	var state: Dictionary = n.save_state()
	assert_bool(bool(state["is_regrowing"])).is_true()
	assert_float(float(state["regen_delay_timer"])).is_equal_approx(3.0, 0.01)
	assert_float(float(state["regen_accum"])).is_equal_approx(0.5, 0.01)


func test_load_state_restores_regen_fields() -> void:
	var n := _create_regen_node(100)
	n.apply_gather_work(100.0)
	n._regen_delay_timer = 2.5
	n._regen_accum = 0.7
	var state: Dictionary = n.save_state()
	var n2 := _create_node()
	n2.load_state(state)
	assert_bool(n2._is_regrowing).is_true()
	assert_float(n2._regen_delay_timer).is_equal_approx(2.5, 0.01)
	assert_float(n2._regen_accum).is_equal_approx(0.7, 0.01)


func test_backward_compat_load_no_regen_fields() -> void:
	# Simulate old save data without regen fields
	var state := {
		"resource_name": "berry_bush",
		"resource_type": "food",
		"total_yield": 100,
		"current_yield": 50,
		"position_x": 10.0,
		"position_y": 20.0,
	}
	var n := _create_node()
	n.load_state(state)
	assert_bool(n._is_regrowing).is_false()
	assert_float(n._regen_delay_timer).is_equal(0.0)
	assert_float(n._regen_accum).is_equal(0.0)


# -- Sprite support --


func test_no_sprite_by_default() -> void:
	var n := _create_node("food", 100)
	assert_object(n._sprite).is_null()
	assert_int(n._sprite_textures.size()).is_equal(0)


func test_sprite_null_when_no_config() -> void:
	var n := _create_regen_node(50)
	assert_object(n._sprite).is_null()


func test_draw_skipped_when_sprite_exists() -> void:
	# Create a node and manually set _sprite to verify _draw returns early
	var n := _create_node("food", 100)
	n._sprite = Sprite2D.new()
	n.add_child(n._sprite)
	# Calling queue_redraw should not crash — _draw returns early
	n.queue_redraw()
	# No assertion needed — we're just verifying no crash


func test_sprite_state_defaults() -> void:
	var n := _create_node("food", 100)
	assert_float(n._half_threshold).is_equal(0.5)
	assert_float(n._sprite_offset_y).is_equal(0.0)


func test_variant_index_defaults_to_zero() -> void:
	var n := _create_node("food", 100)
	assert_int(n.variant_index).is_equal(0)


func test_variant_index_saved_and_loaded() -> void:
	var n := _create_node("wood", 200)
	n.resource_name = "tree"
	n.variant_index = 3
	var state: Dictionary = n.save_state()
	assert_int(int(state["variant_index"])).is_equal(3)
	var n2 := _create_node()
	n2.load_state(state)
	assert_int(n2.variant_index).is_equal(3)


func test_variant_index_backward_compat() -> void:
	# Old save data without variant_index should default to 0
	var state := {
		"resource_name": "berry_bush",
		"resource_type": "food",
		"total_yield": 100,
		"current_yield": 50,
		"position_x": 10.0,
		"position_y": 20.0,
	}
	var n := _create_node()
	n.load_state(state)
	assert_int(n.variant_index).is_equal(0)
