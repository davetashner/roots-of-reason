extends Node
## Manages resource stockpiles for all players.

signal resources_changed(player_id: int, resource_type: String, old_amount: int, new_amount: int)

enum ResourceType { FOOD, WOOD, STONE, GOLD, KNOWLEDGE }

const RESOURCE_NAMES: Dictionary = {
	ResourceType.FOOD: "Food",
	ResourceType.WOOD: "Wood",
	ResourceType.STONE: "Stone",
	ResourceType.GOLD: "Gold",
	ResourceType.KNOWLEDGE: "Knowledge",
}

const RESOURCE_KEYS: Dictionary = {
	ResourceType.FOOD: "food",
	ResourceType.WOOD: "wood",
	ResourceType.STONE: "stone",
	ResourceType.GOLD: "gold",
	ResourceType.KNOWLEDGE: "knowledge",
}

# player_id -> { ResourceType -> amount }
var _stockpiles: Dictionary = {}
var _config: Dictionary = {}


func _ready() -> void:
	_load_config()


func _load_config() -> void:
	_config = DataLoader.load_json("res://data/resources/resource_config.json")
	if _config == null:
		_config = {}


func get_amount(player_id: int, resource_type: ResourceType) -> int:
	if player_id not in _stockpiles:
		return 0
	return _stockpiles[player_id].get(resource_type, 0)


func add_resource(player_id: int, resource_type: ResourceType, amount: int) -> void:
	if player_id not in _stockpiles:
		_stockpiles[player_id] = {}
	var old_amount: int = _stockpiles[player_id].get(resource_type, 0)
	_stockpiles[player_id][resource_type] = old_amount + amount
	(
		resources_changed
		. emit(
			player_id,
			RESOURCE_NAMES[resource_type],
			old_amount,
			_stockpiles[player_id][resource_type],
		)
	)


func can_afford(player_id: int, costs: Dictionary) -> bool:
	for resource_type: ResourceType in costs:
		if get_amount(player_id, resource_type) < costs[resource_type]:
			return false
	return true


func spend(player_id: int, costs: Dictionary) -> bool:
	if not can_afford(player_id, costs):
		return false
	for resource_type: ResourceType in costs:
		add_resource(player_id, resource_type, -costs[resource_type])
	return true


func get_starting_resources(difficulty: String = "") -> Dictionary:
	if difficulty == "":
		difficulty = _config.get("default_difficulty", "normal")
	var resources_data: Dictionary = _config.get("resources", {})
	var result: Dictionary = {}
	for resource_type: ResourceType in ResourceType.values():
		var key: String = RESOURCE_KEYS[resource_type]
		if key in resources_data:
			var starting: Dictionary = resources_data[key].get("starting_amount", {})
			result[resource_type] = starting.get(difficulty, 0)
		else:
			result[resource_type] = 0
	return result


func init_player(player_id: int, starting_resources: Variant = null, difficulty: String = "") -> void:
	if starting_resources == null:
		starting_resources = get_starting_resources(difficulty)
	_stockpiles[player_id] = {}
	for resource_type: ResourceType in ResourceType.values():
		var amount: int = starting_resources.get(resource_type, 0)
		if amount < 0:
			push_warning(
				(
					"ResourceManager: Negative starting %s (%d) for player %d, using 0"
					% [RESOURCE_NAMES[resource_type], amount, player_id]
				)
			)
			amount = 0
		_stockpiles[player_id][resource_type] = amount


func reset() -> void:
	_stockpiles.clear()


func save_state() -> Dictionary:
	var data: Dictionary = {}
	for player_id: int in _stockpiles:
		var player_data: Dictionary = {}
		for resource_type: ResourceType in _stockpiles[player_id]:
			player_data[RESOURCE_KEYS[resource_type]] = _stockpiles[player_id][resource_type]
		data[str(player_id)] = player_data
	return data


func load_state(data: Dictionary) -> void:
	_stockpiles.clear()
	for player_id_str: String in data:
		var player_id: int = int(player_id_str)
		_stockpiles[player_id] = {}
		var player_data: Dictionary = data[player_id_str]
		for resource_type: ResourceType in ResourceType.values():
			var key: String = RESOURCE_KEYS[resource_type]
			_stockpiles[player_id][resource_type] = player_data.get(key, 0)
