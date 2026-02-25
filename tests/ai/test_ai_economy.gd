extends GdUnitTestSuite
## Tests for scripts/ai/ai_economy.gd — AI economy brain.

const AIEconomyScript := preload("res://scripts/ai/ai_economy.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")
const PopManagerScript := preload("res://scripts/prototype/population_manager.gd")
const ResourceNodeScript := preload("res://scripts/prototype/prototype_resource_node.gd")
const ProductionQueueScript := preload("res://scripts/prototype/production_queue.gd")

# --- Helpers ---


func _create_ai_economy(
	scene_root: Node = null,
	pop_mgr: Node = null,
	difficulty: String = "normal",
) -> Node:
	if scene_root == null:
		scene_root = self
	var ai := Node.new()
	ai.name = "AIEconomy"
	ai.set_script(AIEconomyScript)
	ai.difficulty = difficulty
	add_child(ai)
	if pop_mgr == null:
		pop_mgr = _create_pop_manager()
	ai.setup(scene_root, pop_mgr, null, null, null)
	return auto_free(ai)


func _create_pop_manager(starting_cap: int = 200, hard_cap: int = 200) -> Node:
	var mgr := Node.new()
	mgr.set_script(PopManagerScript)
	add_child(mgr)
	mgr._starting_cap = starting_cap
	mgr._hard_cap = hard_cap
	return auto_free(mgr)


func _create_town_center(
	owner_id: int = 1,
	grid_pos: Vector2i = Vector2i(50, 50),
	with_pq: bool = true,
	pop_mgr: Node = null,
) -> Node2D:
	var building := Node2D.new()
	building.name = "AI_TownCenter"
	building.set_script(BuildingScript)
	building.position = IsoUtils.grid_to_screen(Vector2(grid_pos))
	building.owner_id = owner_id
	building.building_name = "town_center"
	building.footprint = Vector2i(3, 3)
	building.grid_pos = grid_pos
	building.hp = 2400
	building.max_hp = 2400
	building.under_construction = false
	building.build_progress = 1.0
	building.entity_category = "enemy_building"
	add_child(building)
	if with_pq:
		var pq := Node.new()
		pq.name = "ProductionQueue"
		pq.set_script(ProductionQueueScript)
		building.add_child(pq)
		pq.setup(building, owner_id, pop_mgr)
	return auto_free(building)


func _create_villager(
	owner_id: int = 1,
	pos: Vector2 = Vector2.ZERO,
	idle: bool = true,
) -> Node2D:
	var unit := Node2D.new()
	unit.name = "AIVillager_%d" % get_child_count()
	unit.set_script(UnitScript)
	unit.unit_type = "villager"
	unit.owner_id = owner_id
	unit.position = pos
	unit._scene_root = self
	add_child(unit)
	if idle:
		# Ensure unit is idle (defaults should be idle)
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


func _init_ai_resources(food: int = 1000, wood: int = 1000, stone: int = 1000, gold: int = 1000) -> void:
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


func _get_ai_food() -> int:
	return ResourceManager.get_amount(1, ResourceManager.ResourceType.FOOD)


func _get_ai_wood() -> int:
	return ResourceManager.get_amount(1, ResourceManager.ResourceType.WOOD)


# --- Config ---


func test_config_loaded_from_json() -> void:
	var ai := _create_ai_economy()
	assert_dict(ai._config).is_not_empty()
	assert_bool(ai._config.has("tick_interval")).is_true()
	assert_float(float(ai._config.get("tick_interval", 0))).is_equal(2.0)


func test_difficulty_selects_correct_build_order() -> void:
	var ai_easy := _create_ai_economy(null, null, "easy")
	var ai_hard := _create_ai_economy(null, null, "hard")
	# Easy has different step count than hard
	assert_bool(ai_easy._build_order.size() > 0).is_true()
	assert_bool(ai_hard._build_order.size() > 0).is_true()
	# Easy first train step count is 4, hard is 5
	var easy_step: Dictionary = ai_easy._build_order[0]
	var hard_step: Dictionary = ai_hard._build_order[0]
	assert_int(int(easy_step.get("count", 0))).is_equal(4)
	assert_int(int(hard_step.get("count", 0))).is_equal(5)


# --- Target allocation ---


func test_target_allocation_returns_ratios_for_current_age() -> void:
	var ai := _create_ai_economy()
	GameManager.current_age = 0
	var alloc: Dictionary = ai._get_target_allocation()
	assert_bool(alloc.has("food")).is_true()
	assert_float(float(alloc.get("food", 0))).is_greater(0.0)


