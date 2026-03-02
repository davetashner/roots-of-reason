extends GdUnitTestSuite
## Tests for Fishing Boat gather cycle: dock→fish deposit→dock return.
## Verifies the full economic loop using GathererComponent with fishing boat stats.

const GathererComponentScript := preload("res://scripts/prototype/gatherer_component.gd")
const ResourceFactory := preload("res://tests/helpers/resource_factory.gd")
const BuildingFactory := preload("res://tests/helpers/building_factory.gd")
const RMGuard := preload("res://tests/helpers/resource_manager_guard.gd")

var _root: Node2D
var _unit: Node2D
var _rm_guard: RefCounted


class MockFishingBoat:
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
	_unit = MockFishingBoat.new()
	_unit._scene_root = _root
	_unit.position = Vector2.ZERO
	_root.add_child(_unit)
	auto_free(_unit)


func after_test() -> void:
	_rm_guard.dispose()


func _make_fishing_boat_component() -> GathererComponentScript:
	var gc := GathererComponentScript.new(_unit)
	gc.carry_capacity = 15
	gc.gather_rates = {"food": 0.5}
	gc.gather_reach = 80.0
	gc.drop_off_reach = 80.0
	return gc


func _make_fish_deposit(
	pos: Vector2 = Vector2(100, 0),
	yield_amt: int = 300,
) -> Node2D:
	var n := (
		ResourceFactory
		. create_resource_node(
			{
				position = pos,
				resource_type = "food",
				resource_name = "fish",
				total_yield = yield_amt,
				regenerates = true,
				regen_rate = 0.3,
				regen_delay = 30.0,
			}
		)
	)
	_root.add_child(n)
	auto_free(n)
	return n


func _make_dock(pos: Vector2 = Vector2(-100, 0)) -> Node2D:
	var b := (
		BuildingFactory
		. create_drop_off(
			{
				building_name = "dock",
				position = pos,
				drop_off_types = ["food"] as Array[String],
				footprint = Vector2i(3, 3),
			}
		)
	)
	_root.add_child(b)
	auto_free(b)
	return b


# ---------------------------------------------------------------------------
# Full gather→deposit→return cycle
# ---------------------------------------------------------------------------


func test_fishing_boat_full_gather_cycle_increases_food() -> void:
	ResourceManager.init_player(0, {})
	var gc := _make_fishing_boat_component()
	var fish := _make_fish_deposit()
	var dock := _make_dock()

	# 1. Assign to fish deposit
	gc.assign_target(fish)
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.MOVING_TO_RESOURCE)

	# 2. Arrive at fish deposit
	_unit.position = Vector2(100, 0)
	_unit._moving = false
	gc.tick(0.0)
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.GATHERING)

	# 3. Gather until full: 15 capacity at 0.5/s = 30s + accumulator overhead
	# Fast-forward: set carried to 14, accumulator near threshold
	gc.carried_amount = 14
	gc.gather_accumulator = 0.9
	gc.tick(0.5)  # 0.5 * 0.5 = 0.25 → accum 1.15 → extract 1 → carried=15 → full
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.MOVING_TO_DROP_OFF)

	# 4. Arrive at dock
	_unit.position = Vector2(-100, 0)
	_unit._moving = false
	gc.tick(0.0)
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.DEPOSITING)

	# 5. Deposit — food should increase by 15
	gc.tick(0.0)
	var food: int = ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)
	assert_int(food).is_equal(15)
	assert_int(gc.carried_amount).is_equal(0)

	# 6. Returns to original fish deposit
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.MOVING_TO_RESOURCE)
	assert_bool(gc.gather_target == fish).is_true()


func test_fishing_boat_gather_rate_matches_data() -> void:
	var gc := _make_fishing_boat_component()
	var fish := _make_fish_deposit()
	_make_dock()
	gc.assign_target(fish)
	gc.gather_state = GathererComponentScript.GatherState.GATHERING
	gc.gather_accumulator = 0.0

	# 2 seconds at 0.5/s food → accumulator = 1.0 → extract 1
	gc.tick(2.0)
	assert_int(gc.carried_amount).is_equal(1)
	assert_int(fish.current_yield).is_equal(299)


func test_fishing_boat_carry_capacity_is_fifteen() -> void:
	var gc := _make_fishing_boat_component()
	assert_int(gc.carry_capacity).is_equal(15)


# ---------------------------------------------------------------------------
# Deposit depletion → reassignment
# ---------------------------------------------------------------------------


