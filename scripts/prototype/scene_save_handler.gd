extends RefCounted
## Orchestrates save/load for all scene-level entities (units, buildings, map,
## managers). Extracted from prototype_main to stay under the 1000-line limit.

const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const ResourceNodeScript := preload("res://scripts/prototype/prototype_resource_node.gd")
const ProductionQueueScript := preload("res://scripts/prototype/production_queue.gd")
const WolfAIScript := preload("res://scripts/fauna/wolf_ai.gd")
const DogAIScript := preload("res://scripts/fauna/dog_ai.gd")
const TradeCartAIScript := preload("res://scripts/prototype/trade_cart_ai.gd")

var _root: Node2D = null
var _map_node: Node = null
var _building_placer: Node = null
var _pathfinder: Node = null
var _target_detector: Node = null
var _input_handler: Node = null
var _population_manager: Node = null
var _tech_manager: Node = null
var _trade_manager: Node = null
var _pirate_manager: Node = null
var _pandemic_manager: Node = null
var _corruption_manager: Node = null
var _victory_manager: Node = null
var _historical_event_manager: Node = null
var _game_stats_tracker: Node = null
var _river_transport: Node = null
var _war_survival: Node = null
var _war_bonus: Node = null
var _singularity_regression: Node = null
var _unit_upgrade_manager: Node = null
var _ai_economy: Node = null
var _ai_military: Node = null
var _ai_tech: Node = null
var _ai_singularity: Node = null
var _visibility_manager: Node = null
var _camera: Node = null


func setup(root: Node2D, overrides: Dictionary = {}) -> void:
	_root = root
	_map_node = overrides.get("map_node", root.get_node_or_null("Map"))
	_building_placer = overrides.get("building_placer", root.get_node_or_null("BuildingPlacer"))
	_pathfinder = overrides.get("pathfinder", root.get_node_or_null("PathfindingGrid"))
	_target_detector = overrides.get("target_detector", root.get_node_or_null("TargetDetector"))
	_input_handler = overrides.get("input_handler", root.get_node_or_null("InputHandler"))
	_population_manager = overrides.get("population_manager", root.get_node_or_null("PopulationManager"))
	_tech_manager = overrides.get("tech_manager", root.get_node_or_null("TechManager"))
	_trade_manager = overrides.get("trade_manager", root.get_node_or_null("TradeManager"))
	_pirate_manager = overrides.get("pirate_manager", root.get_node_or_null("PirateManager"))
	_pandemic_manager = overrides.get("pandemic_manager", root.get_node_or_null("PandemicManager"))
	_corruption_manager = overrides.get("corruption_manager", root.get_node_or_null("CorruptionManager"))
	_victory_manager = overrides.get("victory_manager", root.get_node_or_null("VictoryManager"))
	_historical_event_manager = overrides.get(
		"historical_event_manager", root.get_node_or_null("HistoricalEventManager")
	)
	_game_stats_tracker = overrides.get("game_stats_tracker", root.get_node_or_null("GameStatsTracker"))
	_river_transport = overrides.get("river_transport", root.get_node_or_null("RiverTransport"))
	_war_survival = overrides.get("war_survival", root.get_node_or_null("WarSurvival"))
	_war_bonus = overrides.get("war_bonus", root.get_node_or_null("WarResearchBonus"))
	_singularity_regression = overrides.get("singularity_regression", root.get_node_or_null("SingularityRegression"))
	_unit_upgrade_manager = overrides.get("unit_upgrade_manager", root.get_node_or_null("UnitUpgradeManager"))
	_ai_economy = overrides.get("ai_economy", root.get_node_or_null("AIEconomy"))
	_ai_military = overrides.get("ai_military", root.get_node_or_null("AIMilitary"))
	_ai_tech = overrides.get("ai_tech", root.get_node_or_null("AITech"))
	_ai_singularity = overrides.get("ai_singularity", root.get_node_or_null("AISingularity"))
	_visibility_manager = overrides.get("visibility_manager", root.get_node_or_null("VisibilityManager"))
	_camera = overrides.get("camera", root.get_node_or_null("Camera2D"))


