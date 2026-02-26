class_name AIEconomy
extends Node
## AI economy brain — drives villager allocation, build orders, house building,
## and age advancement. Runs on a configurable tick timer, not every frame.
## Each tick evaluates state and executes at most one resource-spending action.

const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const ProductionQueueScript := preload("res://scripts/prototype/production_queue.gd")

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

var _tick_timer: float = 0.0
var _config: Dictionary = {}
var _build_order: Array = []
var _build_order_index: int = 0
var _villager_allocation: Dictionary = {}
var _town_center: Node2D = null
var _trained_count: Dictionary = {}

# Cached entity lists (refreshed each tick)
var _own_villagers: Array[Node2D] = []
var _own_buildings: Array[Node2D] = []


func setup(
	scene_root: Node,
	pop_mgr: Node,
	pathfinder: Node,
	map_node: Node,
	target_detector: Node,
	tech_manager: Node = null,
) -> void:
	_scene_root = scene_root
	_population_manager = pop_mgr
	_pathfinder = pathfinder
	_map_node = map_node
	_target_detector = target_detector
	_tech_manager = tech_manager
	_load_config()
	_load_build_order()


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
	# Check personality build order override first
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
	# Default: load from difficulty-based build orders
	var data: Variant = DataLoader.load_json("res://data/ai/build_orders.json")
	if data == null or not data is Dictionary:
		return
	var diff_data: Dictionary = data.get(difficulty, {})
	_build_order = diff_data.get("steps", [])
	_villager_allocation = diff_data.get("villager_allocation", {})


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
	# Priority 1: build house if near pop cap
	if _check_house_needed():
		_rebalance_gatherers()
		return
	# Priority 2: walk build order steps (one spending action per tick)
	if _process_build_order():
		_rebalance_gatherers()
		return
	# Fallback: just rebalance
	_rebalance_gatherers()


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
			# It's a unit
			_own_villagers.append(child)
		elif "building_name" in child:
			_own_buildings.append(child)
			if child.building_name == "town_center" and not child.under_construction:
				_town_center = child


func _check_house_needed() -> bool:
	if _population_manager == null:
		return false
	var buffer: int = int(_config.get("near_cap_house_buffer", 3))
	var current: int = _population_manager.get_population(player_id)
	var cap: int = _population_manager.get_population_cap(player_id)
	if cap - current > buffer:
		return false
	# Check if we already have a house under construction
	for building in _own_buildings:
		if building.building_name == "house" and building.under_construction:
			return false
	return _place_building("house") != null


func _process_build_order() -> bool:
	if _build_order_index >= _build_order.size():
		# Build order exhausted — try opportunistic villager training
		return _try_opportunistic_train()
	var step: Dictionary = _build_order[_build_order_index]
	var action: String = str(step.get("action", ""))
	match action:
		"train":
			return _process_train_step(step)
		"build":
			return _process_build_step(step)
		"advance_age":
			return _process_advance_age_step()
	# Unknown action — skip
	_build_order_index += 1
	return false


func _process_train_step(step: Dictionary) -> bool:
	var unit_type: String = str(step.get("unit", "villager"))
	var target_count: int = int(step.get("count", 1))
	var step_key: String = str(_build_order_index)
	var trained_so_far: int = int(_trained_count.get(step_key, 0))
	# Skip step if already trained enough or at max villagers
	var max_vill: int = int(_config.get("max_villagers", 30))
	var at_max: bool = unit_type == "villager" and _own_villagers.size() >= max_vill
	if trained_so_far >= target_count or at_max:
		_build_order_index += 1
		return false
	# Try to queue at town center
	if not _try_queue_unit(unit_type):
		return false
	_trained_count[step_key] = trained_so_far + 1
	if trained_so_far + 1 >= target_count:
		_build_order_index += 1
	return true


func _try_queue_unit(unit_type: String) -> bool:
	if _town_center == null:
		return false
	var pq: Node = _town_center.get_node_or_null("ProductionQueue")
	if pq == null or not pq.has_method("can_produce"):
		return false
	if not pq.can_produce(unit_type):
		return false
	return pq.add_to_queue(unit_type)


func _process_build_step(step: Dictionary) -> bool:
	var building_name: String = str(step.get("building", ""))
	if building_name == "":
		_build_order_index += 1
		return false
	var building := _place_building(building_name)
	if building != null:
		_build_order_index += 1
		return true
	return false


