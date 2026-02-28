class_name AIEconomy
extends Node
## AI economy brain — coordinates AIBuildPlanner (build orders, building placement,
## unit production) and AIResourceAllocator (villager assignment, resource balancing).
## Runs on a configurable tick timer, not every frame. Each tick evaluates state
## and executes at most one resource-spending action.

const RESOURCE_NAME_TO_TYPE: Dictionary = {
	"food": ResourceManager.ResourceType.FOOD,
	"wood": ResourceManager.ResourceType.WOOD,
	"stone": ResourceManager.ResourceType.STONE,
	"gold": ResourceManager.ResourceType.GOLD,
	"knowledge": ResourceManager.ResourceType.KNOWLEDGE,
}

var player_id: int = 1
var difficulty: String = "normal"
var personality: AIPersonality = null

var _scene_root: Node = null
var _population_manager: Node = null
var _pathfinder: Node = null
var _map_node: Node = null
var _target_detector: Node = null
var _tech_manager: Node = null
var _entity_registry: RefCounted = null

var _tick_timer: float = 0.0
var _config: Dictionary = {}
var _build_order: Array = []
var _build_order_index: int = 0
var _villager_allocation: Dictionary = {}
var _town_center: Node2D = null
var _trained_count: Dictionary = {}
var _destroyed_tc_positions: Array[Vector2i] = []
var _tr_config: Dictionary = {}

# Cached entity lists (refreshed each tick)
var _own_villagers: Array[Node2D] = []
var _own_buildings: Array[Node2D] = []

# Component delegates
var _build_planner: AIBuildPlanner = null
var _resource_allocator: AIResourceAllocator = null


func setup(
	scene_root: Node,
	pop_mgr: Node,
	pathfinder: Node,
	map_node: Node,
	target_detector: Node,
	tech_manager: Node = null,
	entity_registry: RefCounted = null,
) -> void:
	_scene_root = scene_root
	_population_manager = pop_mgr
	_pathfinder = pathfinder
	_map_node = map_node
	_target_detector = target_detector
	_tech_manager = tech_manager
	_entity_registry = entity_registry
	_load_config()
	_load_build_order()
	_load_tr_config()
	_setup_components()


func _setup_components() -> void:
	_build_planner = AIBuildPlanner.new()
	_build_planner.player_id = player_id
	_build_planner.build_order_index = _build_order_index
	_build_planner.trained_count = _trained_count
	_build_planner.destroyed_tc_positions = _destroyed_tc_positions
	_build_planner._entity_registry = _entity_registry
	_build_planner.setup(
		_scene_root,
		_population_manager,
		_pathfinder,
		_map_node,
		_target_detector,
		_tech_manager,
		_config,
		_build_order,
		_tr_config
	)

	_resource_allocator = AIResourceAllocator.new()
	_resource_allocator.player_id = player_id
	_resource_allocator.setup(_scene_root, _config, _villager_allocation)


func _load_config() -> void:
	_config = DataLoader.get_settings("ai_economy")
	if _config.is_empty():
		_config = {
			"tick_interval": 2.0,
			"rebalance_threshold": 2.0,
			"near_cap_house_buffer": 3,
			"max_villagers": 30,
			"building_search_radius": 15,
			"resource_search_radius": 20,
		}
	if personality != null:
		_config = personality.apply_economy_modifiers(_config)


func _load_build_order() -> void:
	var override_key: String = ""
	if personality != null:
		override_key = personality.get_build_order_override()
	if override_key != "":
		var pdata: Variant = DataLoader.load_json("res://data/ai/personality_build_orders.json")
		if pdata is Dictionary and pdata.has(override_key):
			var bo: Dictionary = pdata[override_key]
			_build_order = bo.get("steps", [])
			_villager_allocation = bo.get("villager_allocation", {})
			return
	var data: Variant = DataLoader.load_json("res://data/ai/build_orders.json")
	if data == null or not data is Dictionary:
		return
	var diff_data: Dictionary = data.get(difficulty, {})
	_build_order = diff_data.get("steps", [])
	_villager_allocation = diff_data.get("villager_allocation", {})


