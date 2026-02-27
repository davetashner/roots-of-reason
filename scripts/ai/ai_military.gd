class_name AIMilitary
extends Node
## AI military brain — coordinates AIMilitaryStrategy (army composition, training,
## attack evaluation) and AIMilitaryTactics (positioning, targeting, retreat).
## Runs on a configurable tick timer independent of AIEconomy.

const RESOURCE_NAME_TO_TYPE: Dictionary = {
	"food": ResourceManager.ResourceType.FOOD,
	"wood": ResourceManager.ResourceType.WOOD,
	"stone": ResourceManager.ResourceType.STONE,
	"gold": ResourceManager.ResourceType.GOLD,
	"knowledge": ResourceManager.ResourceType.KNOWLEDGE,
}

const TILE_SIZE: float = 64.0

var player_id: int = 1
var difficulty: String = "normal"
var personality: AIPersonality = null
var singularity_target_buildings: Array[String] = []:
	set(value):
		singularity_target_buildings = value
		if _tactics != null:
			_tactics.singularity_target_buildings = value

var _scene_root: Node = null
var _population_manager: Node = null
var _target_detector: Node = null
var _ai_economy: Node = null
var _entity_registry: RefCounted = null

var _tick_timer: float = 0.0
var _config: Dictionary = {}
var _game_time: float = 0.0
var _last_attack_time: float = -9999.0
var _attack_in_progress: bool = false
var _enemy_composition: Dictionary = {}

# Cached entity lists (refreshed each tick)
var _own_military: Array[Node2D] = []
var _own_barracks: Array[Node2D] = []
var _own_factories: Array[Node2D] = []
var _town_center: Node2D = null
var _town_centers: Array[Node2D] = []
var _enemy_units: Array[Node2D] = []
var _enemy_buildings: Array[Node2D] = []
var _enemy_town_centers: Array[Node2D] = []

# Tech regression awareness
var _tech_manager: Node = null
var _tr_config: Dictionary = {}
var _tech_loss_boost_timer: float = 0.0:
	set(value):
		_tech_loss_boost_timer = value
		if _strategy != null:
			_strategy.tech_loss_boost_timer = value
var _destroyed_tc_positions: Array[Vector2i] = []
var _base_attack_threshold: int = 0
var _base_attack_cooldown: float = 0.0

# Component delegates
var _strategy: AIMilitaryStrategy = null
var _tactics: AIMilitaryTactics = null


func setup(
	scene_root: Node,
	pop_mgr: Node,
	target_detector: Node,
	ai_economy: Node,
	tech_manager: Node = null,
	entity_registry: RefCounted = null,
) -> void:
	_scene_root = scene_root
	_population_manager = pop_mgr
	_target_detector = target_detector
	_ai_economy = ai_economy
	_tech_manager = tech_manager
	_entity_registry = entity_registry
	_load_config()
	_load_tr_config()
	_setup_components()


func _setup_components() -> void:
	_strategy = AIMilitaryStrategy.new()
	_strategy.player_id = player_id
	_strategy.personality = personality
	_strategy.setup(_population_manager, _tech_manager, _config, _tr_config)

	_tactics = AIMilitaryTactics.new()
	_tactics.player_id = player_id
	_tactics.singularity_target_buildings = singularity_target_buildings
	_tactics.setup(_tech_manager, _config, _tr_config)


func _load_config() -> void:
	var data: Variant = DataLoader.load_json("res://data/ai/military_config.json")
	if data == null or not data is Dictionary:
		_config = _default_config()
	else:
		_config = data.get(difficulty, _default_config()).duplicate(true)
	if personality != null:
		_config = personality.apply_military_modifiers(_config)
	_base_attack_threshold = int(_config.get("army_attack_threshold", 8))
	_base_attack_cooldown = float(_config.get("attack_cooldown", 90.0))


func _default_config() -> Dictionary:
	return {
		"tick_interval": 3.0,
		"army_attack_threshold": 8,
		"retreat_hp_ratio": 0.25,
		"min_attack_game_time": 420.0,
		"attack_cooldown": 90.0,
		"scout_scan_radius": 35,
		"default_composition": {"infantry": 0.45, "archer": 0.30, "cavalry": 0.25},
		"counter_weights": {"infantry": "cavalry", "archer": "infantry", "cavalry": "archer"},
		"counter_bias": 0.5,
		"max_military_pop_ratio": 0.50,
		"military_budget_ratio": 0.60,
		"target_priority": ["undefended_villagers", "weakest_building", "nearest_building"],
		"weakness_radius": 12,
	}


