extends GdUnitTestSuite
## Tests for river_transport.gd — barge dispatching, routing, pooling, and resource tracking.

const TransportScript := preload("res://scripts/prototype/river_transport.gd")

var _signal_count: int = 0
var _last_resources: Dictionary = {}


func _reset_counter() -> void:
	_signal_count = 0
	_last_resources = {}


func _increment_counter(_barge: Node2D) -> void:
	_signal_count += 1


func _on_destroyed_with_resources(_barge: Node2D, resources: Dictionary) -> void:
	_signal_count += 1
	_last_resources = resources.duplicate()


func _on_arrived_with_resources(_barge: Node2D, resources: Dictionary) -> void:
	_signal_count += 1
	_last_resources = resources.duplicate()


# -- Mock map node with configurable river/flow data --
class MockMap:
	extends Node
	var _river_tiles: Dictionary = {}
	var _flow_directions: Dictionary = {}

	func is_river(pos: Vector2i) -> bool:
		return _river_tiles.has(pos)

	func get_flow_direction(pos: Vector2i) -> Vector2i:
		return _flow_directions.get(pos, Vector2i.ZERO)


# -- Mock building placer with _placed_buildings array --
class MockBuildingPlacer:
	extends Node
	signal building_placed(building: Node2D)
	var _placed_buildings: Array[Dictionary] = []


# -- Mock building (dock or TC) with minimal properties --
class MockBuilding:
	extends Node2D
	signal construction_complete(building: Node2D)
	var building_name: String = ""
	var grid_pos: Vector2i = Vector2i.ZERO
	var owner_id: int = 0
	var is_drop_off: bool = false
	var drop_off_types: Array[String] = []
	var under_construction: bool = false
	var build_progress: float = 1.0
	var hp: int = 0
	var max_hp: int = 0


func _create_dock(gpos: Vector2i, pid: int = 0) -> Node2D:
	var dock := MockBuilding.new()
	dock.building_name = "river_dock"
	dock.grid_pos = gpos
	dock.owner_id = pid
	dock.is_drop_off = true
	dock.drop_off_types = ["food", "wood", "stone", "gold", "knowledge"]
	dock.under_construction = false
	dock.build_progress = 1.0
	dock.hp = 400
	dock.max_hp = 400
	add_child(dock)
	auto_free(dock)
	return dock


func _create_tc(gpos: Vector2i, pid: int = 0) -> Node2D:
	var tc := MockBuilding.new()
	tc.building_name = "town_center"
	tc.grid_pos = gpos
	tc.owner_id = pid
	tc.is_drop_off = true
	tc.drop_off_types = ["food", "wood", "stone", "gold", "knowledge"]
	tc.under_construction = false
	tc.build_progress = 1.0
	tc.hp = 600
	tc.max_hp = 600
	add_child(tc)
	auto_free(tc)
	return tc


func _create_river_chain(start: Vector2i, length: int, direction: Vector2i = Vector2i(0, 1)) -> MockMap:
	## Creates a straight river chain from start in the given direction.
	var mock_map := MockMap.new()
	add_child(mock_map)
	auto_free(mock_map)
	var current := start
	for i in length:
		mock_map._river_tiles[current] = true
		mock_map._flow_directions[current] = direction
		current = current + direction
	# Last tile has no flow (terminus)
	var last := current - direction
	mock_map._flow_directions[last] = Vector2i.ZERO
	return mock_map


func _create_transport(mock_map: MockMap, mock_placer: MockBuildingPlacer) -> Node:
	var transport := Node.new()
	transport.set_script(TransportScript)
	add_child(transport)
	auto_free(transport)
	transport._map_node = mock_map
	transport._building_placer = mock_placer
	# Override config directly for tests
	transport._base_barge_speed = 180.0
	transport._max_downstream_search_depth = 200
	transport._depot_river_proximity = 2
	transport._barge_visual_size = 24.0
	transport._barge_pool_size = 4
	return transport


func _setup_dock_and_tc(_mock_map: MockMap, mock_placer: MockBuildingPlacer) -> Array:
	var dock := _create_dock(Vector2i(4, 0))
	(
		mock_placer
		. _placed_buildings
		. append(
			{
				"building_name": "river_dock",
				"grid_pos": [4, 0],
				"player_id": 0,
				"node": dock,
			}
		)
	)
	var tc := _create_tc(Vector2i(4, 9))
	(
		mock_placer
		. _placed_buildings
		. append(
			{
				"building_name": "town_center",
				"grid_pos": [4, 9],
				"player_id": 0,
				"node": tc,
			}
		)
	)
	return [dock, tc]