func _load_tr_config() -> void:
	var data: Variant = DataLoader.load_json("res://data/ai/tech_regression_config.json")
	if data == null or not data is Dictionary:
		_tr_config = {}
		return
	_tr_config = data
	if personality == null:
		return
	var overrides: Dictionary = _tr_config.get("personality_overrides", {})
	var pid: String = personality.personality_id
	if pid not in overrides:
		return
	var pov: Dictionary = overrides[pid]
	for key: String in pov:
		var parts: Array = key.split(".")
		if parts.size() != 2:
			continue
		var section: String = parts[0]
		var field: String = parts[1]
		if section in _tr_config and _tr_config[section] is Dictionary:
			_tr_config[section][field] = pov[key]


func _process(delta: float) -> void:
	var game_delta := GameManager.get_game_delta(delta)
	if game_delta <= 0.0:
		return
	_tick_timer += game_delta
	var interval: float = float(_config.get("tick_interval", 2.0))
	if _tick_timer < interval:
		return
	_tick_timer -= interval
	_tick()


func _tick() -> void:
	_refresh_entity_lists()
	# Sync planner state from coordinator (in case of load_state)
	_build_planner.build_order_index = _build_order_index
	_build_planner.trained_count = _trained_count
	_build_planner.destroyed_tc_positions = _destroyed_tc_positions
	# Nomadic mode: no TC yet — only execute build order (place TC first)
	if _town_center == null and difficulty in ["hard", "expert"]:
		_build_planner.process_build_order(_own_villagers, _town_center)
		_sync_planner_state()
		return
	# Priority 1: build house if near pop cap
	if _build_planner.check_house_needed(_own_buildings, _own_villagers, _town_center):
		_sync_planner_state()
		_resource_allocator.rebalance_gatherers(_own_villagers, _town_center)
		return
	# Priority 2: walk build order steps (one spending action per tick)
	if _build_planner.process_build_order(_own_villagers, _town_center):
		_sync_planner_state()
		_resource_allocator.rebalance_gatherers(_own_villagers, _town_center)
		return
	# Fallback: just rebalance
	_sync_planner_state()
	_resource_allocator.rebalance_gatherers(_own_villagers, _town_center)


func _sync_planner_state() -> void:
	## Pull mutable state back from planner into coordinator for save/load.
	_build_order_index = _build_planner.build_order_index
	_trained_count = _build_planner.trained_count
	_destroyed_tc_positions = _build_planner.destroyed_tc_positions


func _count_military_units(owner: int) -> int:
	if _entity_registry != null:
		return _entity_registry.get_count_by_owner_and_category(owner, "military")
	var count: int = 0
	if _scene_root == null:
		return count
	for child in _scene_root.get_children():
		if not (child is Node2D):
			continue
		if "owner_id" not in child:
			continue
		if int(child.owner_id) != owner:
			continue
		if not child.has_method("is_idle"):
			continue
		if "unit_category" in child and str(child.unit_category) == "military":
			count += 1
	return count


func _refresh_entity_lists() -> void:
	_own_villagers.clear()
	_own_buildings.clear()
	_town_center = null
	if _scene_root == null:
		return
	for child in _scene_root.get_children():
		if not (child is Node2D):
			continue
		if "owner_id" not in child:
			continue
		if int(child.owner_id) != player_id:
			continue
		if child.has_method("is_idle"):
			_own_villagers.append(child)
		elif "building_name" in child:
			_own_buildings.append(child)
			if child.building_name == "town_center" and not child.under_construction:
				_town_center = child


## Delegation wrappers — maintain backward compatibility for callers and tests.


func _get_target_allocation() -> Dictionary:
	return _resource_allocator._get_target_allocation()


func _rebalance_gatherers() -> void:
	_resource_allocator.rebalance_gatherers(_own_villagers, _town_center)


