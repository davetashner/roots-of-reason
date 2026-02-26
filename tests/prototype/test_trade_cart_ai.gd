extends GdUnitTestSuite
## Tests for trade_cart_ai.gd — trade cart/merchant ship AI state machine.

const TradeCartAIScript := preload("res://scripts/prototype/trade_cart_ai.gd")

var _route_count: int = 0
var _last_route_gold: int = 0


func _reset_counter() -> void:
	_route_count = 0
	_last_route_gold = 0


func _on_route(_owner_id: int, gold: int) -> void:
	_route_count += 1
	_last_route_gold = gold


class MockUnit:
	extends Node2D

	enum Stance { AGGRESSIVE, DEFENSIVE, STAND_GROUND, NO_ATTACK }
	enum CombatState { NONE, ENGAGING, ATTACKING, CHASING }

	var unit_type: String = "trade_cart"
	var owner_id: int = 0
	var selected: bool = false
	var hp: int = 70
	var max_hp: int = 70
	var _stance: Stance = Stance.AGGRESSIVE
	var _combat_state: CombatState = CombatState.NONE
	var _moving: bool = false
	var _path: Array[Vector2] = []
	var _path_index: int = 0
	var _facing: Vector2 = Vector2.RIGHT

	func _cancel_combat() -> void:
		_combat_state = CombatState.NONE

	func get_stat(stat_name: String) -> float:
		if stat_name == "speed":
			return 1.2
		return 0.0

	func is_idle() -> bool:
		return true

	func select() -> void:
		selected = true

	func deselect() -> void:
		selected = false

	func is_point_inside(_pos: Vector2) -> bool:
		return false


class MockMarket:
	extends Node2D
	var building_name: String = "market"
	var grid_pos: Vector2i = Vector2i.ZERO
	var owner_id: int = 0
	var under_construction: bool = false
	var hp: int = 1000
	var max_hp: int = 1000


class MockTradeManager:
	extends Node
	signal route_completed(owner_id: int, gold: int)
	var _markets: Dictionary = {}  # player_id -> Array of markets
	var _route_calls: int = 0
	var _pause_time: float = 0.0  # Use 0 for instant tests

	func get_markets_for_player(player_id: int) -> Array:
		return _markets.get(player_id, [])

	func notify_route_completed(_home: Node2D, _away: Node2D, owner_id: int) -> void:
		_route_calls += 1
		route_completed.emit(owner_id, 25)

	func get_route_pause_time() -> float:
		return _pause_time


func _create_unit(utype: String = "trade_cart") -> Node2D:
	var unit := MockUnit.new()
	unit.unit_type = utype
	unit.position = Vector2(100, 100)
	add_child(unit)
	auto_free(unit)
	return unit


func _create_ai(unit: Node2D, tm: Node = null) -> Node:
	var ai := Node.new()
	ai.name = "TradeCartAI"
	ai.set_script(TradeCartAIScript)
	unit.add_child(ai)
	if tm != null:
		ai._trade_manager = tm
	return ai


func _create_market(gpos: Vector2i, pid: int = 0) -> Node2D:
	var m := MockMarket.new()
	m.grid_pos = gpos
	m.owner_id = pid
	m.position = IsoUtils.grid_to_screen(Vector2(gpos))
	add_child(m)
	auto_free(m)
	return m


func _create_trade_manager_with_markets(markets: Array, pid: int = 0) -> Node:
	var tm := MockTradeManager.new()
	tm._markets[pid] = markets
	add_child(tm)
	auto_free(tm)
	return tm


func test_idle_with_no_trade_manager() -> void:
	var unit := _create_unit()
	var ai := _create_ai(unit)
	# Process a few frames
	ai._process(0.1)
	ai._process(0.1)
	assert_int(ai._state).is_equal(TradeCartAIScript.TradeState.IDLE)


func test_idle_with_one_market() -> void:
	var unit := _create_unit()
	var m := _create_market(Vector2i(5, 5))
	var tm := _create_trade_manager_with_markets([m])
	var ai := _create_ai(unit, tm)
	# Force scan
	ai._scan_timer = 10.0
	ai._tick_idle(1.0)
	assert_int(ai._state).is_equal(TradeCartAIScript.TradeState.IDLE)


func test_enters_moving_to_away_with_two_markets() -> void:
	var unit := _create_unit()
	var m1 := _create_market(Vector2i(1, 1))
	var m2 := _create_market(Vector2i(30, 30))
	# Place unit near m1
	unit.position = m1.position
	var tm := _create_trade_manager_with_markets([m1, m2])
	var ai := _create_ai(unit, tm)
	# Force scan
	ai._scan_timer = 10.0
	ai._tick_idle(1.0)
	assert_int(ai._state).is_equal(TradeCartAIScript.TradeState.MOVING_TO_AWAY)
	assert_that(ai._home_market).is_same(m1)
	assert_that(ai._away_market).is_same(m2)