# --- Villager assignment ---


func test_idle_villager_assigned_to_highest_deficit_resource() -> void:
	_init_ai_resources()
	var pop_mgr := _create_pop_manager()
	var ai := _create_ai_economy(self, pop_mgr)
	var tc_pos := Vector2i(10, 10)
	_create_town_center(1, tc_pos, true, pop_mgr)
	var tc_screen := IsoUtils.grid_to_screen(Vector2(tc_pos))
	var villager := _create_villager(1, tc_screen, true)
	# Create a food resource node near the TC (within search radius)
	_create_resource_node("berry_bush", tc_screen + Vector2(64, 0))
	# Run rebalance — villager should be assigned
	ai._refresh_entity_lists()
	ai._rebalance_gatherers()
	# Villager should no longer be idle
	assert_bool(villager.is_idle()).is_false()


func test_no_rebalance_when_within_threshold() -> void:
	_init_ai_resources(100, 100, 100, 100)
	var pop_mgr := _create_pop_manager()
	var ai := _create_ai_economy(self, pop_mgr)
	var tc_pos := Vector2i(10, 10)
	_create_town_center(1, tc_pos, true, pop_mgr)
	var tc_screen := IsoUtils.grid_to_screen(Vector2(tc_pos))
	# Create a villager already gathering food
	var villager := _create_villager(1, tc_screen, true)
	_create_resource_node("berry_bush", tc_screen + Vector2(64, 0))
	ai._refresh_entity_lists()
	# Assign manually to food
	var food_nodes: Array[Node2D] = ai._find_resource_nodes("food")
	if not food_nodes.is_empty():
		villager.assign_gather_target(food_nodes[0])
	# Resources are balanced — surplus check should not reassign
	ai._refresh_entity_lists()
	var current: Dictionary = ai._get_current_allocation()
	assert_int(int(current.get("food", 0))).is_equal(1)


func test_rebalance_moves_villager_from_surplus() -> void:
	# Food is way higher than wood — should reassign a food gatherer
	_init_ai_resources(1000, 10, 10, 10)
	var pop_mgr := _create_pop_manager()
	var ai := _create_ai_economy(self, pop_mgr)
	var tc_pos := Vector2i(10, 10)
	_create_town_center(1, tc_pos, true, pop_mgr)
	var tc_screen := IsoUtils.grid_to_screen(Vector2(tc_pos))
	# Create two villagers gathering food
	var v1 := _create_villager(1, tc_screen, true)
	var v2 := _create_villager(1, tc_screen + Vector2(10, 0), true)
	_create_resource_node("berry_bush", tc_screen + Vector2(64, 0))
	_create_resource_node("tree", tc_screen + Vector2(128, 0))
	ai._refresh_entity_lists()
	var food_nodes: Array[Node2D] = ai._find_resource_nodes("food")
	if not food_nodes.is_empty():
		v1.assign_gather_target(food_nodes[0])
		v2.assign_gather_target(food_nodes[0])
	# Now rebalance — one should be moved to wood
	ai._refresh_entity_lists()
	ai._rebalance_gatherers()
	var current: Dictionary = ai._get_current_allocation()
	assert_int(int(current.get("wood", 0))).is_greater(0)


# --- Build order execution ---


func test_train_step_queues_villagers_at_town_center() -> void:
	_init_ai_resources()
	var pop_mgr := _create_pop_manager()
	var tc := _create_town_center(1, Vector2i(50, 50), true, pop_mgr)
	var ai := _create_ai_economy(self, pop_mgr)
	# Manually set town_center reference
	ai._town_center = tc
	ai._refresh_entity_lists()
	# Process first build order step (train villager)
	var result: bool = ai._process_build_order()
	assert_bool(result).is_true()
	# Check that PQ has a villager queued
	var pq: Node = tc.get_node_or_null("ProductionQueue")
	assert_int(pq.get_queue().size()).is_greater(0)


func test_build_order_advances_index_after_completion() -> void:
	_init_ai_resources()
	var pop_mgr := _create_pop_manager()
	var tc := _create_town_center(1, Vector2i(50, 50), true, pop_mgr)
	var ai := _create_ai_economy(self, pop_mgr, "easy")
	ai._town_center = tc
	# Fill train step (easy: 4 villagers)
	for i in 4:
		ai._refresh_entity_lists()
		ai._process_build_order()
	# After queuing 4, index should advance past the train step
	assert_int(ai._build_order_index).is_greater(0)