func test_find_dock_river_tile_finds_adjacent_river() -> void:
	var mock_map := MockMap.new()
	add_child(mock_map)
	auto_free(mock_map)
	mock_map._river_tiles[Vector2i(5, 4)] = true
	mock_map._flow_directions[Vector2i(5, 4)] = Vector2i(0, 1)

	var mock_placer := MockBuildingPlacer.new()
	add_child(mock_placer)
	auto_free(mock_placer)

	var transport := _create_transport(mock_map, mock_placer)
	var dock := _create_dock(Vector2i(5, 3))
	var river_tile: Vector2i = transport.find_dock_river_tile(dock)
	assert_bool(river_tile != Vector2i(-1, -1)).is_true()
	assert_bool(mock_map.is_river(river_tile)).is_true()


func test_find_dock_river_tile_returns_invalid_when_no_river() -> void:
	var mock_map := MockMap.new()
	add_child(mock_map)
	auto_free(mock_map)

	var mock_placer := MockBuildingPlacer.new()
	add_child(mock_placer)
	auto_free(mock_placer)

	var transport := _create_transport(mock_map, mock_placer)
	var dock := _create_dock(Vector2i(10, 10))
	var river_tile: Vector2i = transport.find_dock_river_tile(dock)
	assert_bool(river_tile == Vector2i(-1, -1)).is_true()


func test_find_downstream_depot_traces_flow() -> void:
	# River flows from (5,0) to (5,9), dock at (4,0), TC at (4,9)
	var mock_map := _create_river_chain(Vector2i(5, 0), 10)
	var mock_placer := MockBuildingPlacer.new()
	add_child(mock_placer)
	auto_free(mock_placer)

	var tc := _create_tc(Vector2i(4, 9))
	(
		mock_placer
		. _placed_buildings
		. append(
			{
				"building_name": "town_center",
				"grid_pos": [4, 9],
				"player_id": 0,
				"node": tc,
			}
		)
	)

	var transport := _create_transport(mock_map, mock_placer)
	# Start search from first river tile (5,0) — should find TC near (5,9)
	var depot: Node2D = transport.find_downstream_depot(Vector2i(5, 0), 0)
	assert_bool(depot != null).is_true()
	assert_str(depot.building_name).is_equal("town_center")


func test_find_downstream_depot_returns_null_when_none() -> void:
	var mock_map := _create_river_chain(Vector2i(5, 0), 10)
	var mock_placer := MockBuildingPlacer.new()
	add_child(mock_placer)
	auto_free(mock_placer)

	var transport := _create_transport(mock_map, mock_placer)
	var depot: Node2D = transport.find_downstream_depot(Vector2i(5, 0), 0)
	assert_bool(depot == null).is_true()


func test_find_downstream_depot_finds_town_center_near_river() -> void:
	var mock_map := _create_river_chain(Vector2i(5, 0), 5)
	var mock_placer := MockBuildingPlacer.new()
	add_child(mock_placer)
	auto_free(mock_placer)

	# TC at (6, 3) — within proximity 2 of river tile (5, 3)
	var tc := _create_tc(Vector2i(6, 3))
	(
		mock_placer
		. _placed_buildings
		. append(
			{
				"building_name": "town_center",
				"grid_pos": [6, 3],
				"player_id": 0,
				"node": tc,
			}
		)
	)

	var transport := _create_transport(mock_map, mock_placer)
	var depot: Node2D = transport.find_downstream_depot(Vector2i(5, 0), 0)
	assert_bool(depot != null).is_true()
	assert_str(depot.building_name).is_equal("town_center")


func test_dispatch_creates_barge_with_queued_resources() -> void:
	var mock_map := _create_river_chain(Vector2i(5, 0), 10)
	var mock_placer := MockBuildingPlacer.new()
	add_child(mock_placer)
	auto_free(mock_placer)

	var entities: Array = _setup_dock_and_tc(mock_map, mock_placer)
	var dock: Node2D = entities[0]

	var transport := _create_transport(mock_map, mock_placer)
	transport.register_dock(dock)
	transport.notify_resource_deposited(dock, 0, 10)  # 10 food

	_reset_counter()
	transport.barge_dispatched.connect(_increment_counter)

	# Advance time past the barge_spawn_interval (5.0s)
	transport._update_dock_timers(6.0)

	assert_int(_signal_count).is_equal(1)
	var active: Array[Node2D] = transport.get_active_barges()
	assert_int(active.size()).is_equal(1)