func test_depleted_fish_deposit_triggers_reassignment() -> void:
	var gc := _make_fishing_boat_component()
	var fish1 := _make_fish_deposit(Vector2(100, 0), 0)  # already depleted
	var fish2 := _make_fish_deposit(Vector2(200, 0), 300)  # healthy
	_make_dock()

	gc.assign_target(fish1)
	_unit.position = Vector2(100, 0)
	_unit._moving = false
	gc.tick(0.0)  # arrive → GATHERING
	gc.tick(1.0)  # depleted target → search replacement

	assert_bool(gc.gather_target == fish2).is_true()
	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.MOVING_TO_RESOURCE)


func test_all_deposits_depleted_with_cargo_starts_drop_off() -> void:
	var gc := _make_fishing_boat_component()
	var fish := _make_fish_deposit(Vector2(100, 0), 0)
	_make_dock()

	gc.assign_target(fish)
	gc.carried_amount = 5
	_unit.position = Vector2(100, 0)
	_unit._moving = false
	gc.tick(0.0)  # arrive → GATHERING
	gc.tick(1.0)  # depleted + has cargo → drop off

	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.MOVING_TO_DROP_OFF)
	assert_int(gc.carried_amount).is_equal(5)


func test_all_deposits_depleted_no_cargo_cancels() -> void:
	var gc := _make_fishing_boat_component()
	var fish := _make_fish_deposit(Vector2(100, 0), 0)
	_make_dock()

	gc.assign_target(fish)
	gc.carried_amount = 0
	_unit.position = Vector2(100, 0)
	_unit._moving = false
	gc.tick(0.0)  # arrive → GATHERING
	gc.tick(1.0)  # depleted + no cargo → cancel

	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.NONE)


# ---------------------------------------------------------------------------
# Multiple fishing boats sharing deposits
# ---------------------------------------------------------------------------


func test_multiple_fishing_boats_share_deposit() -> void:
	ResourceManager.init_player(0, {})
	var fish := _make_fish_deposit(Vector2(100, 0), 300)
	var dock := _make_dock()

	# Create two fishing boat components sharing the same MockUnit root
	# (they share the fish deposit)
	var gc1 := _make_fishing_boat_component()
	var gc2 := GathererComponentScript.new(_unit)
	gc2.carry_capacity = 15
	gc2.gather_rates = {"food": 0.5}
	gc2.gather_reach = 80.0
	gc2.drop_off_reach = 80.0

	gc1.assign_target(fish)
	gc2.assign_target(fish)

	# Both should target the same fish deposit
	assert_bool(gc1.gather_target == fish).is_true()
	assert_bool(gc2.gather_target == fish).is_true()

	# Simulate both gathering — both reduce the same deposit
	gc1.gather_state = GathererComponentScript.GatherState.GATHERING
	gc2.gather_state = GathererComponentScript.GatherState.GATHERING
	gc1.gather_accumulator = 0.0
	gc2.gather_accumulator = 0.0
	_unit.position = Vector2(100, 0)
	_unit._moving = false

	# 4s at 0.5/s each → 2 extracted per boat → 4 total from deposit
	gc1.tick(4.0)
	gc2.tick(4.0)
	assert_int(gc1.carried_amount + gc2.carried_amount).is_equal(4)
	assert_int(fish.current_yield).is_equal(296)


# ---------------------------------------------------------------------------
# Dock as food drop-off
# ---------------------------------------------------------------------------


func test_dock_accepts_food_drop_off() -> void:
	ResourceManager.init_player(0, {})
	var gc := _make_fishing_boat_component()
	var fish := _make_fish_deposit()
	var dock := _make_dock(Vector2(-50, 0))

	gc.assign_target(fish)
	gc.gather_type = "food"
	gc.carried_amount = 10
	gc.drop_off_target = dock
	gc.gather_state = GathererComponentScript.GatherState.DEPOSITING
	gc.tick(0.0)

	var food: int = ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)
	assert_int(food).is_equal(10)
	assert_int(gc.carried_amount).is_equal(0)


func test_no_dock_enters_waiting_state() -> void:
	var gc := _make_fishing_boat_component()
	var fish := _make_fish_deposit()
	# No dock in scene
	gc.assign_target(fish)
	gc.carried_amount = 15
	gc._start_drop_off_trip()

	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.WAITING_FOR_DROP_OFF)
	assert_int(gc.carried_amount).is_equal(15)


func test_dock_only_accepts_food_not_other_types() -> void:
	var gc := _make_fishing_boat_component()
	gc.gather_type = "wood"
	gc.carried_amount = 10
	var dock := _make_dock()
	# Dock only accepts "food" — wood drop-off should find nothing
	gc._start_drop_off_trip()

	assert_int(gc.gather_state).is_equal(GathererComponentScript.GatherState.WAITING_FOR_DROP_OFF)