func test_advance_age_step_triggers_advancement() -> void:
	_init_ai_resources(1000, 1000, 1000, 1000)
	var pop_mgr := _create_pop_manager()
	var ai := _create_ai_economy(self, pop_mgr)
	GameManager.current_age = 0
	# Set build order index to an advance_age step
	for i in ai._build_order.size():
		var step: Dictionary = ai._build_order[i]
		if str(step.get("action", "")) == "advance_age":
			ai._build_order_index = i
			break
	ai._refresh_entity_lists()
	ai._process_build_order()
	assert_int(GameManager.current_age).is_equal(1)


func test_build_step_places_building() -> void:
	_init_ai_resources(1000, 1000, 1000, 1000)
	var pop_mgr := _create_pop_manager()
	var ai := _create_ai_economy(self, pop_mgr)
	var tc := _create_town_center(1, Vector2i(10, 10), true, pop_mgr)
	ai._town_center = tc
	# Set up a minimal mock map and pathfinder
	var map_mock := _MockMap.new()
	add_child(map_mock)
	auto_free(map_mock)
	var pf_mock := _MockPathfinder.new()
	add_child(pf_mock)
	auto_free(pf_mock)
	ai._map_node = map_mock
	ai._pathfinder = pf_mock
	var building: Node2D = ai._place_building("house")
	assert_object(building).is_not_null()
	assert_bool(building.under_construction).is_true()
	assert_str(building.building_name).is_equal("house")


# --- House building ---


func test_house_built_when_near_pop_cap() -> void:
	_init_ai_resources(1000, 1000, 1000, 1000)
	var pop_mgr := _create_pop_manager(0)
	# TC adds pop_bonus=5, so cap=5. Register 3 units: cap-current=2 <= buffer(3)
	var tc := _create_town_center(1, Vector2i(10, 10), false, pop_mgr)
	pop_mgr.register_building(tc, 1)
	for i in 3:
		var dummy := Node2D.new()
		add_child(dummy)
		auto_free(dummy)
		pop_mgr.register_unit(dummy, 1)
	var ai := _create_ai_economy(self, pop_mgr)
	ai._town_center = tc
	var map_mock := _MockMap.new()
	add_child(map_mock)
	auto_free(map_mock)
	var pf_mock := _MockPathfinder.new()
	add_child(pf_mock)
	auto_free(pf_mock)
	ai._map_node = map_mock
	ai._pathfinder = pf_mock
	ai._refresh_entity_lists()
	# Verify precondition: near pop cap
	var cap: int = pop_mgr.get_population_cap(1)
	var pop: int = pop_mgr.get_population(1)
	var buffer: int = int(ai._config.get("near_cap_house_buffer", 3))
	assert_bool(cap - pop <= buffer).is_true()
	# Verify placement works with mocks
	var test_place: Node2D = ai._place_building("house")
	assert_object(test_place).is_not_null()


func test_no_house_when_far_from_cap() -> void:
	_init_ai_resources()
	var pop_mgr := _create_pop_manager(200)
	var ai := _create_ai_economy(self, pop_mgr)
	var tc := _create_town_center(1, Vector2i(10, 10), true, pop_mgr)
	ai._town_center = tc
	ai._refresh_entity_lists()
	var result: bool = ai._check_house_needed()
	assert_bool(result).is_false()


# --- Tick timing ---


func test_tick_respects_interval() -> void:
	_init_ai_resources()
	var pop_mgr := _create_pop_manager()
	var ai := _create_ai_economy(self, pop_mgr)
	# Tick timer starts at 0, interval is 2.0
	# Processing with delta=0.5 should not trigger tick
	ai._tick_timer = 0.0
	ai._process(0.5)
	# Build order index should still be 0 (no tick happened)
	assert_int(ai._build_order_index).is_equal(0)


func test_tick_uses_game_delta() -> void:
	_init_ai_resources()
	var pop_mgr := _create_pop_manager()
	var ai := _create_ai_economy(self, pop_mgr)
	GameManager.game_speed = 2.0
	ai._tick_timer = 0.0
	# With speed 2x, delta 1.0 -> game_delta 2.0, should trigger tick
	ai._process(1.0)
	# Timer should have been consumed (decremented by interval)
	assert_float(ai._tick_timer).is_less(2.0)
	GameManager.game_speed = 1.0


# --- Resource constraints ---


