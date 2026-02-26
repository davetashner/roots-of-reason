extends GdUnitTestSuite
## Tests for trade_manager.gd — market registration, exchange, rate fluctuation, route gold.

const TradeManagerScript := preload("res://scripts/prototype/trade_manager.gd")

var _signal_count: int = 0
var _last_gold: int = 0
var _last_sell_resource: String = ""


func _reset_counter() -> void:
	_signal_count = 0
	_last_gold = 0
	_last_sell_resource = ""


func _on_exchange(_pid: int, sell_res: String, _amount: int, gold: int) -> void:
	_signal_count += 1
	_last_sell_resource = sell_res
	_last_gold = gold


func _on_route(_owner_id: int, gold: int) -> void:
	_signal_count += 1
	_last_gold = gold


class MockBuildingPlacer:
	extends Node
	signal building_placed(building: Node2D)
	var _placed_buildings: Array[Dictionary] = []


class MockMarket:
	extends Node2D
	signal construction_complete(building: Node2D)
	signal building_destroyed(building: Node2D)
	var building_name: String = "market"
	var grid_pos: Vector2i = Vector2i.ZERO
	var owner_id: int = 0
	var under_construction: bool = false
	var hp: int = 1000
	var max_hp: int = 1000


func _create_manager(placer: Node = null) -> Node:
	var mgr := Node.new()
	mgr.name = "TradeManager"
	mgr.set_script(TradeManagerScript)
	add_child(mgr)
	auto_free(mgr)
	# Override config for deterministic tests
	mgr._base_exchange_rates = {"food": 100, "wood": 100, "stone": 150}
	mgr._route_base_gold = 25
	mgr._route_reference_distance = 20
	mgr._route_pause_time = 1.0
	mgr._rate_window_seconds = 120.0
	mgr._saturation_threshold = 500
	mgr._saturation_max_penalty = 0.5
	if placer != null:
		mgr.setup(placer)
	return mgr


func _create_market(gpos: Vector2i, pid: int = 0) -> Node2D:
	var m := MockMarket.new()
	m.grid_pos = gpos
	m.owner_id = pid
	add_child(m)
	auto_free(m)
	return m


func test_register_and_unregister_market() -> void:
	var mgr := _create_manager()
	var m := _create_market(Vector2i(5, 5))
	mgr.register_market(m)
	assert_int(mgr.get_markets_for_player(0).size()).is_equal(1)
	mgr.unregister_market(m)
	assert_int(mgr.get_markets_for_player(0).size()).is_equal(0)


func test_register_market_duplicate_ignored() -> void:
	var mgr := _create_manager()
	var m := _create_market(Vector2i(5, 5))
	mgr.register_market(m)
	mgr.register_market(m)
	assert_int(mgr.get_markets_for_player(0).size()).is_equal(1)


func test_get_markets_for_player_filters_by_owner() -> void:
	var mgr := _create_manager()
	var m0 := _create_market(Vector2i(5, 5), 0)
	var m1 := _create_market(Vector2i(10, 10), 1)
	mgr.register_market(m0)
	mgr.register_market(m1)
	assert_int(mgr.get_markets_for_player(0).size()).is_equal(1)
	assert_int(mgr.get_markets_for_player(1).size()).is_equal(1)


func test_execute_exchange_success() -> void:
	var mgr := _create_manager()
	_reset_counter()
	mgr.exchange_completed.connect(_on_exchange)
	# Give player 0 some food
	(
		ResourceManager
		. init_player(
			0,
			{
				ResourceManager.ResourceType.FOOD: 500,
				ResourceManager.ResourceType.WOOD: 0,
				ResourceManager.ResourceType.STONE: 0,
				ResourceManager.ResourceType.GOLD: 0,
				ResourceManager.ResourceType.KNOWLEDGE: 0,
			}
		)
	)
	var result: bool = mgr.execute_exchange(0, "food", 100)
	assert_bool(result).is_true()
	assert_int(_signal_count).is_equal(1)
	# Base rate 100 → 100 food * 100/100 = 100 gold
	assert_int(_last_gold).is_equal(100)
	# Check resources changed
	assert_int(ResourceManager.get_amount(0, ResourceManager.ResourceType.FOOD)).is_equal(400)
	assert_int(ResourceManager.get_amount(0, ResourceManager.ResourceType.GOLD)).is_equal(100)


func test_execute_exchange_insufficient_resources_fails() -> void:
	var mgr := _create_manager()
	(
		ResourceManager
		. init_player(
			0,
			{
				ResourceManager.ResourceType.FOOD: 50,
				ResourceManager.ResourceType.WOOD: 0,
				ResourceManager.ResourceType.STONE: 0,
				ResourceManager.ResourceType.GOLD: 0,
				ResourceManager.ResourceType.KNOWLEDGE: 0,
			}
		)
	)
	var result: bool = mgr.execute_exchange(0, "food", 100)
	assert_bool(result).is_false()


func test_execute_exchange_invalid_resource_fails() -> void:
	var mgr := _create_manager()
	var result: bool = mgr.execute_exchange(0, "unobtanium", 100)
	assert_bool(result).is_false()


func test_execute_exchange_zero_amount_fails() -> void:
	var mgr := _create_manager()
	var result: bool = mgr.execute_exchange(0, "food", 0)
	assert_bool(result).is_false()