func _load_tr_config() -> void:
	var data: Variant = DataLoader.load_json("res://data/ai/tech_regression_config.json")
	if data == null or not data is Dictionary:
		_tr_config = {}
		return
	_tr_config = data
	# Apply personality overrides via dot-path keys
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
	_game_time += game_delta
	_tick_timer += game_delta
	if _strategy != null and _strategy.tech_loss_boost_timer > 0.0:
		_strategy.tech_loss_boost_timer = maxf(_strategy.tech_loss_boost_timer - game_delta, 0.0)
	# Keep local mirror in sync for save/load
	_tech_loss_boost_timer = _strategy.tech_loss_boost_timer if _strategy != null else 0.0
	var interval: float = float(_config.get("tick_interval", 3.0))
	if _tick_timer < interval:
		return
	_tick_timer -= interval
	_tick()


func _tick() -> void:
	_refresh_entity_lists()
	_enemy_composition = _strategy.scan_enemy_composition(_enemy_units, _town_center)
	_tactics.retreat_damaged_units(_own_military, _town_center)
	_tactics.try_garrison_outnumbered(_own_military, _enemy_units, _town_center)
	_tactics.allocate_tc_defenders(_town_centers, _own_military, _enemy_units)
	_train_military_units()
	_evaluate_attack()


func _refresh_entity_lists() -> void:
	_own_military.clear()
	_own_barracks.clear()
	_own_factories.clear()
	_town_center = null
	_town_centers.clear()
	_enemy_units.clear()
	_enemy_buildings.clear()
	_enemy_town_centers.clear()
	if _entity_registry != null:
		_refresh_from_registry()
		return
	if _scene_root == null:
		return
	for child in _scene_root.get_children():
		if not (child is Node2D):
			continue
		if "owner_id" not in child:
			continue
		var child_owner: int = int(child.owner_id)
		if child_owner == player_id:
			_classify_own_entity(child)
		elif _is_enemy_entity(child, child_owner):
			_classify_enemy_entity(child)


func _refresh_from_registry() -> void:
	# Own entities — use registry O(1) lookups
	var own_entities: Array[Node2D] = _entity_registry.get_by_owner(player_id)
	for entity in own_entities:
		_classify_own_entity(entity)
	# Enemy entities — iterate non-own factions from registry
	# Collect all enemy player IDs we might face
	for entity in _entity_registry.get_by_owner(0):
		if player_id != 0:
			_classify_enemy_entity(entity)
	# AI player 1 is self when player_id == 1, so check other owners
	if player_id != 1:
		for entity in _entity_registry.get_by_owner(1):
			_classify_enemy_entity(entity)
	# Gaia entities (owner_id == -1) are not enemies


func _classify_own_entity(entity: Node2D) -> void:
	if "building_name" in entity:
		if entity.building_name == "town_center" and not entity.under_construction:
			_town_centers.append(entity)
			if _town_center == null:
				_town_center = entity
		elif entity.building_name == "barracks" and not entity.under_construction:
			_own_barracks.append(entity)
		elif entity.building_name == "factory" and not entity.under_construction:
			_own_factories.append(entity)
		return
	if not entity.has_method("is_idle"):
		return
	var category: String = ""
	if "unit_category" in entity:
		category = str(entity.unit_category)
	if category == "military":
		_own_military.append(entity)


func _is_enemy_entity(entity: Node2D, entity_owner: int) -> bool:
	if entity_owner == player_id:
		return false
	if entity.has_method("is_idle") or "building_name" in entity:
		return true
	return false


func _classify_enemy_entity(entity: Node2D) -> void:
	if "building_name" in entity:
		_enemy_buildings.append(entity)
		if entity.building_name == "town_center" and not entity.under_construction:
			_enemy_town_centers.append(entity)
	elif entity.has_method("is_idle"):
		_enemy_units.append(entity)


func _train_military_units() -> void:
	if not _strategy.can_train_military(_own_barracks, _own_factories, _own_military):
		return
	var unit_type: String = _strategy.get_training_deficit(_own_military, _enemy_composition)
	if unit_type == "":
		return
	var best_building: Node2D = _strategy.find_best_production_building(unit_type, _own_barracks, _own_factories)
	if best_building == null:
		return
	var pq: Node = best_building.get_node_or_null("ProductionQueue")
	if pq != null and pq.has_method("add_to_queue"):
		pq.add_to_queue(unit_type)


func _evaluate_attack() -> void:
	var idle_military: Array[Node2D] = _strategy.should_attack(_game_time, _last_attack_time, _own_military)
	if idle_military.is_empty():
		return
	var prioritize_tc: bool = _strategy.should_prioritize_tc_snipe(_enemy_town_centers, _own_military, _enemy_units)
	var target_pos: Vector2 = _tactics.select_attack_target(
		_enemy_buildings, _enemy_units, _enemy_town_centers, _own_military, _town_center, prioritize_tc
	)
	if target_pos == Vector2.ZERO:
		return
	_attack_in_progress = true
	_last_attack_time = _game_time
	_tactics.launch_attack(idle_military, target_pos)


## Delegation wrappers — maintain backward compatibility for callers and tests.