func test_dispatch_respects_capacity_limit() -> void:
	var mock_map := _create_river_chain(Vector2i(5, 0), 10)
	var mock_placer := MockBuildingPlacer.new()
	add_child(mock_placer)
	auto_free(mock_placer)

	var entities: Array = _setup_dock_and_tc(mock_map, mock_placer)
	var dock: Node2D = entities[0]

	var transport := _create_transport(mock_map, mock_placer)
	transport.register_dock(dock)
	# Queue 50 food — more than capacity of 30
	transport.notify_resource_deposited(dock, 0, 50)

	# Advance time past interval
	transport._update_dock_timers(6.0)

	var barges: Array[Node2D] = transport.get_active_barges()
	assert_int(barges.size()).is_equal(1)
	assert_int(barges[0].total_carried).is_less_equal(30)
	# 20 should remain queued
	var info: Dictionary = transport.get_dock_data()[dock]
	assert_int(info.get("queued_total", 0)).is_equal(20)


func test_dispatch_respects_interval() -> void:
	var mock_map := _create_river_chain(Vector2i(5, 0), 10)
	var mock_placer := MockBuildingPlacer.new()
	add_child(mock_placer)
	auto_free(mock_placer)

	var entities: Array = _setup_dock_and_tc(mock_map, mock_placer)
	var dock: Node2D = entities[0]

	var transport := _create_transport(mock_map, mock_placer)
	transport.register_dock(dock)
	transport.notify_resource_deposited(dock, 0, 10)

	_reset_counter()
	transport.barge_dispatched.connect(_increment_counter)

	# Only 1 second elapsed — should not dispatch (interval is 5.0)
	transport._update_dock_timers(1.0)
	assert_int(_signal_count).is_equal(0)


func test_no_dispatch_without_downstream_depot() -> void:
	var mock_map := _create_river_chain(Vector2i(5, 0), 10)
	var mock_placer := MockBuildingPlacer.new()
	add_child(mock_placer)
	auto_free(mock_placer)

	var dock := _create_dock(Vector2i(4, 0))
	(
		mock_placer
		. _placed_buildings
		. append(
			{
				"building_name": "river_dock",
				"grid_pos": [4, 0],
				"player_id": 0,
				"node": dock,
			}
		)
	)
	# No TC or second dock downstream

	var transport := _create_transport(mock_map, mock_placer)
	transport.register_dock(dock)
	transport.notify_resource_deposited(dock, 0, 10)

	# Advance time past interval
	transport._update_dock_timers(6.0)

	assert_int(transport.get_active_barges().size()).is_equal(0)
	# Resources should remain queued
	var info: Dictionary = transport.get_dock_data()[dock]
	assert_int(info.get("queued_total", 0)).is_equal(10)


func test_register_unregister_dock() -> void:
	var mock_map := MockMap.new()
	add_child(mock_map)
	auto_free(mock_map)
	var mock_placer := MockBuildingPlacer.new()
	add_child(mock_placer)
	auto_free(mock_placer)

	var transport := _create_transport(mock_map, mock_placer)
	var dock := _create_dock(Vector2i(3, 3))

	transport.register_dock(dock)
	assert_int(transport.get_dock_data().size()).is_equal(1)

	transport.unregister_dock(dock)
	assert_int(transport.get_dock_data().size()).is_equal(0)


func test_barge_arrival_is_noop() -> void:
	# Resources are already in stockpile — arrival should just clean up
	var mock_map := _create_river_chain(Vector2i(5, 0), 10)
	var mock_placer := MockBuildingPlacer.new()
	add_child(mock_placer)
	auto_free(mock_placer)

	var entities: Array = _setup_dock_and_tc(mock_map, mock_placer)
	var dock: Node2D = entities[0]

	var transport := _create_transport(mock_map, mock_placer)
	transport.register_dock(dock)
	transport.notify_resource_deposited(dock, 0, 10)

	# Advance time past interval
	transport._update_dock_timers(6.0)

	var barges: Array[Node2D] = transport.get_active_barges()
	assert_int(barges.size()).is_equal(1)

	_reset_counter()
	transport.barge_arrived.connect(_increment_counter)

	# Force barge to arrive
	barges[0].arrived.emit(barges[0])
	assert_int(_signal_count).is_equal(1)


