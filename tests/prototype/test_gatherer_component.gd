extends GdUnitTestSuite
## Tests for GathererComponent in isolation.
## Uses a lightweight mock owner so the component can be exercised without
## spinning up a full prototype_unit scene.

const GathererComponentScript := preload("res://scripts/prototype/gatherer_component.gd")
const ResourceFactory := preload("res://tests/helpers/resource_factory.gd")
const BuildingFactory := preload("res://tests/helpers/building_factory.gd")
const RMGuard := preload("res://tests/helpers/resource_manager_guard.gd")

var _root: Node2D
var _unit: Node2D
var _rm_guard: RefCounted


## Minimal Node2D that satisfies the interface GathererComponent reads from _unit.
class MockUnit:
	extends Node2D

	var owner_id: int = 0
	var _moving: bool = false
	var _path: Array[Vector2] = []
	var _path_index: int = 0
	var _scene_root: Node = null
	var _last_move_target: Vector2 = Vector2.ZERO

	func move_to(pos: Vector2) -> void:
		_last_move_target = pos
		_moving = true


func before_test() -> void:
	_rm_guard = RMGuard.new()
	_root = Node2D.new()
	add_child(_root)
	auto_free(_root)
	_unit = MockUnit.new()
	_unit._scene_root = _root
	_unit.position = Vector2.ZERO
	_root.add_child(_unit)
	auto_free(_unit)


func after_test() -> void:
	_rm_guard.dispose()


func _make_component() -> GathererComponentScript:
	var gc := GathererComponentScript.new(_unit)
	gc.carry_capacity = 10
	gc.gather_rates = {"food": 0.4, "wood": 0.4, "stone": 0.35, "gold": 0.35}
	gc.gather_reach = 80.0
	gc.drop_off_reach = 80.0
	return gc


func _make_resource(
	pos: Vector2 = Vector2(50, 0),
	res_type: String = "food",
	yield_amt: int = 150,
) -> Node2D:
	var n := ResourceFactory.create_resource_node({position = pos, resource_type = res_type, total_yield = yield_amt})
	_root.add_child(n)
	auto_free(n)
	return n


func _make_drop_off(
	pos: Vector2 = Vector2(-50, 0),
	types: Array[String] = ["food", "wood", "stone", "gold"],
) -> Node2D:
	var b := BuildingFactory.create_drop_off({position = pos, drop_off_types = types})
	_root.add_child(b)
	auto_free(b)
	return b


# ---------------------------------------------------------------------------
# assign_target
# ---------------------------------------------------------------------------


func test_assign_target_sets_state_moving_to_resource() -> void:
	var gc := _make_component()
	var res := _make_resource()
	gc.assign_target(res)
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.MOVING_TO_RESOURCE)


func test_assign_target_stores_resource_type() -> void:
	var gc := _make_component()
	var res := _make_resource(Vector2(50, 0), "wood")
	gc.assign_target(res)
	assert_str(gc.gather_type).is_equal("wood")


func test_assign_target_resets_carried_amount() -> void:
	var gc := _make_component()
	gc.carried_amount = 7
	var res := _make_resource()
	gc.assign_target(res)
	assert_int(gc.carried_amount).is_equal(0)


func test_assign_target_calls_move_to() -> void:
	var gc := _make_component()
	var res := _make_resource(Vector2(40, 0))
	gc.assign_target(res)
	assert_bool(_unit._moving).is_true()
	var mu := _unit as MockUnit
	assert_vector(mu._last_move_target).is_equal_approx(Vector2(40, 0), Vector2(0.01, 0.01))


# ---------------------------------------------------------------------------
# cancel
# ---------------------------------------------------------------------------


func test_cancel_resets_to_none() -> void:
	var gc := _make_component()
	var res := _make_resource()
	gc.assign_target(res)
	gc.cancel()
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.NONE)


func test_cancel_clears_gather_target() -> void:
	var gc := _make_component()
	var res := _make_resource()
	gc.assign_target(res)
	gc.cancel()
	assert_bool(gc.gather_target == null).is_true()


