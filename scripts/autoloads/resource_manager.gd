extends Node
## Manages resource stockpiles for all players.

signal resources_changed(player_id: int, resource_type: String, amount: int)

enum ResourceType { FOOD, WOOD, STONE, GOLD, KNOWLEDGE }

const RESOURCE_NAMES: Dictionary = {
	ResourceType.FOOD: "Food",
	ResourceType.WOOD: "Wood",
	ResourceType.STONE: "Stone",
	ResourceType.GOLD: "Gold",
	ResourceType.KNOWLEDGE: "Knowledge",
}

# player_id -> { ResourceType -> amount }
var _stockpiles: Dictionary = {}


func get_amount(player_id: int, resource_type: ResourceType) -> int:
	if player_id not in _stockpiles:
		return 0
	return _stockpiles[player_id].get(resource_type, 0)


func add_resource(player_id: int, resource_type: ResourceType, amount: int) -> void:
	if player_id not in _stockpiles:
		_stockpiles[player_id] = {}
	var current: int = _stockpiles[player_id].get(resource_type, 0)
	_stockpiles[player_id][resource_type] = current + amount
	resources_changed.emit(player_id, RESOURCE_NAMES[resource_type], _stockpiles[player_id][resource_type])


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


func init_player(player_id: int, starting_resources: Dictionary = {}) -> void:
	_stockpiles[player_id] = {}
	for resource_type: ResourceType in ResourceType.values():
		_stockpiles[player_id][resource_type] = starting_resources.get(resource_type, 0)