func test_save_load_state() -> void:
	var mock_map := MockMap.new()
	add_child(mock_map)
	auto_free(mock_map)
	mock_map._river_tiles[Vector2i(5, 3)] = true
	var mock_placer := MockBuildingPlacer.new()
	add_child(mock_placer)
	auto_free(mock_placer)

	var transport := _create_transport(mock_map, mock_placer)
	var dock := _create_dock(Vector2i(5, 2))
	(
		mock_placer
		. _placed_buildings
		. append(
			{
				"building_name": "river_dock",
				"grid_pos": [5, 2],
				"player_id": 0,
				"node": dock,
			}
		)
	)

	transport.register_dock(dock)
	transport.notify_resource_deposited(dock, 0, 7)

	var state: Dictionary = transport.save_state()
	assert_bool(state.has("docks")).is_true()
	assert_bool(state.has("barges")).is_true()

	var docks_arr: Array = state["docks"]
	assert_int(docks_arr.size()).is_equal(1)
	assert_int(docks_arr[0].get("queued_total", 0)).is_equal(7)

	# Load into a new transport
	var transport2 := _create_transport(mock_map, mock_placer)
	transport2.load_state(state)
	var dock_data: Dictionary = transport2.get_dock_data()
	assert_int(dock_data.size()).is_equal(1)


func test_notify_resource_deposited_accumulates() -> void:
	var mock_map := MockMap.new()
	add_child(mock_map)
	auto_free(mock_map)
	var mock_placer := MockBuildingPlacer.new()
	add_child(mock_placer)
	auto_free(mock_placer)

	var transport := _create_transport(mock_map, mock_placer)
	var dock := _create_dock(Vector2i(2, 2))
	transport.register_dock(dock)

	transport.notify_resource_deposited(dock, 0, 5)
	transport.notify_resource_deposited(dock, 0, 3)
	transport.notify_resource_deposited(dock, 1, 2)

	var info: Dictionary = transport.get_dock_data()[dock]
	assert_int(info.get("queued_total", 0)).is_equal(10)
	var queued: Dictionary = info.get("queued_resources", {})
	assert_int(queued.get(0, 0)).is_equal(8)
	assert_int(queued.get(1, 0)).is_equal(2)


# --- Pool tests ---


func test_pool_reuses_released_barges() -> void:
	var mock_map := _create_river_chain(Vector2i(5, 0), 10)
	var mock_placer := MockBuildingPlacer.new()
	add_child(mock_placer)
	auto_free(mock_placer)

	var entities: Array = _setup_dock_and_tc(mock_map, mock_placer)
	var dock: Node2D = entities[0]

	var transport := _create_transport(mock_map, mock_placer)
	transport.register_dock(dock)
	transport.notify_resource_deposited(dock, 0, 10)

	# Dispatch first barge
	transport._update_dock_timers(6.0)
	var barges: Array[Node2D] = transport.get_active_barges()
	assert_int(barges.size()).is_equal(1)

	# Force arrival to return to pool
	barges[0].arrived.emit(barges[0])
	assert_int(transport.get_active_barges().size()).is_equal(0)
	assert_int(transport._barge_pool.size()).is_equal(1)

	# Dispatch second barge — should reuse pooled barge
	transport.notify_resource_deposited(dock, 0, 10)
	transport._update_dock_timers(6.0)
	barges = transport.get_active_barges()
	assert_int(barges.size()).is_equal(1)
	# Pool should now be empty (reused)
	assert_int(transport._barge_pool.size()).is_equal(0)


func test_pool_caps_at_pool_size() -> void:
	var mock_map := _create_river_chain(Vector2i(5, 0), 10)
	var mock_placer := MockBuildingPlacer.new()
	add_child(mock_placer)
	auto_free(mock_placer)

	var entities: Array = _setup_dock_and_tc(mock_map, mock_placer)
	var dock: Node2D = entities[0]

	var transport := _create_transport(mock_map, mock_placer)
	transport._barge_pool_size = 2  # Small cap for testing
	transport.register_dock(dock)

	# Dispatch and arrive multiple barges to fill pool
	for _i in 5:
		transport.notify_resource_deposited(dock, 0, 5)
		transport._update_dock_timers(6.0)
		var barges: Array[Node2D] = transport.get_active_barges()
		if not barges.is_empty():
			barges[barges.size() - 1].arrived.emit(barges[barges.size() - 1])
	# Pool should be capped at 2
	assert_int(transport._barge_pool.size()).is_less_equal(2)


# --- In-transit resource query ---