func save_state() -> Dictionary:
	var units_data: Array[Dictionary] = []
	var resources_data: Array[Dictionary] = []
	var fauna_data: Array[Dictionary] = []
	for child in _root.get_children():
		if not child.has_method("save_state"):
			continue
		if "unit_type" in child and "owner_id" in child:
			var entry: Dictionary = child.save_state()
			entry["node_name"] = str(child.name)
			entry["owner_id"] = child.owner_id
			entry["entity_category"] = child.entity_category if "entity_category" in child else ""
			entry["unit_color_r"] = child.unit_color.r
			entry["unit_color_g"] = child.unit_color.g
			entry["unit_color_b"] = child.unit_color.b
			var wolf_ai: Node = child.get_node_or_null("WolfAI")
			if wolf_ai != null and wolf_ai.has_method("save_state"):
				entry["wolf_ai_state"] = wolf_ai.save_state()
			var dog_ai: Node = child.get_node_or_null("DogAI")
			if dog_ai != null and dog_ai.has_method("save_state"):
				entry["dog_ai_state"] = dog_ai.save_state()
			var trade_ai: Node = child.get_node_or_null("TradeCartAI")
			if trade_ai != null and trade_ai.has_method("save_state"):
				entry["trade_cart_ai_state"] = trade_ai.save_state()
			var cat: String = child.entity_category if "entity_category" in child else ""
			if child.owner_id == -1 or cat in ["wild_fauna", "dog"]:
				fauna_data.append(entry)
			else:
				units_data.append(entry)
		elif "entity_category" in child and child.entity_category == "resource_node":
			var entry: Dictionary = child.save_state()
			entry["node_name"] = str(child.name)
			resources_data.append(entry)

	var buildings_full: Array[Dictionary] = []
	if _building_placer != null and "_placed_buildings" in _building_placer:
		for entry: Dictionary in _building_placer._placed_buildings:
			var node: Node2D = entry.get("node")
			if not is_instance_valid(node) or not node.has_method("save_state"):
				continue
			var bstate: Dictionary = node.save_state()
			bstate["node_name"] = str(node.name)
			var pq: Node = node.get_node_or_null("ProductionQueue")
			if pq != null and pq.has_method("save_state"):
				bstate["production_queue"] = pq.save_state()
			buildings_full.append(bstate)

	return {
		"units": units_data,
		"resources": resources_data,
		"fauna": fauna_data,
		"buildings_full": buildings_full,
		"map": _save_if(_map_node),
		"building_placer": _save_if(_building_placer),
		"tech_manager": _save_if(_tech_manager),
		"trade_manager": _save_if(_trade_manager),
		"pirate_manager": _save_if(_pirate_manager),
		"pandemic_manager": _save_if(_pandemic_manager),
		"corruption_manager": _save_if(_corruption_manager),
		"population_manager": _save_if(_population_manager),
		"victory_manager": _save_if(_victory_manager),
		"historical_event_manager": _save_if(_historical_event_manager),
		"game_stats_tracker": _save_if(_game_stats_tracker),
		"river_transport": _save_if(_river_transport),
		"war_survival": _save_if(_war_survival),
		"war_bonus": _save_if(_war_bonus),
		"singularity_regression": _save_if(_singularity_regression),
		"unit_upgrade_manager": _save_if(_unit_upgrade_manager),
		"ai_economy": _save_if(_ai_economy),
		"ai_military": _save_if(_ai_military),
		"ai_tech": _save_if(_ai_tech),
		"ai_singularity": _save_if(_ai_singularity),
		"input_handler": _save_if(_input_handler),
		"camera": _save_if(_camera),
	}


func load_state(data: Dictionary) -> void:
	# Phase 1: Teardown existing dynamic entities
	await _teardown_scene_entities()
	# Phase 2: Map
	_load_if(_map_node, data, "map")
	# Phase 3: Buildings via building_placer, then apply full state
	_load_if(_building_placer, data, "building_placer")
	_apply_full_building_state(data.get("buildings_full", []))
	# Phase 4: Units
	_restore_units(data.get("units", []))
	# Phase 5: Resources
	_restore_resources(data.get("resources", []))
	# Phase 6: Fauna
	_restore_fauna(data.get("fauna", []))
	# Phase 7: Manager state (entities must exist first)
	_load_if(_tech_manager, data, "tech_manager")
	_load_if(_trade_manager, data, "trade_manager")
	_load_if(_pirate_manager, data, "pirate_manager")
	_load_if(_corruption_manager, data, "corruption_manager")
	_load_if(_population_manager, data, "population_manager")
	_load_if(_pandemic_manager, data, "pandemic_manager")
	_load_if(_victory_manager, data, "victory_manager")
	_load_if(_historical_event_manager, data, "historical_event_manager")
	_load_if(_game_stats_tracker, data, "game_stats_tracker")
	_load_if(_river_transport, data, "river_transport")
	_load_if(_war_survival, data, "war_survival")
	_load_if(_war_bonus, data, "war_bonus")
	_load_if(_singularity_regression, data, "singularity_regression")
	_load_if(_unit_upgrade_manager, data, "unit_upgrade_manager")
	_load_if(_ai_economy, data, "ai_economy")
	_load_if(_ai_military, data, "ai_military")
	_load_if(_ai_tech, data, "ai_tech")
	_load_if(_ai_singularity, data, "ai_singularity")
	# Phase 8: Node reference resolution
	_resolve_all_node_refs()
	# Phase 9: Input and camera (after entities exist)
	_load_if(_input_handler, data, "input_handler")
	_load_if(_camera, data, "camera")
	# Phase 10: Reconnect fog of war
	if _root.has_method("_update_fog_of_war"):
		_root._update_fog_of_war()