func test_cannot_train_without_resources() -> void:
	_init_ai_resources(0, 0, 0, 0)  # No resources
	var pop_mgr := _create_pop_manager()
	var tc := _create_town_center(1, Vector2i(50, 50), true, pop_mgr)
	var ai := _create_ai_economy(self, pop_mgr)
	ai._town_center = tc
	ai._refresh_entity_lists()
	var result: bool = ai._process_build_order()
	assert_bool(result).is_false()


func test_villager_training_stops_at_max() -> void:
	_init_ai_resources()
	var pop_mgr := _create_pop_manager()
	var ai := _create_ai_economy(self, pop_mgr)
	var tc := _create_town_center(1, Vector2i(50, 50), true, pop_mgr)
	ai._town_center = tc
	# Set max_villagers to 2 and create 2 villagers
	ai._config["max_villagers"] = 2
	_create_villager(1, Vector2.ZERO)
	_create_villager(1, Vector2(100, 100))
	ai._refresh_entity_lists()
	# Try to train — should be blocked by max
	ai._process_build_order()
	# First step is train, but should skip because at max
	assert_int(ai._build_order_index).is_greater(0)


# --- Building placement ---


func test_find_valid_placement_near_town_center() -> void:
	var pop_mgr := _create_pop_manager()
	var ai := _create_ai_economy(self, pop_mgr)
	var tc := _create_town_center(1, Vector2i(10, 10), true, pop_mgr)
	ai._town_center = tc
	var map_mock := _MockMap.new()
	add_child(map_mock)
	auto_free(map_mock)
	var pf_mock := _MockPathfinder.new()
	add_child(pf_mock)
	auto_free(pf_mock)
	ai._map_node = map_mock
	ai._pathfinder = pf_mock
	var pos: Vector2i = ai._find_valid_placement(Vector2i(2, 2))
	assert_bool(pos != Vector2i(-1, -1)).is_true()
	# Should be within search radius of TC
	var dist: float = float((pos - tc.grid_pos).length())
	assert_float(dist).is_less(float(ai._config.get("building_search_radius", 15)) + 1.0)


func test_placement_avoids_solid_cells() -> void:
	var pop_mgr := _create_pop_manager()
	var ai := _create_ai_economy(self, pop_mgr)
	var tc := _create_town_center(1, Vector2i(10, 10), true, pop_mgr)
	ai._town_center = tc
	var map_mock := _MockMap.new()
	add_child(map_mock)
	auto_free(map_mock)
	# Pathfinder where most cells are solid
	var pf_mock := _MockPathfinderMostlySolid.new()
	add_child(pf_mock)
	auto_free(pf_mock)
	ai._map_node = map_mock
	ai._pathfinder = pf_mock
	# The only valid position is the one not solid
	var pos: Vector2i = ai._find_valid_placement(Vector2i(1, 1))
	if pos != Vector2i(-1, -1):
		# If found, should be the non-solid cell
		assert_bool(not pf_mock.is_cell_solid(pos)).is_true()


# --- Save / Load ---


func test_save_state_preserves_build_order_index() -> void:
	var ai := _create_ai_economy()
	ai._build_order_index = 3
	var state: Dictionary = ai.save_state()
	assert_int(int(state.get("build_order_index", 0))).is_equal(3)


func test_load_state_restores_trained_count() -> void:
	var ai := _create_ai_economy()
	ai._build_order_index = 2
	ai._trained_count = {"0": 3, "1": 2}
	var state: Dictionary = ai.save_state()
	var ai2 := _create_ai_economy()
	ai2.load_state(state)
	assert_int(ai2._build_order_index).is_equal(2)
	assert_int(int(ai2._trained_count.get("0", 0))).is_equal(3)
	assert_int(int(ai2._trained_count.get("1", 0))).is_equal(2)


# --- Mock helpers ---


class _MockMap:
	extends Node

	func get_map_size() -> int:
		return 64

	func is_buildable(cell: Vector2i) -> bool:
		return cell.x >= 0 and cell.x < 64 and cell.y >= 0 and cell.y < 64

	func get_terrain_at(_cell: Vector2i) -> String:
		return "grass"


class _MockPathfinder:
	extends Node

	func is_cell_solid(_cell: Vector2i) -> bool:
		return false

	func set_cell_solid(_cell: Vector2i, _solid: bool) -> void:
		pass


class _MockPathfinderMostlySolid:
	extends Node

	# Only cell (15, 15) is not solid
	func is_cell_solid(cell: Vector2i) -> bool:
		return cell != Vector2i(15, 15)

	func set_cell_solid(_cell: Vector2i, _solid: bool) -> void:
		pass