func _process_advance_age_step() -> bool:
	var next_age: int = GameManager.current_age + 1
	var ages_data: Array = DataLoader.get_ages_data()
	if next_age >= ages_data.size():
		_build_order_index += 1
		return false
	var age_entry: Dictionary = ages_data[next_age]
	# Check tech prerequisites — wait for AITech to research them
	if _tech_manager != null:
		var prereqs: Array = age_entry.get("advance_prerequisites", [])
		for prereq: String in prereqs:
			if not _tech_manager.is_tech_researched(prereq, player_id):
				return false
	var raw_costs: Dictionary = age_entry.get("advance_cost", {})
	var costs := _parse_costs(raw_costs)
	if not ResourceManager.can_afford(player_id, costs):
		return false
	if not ResourceManager.spend(player_id, costs):
		return false
	GameManager.advance_age(next_age)
	_build_order_index += 1
	return true


func _try_opportunistic_train() -> bool:
	var max_vill: int = int(_config.get("max_villagers", 30))
	if _own_villagers.size() >= max_vill:
		return false
	if _town_center == null:
		return false
	var pq: Node = _town_center.get_node_or_null("ProductionQueue")
	if pq == null:
		return false
	if not pq.has_method("can_produce") or not pq.can_produce("villager"):
		return false
	return pq.add_to_queue("villager")


func _place_building(bname: String) -> Node2D:
	var stats: Dictionary = DataLoader.get_building_stats(bname)
	if stats.is_empty():
		return null
	var raw_costs: Dictionary = stats.get("build_cost", {})
	var costs := _parse_costs(raw_costs)
	if not ResourceManager.can_afford(player_id, costs):
		return null
	var fp: Array = stats.get("footprint", [1, 1])
	var footprint := Vector2i(int(fp[0]), int(fp[1]))
	var grid_pos := _find_valid_placement(footprint)
	if grid_pos == Vector2i(-1, -1):
		return null
	if not ResourceManager.spend(player_id, costs):
		return null
	var building := Node2D.new()
	building.name = "Building_%s_%d_%d" % [bname, grid_pos.x, grid_pos.y]
	building.set_script(BuildingScript)
	building.position = IsoUtils.grid_to_screen(Vector2(grid_pos))
	building.building_name = bname
	building.footprint = footprint
	building.grid_pos = grid_pos
	building.owner_id = player_id
	building.max_hp = int(stats.get("hp", 100))
	building.entity_category = "enemy_building"
	building.under_construction = true
	building.build_progress = 0.0
	building.hp = 0
	building._build_time = float(stats.get("build_time", 25))
	_scene_root.add_child(building)
	# Mark footprint cells solid
	if _pathfinder != null:
		var cells := BuildingValidator.get_footprint_cells(grid_pos, footprint)
		for cell in cells:
			_pathfinder.set_cell_solid(cell, true)
	# Register with target detector
	if _target_detector != null:
		_target_detector.register_entity(building)
	# Connect construction_complete for population registration
	if building.has_signal("construction_complete"):
		building.construction_complete.connect(_on_building_complete)
	# Assign nearest idle villager as builder
	var builder := _find_nearest_idle_villager(building.global_position)
	if builder != null and builder.has_method("assign_build_target"):
		builder.assign_build_target(building)
	return building


func _on_building_complete(building: Node2D) -> void:
	if _population_manager != null and "owner_id" in building:
		_population_manager.register_building(building, building.owner_id)
	# Attach production queue if building produces units
	_try_attach_production_queue(building)


func _try_attach_production_queue(building: Node2D) -> void:
	if not "building_name" in building:
		return
	var bname: String = building.building_name
	if bname == "":
		return
	var stats: Dictionary = DataLoader.get_building_stats(bname)
	var units_produced: Array = stats.get("units_produced", [])
	if units_produced.is_empty():
		return
	var pq := Node.new()
	pq.name = "ProductionQueue"
	pq.set_script(ProductionQueueScript)
	building.add_child(pq)
	pq.setup(building, player_id, _population_manager)
	pq.unit_produced.connect(_on_unit_produced)


func _on_unit_produced(unit_type: String, building: Node2D) -> void:
	if _scene_root == null:
		return
	var unit := Node2D.new()
	var unit_count := _scene_root.get_child_count()
	unit.name = "AIUnit_%d" % unit_count
	unit.set_script(UnitScript)
	unit.unit_type = unit_type
	unit.owner_id = player_id
	unit.unit_color = Color(0.9, 0.2, 0.2)
	# Spawn at building position offset by rally point
	var pq: Node = building.get_node_or_null("ProductionQueue")
	var offset := Vector2i(1, 1)
	if pq != null and pq.has_method("get_rally_point_offset"):
		offset = pq.get_rally_point_offset()
	var spawn_grid := Vector2i.ZERO
	if "grid_pos" in building:
		spawn_grid = building.grid_pos + offset
	unit.position = IsoUtils.grid_to_screen(Vector2(spawn_grid))
	_scene_root.add_child(unit)
	unit._scene_root = _scene_root
	if _target_detector != null:
		_target_detector.register_entity(unit)
	if _population_manager != null:
		_population_manager.register_unit(unit, player_id)


