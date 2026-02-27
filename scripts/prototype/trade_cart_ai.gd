extends Node
## Trade Cart AI — state machine for trade carts and merchant ships.
## Attached as child of a prototype_unit with unit_type "trade_cart" or "merchant_ship".
## Drives movement loop: home market → away market → home → earn gold → repeat.

enum TradeState { IDLE, MOVING_TO_AWAY, AT_AWAY, MOVING_TO_HOME, AT_HOME }

const TILE_SIZE: float = 64.0
const ARRIVAL_THRESHOLD: float = 8.0

var _state: TradeState = TradeState.IDLE
var _unit: Node2D = null
var _trade_manager: Node = null
var _home_market: Node2D = null
var _away_market: Node2D = null
var _pause_timer: float = 0.0
var _pause_duration: float = 1.0
var _scan_timer: float = 0.0
var _scan_interval: float = 2.0

# Save/load pending
var _pending_home_grid: Vector2i = Vector2i(-1, -1)
var _pending_away_grid: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	_unit = get_parent()
	if _unit == null:
		return
	# Suppress combat — trade units are non-combatants
	if "_stance" in _unit:
		_unit._stance = _unit.Stance.STAND_GROUND
	if "_combat_state" in _unit:
		_unit._combat_state = _unit.CombatState.NONE
	if _unit.has_method("_cancel_combat"):
		_unit._cancel_combat()
	call_deferred("_find_trade_manager")


func _find_trade_manager() -> void:
	# Walk up to scene root and find TradeManager
	var current: Node = _unit
	while current != null:
		current = current.get_parent()
		if current == null:
			break
		for child in current.get_children():
			if child.has_method("notify_route_completed") and child.has_method("get_markets_for_player"):
				_trade_manager = child
				return


func _process(delta: float) -> void:
	var game_delta: float = GameUtils.get_game_delta(delta)
	if game_delta == 0.0:
		return
	if _unit == null or not is_instance_valid(_unit):
		return
	# Keep combat suppressed
	if "_combat_state" in _unit and _unit._combat_state != _unit.CombatState.NONE:
		if _unit.has_method("_cancel_combat"):
			_unit._cancel_combat()
	# Suppress prototype_unit's built-in movement so we drive it
	if "_moving" in _unit and _unit._moving:
		_unit._moving = false
		_unit._path.clear()
		_unit._path_index = 0

	match _state:
		TradeState.IDLE:
			_tick_idle(game_delta)
		TradeState.MOVING_TO_AWAY:
			_tick_moving_to_away(game_delta)
		TradeState.AT_AWAY:
			_tick_at_away(game_delta)
		TradeState.MOVING_TO_HOME:
			_tick_moving_to_home(game_delta)
		TradeState.AT_HOME:
			_tick_at_home(game_delta)


func _tick_idle(game_delta: float) -> void:
	_scan_timer += game_delta
	if _scan_timer < _scan_interval:
		return
	_scan_timer = 0.0
	if _trade_manager == null:
		_find_trade_manager()
		return
	var owner_id: int = _unit.owner_id if "owner_id" in _unit else 0
	var markets: Array = _trade_manager.get_markets_for_player(owner_id)
	if markets.size() < 2:
		return  # Need at least 2 markets for a route
	# Home = nearest, away = farthest
	_home_market = _find_nearest_market(markets)
	_away_market = _find_farthest_market(markets)
	if _home_market == null or _away_market == null:
		return
	if _home_market == _away_market:
		return
	_pause_duration = _trade_manager.get_route_pause_time()
	_state = TradeState.MOVING_TO_AWAY


func _tick_moving_to_away(game_delta: float) -> void:
	if not _validate_markets():
		_reset_to_idle()
		return
	var target_pos: Vector2 = _away_market.global_position
	if _move_toward(target_pos, game_delta):
		_state = TradeState.AT_AWAY
		_pause_timer = _pause_duration


func _tick_at_away(game_delta: float) -> void:
	_pause_timer -= game_delta
	if _pause_timer <= 0.0:
		if not _validate_markets():
			_reset_to_idle()
			return
		_state = TradeState.MOVING_TO_HOME


func _tick_moving_to_home(game_delta: float) -> void:
	if not _validate_markets():
		_reset_to_idle()
		return
	var target_pos: Vector2 = _home_market.global_position
	if _move_toward(target_pos, game_delta):
		_state = TradeState.AT_HOME
		_pause_timer = _pause_duration


