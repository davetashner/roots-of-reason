extends GdUnitTestSuite
## Tests for scripts/prototype/production_queue.gd — unit production queue system.

const PQScript := preload("res://scripts/prototype/production_queue.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")
const PopManagerScript := preload("res://scripts/prototype/population_manager.gd")

# --- Helpers ---


func _create_building(bname: String = "town_center") -> Node2D:
	var b := Node2D.new()
	b.set_script(BuildingScript)
	b.building_name = bname
	b.owner_id = 0
	b.max_hp = 2400
	b.hp = 2400
	b.under_construction = false
	b.build_progress = 1.0
	b.footprint = Vector2i(3, 3)
	b.grid_pos = Vector2i(4, 4)
	add_child(b)
	return auto_free(b)


func _create_pop_manager(starting_cap: int = 200, hard_cap: int = 200) -> Node:
	var mgr := Node.new()
	mgr.set_script(PopManagerScript)
	add_child(mgr)
	mgr._starting_cap = starting_cap
	mgr._hard_cap = hard_cap
	return auto_free(mgr)


func _create_queue(
	building: Node2D = null,
	owner_id: int = 0,
	pop_manager: Node = null,
) -> Node:
	if building == null:
		building = _create_building()
	var pq := Node.new()
	pq.set_script(PQScript)
	building.add_child(pq)
	pq.setup(building, owner_id, pop_manager)
	return auto_free(pq)


func _init_resources(food: int = 1000, wood: int = 1000, gold: int = 1000) -> void:
	(
		ResourceManager
		. init_player(
			0,
			{
				ResourceManager.ResourceType.FOOD: food,
				ResourceManager.ResourceType.WOOD: wood,
				ResourceManager.ResourceType.STONE: 1000,
				ResourceManager.ResourceType.GOLD: gold,
				ResourceManager.ResourceType.KNOWLEDGE: 0,
			}
		)
	)


func _get_food() -> int:
	return ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)


func _get_gold() -> int:
	return ResourceManager.get_amount(0, ResourceManager.ResourceType.GOLD)


# --- Queue add / size ---


func test_add_to_queue_increases_queue_size() -> void:
	_init_resources()
	var pq := _create_queue()
	assert_bool(pq.add_to_queue("villager")).is_true()
	assert_int(pq.get_queue().size()).is_equal(1)


func test_add_to_queue_spends_resources() -> void:
	_init_resources(200)
	var pq := _create_queue()
	pq.add_to_queue("villager")  # costs 50 food
	assert_int(_get_food()).is_equal(150)


func test_queue_limit_enforced() -> void:
	_init_resources()
	var pq := _create_queue()
	for i in 5:
		assert_bool(pq.add_to_queue("villager")).is_true()
	# 6th should fail
	assert_bool(pq.add_to_queue("villager")).is_false()
	assert_int(pq.get_queue().size()).is_equal(5)


func test_add_fails_when_cannot_afford() -> void:
	_init_resources(10)  # only 10 food, villager costs 50
	var pq := _create_queue()
	assert_bool(pq.add_to_queue("villager")).is_false()
	assert_int(pq.get_queue().size()).is_equal(0)


func test_add_fails_for_wrong_building() -> void:
	_init_resources()
	var building := _create_building("town_center")
	var pq := _create_queue(building)
	# Town center does not produce infantry
	assert_bool(pq.add_to_queue("infantry")).is_false()


# --- Cancel / refund ---


func test_cancel_refunds_resources() -> void:
	_init_resources(200)
	var pq := _create_queue()
	pq.add_to_queue("villager")  # costs 50 food
	assert_int(_get_food()).is_equal(150)
	pq.cancel_at(0)
	assert_int(_get_food()).is_equal(200)


func test_cancel_removes_from_queue() -> void:
	_init_resources()
	var pq := _create_queue()
	pq.add_to_queue("villager")
	pq.add_to_queue("villager")
	pq.cancel_at(1)
	assert_int(pq.get_queue().size()).is_equal(1)


func test_cancel_all_refunds_everything() -> void:
	_init_resources(500)
	var pq := _create_queue()
	for i in 3:
		pq.add_to_queue("villager")
	# 3 * 50 = 150 spent, 350 remaining
	assert_int(_get_food()).is_equal(350)
	pq.cancel_all()
	assert_int(_get_food()).is_equal(500)
	assert_int(pq.get_queue().size()).is_equal(0)


# --- Production timing ---


