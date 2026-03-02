extends GdUnitTestSuite
## Tests for Dock building production queue — naval unit training with tech gating.

const PQScript := preload("res://scripts/prototype/production_queue.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")


class _MockTechManager:
	extends Node
	## Minimal tech manager mock that tracks researched techs.

	var _researched: Dictionary = {}  # {player_id: Array[String]}

	func is_tech_researched(tech_id: String, player_id: int = 0) -> bool:
		return tech_id in _researched.get(player_id, [])

	func research(tech_id: String, player_id: int = 0) -> void:
		if player_id not in _researched:
			_researched[player_id] = []
		if tech_id not in _researched[player_id]:
			_researched[player_id].append(tech_id)


# --- Helpers ---


func _create_dock() -> Node2D:
	var b := Node2D.new()
	b.set_script(BuildingScript)
	b.building_name = "dock"
	b.owner_id = 0
	b.max_hp = 1800
	b.hp = 1800
	b.under_construction = false
	b.build_progress = 1.0
	b.footprint = Vector2i(3, 3)
	b.grid_pos = Vector2i(4, 4)
	add_child(b)
	return auto_free(b)


func _create_tech_manager() -> _MockTechManager:
	var tm := _MockTechManager.new()
	add_child(tm)
	return auto_free(tm)


func _create_queue(
	building: Node2D = null,
	owner_id: int = 0,
	tech_manager: Node = null,
) -> Node:
	if building == null:
		building = _create_dock()
	var pq := Node.new()
	pq.set_script(PQScript)
	building.add_child(pq)
	pq.setup(building, owner_id, null, tech_manager)
	return auto_free(pq)


func _init_resources(
	food: int = 2000,
	wood: int = 2000,
	gold: int = 2000,
) -> void:
	(
		ResourceManager
		. init_player(
			0,
			{
				ResourceManager.ResourceType.FOOD: food,
				ResourceManager.ResourceType.WOOD: wood,
				ResourceManager.ResourceType.STONE: 2000,
				ResourceManager.ResourceType.GOLD: gold,
				ResourceManager.ResourceType.KNOWLEDGE: 0,
			}
		)
	)


func _get_wood() -> int:
	return ResourceManager.get_amount(0, ResourceManager.ResourceType.WOOD)


func _get_gold() -> int:
	return ResourceManager.get_amount(0, ResourceManager.ResourceType.GOLD)


# --- Dock queues Fishing Boat (requires Sailing tech from tech tree) ---


func test_dock_queues_fishing_boat() -> void:
	_init_resources()
	var tm := _create_tech_manager()
	tm.research("sailing", 0)
	var pq := _create_queue(null, 0, tm)
	assert_bool(pq.add_to_queue("fishing_boat")).is_true()
	assert_int(pq.get_queue().size()).is_equal(1)
	assert_str(pq.get_queue()[0]).is_equal("fishing_boat")


func test_dock_produces_fishing_boat_after_train_time() -> void:
	_init_resources()
	var tm := _create_tech_manager()
	tm.research("sailing", 0)
	var pq := _create_queue(null, 0, tm)
	pq.add_to_queue("fishing_boat")
	var produced: Array[String] = []
	pq.unit_produced.connect(func(ut: String, _b: Node2D) -> void: produced.append(ut))
	# fishing_boat train_time = 25s
	for i in 26:
		pq._process(1.0)
	assert_int(produced.size()).is_equal(1)
	assert_str(produced[0]).is_equal("fishing_boat")


# --- Tech gating: War Galley requires Trireme ---


func test_war_galley_blocked_without_trireme() -> void:
	_init_resources()
	var tm := _create_tech_manager()
	var pq := _create_queue(null, 0, tm)
	# War Galley requires trireme tech — should fail without it
	assert_bool(pq.can_produce("war_galley")).is_false()
	assert_bool(pq.add_to_queue("war_galley")).is_false()
	assert_int(pq.get_queue().size()).is_equal(0)