func _tick_at_home(game_delta: float) -> void:
	_pause_timer -= game_delta
	if _pause_timer <= 0.0:
		if not _validate_markets():
			_reset_to_idle()
			return
		# Route completed — earn gold
		var owner_id: int = _unit.owner_id if "owner_id" in _unit else 0
		if _trade_manager != null:
			_trade_manager.notify_route_completed(_home_market, _away_market, owner_id)
		# Start next trip
		_state = TradeState.MOVING_TO_AWAY


func _validate_markets() -> bool:
	if _home_market == null or not is_instance_valid(_home_market):
		return false
	if _away_market == null or not is_instance_valid(_away_market):
		return false
	return true


func _reset_to_idle() -> void:
	_state = TradeState.IDLE
	_home_market = null
	_away_market = null
	_scan_timer = 0.0


func _move_toward(target: Vector2, game_delta: float) -> bool:
	var dist := _unit.position.distance_to(target)
	if dist < ARRIVAL_THRESHOLD:
		_unit.position = target
		_unit.queue_redraw()
		return true
	var speed_pixels: float = _get_speed_pixels()
	var direction := (target - _unit.position).normalized()
	if "_facing" in _unit:
		_unit._facing = direction
	_unit.position = _unit.position.move_toward(target, speed_pixels * game_delta)
	_unit.queue_redraw()
	return false


func _get_speed_pixels() -> float:
	var base_speed: float = 1.0
	if _unit.has_method("get_stat"):
		base_speed = float(_unit.get_stat("speed"))
	return base_speed * TILE_SIZE * 1.5


func _find_nearest_market(markets: Array) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for market in markets:
		if not is_instance_valid(market):
			continue
		var dist: float = _unit.position.distance_to(market.global_position)
		if dist < best_dist:
			best_dist = dist
			best = market
	return best


func _find_farthest_market(markets: Array) -> Node2D:
	var best: Node2D = null
	var best_dist: float = -1.0
	for market in markets:
		if not is_instance_valid(market):
			continue
		var dist: float = _unit.position.distance_to(market.global_position)
		if dist > best_dist:
			best_dist = dist
			best = market
	return best


func save_state() -> Dictionary:
	var home_grid := Vector2i(-1, -1)
	var away_grid := Vector2i(-1, -1)
	if _home_market != null and is_instance_valid(_home_market) and "grid_pos" in _home_market:
		home_grid = _home_market.grid_pos
	if _away_market != null and is_instance_valid(_away_market) and "grid_pos" in _away_market:
		away_grid = _away_market.grid_pos
	return {
		"state": _state,
		"pause_timer": _pause_timer,
		"scan_timer": _scan_timer,
		"home_grid": [home_grid.x, home_grid.y],
		"away_grid": [away_grid.x, away_grid.y],
	}


func load_state(data: Dictionary) -> void:
	_state = int(data.get("state", TradeState.IDLE)) as TradeState
	_pause_timer = float(data.get("pause_timer", 0.0))
	_scan_timer = float(data.get("scan_timer", 0.0))
	var home_arr: Array = data.get("home_grid", [-1, -1])
	_pending_home_grid = Vector2i(int(home_arr[0]), int(home_arr[1]))
	var away_arr: Array = data.get("away_grid", [-1, -1])
	_pending_away_grid = Vector2i(int(away_arr[0]), int(away_arr[1]))


func resolve_markets(trade_manager: Node) -> void:
	_trade_manager = trade_manager
	if _pending_home_grid != Vector2i(-1, -1):
		_home_market = _find_market_at_grid(_pending_home_grid)
		_pending_home_grid = Vector2i(-1, -1)
	if _pending_away_grid != Vector2i(-1, -1):
		_away_market = _find_market_at_grid(_pending_away_grid)
		_pending_away_grid = Vector2i(-1, -1)


func _find_market_at_grid(grid_pos: Vector2i) -> Node2D:
	if _trade_manager == null:
		return null
	var owner_id: int = _unit.owner_id if "owner_id" in _unit else 0
	var markets: Array = _trade_manager.get_markets_for_player(owner_id)
	for market in markets:
		if is_instance_valid(market) and "grid_pos" in market and market.grid_pos == grid_pos:
			return market
	return null