func _teardown_scene_entities() -> void:
	var to_remove: Array[Node] = []
	for child in _root.get_children():
		if "unit_type" in child and "owner_id" in child:
			to_remove.append(child)
		elif "entity_category" in child and child.entity_category == "resource_node":
			to_remove.append(child)
	# Buildings are managed by building_placer — remove them too
	if _building_placer != null and "_placed_buildings" in _building_placer:
		for entry: Dictionary in _building_placer._placed_buildings:
			var node: Node2D = entry.get("node")
			if is_instance_valid(node) and node not in to_remove:
				to_remove.append(node)
		_building_placer._placed_buildings.clear()
	for node in to_remove:
		if is_instance_valid(node):
			node.queue_free()
	# Clear target detector registry
	if _target_detector != null:
		if _target_detector.has_method("clear"):
			_target_detector.clear()
		elif "_entities" in _target_detector:
			_target_detector._entities.clear()
	# Wait one frame for queue_free to process
	if not to_remove.is_empty() and _root.get_tree() != null:
		await _root.get_tree().process_frame


func _apply_full_building_state(buildings_full: Array) -> void:
	if _building_placer == null or not ("_placed_buildings" in _building_placer):
		return
	for bstate: Dictionary in buildings_full:
		var bname: String = str(bstate.get("building_name", ""))
		var pos_arr: Array = bstate.get("grid_pos", [0, 0])
		var target_x: int = int(pos_arr[0])
		var target_y: int = int(pos_arr[1])
		for entry: Dictionary in _building_placer._placed_buildings:
			var node: Node2D = entry.get("node")
			if not is_instance_valid(node):
				continue
			var e_pos: Array = entry.get("grid_pos", [0, 0])
			if entry.get("building_name", "") != bname:
				continue
			if int(e_pos[0]) != target_x or int(e_pos[1]) != target_y:
				continue
			node.load_state(bstate)
			_try_attach_production_queue(node, bstate)
			node.building_destroyed.connect(_root._on_building_destroyed)
			if _population_manager != null and not node.under_construction:
				_population_manager.register_building(node, node.owner_id)
			if _victory_manager != null and node.building_name == "town_center":
				if not node.under_construction and _victory_manager.has_method("register_town_center"):
					_victory_manager.register_town_center(node.owner_id, node)
			break


func _try_attach_production_queue(building: Node2D, bstate: Dictionary) -> void:
	if not "building_name" in building:
		return
	var building_name: String = building.building_name
	if building_name == "":
		return
	var stats: Dictionary = DataLoader.get_building_stats(building_name)
	var units_produced: Array = stats.get("units_produced", [])
	if units_produced.is_empty():
		return
	var pq := Node.new()
	pq.name = "ProductionQueue"
	pq.set_script(ProductionQueueScript)
	building.add_child(pq)
	var oid: int = building.owner_id if "owner_id" in building else 0
	pq.setup(building, oid, _population_manager)
	pq.unit_produced.connect(_root._on_unit_produced)
	if bstate.has("production_queue"):
		pq.load_state(bstate["production_queue"])


func _restore_units(units_data: Array) -> void:
	for entry: Dictionary in units_data:
		var unit := Node2D.new()
		unit.name = str(entry.get("node_name", "Unit_%d" % _root.get_child_count()))
		unit.set_script(UnitScript)
		unit.unit_type = str(entry.get("unit_type", "villager"))
		unit.owner_id = int(entry.get("owner_id", 0))
		unit.unit_color = Color(
			float(entry.get("unit_color_r", 0.2)),
			float(entry.get("unit_color_g", 0.4)),
			float(entry.get("unit_color_b", 0.9)),
		)
		_root.add_child(unit)
		unit._scene_root = _root
		unit._pathfinder = _pathfinder
		if _visibility_manager != null:
			unit._visibility_manager = _visibility_manager
		if _war_survival != null:
			unit._war_survival = _war_survival
		unit.load_state(entry)
		unit.unit_died.connect(_root._on_unit_died)
		if _input_handler != null and _input_handler.has_method("register_unit"):
			_input_handler.register_unit(unit)
		if _target_detector != null:
			_target_detector.register_entity(unit)
		if _population_manager != null:
			_population_manager.register_unit(unit, unit.owner_id)
		if entry.has("trade_cart_ai_state"):
			var trade_ai := Node.new()
			trade_ai.name = "TradeCartAI"
			trade_ai.set_script(TradeCartAIScript)
			unit.add_child(trade_ai)
			trade_ai.load_state(entry["trade_cart_ai_state"])