func test_get_in_transit_resources_returns_cargo() -> void:
	var mock_map := _create_river_chain(Vector2i(5, 0), 10)
	var mock_placer := MockBuildingPlacer.new()
	add_child(mock_placer)
	auto_free(mock_placer)

	var entities: Array = _setup_dock_and_tc(mock_map, mock_placer)
	var dock: Node2D = entities[0]

	var transport := _create_transport(mock_map, mock_placer)
	transport.register_dock(dock)
	transport.notify_resource_deposited(dock, 0, 10)
	transport.notify_resource_deposited(dock, 1, 5)
	transport._update_dock_timers(6.0)

	var in_transit: Dictionary = transport.get_in_transit_resources(0)
	assert_int(in_transit.get(0, 0)).is_equal(10)
	assert_int(in_transit.get(1, 0)).is_equal(5)


func test_get_in_transit_resources_empty_when_no_barges() -> void:
	var mock_map := MockMap.new()
	add_child(mock_map)
	auto_free(mock_map)
	var mock_placer := MockBuildingPlacer.new()
	add_child(mock_placer)
	auto_free(mock_placer)

	var transport := _create_transport(mock_map, mock_placer)
	var in_transit: Dictionary = transport.get_in_transit_resources(0)
	assert_int(in_transit.size()).is_equal(0)


# --- Dock info query ---


func test_get_dock_info_returns_summary() -> void:
	var mock_map := MockMap.new()
	add_child(mock_map)
	auto_free(mock_map)
	var mock_placer := MockBuildingPlacer.new()
	add_child(mock_placer)
	auto_free(mock_placer)

	var transport := _create_transport(mock_map, mock_placer)
	var dock := _create_dock(Vector2i(3, 3))
	transport.register_dock(dock)
	transport.notify_resource_deposited(dock, 0, 12)

	var info: Dictionary = transport.get_dock_info(dock)
	assert_bool(info.has("queued_total")).is_true()
	assert_int(info.get("queued_total", 0)).is_equal(12)
	assert_bool(info.has("active_barge_count")).is_true()
	assert_bool(info.has("time_until_next_dispatch")).is_true()


func test_get_dock_info_returns_empty_for_unknown_dock() -> void:
	var mock_map := MockMap.new()
	add_child(mock_map)
	auto_free(mock_map)
	var mock_placer := MockBuildingPlacer.new()
	add_child(mock_placer)
	auto_free(mock_placer)

	var transport := _create_transport(mock_map, mock_placer)
	var dock := _create_dock(Vector2i(3, 3))

	var info: Dictionary = transport.get_dock_info(dock)
	assert_int(info.size()).is_equal(0)


# --- Enhanced signals ---


func test_barge_destroyed_with_resources_signal() -> void:
	var mock_map := _create_river_chain(Vector2i(5, 0), 10)
	var mock_placer := MockBuildingPlacer.new()
	add_child(mock_placer)
	auto_free(mock_placer)

	var entities: Array = _setup_dock_and_tc(mock_map, mock_placer)
	var dock: Node2D = entities[0]

	var transport := _create_transport(mock_map, mock_placer)
	transport.register_dock(dock)
	transport.notify_resource_deposited(dock, 0, 10)
	transport._update_dock_timers(6.0)

	_reset_counter()
	transport.barge_destroyed_with_resources.connect(_on_destroyed_with_resources)

	var barges: Array[Node2D] = transport.get_active_barges()
	barges[0].take_damage(barges[0].hp)

	assert_int(_signal_count).is_equal(1)
	assert_int(_last_resources.get(0, 0)).is_equal(10)


func test_barge_arrived_with_resources_signal() -> void:
	var mock_map := _create_river_chain(Vector2i(5, 0), 10)
	var mock_placer := MockBuildingPlacer.new()
	add_child(mock_placer)
	auto_free(mock_placer)

	var entities: Array = _setup_dock_and_tc(mock_map, mock_placer)
	var dock: Node2D = entities[0]

	var transport := _create_transport(mock_map, mock_placer)
	transport.register_dock(dock)
	transport.notify_resource_deposited(dock, 0, 10)
	transport._update_dock_timers(6.0)

	_reset_counter()
	transport.barge_arrived_with_resources.connect(_on_arrived_with_resources)

	var barges: Array[Node2D] = transport.get_active_barges()
	barges[0].arrived.emit(barges[0])

	assert_int(_signal_count).is_equal(1)
	assert_int(_last_resources.get(0, 0)).is_equal(10)
