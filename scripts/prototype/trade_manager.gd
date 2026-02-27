extends Node
## Manages market registration, exchange rates, and trade route gold income.
## Markets allow selling resources for gold at fluctuating rates.
## Trade carts/merchant ships earn gold by completing routes between markets.

signal exchange_completed(player_id: int, sell_resource: String, amount: int, gold_earned: int)
signal route_completed(owner_id: int, gold_earned: int)

const RESOURCE_NAME_TO_TYPE: Dictionary = {
	"food": ResourceManager.ResourceType.FOOD,
	"wood": ResourceManager.ResourceType.WOOD,
	"stone": ResourceManager.ResourceType.STONE,
	"knowledge": ResourceManager.ResourceType.KNOWLEDGE,
}

# Config loaded from data/settings/economy/trade.json
var _base_exchange_rates: Dictionary = {}
var _route_base_gold: int = 25
var _route_reference_distance: int = 20
var _route_pause_time: float = 1.0
var _rate_window_seconds: float = 120.0
var _saturation_threshold: int = 500
var _saturation_max_penalty: float = 0.5

# Market tracking: Node2D -> { owner_id, grid_pos }
var _market_data: Dictionary = {}

# Rate fluctuation: resource_name -> Array of [timestamp, amount]
var _volume_history: Dictionary = {}

# Event-driven trade income multiplier: player_id -> float (default 1.0)
var _trade_income_multiplier: Dictionary = {}

# References
var _building_placer: Node = null


func _ready() -> void:
	_load_config()


func _load_config() -> void:
	var cfg := _load_settings("trade")
	var rates: Dictionary = cfg.get("base_exchange_rates", {})
	if not rates.is_empty():
		_base_exchange_rates = rates
	else:
		_base_exchange_rates = {"food": 100, "wood": 100, "stone": 150, "knowledge": 200}
	_route_base_gold = int(cfg.get("route_base_gold", _route_base_gold))
	_route_reference_distance = int(cfg.get("route_reference_distance", _route_reference_distance))
	_route_pause_time = float(cfg.get("route_pause_time", _route_pause_time))
	_rate_window_seconds = float(cfg.get("rate_window_seconds", _rate_window_seconds))
	_saturation_threshold = int(cfg.get("saturation_threshold", _saturation_threshold))
	_saturation_max_penalty = float(cfg.get("saturation_max_penalty", _saturation_max_penalty))


func _load_settings(settings_name: String) -> Dictionary:
	if is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_settings"):
			return dl.get_settings(settings_name)
	# Direct file fallback for tests
	var dl_class: GDScript = load("res://scripts/autoloads/data_loader.gd")
	var subpath: String = dl_class.SETTINGS_PATHS.get(settings_name, settings_name)
	var path := "res://data/settings/%s.json" % subpath
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	if json.data is Dictionary:
		return json.data
	return {}


func setup(building_placer: Node) -> void:
	_building_placer = building_placer
	if _building_placer and _building_placer.has_signal("building_placed"):
		_building_placer.building_placed.connect(_on_building_placed)


func register_market(building: Node2D) -> void:
	if _market_data.has(building):
		return
	_market_data[building] = {
		"owner_id": building.owner_id,
		"grid_pos": building.grid_pos,
	}


func unregister_market(building: Node2D) -> void:
	_market_data.erase(building)


func execute_exchange(player_id: int, sell_resource: String, amount: int) -> bool:
	if amount <= 0:
		return false
	if not RESOURCE_NAME_TO_TYPE.has(sell_resource):
		return false
	var res_type: int = RESOURCE_NAME_TO_TYPE[sell_resource]
	# Check player has enough
	var current: int = ResourceManager.get_amount(player_id, res_type)
	if current < amount:
		return false
	var rate: float = get_current_rate(sell_resource)
	var gold_earned: int = int(float(amount) * rate / 100.0)
	gold_earned = int(float(gold_earned) * _trade_income_multiplier.get(player_id, 1.0))
	if gold_earned <= 0:
		return false
	# Deduct resource and add gold
	ResourceManager.add_resource(player_id, res_type, -amount)
	ResourceManager.add_resource(player_id, ResourceManager.ResourceType.GOLD, gold_earned)
	# Record volume for rate fluctuation
	_record_volume(sell_resource, amount)
	exchange_completed.emit(player_id, sell_resource, amount, gold_earned)
	return true


func get_current_rate(sell_resource: String) -> float:
	var base_rate: float = float(_base_exchange_rates.get(sell_resource, 100))
	var volume: int = _get_recent_volume(sell_resource)
	if _saturation_threshold <= 0:
		return base_rate
	var penalty: float = float(volume) / float(_saturation_threshold)
	penalty = minf(penalty, _saturation_max_penalty)
	return base_rate * (1.0 - penalty)


func get_route_pause_time() -> float:
	return _route_pause_time