func test_cancel_clears_gather_type() -> void:
	var gc := _make_component()
	var res := _make_resource()
	gc.assign_target(res)
	gc.cancel()
	assert_str(gc.gather_type).is_equal("")


func test_cancel_clears_accumulator() -> void:
	var gc := _make_component()
	var res := _make_resource()
	gc.assign_target(res)
	gc.gather_accumulator = 0.75
	gc.cancel()
	assert_float(gc.gather_accumulator).is_equal_approx(0.0, 0.001)


# ---------------------------------------------------------------------------
# MOVING_TO_RESOURCE → GATHERING transition
# ---------------------------------------------------------------------------


func test_arrival_in_range_transitions_to_gathering() -> void:
	var gc := _make_component()
	var res := _make_resource(Vector2(30, 0))
	gc.assign_target(res)
	# Simulate unit arriving
	_unit.position = Vector2(30, 0)
	_unit._moving = false
	gc.tick(0.0)
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.GATHERING)


func test_not_yet_in_range_stays_moving_to_resource() -> void:
	var gc := _make_component()
	var res := _make_resource(Vector2(200, 0))
	gc.assign_target(res)
	_unit.position = Vector2.ZERO
	_unit._moving = true
	gc.tick(0.0)
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.MOVING_TO_RESOURCE)


func test_null_target_during_moving_cancels() -> void:
	var gc := _make_component()
	gc.gather_state = GathererComponentScript.GatherState.MOVING_TO_RESOURCE
	gc.gather_type = "food"
	gc.gather_target = null
	gc.tick(0.0)
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.NONE)


# ---------------------------------------------------------------------------
# GATHERING accumulation
# ---------------------------------------------------------------------------


func test_gathering_accumulates_fractional_work() -> void:
	var gc := _make_component()
	var res := _make_resource(Vector2(30, 0))
	_make_drop_off()
	gc.assign_target(res)
	gc.gather_state = GathererComponentScript.GatherState.GATHERING
	gc.gather_accumulator = 0.0
	# 1 second at food rate 0.4/s → accumulator = 0.4, nothing extracted yet
	gc.tick(1.0)
	assert_float(gc.gather_accumulator).is_equal_approx(0.4, 0.01)
	assert_int(gc.carried_amount).is_equal(0)


func test_gathering_extracts_whole_unit_from_resource() -> void:
	var gc := _make_component()
	var res := _make_resource(Vector2(30, 0))
	_make_drop_off()
	gc.assign_target(res)
	gc.gather_state = GathererComponentScript.GatherState.GATHERING
	gc.gather_accumulator = 0.0
	# 3 seconds at 0.4/s → 1.2 → extract 1
	gc.tick(3.0)
	assert_int(gc.carried_amount).is_equal(1)
	assert_int(res.current_yield).is_equal(149)


func test_gathering_respects_rate_multiplier() -> void:
	var gc := _make_component()
	gc.gather_rate_multiplier = 2.0
	var res := _make_resource(Vector2(30, 0))
	_make_drop_off()
	gc.assign_target(res)
	gc.gather_state = GathererComponentScript.GatherState.GATHERING
	gc.gather_accumulator = 0.0
	# 1 second at 0.4 * 2.0 = 0.8/s → accumulator 0.8
	gc.tick(1.0)
	assert_float(gc.gather_accumulator).is_equal_approx(0.8, 0.01)


# ---------------------------------------------------------------------------
# carry_capacity limits
# ---------------------------------------------------------------------------


func test_carry_capacity_triggers_drop_off_trip() -> void:
	var gc := _make_component()
	var res := _make_resource(Vector2(30, 0))
	_make_drop_off()
	gc.assign_target(res)
	gc.gather_state = GathererComponentScript.GatherState.GATHERING
	gc.carried_amount = 9
	gc.gather_accumulator = 0.9
	# 0.75s at 0.4/s → accumulator 1.2 → extract 1 → carried=10 → full
	gc.tick(0.75)
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.MOVING_TO_DROP_OFF)