func _restore_resources(resources_data: Array) -> void:
	for entry: Dictionary in resources_data:
		var res_node := Node2D.new()
		res_node.name = str(entry.get("node_name", "Resource_%d" % _root.get_child_count()))
		res_node.set_script(ResourceNodeScript)
		_root.add_child(res_node)
		res_node.load_state(entry)
		res_node.depleted.connect(_root._on_resource_depleted)
		if _target_detector != null:
			_target_detector.register_entity(res_node)


func _restore_fauna(fauna_data: Array) -> void:
	for entry: Dictionary in fauna_data:
		var unit := Node2D.new()
		unit.name = str(entry.get("node_name", "Fauna_%d" % _root.get_child_count()))
		unit.set_script(UnitScript)
		unit.unit_type = str(entry.get("unit_type", "wolf"))
		unit.owner_id = int(entry.get("owner_id", -1))
		unit.unit_color = Color(
			float(entry.get("unit_color_r", 0.5)),
			float(entry.get("unit_color_g", 0.5)),
			float(entry.get("unit_color_b", 0.5)),
		)
		var cat: String = str(entry.get("entity_category", ""))
		if cat != "":
			unit.entity_category = cat
		_root.add_child(unit)
		unit._scene_root = _root
		unit._pathfinder = _pathfinder
		if _war_survival != null:
			unit._war_survival = _war_survival
		unit.load_state(entry)
		if unit.has_signal("unit_died"):
			unit.unit_died.connect(_root._on_fauna_died)
		if cat == "dog":
			var dog_ai := Node.new()
			dog_ai.name = "DogAI"
			dog_ai.set_script(DogAIScript)
			unit.add_child(dog_ai)
			if _root.has_method("_on_dog_danger_alert"):
				dog_ai.danger_alert.connect(_root._on_dog_danger_alert)
			if entry.has("dog_ai_state"):
				dog_ai.load_state(entry["dog_ai_state"])
			if _input_handler != null and _input_handler.has_method("register_unit"):
				_input_handler.register_unit(unit)
		elif entry.has("wolf_ai_state"):
			var wolf_ai := Node.new()
			wolf_ai.name = "WolfAI"
			wolf_ai.set_script(WolfAIScript)
			unit.add_child(wolf_ai)
			wolf_ai.domesticated.connect(func(foid: int) -> void: _root._on_wolf_domesticated(unit, foid))
			wolf_ai.load_state(entry["wolf_ai_state"])
		if _target_detector != null:
			_target_detector.register_entity(unit)


func _resolve_all_node_refs() -> void:
	for child in _root.get_children():
		if child.has_method("resolve_build_target"):
			child.resolve_build_target(_root)
		if child.has_method("resolve_gather_target"):
			child.resolve_gather_target(_root)
		if child.has_method("resolve_combat_target"):
			child.resolve_combat_target(_root)
		if child.has_method("resolve_feed_target"):
			child.resolve_feed_target(_root)
		if child.has_method("resolve_garrison"):
			child.resolve_garrison(_root)
		if child.has_method("resolve_embarked"):
			child.resolve_embarked(_root)
		var trade_ai: Node = child.get_node_or_null("TradeCartAI")
		if trade_ai != null and trade_ai.has_method("resolve_targets"):
			trade_ai.resolve_targets(_root)
		var wolf_ai: Node = child.get_node_or_null("WolfAI")
		if wolf_ai != null and wolf_ai.has_method("resolve_targets"):
			wolf_ai.resolve_targets(_root)
		var dog_ai: Node = child.get_node_or_null("DogAI")
		if dog_ai != null and dog_ai.has_method("resolve_targets"):
			dog_ai.resolve_targets(_root)


func _save_if(node: Node) -> Dictionary:
	if node != null and node.has_method("save_state"):
		return node.save_state()
	return {}


func _load_if(node: Node, data: Dictionary, key: String) -> void:
	if node != null and data.has(key) and node.has_method("load_state"):
		node.load_state(data[key])
