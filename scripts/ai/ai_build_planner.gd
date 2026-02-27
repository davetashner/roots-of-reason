class_name AIBuildPlanner
extends RefCounted
## AIBuildPlanner — decides what buildings to place, processes build order steps,
## handles unit production and age advancement. Extracted from AIEconomy to
## separate build planning from resource allocation.

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
var config: Dictionary = {}
var build_order: Array = []
var build_order_index: int = 0
var trained_count: Dictionary = {}
var destroyed_tc_positions: Array[Vector2i] = []
var tr_config: Dictionary = {}

var _scene_root: Node = null
var _population_manager: Node = null
var _pathfinder: Node = null
var _map_node: Node = null
var _target_detector: Node = null
var _tech_manager: Node = null
var _own_villagers: Array[Node2D] = []


func setup(
	scene_root: Node,
	pop_mgr: Node,
	pathfinder: Node,
	map_node: Node,
	target_detector: Node,
	tech_manager: Node,
	p_config: Dictionary,
	p_build_order: Array,
	p_tr_config: Dictionary,
) -> void:
	_scene_root = scene_root
	_population_manager = pop_mgr
	_pathfinder = pathfinder
	_map_node = map_node
	_target_detector = target_detector
	_tech_manager = tech_manager
	config = p_config
	build_order = p_build_order
	tr_config = p_tr_config


func check_house_needed(
	own_buildings: Array[Node2D],
	own_villagers: Array[Node2D],
	town_center: Node2D,
) -> bool:
	_own_villagers = own_villagers
	if _population_manager == null:
		return false
	var buffer: int = int(config.get("near_cap_house_buffer", 3))
	var current: int = _population_manager.get_population(player_id)
	var cap: int = _population_manager.get_population_cap(player_id)
	if cap - current > buffer:
		return false
	# Check if we already have a house under construction
	for building in own_buildings:
		if building.building_name == "house" and building.under_construction:
			return false
	return place_building("house", town_center) != null


func process_build_order(
	own_villagers: Array[Node2D],
	town_center: Node2D,
) -> bool:
	_own_villagers = own_villagers
	if build_order_index >= build_order.size():
		return _try_opportunistic_train(own_villagers, town_center)
	var step: Dictionary = build_order[build_order_index]
	var action: String = str(step.get("action", ""))
	match action:
		"train":
			return _process_train_step(step, own_villagers, town_center)
		"build":
			return _process_build_step(step, town_center)
		"advance_age":
			return _process_advance_age_step()
	# Unknown action — skip
	build_order_index += 1
	return false


func place_building(bname: String, town_center: Node2D) -> Node2D:
	var stats: Dictionary = DataLoader.get_building_stats(bname)
	if stats.is_empty():
		return null
	var raw_costs: Dictionary = stats.get("build_cost", {})
	var costs := _parse_costs(raw_costs)
	if not ResourceManager.can_afford(player_id, costs):
		return null
	var fp: Array = stats.get("footprint", [1, 1])
	var footprint := Vector2i(int(fp[0]), int(fp[1]))
	var grid_pos := _find_valid_placement(footprint, bname, town_center)
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


func on_unit_produced(unit_type: String, building: Node2D) -> void:
	if _scene_root == null:
		return
	var unit := Node2D.new()
	var unit_count := _scene_root.get_child_count()
	unit.name = "AIUnit_%d" % unit_count
	unit.set_script(UnitScript)
	unit.unit_type = unit_type
	unit.owner_id = player_id
	unit.unit_color = Color(0.9, 0.2, 0.2)
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


func _process_train_step(
	step: Dictionary,
	own_villagers: Array[Node2D],
	town_center: Node2D,
) -> bool:
	var unit_type: String = str(step.get("unit", "villager"))
	var target_count: int = int(step.get("count", 1))
	var step_key: String = str(build_order_index)
	var trained_so_far: int = int(trained_count.get(step_key, 0))
	var max_vill: int = int(config.get("max_villagers", 30))
	var at_max: bool = unit_type == "villager" and own_villagers.size() >= max_vill
	if trained_so_far >= target_count or at_max:
		build_order_index += 1
		return false
	if not _try_queue_unit(unit_type, town_center):
		return false
	trained_count[step_key] = trained_so_far + 1
	if trained_so_far + 1 >= target_count:
		build_order_index += 1
	return true