func test_get_current_rate_no_volume() -> void:
	var mgr := _create_manager()
	var rate: float = mgr.get_current_rate("food")
	assert_float(rate).is_equal_approx(100.0, 0.01)


func test_rate_fluctuation_degrades_with_volume() -> void:
	var mgr := _create_manager()
	# Record volume to degrade rate
	mgr._record_volume("food", 250)
	var rate: float = mgr.get_current_rate("food")
	# volume=250, threshold=500 → penalty = 250/500 = 0.5 → rate = 100*(1-0.5) = 50
	assert_float(rate).is_equal_approx(50.0, 0.01)


func test_rate_fluctuation_caps_at_max_penalty() -> void:
	var mgr := _create_manager()
	# Record huge volume
	mgr._record_volume("food", 2000)
	var rate: float = mgr.get_current_rate("food")
	# penalty capped at 0.5 → rate = 100*(1-0.5) = 50
	assert_float(rate).is_equal_approx(50.0, 0.01)


func test_rate_recovers_after_window() -> void:
	var mgr := _create_manager()
	# Record volume with expired timestamp
	var old_time: float = float(Time.get_ticks_msec()) / 1000.0 - 200.0
	mgr._volume_history["food"] = [[old_time, 500]]
	var rate: float = mgr.get_current_rate("food")
	# Old entries should be pruned → no volume → full rate
	assert_float(rate).is_equal_approx(100.0, 0.01)


func test_route_completed_earns_gold() -> void:
	var mgr := _create_manager()
	_reset_counter()
	mgr.route_completed.connect(_on_route)
	(
		ResourceManager
		. init_player(
			0,
			{
				ResourceManager.ResourceType.FOOD: 0,
				ResourceManager.ResourceType.WOOD: 0,
				ResourceManager.ResourceType.STONE: 0,
				ResourceManager.ResourceType.GOLD: 0,
				ResourceManager.ResourceType.KNOWLEDGE: 0,
			}
		)
	)
	var home := _create_market(Vector2i(0, 0))
	var away := _create_market(Vector2i(20, 0))
	mgr.register_market(home)
	mgr.register_market(away)
	mgr.notify_route_completed(home, away, 0)
	assert_int(_signal_count).is_equal(1)
	# distance=20, ref=20 → gold = 25 * 20/20 = 25
	assert_int(_last_gold).is_equal(25)
	assert_int(ResourceManager.get_amount(0, ResourceManager.ResourceType.GOLD)).is_equal(25)


func test_route_completed_distance_scaling() -> void:
	var mgr := _create_manager()
	_reset_counter()
	mgr.route_completed.connect(_on_route)
	(
		ResourceManager
		. init_player(
			0,
			{
				ResourceManager.ResourceType.FOOD: 0,
				ResourceManager.ResourceType.WOOD: 0,
				ResourceManager.ResourceType.STONE: 0,
				ResourceManager.ResourceType.GOLD: 0,
				ResourceManager.ResourceType.KNOWLEDGE: 0,
			}
		)
	)
	var home := _create_market(Vector2i(0, 0))
	var away := _create_market(Vector2i(40, 0))
	mgr.register_market(home)
	mgr.register_market(away)
	mgr.notify_route_completed(home, away, 0)
	# distance=40, ref=20 → gold = 25 * 40/20 = 50
	assert_int(_last_gold).is_equal(50)


func test_route_same_market_earns_nothing() -> void:
	var mgr := _create_manager()
	_reset_counter()
	mgr.route_completed.connect(_on_route)
	var m := _create_market(Vector2i(5, 5))
	mgr.register_market(m)
	mgr.notify_route_completed(m, m, 0)
	assert_int(_signal_count).is_equal(0)


func test_get_market_info() -> void:
	var mgr := _create_manager()
	var m := _create_market(Vector2i(5, 5))
	mgr.register_market(m)
	var info: Dictionary = mgr.get_market_info(m)
	assert_bool(info.has("rates")).is_true()
	assert_bool(info.has("active_cart_count")).is_true()


func test_get_market_info_unregistered_returns_empty() -> void:
	var mgr := _create_manager()
	var m := _create_market(Vector2i(5, 5))
	var info: Dictionary = mgr.get_market_info(m)
	assert_int(info.size()).is_equal(0)


func test_save_load_roundtrip() -> void:
	var mgr := _create_manager()
	var m := _create_market(Vector2i(5, 5))
	mgr.register_market(m)
	mgr._record_volume("food", 100)
	var state: Dictionary = mgr.save_state()
	assert_bool(state.has("markets")).is_true()
	assert_bool(state.has("volume_history")).is_true()
	# Create new manager and load state
	var mgr2 := _create_manager()
	mgr2.load_state(state)
	assert_bool(mgr2._volume_history.has("food")).is_true()


func test_building_placed_signal_registers_market() -> void:
	var placer := MockBuildingPlacer.new()
	add_child(placer)
	auto_free(placer)
	var mgr := _create_manager(placer)
	var m := _create_market(Vector2i(5, 5))
	# Simulate building placement
	placer.building_placed.emit(m)
	assert_int(mgr.get_markets_for_player(0).size()).is_equal(1)