func test_war_galley_available_with_trireme() -> void:
	_init_resources()
	var tm := _create_tech_manager()
	tm.research("trireme", 0)
	var pq := _create_queue(null, 0, tm)
	assert_bool(pq.can_produce("war_galley")).is_true()
	assert_bool(pq.add_to_queue("war_galley")).is_true()
	assert_int(pq.get_queue().size()).is_equal(1)


# --- Tech gating: Cannon Ship requires Galleon ---


func test_cannon_ship_blocked_without_galleon() -> void:
	_init_resources()
	var tm := _create_tech_manager()
	var pq := _create_queue(null, 0, tm)
	assert_bool(pq.can_produce("cannon_ship")).is_false()
	assert_bool(pq.add_to_queue("cannon_ship")).is_false()


func test_cannon_ship_available_with_galleon() -> void:
	_init_resources()
	var tm := _create_tech_manager()
	tm.research("galleon", 0)
	var pq := _create_queue(null, 0, tm)
	assert_bool(pq.can_produce("cannon_ship")).is_true()
	assert_bool(pq.add_to_queue("cannon_ship")).is_true()


# --- Queue cancel refunds full cost ---


func test_cancel_fishing_boat_refunds_wood() -> void:
	_init_resources(2000, 200, 2000)
	var tm := _create_tech_manager()
	tm.research("sailing", 0)
	var pq := _create_queue(null, 0, tm)
	pq.add_to_queue("fishing_boat")  # costs 75 wood
	assert_int(_get_wood()).is_equal(125)
	pq.cancel_at(0)
	assert_int(_get_wood()).is_equal(200)
	assert_int(pq.get_queue().size()).is_equal(0)


func test_cancel_war_galley_refunds_wood_and_gold() -> void:
	_init_resources(2000, 500, 500)
	var tm := _create_tech_manager()
	tm.research("trireme", 0)
	var pq := _create_queue(null, 0, tm)
	var wood_before := _get_wood()
	var gold_before := _get_gold()
	pq.add_to_queue("war_galley")  # costs 150 wood, 50 gold
	assert_int(_get_wood()).is_equal(wood_before - 150)
	assert_int(_get_gold()).is_equal(gold_before - 50)
	pq.cancel_at(0)
	assert_int(_get_wood()).is_equal(wood_before)
	assert_int(_get_gold()).is_equal(gold_before)


# --- Queue max 5 units ---


func test_dock_queue_max_five_units() -> void:
	_init_resources()
	var tm := _create_tech_manager()
	tm.research("sailing", 0)
	var pq := _create_queue(null, 0, tm)
	for i in 5:
		assert_bool(pq.add_to_queue("fishing_boat")).is_true()
	# 6th should fail
	assert_bool(pq.add_to_queue("fishing_boat")).is_false()
	assert_int(pq.get_queue().size()).is_equal(5)


# --- All 5 naval unit types can be queued ---


func test_dock_can_queue_all_naval_units() -> void:
	_init_resources(5000, 5000, 5000)
	var tm := _create_tech_manager()
	# Unlock all naval techs
	tm.research("sailing", 0)
	tm.research("trireme", 0)
	tm.research("galleon", 0)
	var pq := _create_queue(null, 0, tm)
	var naval_units: Array[String] = [
		"fishing_boat",
		"transport_ship",
		"war_galley",
		"merchant_ship",
		"cannon_ship",
	]
	for unit_type in naval_units:
		assert_bool(pq.can_produce(unit_type)).is_true()


# --- Cancel all refunds everything ---


func test_cancel_all_refunds_dock_units() -> void:
	_init_resources(2000, 2000, 2000)
	var tm := _create_tech_manager()
	tm.research("sailing", 0)
	var pq := _create_queue(null, 0, tm)
	var wood_before := _get_wood()
	for i in 3:
		pq.add_to_queue("fishing_boat")
	# 3 * 75 wood spent = 225
	assert_int(_get_wood()).is_equal(wood_before - 225)
	pq.cancel_all()
	assert_int(_get_wood()).is_equal(wood_before)
	assert_int(pq.get_queue().size()).is_equal(0)