func test_carry_capacity_of_one_fills_on_single_extract() -> void:
	var gc := _make_component()
	gc.carry_capacity = 1
	var res := _make_resource(Vector2(30, 0))
	_make_drop_off()
	gc.assign_target(res)
	gc.gather_state = GathererComponentScript.GatherState.GATHERING
	gc.gather_accumulator = 0.0
	# 3 seconds at 0.4/s → 1 extracted → hits capacity of 1
	gc.tick(3.0)
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.MOVING_TO_DROP_OFF)


# ---------------------------------------------------------------------------
# MOVING_TO_DROP_OFF → DEPOSITING transition
# ---------------------------------------------------------------------------


func test_arrival_at_drop_off_transitions_to_depositing() -> void:
	var gc := _make_component()
	var drop := _make_drop_off(Vector2(-50, 0))
	_unit.position = Vector2(-50, 0)
	_unit._moving = false
	gc.gather_state = GathererComponentScript.GatherState.MOVING_TO_DROP_OFF
	gc.gather_type = "food"
	gc.drop_off_target = drop
	gc.carried_amount = 5
	gc.tick(0.0)
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.DEPOSITING)


func test_no_drop_off_target_enters_waiting() -> void:
	var gc := _make_component()
	gc.gather_state = GathererComponentScript.GatherState.MOVING_TO_DROP_OFF
	gc.gather_type = "food"
	gc.drop_off_target = null
	gc.carried_amount = 5
	# No drop-off in scene → wait (preserves carried resources)
	gc.tick(0.0)
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.WAITING_FOR_DROP_OFF)
	assert_int(gc.carried_amount).is_equal(5)


# ---------------------------------------------------------------------------
# DEPOSITING
# ---------------------------------------------------------------------------


func test_depositing_adds_resources_to_manager() -> void:
	ResourceManager.init_player(0, {})
	var gc := _make_component()
	var res := _make_resource(Vector2(50, 0))
	var drop := _make_drop_off(Vector2(-50, 0))
	gc.gather_state = GathererComponentScript.GatherState.DEPOSITING
	gc.gather_type = "food"
	gc.gather_target = res
	gc.drop_off_target = drop
	gc.carried_amount = 8
	gc.tick(0.0)
	var food: int = ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)
	assert_int(food).is_equal(8)


func test_depositing_resets_carried_amount() -> void:
	ResourceManager.init_player(0, {})
	var gc := _make_component()
	var res := _make_resource(Vector2(50, 0))
	var drop := _make_drop_off(Vector2(-50, 0))
	gc.gather_state = GathererComponentScript.GatherState.DEPOSITING
	gc.gather_type = "food"
	gc.gather_target = res
	gc.drop_off_target = drop
	gc.carried_amount = 5
	gc.tick(0.0)
	assert_int(gc.carried_amount).is_equal(0)


func test_depositing_returns_to_moving_to_resource_when_target_valid() -> void:
	ResourceManager.init_player(0, {})
	var gc := _make_component()
	var res := _make_resource(Vector2(50, 0))
	var drop := _make_drop_off(Vector2(-50, 0))
	gc.gather_state = GathererComponentScript.GatherState.DEPOSITING
	gc.gather_type = "food"
	gc.gather_target = res
	gc.drop_off_target = drop
	gc.carried_amount = 5
	gc.tick(0.0)
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.MOVING_TO_RESOURCE)
	assert_bool(_unit._moving).is_true()


func test_depositing_unknown_type_does_not_crash() -> void:
	ResourceManager.init_player(0, {})
	var gc := _make_component()
	var res := _make_resource(Vector2(50, 0), "fish")
	var drop := _make_drop_off(Vector2(-50, 0), ["fish"])
	gc.gather_state = GathererComponentScript.GatherState.DEPOSITING
	gc.gather_type = "fish"
	gc.gather_target = res
	gc.drop_off_target = drop
	gc.carried_amount = 3
	# Should not error — _resource_type_to_enum returns null for unknown types
	gc.tick(0.0)
	assert_int(gc.carried_amount).is_equal(0)