func notify_route_completed(home_market: Node2D, away_market: Node2D, owner_id: int) -> void:
	if home_market == away_market:
		return
	if not is_instance_valid(home_market) or not is_instance_valid(away_market):
		return
	var home_pos: Vector2i = home_market.grid_pos
	var away_pos: Vector2i = away_market.grid_pos
	var distance: int = maxi(absi(home_pos.x - away_pos.x), absi(home_pos.y - away_pos.y))
	if distance <= 0:
		return
	var ref_dist: int = maxi(_route_reference_distance, 1)
	var gold: int = int(float(_route_base_gold) * float(distance) / float(ref_dist))
	gold = int(float(gold) * _trade_income_multiplier.get(owner_id, 1.0))
	if gold <= 0:
		gold = 1
	ResourceManager.add_resource(owner_id, ResourceManager.ResourceType.GOLD, gold)
	route_completed.emit(owner_id, gold)


func get_market_info(market: Node2D) -> Dictionary:
	if not _market_data.has(market):
		return {}
	var info: Dictionary = _market_data[market]
	var rates: Dictionary = {}
	for res_name: String in _base_exchange_rates:
		rates[res_name] = get_current_rate(res_name)
	var cart_count: int = _count_active_carts(info.get("owner_id", 0))
	return {
		"rates": rates,
		"active_cart_count": cart_count,
	}


func get_markets_for_player(player_id: int) -> Array:
	var result: Array = []
	for market: Node2D in _market_data:
		if not is_instance_valid(market):
			continue
		var info: Dictionary = _market_data[market]
		if info.get("owner_id", -1) == player_id:
			result.append(market)
	return result


func set_trade_income_multiplier(player_id: int, mult: float) -> void:
	_trade_income_multiplier[player_id] = mult


func clear_trade_income_multiplier(player_id: int) -> void:
	_trade_income_multiplier.erase(player_id)


func _count_active_carts(owner_id: int) -> int:
	var count: int = 0
	var scene_root := get_parent()
	if scene_root == null:
		return 0
	for child in scene_root.get_children():
		if not (child is Node2D):
			continue
		if "owner_id" not in child or child.owner_id != owner_id:
			continue
		if "unit_type" not in child:
			continue
		if child.unit_type == "trade_cart" or child.unit_type == "merchant_ship":
			count += 1
	return count


func _record_volume(sell_resource: String, amount: int) -> void:
	if not _volume_history.has(sell_resource):
		_volume_history[sell_resource] = []
	var now: float = _get_time()
	_volume_history[sell_resource].append([now, amount])


func _get_recent_volume(sell_resource: String) -> int:
	if not _volume_history.has(sell_resource):
		return 0
	var now: float = _get_time()
	var cutoff: float = now - _rate_window_seconds
	var entries: Array = _volume_history[sell_resource]
	# Prune old entries
	var pruned: Array = []
	var total: int = 0
	for entry: Array in entries:
		if float(entry[0]) >= cutoff:
			pruned.append(entry)
			total += int(entry[1])
	_volume_history[sell_resource] = pruned
	return total


func _get_time() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _on_building_placed(building: Node2D) -> void:
	if not is_instance_valid(building):
		return
	if building.building_name == "market":
		if building.under_construction:
			building.construction_complete.connect(_on_market_construction_complete)
		else:
			register_market(building)
	# Listen for destruction
	if building.has_signal("building_destroyed"):
		building.building_destroyed.connect(_on_building_destroyed)


func _on_market_construction_complete(building: Node2D) -> void:
	register_market(building)


func _on_building_destroyed(building: Node2D) -> void:
	if building.building_name == "market":
		unregister_market(building)


func save_state() -> Dictionary:
	var markets_out: Array[Dictionary] = []
	for market: Node2D in _market_data:
		if not is_instance_valid(market):
			continue
		var info: Dictionary = _market_data[market]
		(
			markets_out
			. append(
				{
					"grid_pos": [info["grid_pos"].x, info["grid_pos"].y],
					"owner_id": info.get("owner_id", 0),
				}
			)
		)
	# Serialize volume history
	var volumes_out: Dictionary = {}
	for res_name: String in _volume_history:
		var entries: Array = _volume_history[res_name]
		var serialized: Array = []
		for entry: Array in entries:
			serialized.append([float(entry[0]), int(entry[1])])
		volumes_out[res_name] = serialized
	return {
		"markets": markets_out,
		"volume_history": volumes_out,
	}


func load_state(data: Dictionary) -> void:
	# Restore volume history
	var volumes_in: Dictionary = data.get("volume_history", {})
	_volume_history.clear()
	for res_name: String in volumes_in:
		var entries: Array = volumes_in[res_name]
		var restored: Array = []
		for entry: Array in entries:
			restored.append([float(entry[0]), int(entry[1])])
		_volume_history[res_name] = restored
	# Markets are restored by matching grid positions to placed buildings
	var markets_data: Array = data.get("markets", [])
	for entry: Dictionary in markets_data:
		var pos_arr: Array = entry.get("grid_pos", [0, 0])
		var grid_pos := Vector2i(int(pos_arr[0]), int(pos_arr[1]))
		var market := _find_market_at(grid_pos)
		if market != null:
			register_market(market)


func _find_market_at(grid_pos: Vector2i) -> Node2D:
	if _building_placer == null:
		return null
	for entry: Dictionary in _building_placer._placed_buildings:
		var node: Node2D = entry.get("node")
		if is_instance_valid(node) and node.grid_pos == grid_pos:
			if entry.get("building_name", "") == "market":
				return node
	return null
