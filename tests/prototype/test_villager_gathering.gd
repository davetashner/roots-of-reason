extends GdUnitTestSuite
## Tests for villager gathering mechanics — state machine, carry capacity,
## deposit, replacement search, save/load.

const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const ResourceNodeScript := preload("res://scripts/prototype/prototype_resource_node.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")

var _root: Node2D


func before_test() -> void:
	_root = Node2D.new()
	add_child(_root)
	auto_free(_root)


func _create_unit(pos: Vector2 = Vector2.ZERO) -> Node2D:
	var u := Node2D.new()
	u.set_script(UnitScript)
	u.unit_type = "villager"
	u.position = pos
	u._build_speed = 1.0
	u._build_reach = 80.0
	u._carry_capacity = 10
	u._gather_rates = {"food": 0.4, "wood": 0.4, "stone": 0.35, "gold": 0.35}
	u._gather_reach = 80.0
	u._drop_off_reach = 80.0
	u._scene_root = _root
	_root.add_child(u)
	auto_free(u)
	return u


func _create_resource(
	pos: Vector2 = Vector2(50, 0),
	res_type: String = "food",
	yield_amt: int = 150,
) -> Node2D:
	var n := Node2D.new()
	n.set_script(ResourceNodeScript)
	n.resource_name = "berry_bush"
	n.resource_type = res_type
	n.total_yield = yield_amt
	n.current_yield = yield_amt
	n.position = pos
	_root.add_child(n)
	auto_free(n)
	return n


func _create_drop_off(
	pos: Vector2 = Vector2(-50, 0),
	types: Array[String] = ["food", "wood", "stone", "gold"],
) -> Node2D:
	var b := Node2D.new()
	b.set_script(BuildingScript)
	b.building_name = "town_center"
	b.is_drop_off = true
	b.drop_off_types = types
	b.under_construction = false
	b.build_progress = 1.0
	b.max_hp = 2400
	b.hp = 2400
	b.footprint = Vector2i(3, 3)
	b.grid_pos = Vector2i(4, 4)
	b.position = pos
	_root.add_child(b)
	auto_free(b)
	return b


# -- assign_gather_target --


func test_assign_sets_moving_to_resource() -> void:
	var u := _create_unit()
	var res := _create_resource()
	u.assign_gather_target(res)
	assert_int(u._gather_state).is_equal(UnitScript.GatherState.MOVING_TO_RESOURCE)
	assert_bool(u._moving).is_true()


func test_assign_cancels_build() -> void:
	var u := _create_unit()
	var b := _create_drop_off()
	u._build_target = b
	var res := _create_resource()
	u.assign_gather_target(res)
	assert_bool(u._build_target == null).is_true()


func test_assign_build_cancels_gather() -> void:
	var u := _create_unit()
	var res := _create_resource()
	u.assign_gather_target(res)
	var b := Node2D.new()
	b.set_script(BuildingScript)
	b.under_construction = true
	b._build_time = 25.0
	b.max_hp = 100
	b.hp = 0
	b.position = Vector2(30, 0)
	_root.add_child(b)
	auto_free(b)
	u.assign_build_target(b)
	assert_int(u._gather_state).is_equal(UnitScript.GatherState.NONE)


func test_assign_sets_gather_type() -> void:
	var u := _create_unit()
	var res := _create_resource(Vector2(50, 0), "wood")
	u.assign_gather_target(res)
	assert_str(u._gather_type).is_equal("wood")


# -- state transitions --


func test_arrival_transitions_to_gathering() -> void:
	var u := _create_unit(Vector2.ZERO)
	var res := _create_resource(Vector2(30, 0))
	u.assign_gather_target(res)
	# Simulate arrival — place unit in range, stop moving
	u.position = Vector2(30, 0)
	u._moving = false
	u._tick_gather(0.0)
	assert_int(u._gather_state).is_equal(UnitScript.GatherState.GATHERING)


func test_gathering_accumulates_fractional_work() -> void:
	var u := _create_unit(Vector2(30, 0))
	var res := _create_resource(Vector2(30, 0))
	_create_drop_off()
	u.assign_gather_target(res)
	u._moving = false
	u._gather_state = UnitScript.GatherState.GATHERING
	u._gather_accumulator = 0.0
	# 1 second at 0.4/s food rate = 0.4 accumulated, not yet 1
	u._tick_gather(1.0)
	assert_float(u._gather_accumulator).is_equal_approx(0.4, 0.01)
	assert_int(u._carried_amount).is_equal(0)