# ---------------------------------------------------------------------------
# Replacement resource search
# ---------------------------------------------------------------------------


func test_depleted_target_finds_replacement() -> void:
	var gc := _make_component()
	var res1 := _make_resource(Vector2(30, 0), "food", 0)
	var res2 := _make_resource(Vector2(60, 0), "food", 100)
	_make_drop_off()
	gc.assign_target(res1)
	_unit._moving = false
	gc.gather_state = GathererComponentScript.GatherState.GATHERING
	gc.carried_amount = 0
	gc.tick(1.0)
	assert_bool(gc.gather_target == res2).is_true()
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.MOVING_TO_RESOURCE)


func test_no_replacement_with_no_carry_cancels() -> void:
	var gc := _make_component()
	var res := _make_resource(Vector2(30, 0), "food", 0)
	gc.assign_target(res)
	_unit._moving = false
	gc.gather_state = GathererComponentScript.GatherState.GATHERING
	gc.carried_amount = 0
	gc.tick(1.0)
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.NONE)


func test_depleted_with_carried_amount_starts_drop_off() -> void:
	var gc := _make_component()
	var res := _make_resource(Vector2(30, 0), "food", 0)
	_make_drop_off()
	gc.assign_target(res)
	_unit._moving = false
	gc.gather_state = GathererComponentScript.GatherState.GATHERING
	gc.carried_amount = 5
	gc.tick(1.0)
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.MOVING_TO_DROP_OFF)


func test_replacement_ignores_depleted_alternatives() -> void:
	var gc := _make_component()
	var res1 := _make_resource(Vector2(30, 0), "food", 0)
	# Only available replacement is also depleted
	var res2 := _make_resource(Vector2(60, 0), "food", 0)
	gc.assign_target(res1)
	_unit._moving = false
	gc.gather_state = GathererComponentScript.GatherState.GATHERING
	gc.carried_amount = 0
	gc.tick(1.0)
	# res2 has current_yield=0 so it should not be chosen; gather cancels
	assert_bool(gc.gather_target != res2).is_true()
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.NONE)


# ---------------------------------------------------------------------------
# save_state / load_state round-trip
# ---------------------------------------------------------------------------


func test_save_state_preserves_gather_fields() -> void:
	var gc := _make_component()
	var res := _make_resource()
	res.name = "TestResource"
	gc.assign_target(res)
	gc.carried_amount = 6
	gc.gather_accumulator = 0.3
	gc.gather_rate_multiplier = 1.5
	var state: Dictionary = gc.save_state()
	assert_int(int(state["gather_state"])).is_equal(GathererComponentScript.GatherState.MOVING_TO_RESOURCE)
	assert_str(state["gather_type"]).is_equal("food")
	assert_int(int(state["carried_amount"])).is_equal(6)
	assert_float(float(state["gather_accumulator"])).is_equal_approx(0.3, 0.01)
	assert_float(float(state["gather_rate_multiplier"])).is_equal_approx(1.5, 0.01)
	assert_str(state["gather_target_name"]).is_equal("TestResource")


func test_save_state_omits_target_name_when_null() -> void:
	var gc := _make_component()
	gc.gather_state = GathererComponentScript.GatherState.NONE
	gc.gather_target = null
	var state: Dictionary = gc.save_state()
	assert_bool(state.has("gather_target_name")).is_false()