func test_production_completes_after_time() -> void:
	_init_resources()
	var pq := _create_queue()
	pq.add_to_queue("villager")
	# Villager train_time = 20s. Simulate enough _process calls.
	var produced_types: Array[String] = []
	pq.unit_produced.connect(func(ut: String, _b: Node2D) -> void: produced_types.append(ut))
	for i in 21:
		pq._process(1.0)
	assert_int(produced_types.size()).is_equal(1)
	assert_str(produced_types[0]).is_equal("villager")


func test_unit_produced_signal_emitted() -> void:
	_init_resources()
	var pq := _create_queue()
	var produced_buildings: Array = []
	pq.unit_produced.connect(func(ut: String, b: Node2D) -> void: produced_buildings.append([ut, b]))
	pq.add_to_queue("villager")
	# Advance past train_time (20s)
	for i in 21:
		pq._process(1.0)
	assert_int(produced_buildings.size()).is_equal(1)
	assert_str(produced_buildings[0][0]).is_equal("villager")
	assert_object(produced_buildings[0][1]).is_same(pq._building)


func test_queue_auto_starts_next() -> void:
	_init_resources()
	var pq := _create_queue()
	pq.add_to_queue("villager")
	pq.add_to_queue("villager")
	# Complete first (20s train time)
	for i in 21:
		pq._process(1.0)
	# Queue should now have 1 remaining, progress should be near 0
	assert_int(pq.get_queue().size()).is_equal(1)
	assert_float(pq.get_progress()).is_less(0.1)


# --- Progress ---


func test_progress_resets_between_units() -> void:
	_init_resources()
	var pq := _create_queue()
	pq.add_to_queue("villager")
	pq.add_to_queue("villager")
	# Complete first unit
	for i in 21:
		pq._process(1.0)
	# Progress for second unit should be near start
	assert_float(pq.get_progress()).is_less(0.1)


func test_get_progress_returns_ratio() -> void:
	_init_resources()
	var pq := _create_queue()
	pq.add_to_queue("villager")
	# Advance half the train time (10s out of 20s)
	for i in 10:
		pq._process(1.0)
	var progress: float = pq.get_progress()
	# Should be approximately 10/20 = 0.5
	assert_float(progress).is_greater(0.4)
	assert_float(progress).is_less(0.6)


# --- Pop cap pausing ---


func test_pop_cap_pauses_production() -> void:
	_init_resources()
	var pop_mgr := _create_pop_manager(1)  # cap of 1
	# Register 1 unit to fill cap
	var dummy := Node2D.new()
	add_child(dummy)
	auto_free(dummy)
	pop_mgr.register_unit(dummy, 0)
	var pq := _create_queue(null, 0, pop_mgr)
	pq.add_to_queue("villager")
	# Process should not advance (paused at pop cap)
	pq._process(1.0)
	assert_bool(pq.is_paused()).is_true()


func test_pop_cap_resumes_when_freed() -> void:
	_init_resources()
	var pop_mgr := _create_pop_manager(1)
	var dummy := Node2D.new()
	add_child(dummy)
	auto_free(dummy)
	pop_mgr.register_unit(dummy, 0)
	var pq := _create_queue(null, 0, pop_mgr)
	pq.add_to_queue("villager")
	pq._process(1.0)
	assert_bool(pq.is_paused()).is_true()
	# Free the slot
	pop_mgr.unregister_unit(dummy, 0)
	pq._process(1.0)
	assert_bool(pq.is_paused()).is_false()


# --- Empty queue ---


func test_empty_queue_does_nothing() -> void:
	_init_resources()
	var pq := _create_queue()
	# Should not error
	pq._process(1.0)
	assert_int(pq.get_queue().size()).is_equal(0)
	assert_float(pq.get_progress()).is_equal(0.0)


# --- Save / Load ---


func test_save_load_preserves_queue() -> void:
	_init_resources()
	var pq := _create_queue()
	pq.add_to_queue("villager")
	pq.add_to_queue("villager")
	var state: Dictionary = pq.save_state()
	# Create a fresh queue and load state
	var pq2 := _create_queue()
	pq2.load_state(state)
	assert_int(pq2.get_queue().size()).is_equal(2)
	assert_str(pq2.get_queue()[0]).is_equal("villager")


func test_save_load_preserves_progress() -> void:
	_init_resources()
	var pq := _create_queue()
	pq.add_to_queue("villager")
	# Advance 10 seconds
	for i in 10:
		pq._process(1.0)
	var state: Dictionary = pq.save_state()
	var pq2 := _create_queue()
	pq2.load_state(state)
	# Progress should be approximately 10/20 = 0.5
	assert_float(pq2._progress).is_greater(9.0)
	assert_float(pq2._current_train_time).is_greater(0.0)
