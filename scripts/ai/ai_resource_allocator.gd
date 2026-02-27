class_name AIResourceAllocator
extends RefCounted
## AIResourceAllocator — handles villager assignment to resources and
## rebalancing gatherers between resource types. Extracted from AIEconomy
## to separate resource allocation from build planning.

const RESOURCE_NAME_TO_TYPE: Dictionary = {
	"food": ResourceManager.ResourceType.FOOD,
	"wood": ResourceManager.ResourceType.WOOD,
	"stone": ResourceManager.ResourceType.STONE,
	"gold": ResourceManager.ResourceType.GOLD,
	"knowledge": ResourceManager.ResourceType.KNOWLEDGE,
}

var player_id: int = 1
var config: Dictionary = {}
var villager_allocation: Dictionary = {}

var _scene_root: Node = null
var _town_center: Node2D = null


func setup(
	scene_root: Node,
	p_config: Dictionary,
	p_villager_allocation: Dictionary,
) -> void:
	_scene_root = scene_root
	config = p_config
	villager_allocation = p_villager_allocation


func rebalance_gatherers(
	own_villagers: Array[Node2D],
	town_center: Node2D,
) -> void:
	_town_center = town_center
	var target := _get_target_allocation()
	if target.is_empty():
		return
	var current := _get_current_allocation(own_villagers)
	var total_villagers: int = own_villagers.size()
	if total_villagers == 0:
		return
	# Assign idle villagers to the highest-deficit resource
	for villager in own_villagers:
		if not villager.has_method("is_idle") or not villager.is_idle():
			continue
		var best_type: String = _get_highest_deficit_resource(target, current, total_villagers)
		if best_type != "":
			if _assign_villager_to_resource(villager, best_type):
				current[best_type] = int(current.get(best_type, 0)) + 1
	# Imbalance check: reassign from surplus
	var threshold: float = float(config.get("rebalance_threshold", 2.0))
	_check_surplus_rebalance(target, current, total_villagers, threshold, own_villagers)


func find_nearest_idle_villager(
	own_villagers: Array[Node2D],
	target_pos: Vector2,
) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for villager in own_villagers:
		if not villager.has_method("is_idle") or not villager.is_idle():
			continue
		var dist: float = villager.global_position.distance_to(target_pos)
		if dist < best_dist:
			best_dist = dist
			best = villager
	return best


func _get_target_allocation() -> Dictionary:
	var age_key: String = str(GameManager.current_age)
	if villager_allocation.has(age_key):
		return villager_allocation[age_key]
	return villager_allocation.get("0", {})


func _get_current_allocation(own_villagers: Array[Node2D]) -> Dictionary:
	var counts: Dictionary = {"food": 0, "wood": 0, "stone": 0, "gold": 0}
	for villager in own_villagers:
		if "_gather_type" not in villager:
			continue
		var gtype: String = villager._gather_type
		if gtype in counts:
			counts[gtype] = int(counts[gtype]) + 1
	return counts


func _get_highest_deficit_resource(
	target: Dictionary,
	current: Dictionary,
	total: int,
) -> String:
	var best_type: String = ""
	var best_deficit: float = -INF
	for res_type: String in target:
		var target_count: float = float(target[res_type]) * total
		var actual_count: float = float(current.get(res_type, 0))
		var deficit: float = target_count - actual_count
		if deficit > best_deficit:
			best_deficit = deficit
			best_type = res_type
	return best_type


func _check_surplus_rebalance(
	target: Dictionary,
	current: Dictionary,
	total: int,
	threshold: float,
	own_villagers: Array[Node2D],
) -> void:
	var min_needed: float = INF
	for res_type: String in target:
		if float(target[res_type]) <= 0.0:
			continue
		var res_enum: Variant = RESOURCE_NAME_TO_TYPE.get(res_type)
		if res_enum == null:
			continue
		var amount: float = float(ResourceManager.get_amount(player_id, res_enum))
		if amount < min_needed:
			min_needed = amount
	if min_needed == INF or min_needed <= 0.0:
		return
	for res_type: String in target:
		var res_enum: Variant = RESOURCE_NAME_TO_TYPE.get(res_type)
		if res_enum == null:
			continue
		var amount: float = float(ResourceManager.get_amount(player_id, res_enum))
		if amount > threshold * min_needed and int(current.get(res_type, 0)) > 0:
			var deficit_type := _get_highest_deficit_resource(target, current, total)
			if deficit_type == "" or deficit_type == res_type:
				continue
			for villager in own_villagers:
				if "_gather_type" not in villager:
					continue
				if villager._gather_type != res_type:
					continue
				if _assign_villager_to_resource(villager, deficit_type):
					current[res_type] = maxi(int(current.get(res_type, 0)) - 1, 0)
					current[deficit_type] = int(current.get(deficit_type, 0)) + 1
					return


func _assign_villager_to_resource(villager: Node2D, res_type: String) -> bool:
	var nodes := _find_resource_nodes(res_type)
	if nodes.is_empty():
		return false
	var best: Node2D = null
	var best_dist := INF
	for node in nodes:
		var dist: float = villager.global_position.distance_to(node.global_position)
		if dist < best_dist:
			best_dist = dist
			best = node
	if best == null:
		return false
	if villager.has_method("assign_gather_target"):
		villager.assign_gather_target(best)
		return true
	return false


func _find_resource_nodes(res_type: String) -> Array[Node2D]:
	var result: Array[Node2D] = []
	if _scene_root == null:
		return result
	var search_radius: float = float(config.get("resource_search_radius", 20))
	var search_pixels: float = search_radius * 64.0
	var origin := Vector2.ZERO
	if _town_center != null:
		origin = _town_center.global_position
	for child in _scene_root.get_children():
		if "entity_category" not in child:
			continue
		if child.entity_category != "resource_node":
			continue
		if "resource_type" not in child or child.resource_type != res_type:
			continue
		if "current_yield" in child and child.current_yield <= 0:
			continue
		if origin != Vector2.ZERO:
			var dist: float = child.global_position.distance_to(origin)
			if dist > search_pixels:
				continue
		result.append(child)
	return result