func _find_resource_nodes(res_type: String) -> Array[Node2D]:
	_resource_allocator._town_center = _town_center
	return _resource_allocator._find_resource_nodes(res_type)


func _get_current_allocation() -> Dictionary:
	return _resource_allocator._get_current_allocation(_own_villagers)


func _process_build_order() -> bool:
	_build_planner.build_order_index = _build_order_index
	_build_planner.trained_count = _trained_count
	var result: bool = _build_planner.process_build_order(_own_villagers, _town_center)
	_sync_planner_state()
	return result


func _place_building(bname: String) -> Node2D:
	_build_planner._own_villagers = _own_villagers
	_build_planner._map_node = _map_node
	_build_planner._pathfinder = _pathfinder
	var building: Node2D = _build_planner.place_building(bname, _town_center)
	return building


func _check_house_needed() -> bool:
	_build_planner._map_node = _map_node
	_build_planner._pathfinder = _pathfinder
	_build_planner._own_villagers = _own_villagers
	return _build_planner.check_house_needed(_own_buildings, _own_villagers, _town_center)


func _find_valid_placement(footprint: Vector2i, building_name: String = "") -> Vector2i:
	_build_planner._map_node = _map_node
	_build_planner._pathfinder = _pathfinder
	return _build_planner._find_valid_placement(footprint, building_name, _town_center)


func _should_build_forward_tc() -> bool:
	return _build_planner._should_build_forward_tc(_town_center)


func _is_near_destroyed_tc(pos: Vector2i, radius: int) -> bool:
	_build_planner.destroyed_tc_positions = _destroyed_tc_positions
	return _build_planner._is_near_destroyed_tc(pos, radius)


func on_building_destroyed(building: Node2D) -> void:
	if not "building_name" in building:
		return
	if building.building_name != "town_center":
		return
	if "grid_pos" in building:
		_destroyed_tc_positions.append(building.grid_pos)
		if _build_planner != null:
			_build_planner.destroyed_tc_positions = _destroyed_tc_positions


func save_state() -> Dictionary:
	var tc: Dictionary = {}
	for k: String in _trained_count:
		tc[k] = int(_trained_count[k])
	var dtc_serialized: Array = []
	for pos in _destroyed_tc_positions:
		dtc_serialized.append([pos.x, pos.y])
	var state: Dictionary = {
		"build_order_index": _build_order_index,
		"trained_count": tc,
		"tick_timer": _tick_timer,
		"difficulty": difficulty,
		"player_id": player_id,
		"destroyed_tc_positions": dtc_serialized,
	}
	if personality != null:
		state["personality_id"] = personality.personality_id
	if _build_planner != null and _build_planner.spawn_position != Vector2i(-1, -1):
		state["spawn_position"] = [_build_planner.spawn_position.x, _build_planner.spawn_position.y]
	return state


func load_state(data: Dictionary) -> void:
	_build_order_index = int(data.get("build_order_index", 0))
	_tick_timer = float(data.get("tick_timer", 0.0))
	difficulty = str(data.get("difficulty", difficulty))
	player_id = int(data.get("player_id", player_id))
	var pid: String = str(data.get("personality_id", ""))
	if pid != "":
		personality = AIPersonality.get_personality(pid)
	var tc: Dictionary = data.get("trained_count", {})
	_trained_count.clear()
	for k: String in tc:
		_trained_count[k] = int(tc[k])
	_destroyed_tc_positions.clear()
	var dtc: Array = data.get("destroyed_tc_positions", [])
	for entry in dtc:
		if entry is Array and entry.size() == 2:
			_destroyed_tc_positions.append(Vector2i(int(entry[0]), int(entry[1])))
	var sp: Array = data.get("spawn_position", [])
	_load_config()
	_load_build_order()
	_load_tr_config()
	_setup_components()
	if sp.size() == 2:
		_build_planner.spawn_position = Vector2i(int(sp[0]), int(sp[1]))