func test_load_state_restores_all_fields() -> void:
	var gc := _make_component()
	var data := {
		"gather_state": GathererComponentScript.GatherState.GATHERING,
		"gather_type": "wood",
		"carried_amount": 4,
		"gather_accumulator": 0.6,
		"gather_rate_multiplier": 2.0,
		"gather_target_name": "MyResource",
	}
	gc.load_state(data)
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.GATHERING)
	assert_str(gc.gather_type).is_equal("wood")
	assert_int(gc.carried_amount).is_equal(4)
	assert_float(gc.gather_accumulator).is_equal_approx(0.6, 0.01)
	assert_float(gc.gather_rate_multiplier).is_equal_approx(2.0, 0.01)
	assert_str(gc.pending_gather_target_name).is_equal("MyResource")


func test_load_state_defaults_when_keys_missing() -> void:
	var gc := _make_component()
	gc.load_state({})
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.NONE)
	assert_str(gc.gather_type).is_equal("")
	assert_int(gc.carried_amount).is_equal(0)
	assert_float(gc.gather_accumulator).is_equal_approx(0.0, 0.001)
	assert_float(gc.gather_rate_multiplier).is_equal_approx(1.0, 0.001)


func test_save_load_round_trip() -> void:
	var gc := _make_component()
	var res := _make_resource()
	res.name = "RoundTripRes"
	gc.assign_target(res)
	gc.carried_amount = 3
	gc.gather_accumulator = 0.55
	gc.gather_rate_multiplier = 1.25
	var saved: Dictionary = gc.save_state()

	var gc2 := _make_component()
	gc2.load_state(saved)
	assert_int(gc2.gather_state).is_equal(gc.gather_state)
	assert_str(gc2.gather_type).is_equal(gc.gather_type)
	assert_int(gc2.carried_amount).is_equal(gc.carried_amount)
	assert_float(gc2.gather_accumulator).is_equal_approx(gc.gather_accumulator, 0.01)
	assert_float(gc2.gather_rate_multiplier).is_equal_approx(gc.gather_rate_multiplier, 0.01)
	assert_str(gc2.pending_gather_target_name).is_equal("RoundTripRes")


# ---------------------------------------------------------------------------
# resolve_target
# ---------------------------------------------------------------------------


func test_resolve_target_links_named_node() -> void:
	var gc := _make_component()
	var res := _make_resource()
	res.name = "BerryBush42"
	gc.pending_gather_target_name = "BerryBush42"
	gc.resolve_target(_root)
	assert_bool(gc.gather_target == res).is_true()
	assert_str(gc.pending_gather_target_name).is_equal("")


func test_resolve_target_noop_when_name_empty() -> void:
	var gc := _make_component()
	gc.pending_gather_target_name = ""
	gc.resolve_target(_root)
	assert_bool(gc.gather_target == null).is_true()


func test_resolve_target_noop_when_node_not_found() -> void:
	var gc := _make_component()
	gc.pending_gather_target_name = "NonExistent"
	gc.resolve_target(_root)
	assert_bool(gc.gather_target == null).is_true()
	assert_str(gc.pending_gather_target_name).is_equal("")


# ---------------------------------------------------------------------------
# load_config
# ---------------------------------------------------------------------------


func test_load_config_sets_carry_capacity() -> void:
	var gc := _make_component()
	gc.load_config({"carry_capacity": 20}, {})
	assert_int(gc.carry_capacity).is_equal(20)


func test_load_config_sets_gather_rates() -> void:
	var gc := _make_component()
	gc.load_config({"gather_rates": {"food": 1.0, "wood": 0.5}}, {})
	assert_float(float(gc.gather_rates.get("food", 0.0))).is_equal_approx(1.0, 0.01)
	assert_float(float(gc.gather_rates.get("wood", 0.0))).is_equal_approx(0.5, 0.01)


func test_load_config_sets_gather_reach() -> void:
	var gc := _make_component()
	gc.load_config({}, {"gather_reach": 120.0, "drop_off_reach": 100.0})
	assert_float(gc.gather_reach).is_equal_approx(120.0, 0.01)
	assert_float(gc.drop_off_reach).is_equal_approx(100.0, 0.01)