func test_home_is_nearest_away_is_farthest() -> void:
	var unit := _create_unit()
	var near := _create_market(Vector2i(2, 2))
	var far := _create_market(Vector2i(50, 50))
	unit.position = near.position
	var tm := _create_trade_manager_with_markets([near, far])
	var ai := _create_ai(unit, tm)
	ai._scan_timer = 10.0
	ai._tick_idle(1.0)
	assert_that(ai._home_market).is_same(near)
	assert_that(ai._away_market).is_same(far)


func test_arrival_transitions_to_at_away() -> void:
	var unit := _create_unit()
	var m1 := _create_market(Vector2i(1, 1))
	var m2 := _create_market(Vector2i(5, 5))
	unit.position = m1.position
	var tm := _create_trade_manager_with_markets([m1, m2])
	var ai := _create_ai(unit, tm)
	ai._state = TradeCartAIScript.TradeState.MOVING_TO_AWAY
	ai._home_market = m1
	ai._away_market = m2
	ai._pause_duration = 0.5
	# Place unit at away market
	unit.position = m2.position
	ai._tick_moving_to_away(0.1)
	assert_int(ai._state).is_equal(TradeCartAIScript.TradeState.AT_AWAY)


func test_at_away_transitions_to_moving_home() -> void:
	var unit := _create_unit()
	var m1 := _create_market(Vector2i(1, 1))
	var m2 := _create_market(Vector2i(5, 5))
	var tm := _create_trade_manager_with_markets([m1, m2])
	var ai := _create_ai(unit, tm)
	ai._state = TradeCartAIScript.TradeState.AT_AWAY
	ai._home_market = m1
	ai._away_market = m2
	ai._pause_timer = 0.1
	ai._tick_at_away(0.2)
	assert_int(ai._state).is_equal(TradeCartAIScript.TradeState.MOVING_TO_HOME)


func test_route_completion_triggers_gold() -> void:
	var unit := _create_unit()
	var m1 := _create_market(Vector2i(1, 1))
	var m2 := _create_market(Vector2i(5, 5))
	var tm := _create_trade_manager_with_markets([m1, m2])
	var ai := _create_ai(unit, tm)
	ai._state = TradeCartAIScript.TradeState.AT_HOME
	ai._home_market = m1
	ai._away_market = m2
	ai._pause_timer = 0.1
	ai._pause_duration = 0.0
	ai._tick_at_home(0.2)
	# Should have called notify_route_completed and moved to MOVING_TO_AWAY
	assert_int(ai._state).is_equal(TradeCartAIScript.TradeState.MOVING_TO_AWAY)
	assert_int(tm._route_calls).is_equal(1)


func test_combat_suppressed_on_ready() -> void:
	var unit := _create_unit()
	var ai := _create_ai(unit)
	assert_int(unit._stance).is_equal(MockUnit.Stance.STAND_GROUND)
	assert_int(unit._combat_state).is_equal(MockUnit.CombatState.NONE)


func test_invalid_market_resets_to_idle() -> void:
	var unit := _create_unit()
	var m1 := _create_market(Vector2i(1, 1))
	var tm := _create_trade_manager_with_markets([m1])
	var ai := _create_ai(unit, tm)
	ai._state = TradeCartAIScript.TradeState.MOVING_TO_AWAY
	ai._home_market = m1
	ai._away_market = null  # Invalid
	ai._tick_moving_to_away(0.1)
	assert_int(ai._state).is_equal(TradeCartAIScript.TradeState.IDLE)


func test_save_load_state() -> void:
	var unit := _create_unit()
	var m1 := _create_market(Vector2i(1, 1))
	var m2 := _create_market(Vector2i(10, 10))
	var tm := _create_trade_manager_with_markets([m1, m2])
	var ai := _create_ai(unit, tm)
	ai._state = TradeCartAIScript.TradeState.MOVING_TO_AWAY
	ai._home_market = m1
	ai._away_market = m2
	ai._pause_timer = 0.5
	var state: Dictionary = ai.save_state()
	assert_int(int(state["state"])).is_equal(TradeCartAIScript.TradeState.MOVING_TO_AWAY)
	# Load into new AI
	var unit2 := _create_unit()
	var ai2 := _create_ai(unit2, tm)
	ai2.load_state(state)
	assert_int(ai2._state).is_equal(TradeCartAIScript.TradeState.MOVING_TO_AWAY)
	assert_float(ai2._pause_timer).is_equal_approx(0.5, 0.01)


func test_merchant_ship_uses_same_ai() -> void:
	var unit := _create_unit("merchant_ship")
	var m1 := _create_market(Vector2i(1, 1))
	var m2 := _create_market(Vector2i(30, 30))
	unit.position = m1.position
	var tm := _create_trade_manager_with_markets([m1, m2])
	var ai := _create_ai(unit, tm)
	ai._scan_timer = 10.0
	ai._tick_idle(1.0)
	assert_int(ai._state).is_equal(TradeCartAIScript.TradeState.MOVING_TO_AWAY)
