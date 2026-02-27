extends GdUnitTestSuite
## Tests for EventBus autoload singleton.


func before_test() -> void:
	EventBus.reset()


func after_test() -> void:
	EventBus.reset()


# --- Signal emission tests ---


func test_resource_changed_signal_emitted() -> void:
	var received: Array = []
	EventBus.resource_changed.connect(
		func(pid: int, rtype: String, old_val: int, new_val: int) -> void:
			received.append({"pid": pid, "type": rtype, "old": old_val, "new": new_val})
	)
	EventBus.emit_resource_changed(0, "Food", 100, 150)
	assert_int(received.size()).is_equal(1)
	assert_int(received[0]["pid"]).is_equal(0)
	assert_str(received[0]["type"]).is_equal("Food")
	assert_int(received[0]["old"]).is_equal(100)
	assert_int(received[0]["new"]).is_equal(150)


func test_unit_spawned_signal_emitted() -> void:
	var received: Array = []
	EventBus.unit_spawned.connect(
		func(unit: Node2D, owner_id: int, unit_type: String) -> void:
			received.append({"unit": unit, "owner": owner_id, "type": unit_type})
	)
	var mock_unit := Node2D.new()
	add_child(mock_unit)
	EventBus.emit_unit_spawned(mock_unit, 0, "villager")
	assert_int(received.size()).is_equal(1)
	assert_int(received[0]["owner"]).is_equal(0)
	assert_str(received[0]["type"]).is_equal("villager")
	mock_unit.queue_free()


func test_unit_died_signal_emitted() -> void:
	var received: Array = []
	EventBus.unit_died.connect(
		func(unit: Node2D, killer: Node2D, owner_id: int) -> void:
			received.append({"unit": unit, "killer": killer, "owner": owner_id})
	)
	var mock_unit := Node2D.new()
	var mock_killer := Node2D.new()
	add_child(mock_unit)
	add_child(mock_killer)
	EventBus.emit_unit_died(mock_unit, mock_killer, 1)
	assert_int(received.size()).is_equal(1)
	assert_int(received[0]["owner"]).is_equal(1)
	mock_unit.queue_free()
	mock_killer.queue_free()


func test_tech_completed_signal_emitted() -> void:
	var received: Array = []
	EventBus.tech_completed.connect(
		func(pid: int, tid: String, effects: Dictionary) -> void:
			received.append({"pid": pid, "tid": tid, "effects": effects})
	)
	EventBus.emit_tech_completed(0, "bronze_working", {"attack_bonus": 2})
	assert_int(received.size()).is_equal(1)
	assert_str(received[0]["tid"]).is_equal("bronze_working")


func test_building_placed_signal_emitted() -> void:
	var received: Array = []
	EventBus.building_placed.connect(
		func(building: Node2D, owner_id: int, building_type: String) -> void:
			received.append({"building": building, "owner": owner_id, "type": building_type})
	)
	var mock_building := Node2D.new()
	add_child(mock_building)
	EventBus.emit_building_placed(mock_building, 0, "barracks")
	assert_int(received.size()).is_equal(1)
	assert_str(received[0]["type"]).is_equal("barracks")
	mock_building.queue_free()


func test_victory_condition_met_signal_emitted() -> void:
	var received: Array = []
	EventBus.victory_condition_met.connect(
		func(pid: int, condition: String) -> void: received.append({"pid": pid, "condition": condition})
	)
	EventBus.emit_victory_condition_met(0, "singularity")
	assert_int(received.size()).is_equal(1)
	assert_str(received[0]["condition"]).is_equal("singularity")


func test_knowledge_burned_signal_emitted() -> void:
	var received: Array = []
	EventBus.knowledge_burned.connect(
		func(attacker_id: int, defender_id: int, regressed_techs: Array) -> void:
			received.append({"attacker": attacker_id, "defender": defender_id, "techs": regressed_techs})
	)
	EventBus.emit_knowledge_burned(1, 0, ["bronze_working", "iron_smelting"])
	assert_int(received.size()).is_equal(1)
	assert_int(received[0]["attacker"]).is_equal(1)
	assert_array(received[0]["techs"]).has_size(2)


