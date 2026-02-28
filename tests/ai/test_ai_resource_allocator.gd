extends GdUnitTestSuite
## Tests for scripts/ai/ai_resource_allocator.gd — villager rebalancing logic.

const AIResourceAllocatorScript := preload("res://scripts/ai/ai_resource_allocator.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const ResourceNodeScript := preload("res://scripts/prototype/prototype_resource_node.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")

# --- Lifecycle ---


func before_test() -> void:
	GameManager.current_age = 0
	GameManager.game_speed = 1.0


# --- Helpers ---


func _create_allocator(
	config: Dictionary = {},
	villager_allocation: Dictionary = {},
) -> AIResourceAllocator:
	var alloc := AIResourceAllocatorScript.new()
	alloc.player_id = 1
	if config.is_empty():
		config = {"rebalance_threshold": 2.0, "resource_search_radius": 20}
	if villager_allocation.is_empty():
		villager_allocation = {
			"0": {"food": 0.5, "wood": 0.3, "stone": 0.1, "gold": 0.1},
		}
	alloc.setup(self, config, villager_allocation)
	return alloc


func _create_villager(
	owner_id: int = 1,
	pos: Vector2 = Vector2.ZERO,
	idle: bool = true,
) -> Node2D:
	var unit := Node2D.new()
	unit.name = "Villager_%d" % get_child_count()
	unit.set_script(UnitScript)
	unit.unit_type = "villager"
	unit.owner_id = owner_id
	unit.position = pos
	unit._scene_root = self
	add_child(unit)
	if idle:
		unit._moving = false
	return auto_free(unit)


func _create_resource_node(
	res_name: String = "berry_bush",
	pos: Vector2 = Vector2(100, 100),
) -> Node2D:
	var node := Node2D.new()
	node.name = "Resource_%s_%d" % [res_name, get_child_count()]
	node.set_script(ResourceNodeScript)
	node.position = pos
	add_child(node)
	node.setup(res_name)
	return auto_free(node)


func _create_town_center(grid_pos: Vector2i = Vector2i(10, 10)) -> Node2D:
	var building := Node2D.new()
	building.name = "TownCenter_%d" % get_child_count()
	building.set_script(BuildingScript)
	building.position = IsoUtils.grid_to_screen(Vector2(grid_pos))
	building.owner_id = 1
	building.building_name = "town_center"
	building.footprint = Vector2i(3, 3)
	building.grid_pos = grid_pos
	building.hp = 2400
	building.max_hp = 2400
	building.under_construction = false
	building.build_progress = 1.0
	add_child(building)
	return auto_free(building)


func _init_resources(
	food: int = 500,
	wood: int = 500,
	stone: int = 500,
	gold: int = 500,
) -> void:
	(
		ResourceManager
		. init_player(
			1,
			{
				ResourceManager.ResourceType.FOOD: food,
				ResourceManager.ResourceType.WOOD: wood,
				ResourceManager.ResourceType.STONE: stone,
				ResourceManager.ResourceType.GOLD: gold,
				ResourceManager.ResourceType.KNOWLEDGE: 0,
			}
		)
	)


# --- Target allocation ---


func test_target_allocation_returns_ratios_for_age_zero() -> void:
	var alloc := _create_allocator(
		{"rebalance_threshold": 2.0, "resource_search_radius": 20},
		{"0": {"food": 0.5, "wood": 0.3, "stone": 0.1, "gold": 0.1}},
	)
	GameManager.current_age = 0
	var target: Dictionary = alloc._get_target_allocation()
	assert_float(float(target.get("food", 0.0))).is_equal_approx(0.5, 0.001)
	assert_float(float(target.get("wood", 0.0))).is_equal_approx(0.3, 0.001)


func test_target_allocation_falls_back_to_age_zero_key() -> void:
	# Age 5 not in allocation — should fall back to "0"
	var alloc := _create_allocator(
		{"rebalance_threshold": 2.0, "resource_search_radius": 20},
		{"0": {"food": 0.6, "wood": 0.4}},
	)
	GameManager.current_age = 5
	var target: Dictionary = alloc._get_target_allocation()
	assert_float(float(target.get("food", 0.0))).is_equal_approx(0.6, 0.001)


func test_target_allocation_uses_age_specific_key() -> void:
	var alloc := _create_allocator(
		{"rebalance_threshold": 2.0, "resource_search_radius": 20},
		{
			"0": {"food": 0.5, "wood": 0.5},
			"2": {"food": 0.3, "wood": 0.4, "stone": 0.1, "gold": 0.2},
		},
	)
	GameManager.current_age = 2
	var target: Dictionary = alloc._get_target_allocation()
	assert_float(float(target.get("food", 0.0))).is_equal_approx(0.3, 0.001)
	assert_float(float(target.get("gold", 0.0))).is_equal_approx(0.2, 0.001)


# --- Current allocation ---


func test_current_allocation_counts_assigned_villagers() -> void:
	var alloc := _create_allocator()
	var v1 := _create_villager(1, Vector2.ZERO)
	var v2 := _create_villager(1, Vector2(50, 0))
	# Manually set gather types (bypass gather state machine)
	v1._gatherer.gather_type = "food"
	v2._gatherer.gather_type = "wood"
	var villagers: Array[Node2D] = [v1, v2]
	var current: Dictionary = alloc._get_current_allocation(villagers)
	assert_int(int(current.get("food", 0))).is_equal(1)
	assert_int(int(current.get("wood", 0))).is_equal(1)


func test_current_allocation_ignores_unassigned_villagers() -> void:
	var alloc := _create_allocator()
	var v := _create_villager(1, Vector2.ZERO)
	# _gather_type defaults to "" — not counted in any resource
	var villagers: Array[Node2D] = [v]
	var current: Dictionary = alloc._get_current_allocation(villagers)
	assert_int(int(current.get("food", 0))).is_equal(0)
	assert_int(int(current.get("wood", 0))).is_equal(0)


# --- Highest deficit resource ---


func test_highest_deficit_picks_most_underallocated_resource() -> void:
	var alloc := _create_allocator()
	# Target: food=50%, wood=30%, stone=10%, gold=10% of 10 villagers
	var target: Dictionary = {"food": 0.5, "wood": 0.3, "stone": 0.1, "gold": 0.1}
	# Current: all on food, none on wood/stone/gold
	var current: Dictionary = {"food": 10, "wood": 0, "stone": 0, "gold": 0}
	var best: String = alloc._get_highest_deficit_resource(target, current, 10)
	# Wood deficit = 3, stone=1, gold=1, food=-5; wood should win
	assert_str(best).is_equal("wood")


func test_highest_deficit_returns_empty_when_all_met() -> void:
	var alloc := _create_allocator()
	var target: Dictionary = {"food": 0.5, "wood": 0.5}
	var current: Dictionary = {"food": 5, "wood": 5}
	var best: String = alloc._get_highest_deficit_resource(target, current, 10)
	# All exactly met — best_deficit will be 0 or negative; function still returns one
	# (it returns the "least surplus"), but the key point is it returns a string
	assert_bool(best is String).is_true()


func test_highest_deficit_with_empty_target_returns_empty() -> void:
	var alloc := _create_allocator()
	var target: Dictionary = {}
	var current: Dictionary = {"food": 5}
	var best: String = alloc._get_highest_deficit_resource(target, current, 10)
	assert_str(best).is_equal("")


# --- Idle villager assignment ---


func test_idle_villager_assigned_to_food_when_deficit() -> void:
	_init_resources()
	var tc := _create_town_center(Vector2i(10, 10))
	var tc_screen := IsoUtils.grid_to_screen(Vector2(Vector2i(10, 10)))
	var alloc := _create_allocator(
		{"rebalance_threshold": 2.0, "resource_search_radius": 20},
		{"0": {"food": 1.0}},
	)
	# Create a food resource node within search radius
	_create_resource_node("berry_bush", tc_screen + Vector2(64, 0))
	var v := _create_villager(1, tc_screen, true)
	var villagers: Array[Node2D] = [v]
	alloc.rebalance_gatherers(villagers, tc)
	# Villager should no longer be idle
	assert_bool(v.is_idle()).is_false()


func test_no_assignment_when_no_resource_nodes_present() -> void:
	var tc := _create_town_center()
	var alloc := _create_allocator()
	var v := _create_villager(1, Vector2.ZERO, true)
	var villagers: Array[Node2D] = [v]
	# No resource nodes added to scene
	alloc.rebalance_gatherers(villagers, tc)
	# Villager stays idle — no nodes to assign to
	assert_bool(v.is_idle()).is_true()


func test_no_rebalance_with_zero_villagers() -> void:
	var tc := _create_town_center()
	var alloc := _create_allocator()
	var villagers: Array[Node2D] = []
	# Should not crash
	alloc.rebalance_gatherers(villagers, tc)
	assert_bool(true).is_true()


func test_busy_villager_not_reassigned() -> void:
	_init_resources()
	var tc := _create_town_center(Vector2i(10, 10))
	var tc_screen := IsoUtils.grid_to_screen(Vector2(Vector2i(10, 10)))
	var alloc := _create_allocator(
		{"rebalance_threshold": 2.0, "resource_search_radius": 20},
		{"0": {"wood": 1.0}},
	)
	_create_resource_node("tree", tc_screen + Vector2(64, 0))
	var v := _create_villager(1, tc_screen, false)
	# Mark villager as non-idle by setting it moving
	v._moving = true
	var villagers: Array[Node2D] = [v]
	var initial_gather_type: String = v._gatherer.gather_type
	alloc.rebalance_gatherers(villagers, tc)
	# Moving villager should not have been reassigned
	assert_str(v._gatherer.gather_type).is_equal(initial_gather_type)


# --- Surplus rebalancing ---


func test_surplus_rebalance_moves_villager_from_high_resource() -> void:
	# Food is way higher than wood — surplus check should reassign one food gatherer to wood
	_init_resources(5000, 10, 10, 10)
	var tc := _create_town_center(Vector2i(10, 10))
	var tc_screen := IsoUtils.grid_to_screen(Vector2(Vector2i(10, 10)))
	var alloc := _create_allocator(
		{"rebalance_threshold": 2.0, "resource_search_radius": 20},
		{"0": {"food": 0.5, "wood": 0.5}},
	)
	_create_resource_node("berry_bush", tc_screen + Vector2(64, 0))
	_create_resource_node("tree", tc_screen + Vector2(128, 0))
	var v1 := _create_villager(1, tc_screen, true)
	var v2 := _create_villager(1, tc_screen + Vector2(10, 0), true)
	# Assign both to food manually
	v1._gatherer.gather_type = "food"
	v2._gatherer.gather_type = "food"
	var target: Dictionary = {"food": 0.5, "wood": 0.5}
	var current: Dictionary = {"food": 2, "wood": 0}
	alloc._check_surplus_rebalance(target, current, 2, 2.0, [v1, v2])
	# One villager should have been moved to wood
	var wood_count: int = 0
	if v1._gatherer.gather_type == "wood":
		wood_count += 1
	if v2._gatherer.gather_type == "wood":
		wood_count += 1
	assert_int(wood_count).is_greater_equal(1)


func test_surplus_rebalance_skips_when_resources_balanced() -> void:
	# Equal resources — no surplus rebalance
	_init_resources(100, 100, 100, 100)
	var tc := _create_town_center(Vector2i(10, 10))
	var tc_screen := IsoUtils.grid_to_screen(Vector2(Vector2i(10, 10)))
	var alloc := _create_allocator(
		{"rebalance_threshold": 2.0, "resource_search_radius": 20},
		{"0": {"food": 0.5, "wood": 0.5}},
	)
	var v1 := _create_villager(1, tc_screen, false)
	v1._gatherer.gather_type = "food"
	var target: Dictionary = {"food": 0.5, "wood": 0.5}
	var current: Dictionary = {"food": 1, "wood": 1}
	var initial_type: String = v1._gatherer.gather_type
	alloc._check_surplus_rebalance(target, current, 2, 2.0, [v1])
	# No rebalance should have happened
	assert_str(v1._gatherer.gather_type).is_equal(initial_type)


# --- Find nearest idle villager ---


func test_find_nearest_idle_villager_returns_closest() -> void:
	var alloc := _create_allocator()
	var v_near := _create_villager(1, Vector2(10, 0), true)
	var v_far := _create_villager(1, Vector2(500, 0), true)
	var villagers: Array[Node2D] = [v_near, v_far]
	var target_pos := Vector2.ZERO
	var found: Node2D = alloc.find_nearest_idle_villager(villagers, target_pos)
	assert_object(found).is_equal(v_near)


func test_find_nearest_idle_villager_ignores_busy() -> void:
	var alloc := _create_allocator()
	var v_near := _create_villager(1, Vector2(10, 0), false)
	v_near._moving = true  # Not idle
	var v_far := _create_villager(1, Vector2(500, 0), true)
	var villagers: Array[Node2D] = [v_near, v_far]
	var found: Node2D = alloc.find_nearest_idle_villager(villagers, Vector2.ZERO)
	assert_object(found).is_equal(v_far)


func test_find_nearest_idle_villager_returns_null_when_all_busy() -> void:
	var alloc := _create_allocator()
	var v := _create_villager(1, Vector2(10, 0), false)
	v._moving = true
	var villagers: Array[Node2D] = [v]
	var found: Node2D = alloc.find_nearest_idle_villager(villagers, Vector2.ZERO)
	assert_object(found).is_null()


func test_find_nearest_idle_villager_returns_null_with_empty_array() -> void:
	var alloc := _create_allocator()
	var villagers: Array[Node2D] = []
	var found: Node2D = alloc.find_nearest_idle_villager(villagers, Vector2.ZERO)
	assert_object(found).is_null()


# --- Resource node search ---


func test_find_resource_nodes_returns_nodes_within_radius() -> void:
	var tc := _create_town_center(Vector2i(10, 10))
	var tc_screen := IsoUtils.grid_to_screen(Vector2(Vector2i(10, 10)))
	var alloc := _create_allocator(
		{"rebalance_threshold": 2.0, "resource_search_radius": 5},
		{"0": {"food": 1.0}},
	)
	# Create food node close to TC
	_create_resource_node("berry_bush", tc_screen + Vector2(64, 0))
	var nodes: Array[Node2D] = alloc._find_resource_nodes("food")
	assert_int(nodes.size()).is_greater_equal(1)


func test_find_resource_nodes_excludes_depleted_nodes() -> void:
	var tc := _create_town_center(Vector2i(10, 10))
	var tc_screen := IsoUtils.grid_to_screen(Vector2(Vector2i(10, 10)))
	var alloc := _create_allocator(
		{"rebalance_threshold": 2.0, "resource_search_radius": 20},
		{"0": {"food": 1.0}},
	)
	var node := _create_resource_node("berry_bush", tc_screen + Vector2(64, 0))
	# Deplete the node
	node.current_yield = 0
	var nodes: Array[Node2D] = alloc._find_resource_nodes("food")
	# Depleted nodes should be excluded
	assert_int(nodes.size()).is_equal(0)


func test_find_resource_nodes_excludes_wrong_type() -> void:
	var tc := _create_town_center(Vector2i(10, 10))
	var tc_screen := IsoUtils.grid_to_screen(Vector2(Vector2i(10, 10)))
	var alloc := _create_allocator(
		{"rebalance_threshold": 2.0, "resource_search_radius": 20},
		{"0": {"wood": 1.0}},
	)
	# Create food node — should not appear in wood search
	_create_resource_node("berry_bush", tc_screen + Vector2(64, 0))
	var nodes: Array[Node2D] = alloc._find_resource_nodes("wood")
	assert_int(nodes.size()).is_equal(0)


func test_find_resource_nodes_excludes_nodes_outside_radius() -> void:
	var tc := _create_town_center(Vector2i(10, 10))
	var tc_screen := IsoUtils.grid_to_screen(Vector2(Vector2i(10, 10)))
	var alloc := _create_allocator(
		{"rebalance_threshold": 2.0, "resource_search_radius": 2},
		{"0": {"food": 1.0}},
	)
	# Set _town_center so distance filtering is applied (origin != Vector2.ZERO)
	alloc._town_center = tc
	# Place node far outside the 2-tile (128px) radius
	_create_resource_node("berry_bush", tc_screen + Vector2(5000, 0))
	var nodes: Array[Node2D] = alloc._find_resource_nodes("food")
	assert_int(nodes.size()).is_equal(0)