func test_gathering_extracts_whole_unit() -> void:
	var u := _create_unit(Vector2(30, 0))
	var res := _create_resource(Vector2(30, 0))
	_create_drop_off()
	u.assign_gather_target(res)
	u._moving = false
	u._gather_state = UnitScript.GatherState.GATHERING
	u._gather_accumulator = 0.0
	# 3 seconds at 0.4/s = 1.2 → extract 1
	u._tick_gather(3.0)
	assert_int(u._carried_amount).is_equal(1)
	assert_int(res.current_yield).is_equal(149)


func test_carry_capacity_triggers_drop_off() -> void:
	var u := _create_unit(Vector2(30, 0))
	var res := _create_resource(Vector2(30, 0))
	_create_drop_off()
	u.assign_gather_target(res)
	u._moving = false
	u._gather_state = UnitScript.GatherState.GATHERING
	u._carried_amount = 9
	u._gather_accumulator = 0.9
	# 0.3 more seconds → accumulator 1.2 → extract 1 → carried=10 → full
	u._tick_gather(0.75)
	assert_int(u._gather_state).is_equal(UnitScript.GatherState.MOVING_TO_DROP_OFF)


# -- depositing --


func test_deposit_adds_to_resource_manager() -> void:
	var u := _create_unit(Vector2(-50, 0))
	var res := _create_resource(Vector2(50, 0))
	var drop := _create_drop_off(Vector2(-50, 0))
	ResourceManager.init_player(0)
	u.assign_gather_target(res)
	u._gather_state = UnitScript.GatherState.MOVING_TO_DROP_OFF
	u._carried_amount = 10
	u._drop_off_target = drop
	u._moving = false
	u.position = Vector2(-50, 0)
	# Arrive at drop-off
	u._tick_gather(0.0)
	assert_int(u._gather_state).is_equal(UnitScript.GatherState.DEPOSITING)
	# Deposit
	u._tick_gather(0.0)
	assert_int(u._carried_amount).is_equal(0)
	var food := ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)
	assert_int(food).is_equal(10)
	# Cleanup
	ResourceManager._stockpiles.clear()


func test_deposit_returns_to_resource() -> void:
	var u := _create_unit(Vector2(-50, 0))
	var res := _create_resource(Vector2(50, 0))
	var drop := _create_drop_off(Vector2(-50, 0))
	ResourceManager.init_player(0)
	u._gather_target = res
	u._gather_type = "food"
	u._gather_state = UnitScript.GatherState.DEPOSITING
	u._carried_amount = 5
	u._drop_off_target = drop
	u._scene_root = _root
	u._tick_gather(0.0)
	assert_int(u._gather_state).is_equal(UnitScript.GatherState.MOVING_TO_RESOURCE)
	assert_bool(u._moving).is_true()
	ResourceManager._stockpiles.clear()


# -- depletion / replacement --


func test_depleted_node_triggers_replacement_search() -> void:
	var u := _create_unit(Vector2(30, 0))
	var res1 := _create_resource(Vector2(30, 0), "food", 1)
	var res2 := _create_resource(Vector2(60, 0), "food", 100)
	_create_drop_off()
	u.assign_gather_target(res1)
	u._moving = false
	u._gather_state = UnitScript.GatherState.GATHERING
	u._gather_accumulator = 0.0
	# Deplete res1 completely
	res1.current_yield = 0
	u._tick_gather(1.0)
	# Should find res2 as replacement
	assert_bool(u._gather_target == res2).is_true()
	assert_int(u._gather_state).is_equal(UnitScript.GatherState.MOVING_TO_RESOURCE)


func test_no_replacement_cancels_gather() -> void:
	var u := _create_unit(Vector2(30, 0))
	var res := _create_resource(Vector2(30, 0), "food", 0)
	u.assign_gather_target(res)
	u._moving = false
	u._gather_state = UnitScript.GatherState.GATHERING
	u._tick_gather(1.0)
	assert_int(u._gather_state).is_equal(UnitScript.GatherState.NONE)


func test_depleted_with_carry_triggers_drop_off() -> void:
	var u := _create_unit(Vector2(30, 0))
	var res := _create_resource(Vector2(30, 0), "food", 0)
	_create_drop_off()
	u.assign_gather_target(res)
	u._moving = false
	u._gather_state = UnitScript.GatherState.GATHERING
	u._carried_amount = 5
	u._tick_gather(1.0)
	assert_int(u._gather_state).is_equal(UnitScript.GatherState.MOVING_TO_DROP_OFF)


# -- idle --


func test_is_idle_when_not_gathering() -> void:
	var u := _create_unit()
	assert_bool(u.is_idle()).is_true()


func test_not_idle_when_gathering() -> void:
	var u := _create_unit()
	var res := _create_resource()
	u.assign_gather_target(res)
	assert_bool(u.is_idle()).is_false()