func test_load_config_empty_dicts_leave_defaults() -> void:
	var gc := _make_component()
	var orig_cap := gc.carry_capacity
	var orig_reach := gc.gather_reach
	gc.load_config({}, {})
	assert_int(gc.carry_capacity).is_equal(orig_cap)
	assert_float(gc.gather_reach).is_equal_approx(orig_reach, 0.01)


# ---------------------------------------------------------------------------
# NONE state — tick is no-op
# ---------------------------------------------------------------------------


func test_tick_in_none_state_does_nothing() -> void:
	var gc := _make_component()
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.NONE)
	gc.tick(1.0)
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.NONE)
	assert_bool(_unit._moving).is_false()


# ---------------------------------------------------------------------------
# WAITING_FOR_DROP_OFF — resilience when no drop-off exists
# ---------------------------------------------------------------------------


func test_no_drop_off_enters_waiting_state() -> void:
	var gc := _make_component()
	var res := _make_resource()
	gc.assign_target(res)
	gc.carried_amount = 10
	# No drop-off exists — should enter waiting, not cancel
	gc._start_drop_off_trip()
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.WAITING_FOR_DROP_OFF)
	assert_int(gc.carried_amount).is_equal(10)


func test_waiting_transitions_when_drop_off_appears() -> void:
	var gc := _make_component()
	var res := _make_resource()
	gc.assign_target(res)
	gc.carried_amount = 10
	gc._start_drop_off_trip()
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.WAITING_FOR_DROP_OFF)
	# Now add a drop-off
	var drop := _make_drop_off()
	gc.tick(0.016)
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.MOVING_TO_DROP_OFF)


func test_waiting_preserves_carried_resources() -> void:
	var gc := _make_component()
	var res := _make_resource()
	gc.assign_target(res)
	gc.carried_amount = 7
	gc.gather_type = "food"
	gc._start_drop_off_trip()
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.WAITING_FOR_DROP_OFF)
	# Tick several times with no drop-off
	gc.tick(1.0)
	gc.tick(1.0)
	gc.tick(1.0)
	assert_int(gc.carried_amount).is_equal(7)
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.WAITING_FOR_DROP_OFF)


func test_moving_to_drop_off_enters_waiting_on_invalid_target() -> void:
	var gc := _make_component()
	var res := _make_resource()
	gc.assign_target(res)
	gc.carried_amount = 5
	gc.gather_type = "food"
	gc.gather_state = GathererComponentScript.GatherState.MOVING_TO_DROP_OFF
	gc.drop_off_target = null
	# No drop-off exists — tick should go to waiting
	gc.tick(0.016)
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.WAITING_FOR_DROP_OFF)
	assert_int(gc.carried_amount).is_equal(5)


# ---------------------------------------------------------------------------
# gather_offset
# ---------------------------------------------------------------------------


func test_assign_target_with_offset_moves_to_offset_position() -> void:
	var gc := _make_component()
	var res := _make_resource(Vector2(40, 0))
	gc.assign_target(res, Vector2(20, 10))
	assert_vector(gc.gather_offset).is_equal(Vector2(20, 10))
	var mu := _unit as MockUnit
	assert_vector(mu._last_move_target).is_equal_approx(Vector2(60, 10), Vector2(0.01, 0.01))


func test_cancel_resets_gather_offset() -> void:
	var gc := _make_component()
	var res := _make_resource()
	gc.assign_target(res, Vector2(20, 10))
	gc.cancel()
	assert_vector(gc.gather_offset).is_equal(Vector2.ZERO)


func test_save_load_preserves_gather_offset() -> void:
	var gc := _make_component()
	gc.gather_offset = Vector2(30, -15)
	var state: Dictionary = gc.save_state()
	assert_float(float(state["gather_offset_x"])).is_equal_approx(30.0, 0.01)
	assert_float(float(state["gather_offset_y"])).is_equal_approx(-15.0, 0.01)
	var gc2 := _make_component()
	gc2.load_state(state)
	assert_vector(gc2.gather_offset).is_equal_approx(Vector2(30, -15), Vector2(0.01, 0.01))