func _find_valid_placement(footprint: Vector2i) -> Vector2i:
	if _town_center == null:
		return Vector2i(-1, -1)
	var tc_pos: Vector2i = _town_center.grid_pos
	var radius: int = int(_config.get("building_search_radius", 15))
	# Spiral search outward from town center
	for r in range(3, radius + 1):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var pos := tc_pos + Vector2i(dx, dy)
				var constraint: String = ""
				if BuildingValidator.is_placement_valid(pos, footprint, _map_node, _pathfinder, constraint):
					return pos
	return Vector2i(-1, -1)


func _find_nearest_idle_villager(target_pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for villager in _own_villagers:
		if not villager.has_method("is_idle") or not villager.is_idle():
			continue
		var dist: float = villager.global_position.distance_to(target_pos)
		if dist < best_dist:
			best_dist = dist
			best = villager
	return best


func _rebalance_gatherers() -> void:
	var target := _get_target_allocation()
	if target.is_empty():
		return
	var current := _get_current_allocation()
	var total_villagers: int = _own_villagers.size()
	if total_villagers == 0:
		return
	# Assign idle villagers to the highest-deficit resource
	for villager in _own_villagers:
		if not villager.has_method("is_idle") or not villager.is_idle():
			continue
		var best_type: String = _get_highest_deficit_resource(target, current, total_villagers)
		if best_type != "":
			if _assign_villager_to_resource(villager, best_type):
				current[best_type] = int(current.get(best_type, 0)) + 1
	# Imbalance check: reassign from surplus
	var threshold: float = float(_config.get("rebalance_threshold", 2.0))
	_check_surplus_rebalance(target, current, total_villagers, threshold)


func _get_target_allocation() -> Dictionary:
	var age_key: String = str(GameManager.current_age)
	if _villager_allocation.has(age_key):
		return _villager_allocation[age_key]
	# Fallback to age 0
	return _villager_allocation.get("0", {})


func _get_current_allocation() -> Dictionary:
	var counts: Dictionary = {"food": 0, "wood": 0, "stone": 0, "gold": 0}
	for villager in _own_villagers:
		if "_gather_type" not in villager:
			continue
		var gtype: String = villager._gather_type
		if gtype in counts:
			counts[gtype] = int(counts[gtype]) + 1
	return counts


func _get_highest_deficit_resource(target: Dictionary, current: Dictionary, total: int) -> String:
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


func _check_surplus_rebalance(target: Dictionary, current: Dictionary, total: int, threshold: float) -> void:
	# Find resource with lowest needed stockpile
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
	# Check if any stockpile exceeds threshold * lowest
	for res_type: String in target:
		var res_enum: Variant = RESOURCE_NAME_TO_TYPE.get(res_type)
		if res_enum == null:
			continue
		var amount: float = float(ResourceManager.get_amount(player_id, res_enum))
		if amount > threshold * min_needed and int(current.get(res_type, 0)) > 0:
			# Find a gatherer of this type and reassign
			var deficit_type := _get_highest_deficit_resource(target, current, total)
			if deficit_type == "" or deficit_type == res_type:
				continue
			for villager in _own_villagers:
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
	# Find nearest to villager
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
	var search_radius: float = float(_config.get("resource_search_radius", 20))
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


func _parse_costs(raw_costs: Dictionary) -> Dictionary:
	var costs: Dictionary = {}
	for key: String in raw_costs:
		var lower_key := key.to_lower()
		if RESOURCE_NAME_TO_TYPE.has(lower_key):
			costs[RESOURCE_NAME_TO_TYPE[lower_key]] = int(raw_costs[key])
	return costs


func save_state() -> Dictionary:
	var tc: Dictionary = {}
	for k: String in _trained_count:
		tc[k] = int(_trained_count[k])
	var state: Dictionary = {
		"build_order_index": _build_order_index,
		"trained_count": tc,
		"tick_timer": _tick_timer,
		"difficulty": difficulty,
		"player_id": player_id,
	}
	if personality != null:
		state["personality_id"] = personality.personality_id
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
	_load_config()
	_load_build_order()