# --- Event logging tests ---


func test_event_log_records_events() -> void:
	EventBus.emit_resource_changed(0, "Food", 0, 100)
	EventBus.emit_unit_spawned(Node2D.new(), 0, "villager")
	var log: Array[Dictionary] = EventBus.get_event_log()
	assert_int(log.size()).is_equal(2)
	assert_str(log[0]["event"]).is_equal("resource_changed")
	assert_str(log[1]["event"]).is_equal("unit_spawned")


func test_event_log_respects_max_size() -> void:
	for i in range(EventBus.MAX_LOG_SIZE + 50):
		EventBus.emit_resource_changed(0, "Food", i, i + 1)
	var log: Array[Dictionary] = EventBus.get_event_log()
	assert_int(log.size()).is_equal(EventBus.MAX_LOG_SIZE)


func test_clear_event_log() -> void:
	EventBus.emit_resource_changed(0, "Wood", 0, 50)
	EventBus.clear_event_log()
	assert_int(EventBus.get_event_log().size()).is_equal(0)


func test_get_events_by_type() -> void:
	EventBus.emit_resource_changed(0, "Food", 0, 100)
	EventBus.emit_unit_spawned(Node2D.new(), 0, "villager")
	EventBus.emit_resource_changed(0, "Wood", 0, 50)
	var resource_events: Array[Dictionary] = EventBus.get_events_by_type("resource_changed")
	assert_int(resource_events.size()).is_equal(2)
	var unit_events: Array[Dictionary] = EventBus.get_events_by_type("unit_spawned")
	assert_int(unit_events.size()).is_equal(1)


func test_event_log_contains_timestamp() -> void:
	EventBus.emit_resource_changed(0, "Gold", 0, 25)
	var log: Array[Dictionary] = EventBus.get_event_log()
	assert_bool(log[0].has("time")).is_true()
	assert_bool(log[0]["time"] is int or log[0]["time"] is float).is_true()


# --- Debug logging toggle ---


func test_debug_logging_default_off() -> void:
	assert_bool(EventBus.debug_logging).is_false()


func test_debug_logging_can_be_toggled() -> void:
	EventBus.debug_logging = true
	assert_bool(EventBus.debug_logging).is_true()
	EventBus.debug_logging = false
	assert_bool(EventBus.debug_logging).is_false()


# --- Save/Load ---


func test_save_state() -> void:
	EventBus.debug_logging = true
	var state: Dictionary = EventBus.save_state()
	assert_bool(state["debug_logging"]).is_true()


func test_load_state() -> void:
	EventBus.load_state({"debug_logging": true})
	assert_bool(EventBus.debug_logging).is_true()


func test_reset_clears_state() -> void:
	EventBus.debug_logging = true
	EventBus.emit_resource_changed(0, "Food", 0, 100)
	EventBus.reset()
	assert_bool(EventBus.debug_logging).is_false()
	assert_int(EventBus.get_event_log().size()).is_equal(0)


# --- ResourceManager relay ---


func test_resource_manager_relay() -> void:
	## Verify that ResourceManager.resources_changed is relayed through EventBus.
	var received: Array = []
	EventBus.resource_changed.connect(
		func(pid: int, rtype: String, old_val: int, new_val: int) -> void:
			received.append({"pid": pid, "type": rtype, "old": old_val, "new": new_val})
	)
	ResourceManager.init_player(99, {ResourceManager.ResourceType.FOOD: 0})
	ResourceManager.add_resource(99, ResourceManager.ResourceType.FOOD, 50)
	# The relay fires once from ResourceManager -> EventBus
	var food_events: Array = received.filter(func(e: Dictionary) -> bool: return e["type"] == "Food" and e["pid"] == 99)
	assert_bool(food_events.size() >= 1).is_true()
	ResourceManager.reset()