func _try_queue_unit(unit_type: String, town_center: Node2D) -> bool:
	if town_center == null:
		return false
	var pq: Node = town_center.get_node_or_null("ProductionQueue")
	if pq == null or not pq.has_method("can_produce"):
		return false
	if not pq.can_produce(unit_type):
		return false
	return pq.add_to_queue(unit_type)


func _process_build_step(step: Dictionary, town_center: Node2D) -> bool:
	var building_name: String = str(step.get("building", ""))
	if building_name == "":
		build_order_index += 1
		return false
	if building_name == "town_center" and not _should_build_forward_tc(town_center):
		return false
	var building := place_building(building_name, town_center)
	if building != null:
		build_order_index += 1
		return true
	return false


func _process_advance_age_step() -> bool:
	var next_age: int = GameManager.current_age + 1
	var ages_data: Array = DataLoader.get_ages_data()
	if next_age >= ages_data.size():
		build_order_index += 1
		return false
	var age_entry: Dictionary = ages_data[next_age]
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
	build_order_index += 1
	return true


func _try_opportunistic_train(
	own_villagers: Array[Node2D],
	town_center: Node2D,
) -> bool:
	var max_vill: int = int(config.get("max_villagers", 30))
	if own_villagers.size() >= max_vill:
		return false
	if town_center == null:
		return false
	var pq: Node = town_center.get_node_or_null("ProductionQueue")
	if pq == null:
		return false
	if not pq.has_method("can_produce") or not pq.can_produce("villager"):
		return false
	return pq.add_to_queue("villager")


func _should_build_forward_tc(_town_center: Node2D) -> bool:
	var ftc: Dictionary = tr_config.get("forward_tc", {})
	var min_adv: float = float(ftc.get("min_military_advantage_ratio", 1.8))
	var max_tech_risky: int = int(ftc.get("max_tech_count_for_risky_build", 15))
	var own_mil: int = _count_military_units(player_id)
	var enemy_pid: int = 0 if player_id != 0 else 1
	var enemy_mil: int = _count_military_units(enemy_pid)
	if _tech_manager != null:
		var tech_count: int = _tech_manager.get_researched_techs(player_id).size()
		if tech_count > max_tech_risky:
			min_adv *= 1.5
	if enemy_mil > 0:
		var ratio: float = float(own_mil) / float(enemy_mil)
		return ratio >= min_adv
	return own_mil > 0


func _count_military_units(owner: int) -> int:
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


func _find_valid_placement(
	footprint: Vector2i,
	building_name: String,
	town_center: Node2D,
) -> Vector2i:
	if town_center == null:
		return Vector2i(-1, -1)
	var tc_pos: Vector2i = town_center.grid_pos
	var radius: int = int(config.get("building_search_radius", 15))
	var avoid_radius: int = 0
	if building_name == "town_center":
		var tlr: Dictionary = tr_config.get("tech_loss_response", {})
		avoid_radius = int(tlr.get("destroyed_position_avoid_radius_tiles", 10))
	for r in range(3, radius + 1):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var pos := tc_pos + Vector2i(dx, dy)
				var constraint: String = ""
				if not BuildingValidator.is_placement_valid(pos, footprint, _map_node, _pathfinder, constraint):
					continue
				if avoid_radius > 0 and _is_near_destroyed_tc(pos, avoid_radius):
					continue
				return pos
	return Vector2i(-1, -1)


func _is_near_destroyed_tc(pos: Vector2i, radius: int) -> bool:
	for dtc_pos in destroyed_tc_positions:
		var dist: int = absi(pos.x - dtc_pos.x) + absi(pos.y - dtc_pos.y)
		if dist <= radius:
			return true
	return false


func _on_building_complete(building: Node2D) -> void:
	if _population_manager != null and "owner_id" in building:
		_population_manager.register_building(building, building.owner_id)
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
	pq.unit_produced.connect(on_unit_produced)


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


func _parse_costs(raw_costs: Dictionary) -> Dictionary:
	var costs: Dictionary = {}
	for key: String in raw_costs:
		var lower_key := key.to_lower()
		if RESOURCE_NAME_TO_TYPE.has(lower_key):
			costs[RESOURCE_NAME_TO_TYPE[lower_key]] = int(raw_costs[key])
	return costs