# -- drop-off search --


func test_find_nearest_drop_off() -> void:
	var u := _create_unit(Vector2.ZERO)
	var close := _create_drop_off(Vector2(50, 0))
	var far := _create_drop_off(Vector2(200, 0))
	u._scene_root = _root
	var found: Node2D = u._find_nearest_drop_off("food")
	assert_bool(found == close).is_true()


func test_find_drop_off_respects_type() -> void:
	var u := _create_unit(Vector2.ZERO)
	# This drop-off only accepts wood — set after add_child to override _ready
	var drop := _create_drop_off(Vector2(50, 0))
	drop.drop_off_types = ["wood"] as Array[String]
	u._scene_root = _root
	var found: Node2D = u._find_nearest_drop_off("food")
	assert_bool(found == null).is_true()


# -- multiple villagers --


func test_multiple_villagers_gather_same_node() -> void:
	var res := _create_resource(Vector2(30, 0), "food", 100)
	_create_drop_off()
	var u1 := _create_unit(Vector2(30, 0))
	var u2 := _create_unit(Vector2(30, 0))
	u1.assign_gather_target(res)
	u2.assign_gather_target(res)
	u1._moving = false
	u2._moving = false
	u1._gather_state = UnitScript.GatherState.GATHERING
	u2._gather_state = UnitScript.GatherState.GATHERING
	# 3 seconds each at 0.4/s = 1.2 → 1 each
	u1._tick_gather(3.0)
	u2._tick_gather(3.0)
	assert_int(u1._carried_amount).is_equal(1)
	assert_int(u2._carried_amount).is_equal(1)
	assert_int(res.current_yield).is_equal(98)


# -- save/load --


func test_save_state_includes_gather_fields() -> void:
	var u := _create_unit()
	var res := _create_resource()
	res.name = "Resource_berry_0"
	u.assign_gather_target(res)
	u._carried_amount = 5
	u._gather_accumulator = 0.3
	var state: Dictionary = u.save_state()
	assert_int(int(state["gather_state"])).is_equal(UnitScript.GatherState.MOVING_TO_RESOURCE)
	assert_str(state["gather_type"]).is_equal("food")
	assert_int(int(state["carried_amount"])).is_equal(5)
	assert_str(state["gather_target_name"]).is_equal("Resource_berry_0")


func test_load_state_restores_gather_fields() -> void:
	var u := _create_unit()
	var state := {
		"position_x": 10.0,
		"position_y": 20.0,
		"unit_type": "villager",
		"gather_state": UnitScript.GatherState.MOVING_TO_RESOURCE,
		"gather_type": "food",
		"carried_amount": 7,
		"gather_accumulator": 0.5,
		"gather_target_name": "Resource_berry_0",
	}
	u.load_state(state)
	assert_int(u._gather_state).is_equal(UnitScript.GatherState.MOVING_TO_RESOURCE)
	assert_str(u._gather_type).is_equal("food")
	assert_int(u._carried_amount).is_equal(7)
	assert_float(u._gather_accumulator).is_equal_approx(0.5, 0.01)
	assert_str(u._pending_gather_target_name).is_equal("Resource_berry_0")


# -- integration: gather 100 food --


func test_integration_gather_100_food() -> void:
	ResourceManager.init_player(0)
	var res := _create_resource(Vector2(30, 0), "food", 200)
	var drop := _create_drop_off(Vector2(-30, 0))
	var u := _create_unit(Vector2(30, 0))
	u.assign_gather_target(res)
	u._moving = false
	# Run gather loop: each cycle takes enough ticks to fill carry capacity
	# then manually handle drop-off
	var total_deposited := 0
	for _cycle in 100:
		if u._gather_state == UnitScript.GatherState.NONE:
			break
		# Tick many times in gather state
		if u._gather_state == UnitScript.GatherState.GATHERING:
			# 10 units at 0.4/s = 25 seconds needed
			u._tick_gather(25.0)
		elif u._gather_state == UnitScript.GatherState.MOVING_TO_DROP_OFF:
			# Simulate arrival
			u.position = drop.position
			u._moving = false
			u._tick_gather(0.0)
		elif u._gather_state == UnitScript.GatherState.DEPOSITING:
			u._tick_gather(0.0)
		elif u._gather_state == UnitScript.GatherState.MOVING_TO_RESOURCE:
			u.position = res.position
			u._moving = false
			u._tick_gather(0.0)
		total_deposited = ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)
		if total_deposited >= 100:
			break
	assert_int(total_deposited).is_greater_equal(100)
	ResourceManager._stockpiles.clear()