func _scan_enemy_composition() -> void:
	_enemy_composition = _strategy.scan_enemy_composition(_enemy_units, _town_center)


func _compute_desired_composition() -> Dictionary:
	return _strategy.compute_desired_composition(_enemy_composition)


func _get_training_deficit() -> String:
	return _strategy.get_training_deficit(_own_military, _enemy_composition)


func _find_weakest_building() -> Vector2:
	return _tactics._find_weakest_building(_enemy_buildings)


func _find_undefended_villagers() -> Vector2:
	return _tactics._find_undefended_villagers(_enemy_units)


func _select_attack_target() -> Vector2:
	var prioritize_tc: bool = _strategy.should_prioritize_tc_snipe(_enemy_town_centers, _own_military, _enemy_units)
	return _tactics.select_attack_target(
		_enemy_buildings, _enemy_units, _enemy_town_centers, _own_military, _town_center, prioritize_tc
	)


func _retreat_damaged_units() -> void:
	_tactics.retreat_damaged_units(_own_military, _town_center)


func _compute_tc_vulnerability(tc: Node2D) -> float:
	return _tactics._compute_tc_vulnerability(tc, _own_military, _enemy_units)


func _allocate_tc_defenders() -> void:
	_tactics.allocate_tc_defenders(_town_centers, _own_military, _enemy_units)


func _count_own_military_near(pos: Vector2, radius: float) -> int:
	return _tactics._count_own_military_near(pos, radius, _own_military)


func _should_prioritize_tc_snipe() -> bool:
	return _strategy.should_prioritize_tc_snipe(_enemy_town_centers, _own_military, _enemy_units)


func _can_train_military() -> bool:
	return _strategy.can_train_military(_own_barracks, _own_factories, _own_military)


func set_aggression_override(threshold_mult: float, cooldown_mult: float) -> void:
	_strategy.set_aggression_override(threshold_mult, cooldown_mult)
	# Keep coordinator config in sync for save/load
	_config["army_attack_threshold"] = _strategy.config.get("army_attack_threshold", 8)
	_config["attack_cooldown"] = _strategy.config.get("attack_cooldown", 90.0)


func clear_aggression_override() -> void:
	_strategy.clear_aggression_override()
	_config["army_attack_threshold"] = _strategy.config.get("army_attack_threshold", 8)
	_config["attack_cooldown"] = _strategy.config.get("attack_cooldown", 90.0)


func on_tech_regressed(p_id: int, tech_id: String, tech_data: Dictionary) -> void:
	_strategy.on_tech_regressed(p_id, tech_id, tech_data)
	_tech_loss_boost_timer = _strategy.tech_loss_boost_timer


func on_building_destroyed(building: Node2D) -> void:
	if not "building_name" in building:
		return
	if building.building_name != "town_center":
		return
	if "grid_pos" in building:
		_destroyed_tc_positions.append(building.grid_pos)


func save_state() -> Dictionary:
	var dtc_serialized: Array = []
	for pos in _destroyed_tc_positions:
		dtc_serialized.append([pos.x, pos.y])
	var state: Dictionary = {
		"game_time": _game_time,
		"last_attack_time": _last_attack_time,
		"attack_in_progress": _attack_in_progress,
		"enemy_composition": _enemy_composition.duplicate(),
		"tick_timer": _tick_timer,
		"difficulty": difficulty,
		"player_id": player_id,
		"tech_loss_boost_timer": _tech_loss_boost_timer,
		"destroyed_tc_positions": dtc_serialized,
	}
	if personality != null:
		state["personality_id"] = personality.personality_id
	return state


func load_state(data: Dictionary) -> void:
	_game_time = float(data.get("game_time", 0.0))
	_last_attack_time = float(data.get("last_attack_time", -9999.0))
	_attack_in_progress = bool(data.get("attack_in_progress", false))
	_tick_timer = float(data.get("tick_timer", 0.0))
	difficulty = str(data.get("difficulty", difficulty))
	player_id = int(data.get("player_id", player_id))
	var pid: String = str(data.get("personality_id", ""))
	if pid != "":
		personality = AIPersonality.get_personality(pid)
	var ec: Dictionary = data.get("enemy_composition", {})
	_enemy_composition.clear()
	for k: String in ec:
		_enemy_composition[k] = int(ec[k])
	_tech_loss_boost_timer = float(data.get("tech_loss_boost_timer", 0.0))
	_destroyed_tc_positions.clear()
	var dtc: Array = data.get("destroyed_tc_positions", [])
	for entry in dtc:
		if entry is Array and entry.size() == 2:
			_destroyed_tc_positions.append(Vector2i(int(entry[0]), int(entry[1])))
	_load_config()
	_load_tr_config()
	_setup_components()
	if _strategy != null:
		_strategy.tech_loss_boost_timer = _tech_loss_boost_timer
