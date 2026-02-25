class_name AIMilitary
extends Node
## AI military brain — drives army composition, unit training at barracks,
## attack wave decisions, retreat, and target selection. Runs on a configurable
## tick timer independent of AIEconomy.

const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")

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

var _scene_root: Node = null
var _population_manager: Node = null
var _target_detector: Node = null
var _ai_economy: Node = null

var _tick_timer: float = 0.0
var _config: Dictionary = {}
var _game_time: float = 0.0
var _last_attack_time: float = -9999.0
var _attack_in_progress: bool = false
var _enemy_composition: Dictionary = {}

# Cached entity lists (refreshed each tick)
var _own_military: Array[Node2D] = []
var _own_barracks: Array[Node2D] = []
var _town_center: Node2D = null
var _enemy_units: Array[Node2D] = []
var _enemy_buildings: Array[Node2D] = []


func setup(
	scene_root: Node,
	pop_mgr: Node,
	target_detector: Node,
	ai_economy: Node,
) -> void:
	_scene_root = scene_root
	_population_manager = pop_mgr
	_target_detector = target_detector
	_ai_economy = ai_economy
	_load_config()


func _load_config() -> void:
	var data: Variant = DataLoader.load_json("res://data/ai/military_config.json")
	if data == null or not data is Dictionary:
		_config = _default_config()
		return
	_config = data.get(difficulty, _default_config())


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


func _process(delta: float) -> void:
	var game_delta := GameManager.get_game_delta(delta)
	if game_delta <= 0.0:
		return
	_game_time += game_delta
	_tick_timer += game_delta
	var interval: float = float(_config.get("tick_interval", 3.0))
	if _tick_timer < interval:
		return
	_tick_timer -= interval
	_tick()


func _tick() -> void:
	_refresh_entity_lists()
	_scan_enemy_composition()
	_retreat_damaged_units()
	_try_garrison_outnumbered()
	_train_military_units()
	_evaluate_attack()


func _refresh_entity_lists() -> void:
	_own_military.clear()
	_own_barracks.clear()
	_town_center = null
	_enemy_units.clear()
	_enemy_buildings.clear()
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


func _classify_own_entity(entity: Node2D) -> void:
	if "building_name" in entity:
		if entity.building_name == "town_center" and not entity.under_construction:
			_town_center = entity
		elif entity.building_name == "barracks" and not entity.under_construction:
			_own_barracks.append(entity)
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
	# Check it's a valid game entity (unit or building)
	if entity.has_method("is_idle") or "building_name" in entity:
		return true
	return false


func _classify_enemy_entity(entity: Node2D) -> void:
	if "building_name" in entity:
		_enemy_buildings.append(entity)
	elif entity.has_method("is_idle"):
		_enemy_units.append(entity)


func _scan_enemy_composition() -> void:
	_enemy_composition.clear()
	if _town_center == null:
		return
	var scan_radius: float = float(_config.get("scout_scan_radius", 35)) * TILE_SIZE
	var tc_pos: Vector2 = _town_center.global_position
	for enemy in _enemy_units:
		if "hp" in enemy and enemy.hp <= 0:
			continue
		var dist: float = tc_pos.distance_to(enemy.global_position)
		if dist > scan_radius:
			continue
		var utype: String = _get_unit_type_category(enemy)
		_enemy_composition[utype] = int(_enemy_composition.get(utype, 0)) + 1


func _get_unit_type_category(entity: Node2D) -> String:
	if "unit_type" in entity:
		return str(entity.unit_type)
	return "infantry"


func _compute_desired_composition() -> Dictionary:
	var default_comp: Dictionary = _config.get("default_composition", {})
	var counter_weights: Dictionary = _config.get("counter_weights", {})
	var counter_bias: float = float(_config.get("counter_bias", 0.5))

	# If no enemies seen, use default composition
	var total_enemies: int = 0
	for count: int in _enemy_composition.values():
		total_enemies += count
	if total_enemies == 0:
		return default_comp.duplicate()

	# Build counter demand from enemy ratios
	var counter_demand: Dictionary = {}
	for enemy_type: String in _enemy_composition:
		var enemy_ratio: float = float(_enemy_composition[enemy_type]) / float(total_enemies)
		var counter_unit: String = str(counter_weights.get(enemy_type, ""))
		if counter_unit != "":
			counter_demand[counter_unit] = float(counter_demand.get(counter_unit, 0.0)) + enemy_ratio

	# Blend default and counter compositions
	var desired: Dictionary = {}
	for unit_type: String in default_comp:
		var base: float = float(default_comp[unit_type])
		var counter: float = float(counter_demand.get(unit_type, 0.0))
		desired[unit_type] = (1.0 - counter_bias) * base + counter_bias * counter

	# Normalize to 1.0
	var total: float = 0.0
	for val: float in desired.values():
		total += val
	if total > 0.0:
		for unit_type: String in desired:
			desired[unit_type] = float(desired[unit_type]) / total

	return desired


func _get_training_deficit() -> String:
	var desired: Dictionary = _compute_desired_composition()
	if desired.is_empty():
		return "infantry"

	# Count own military by type
	var own_counts: Dictionary = {}
	var total_own: int = 0
	for unit in _own_military:
		var utype: String = _get_unit_type_category(unit)
		own_counts[utype] = int(own_counts.get(utype, 0)) + 1
		total_own += 1

	# Find type with largest deficit (desired ratio - actual ratio)
	var best_type: String = ""
	var best_deficit: float = -INF
	var effective_total: float = maxf(float(total_own), 1.0)
	for unit_type: String in desired:
		var target_ratio: float = float(desired[unit_type])
		var actual_count: float = float(own_counts.get(unit_type, 0))
		var actual_ratio: float = actual_count / effective_total
		var deficit: float = target_ratio - actual_ratio
		if deficit > best_deficit:
			best_deficit = deficit
			best_type = unit_type
	return best_type


func _train_military_units() -> void:
	if not _can_train_military():
		return
	var unit_type: String = _get_training_deficit()
	if unit_type == "":
		return
	# Find barracks with shortest queue
	var best_barracks: Node2D = _find_best_barracks(unit_type)
	if best_barracks == null:
		return
	var pq: Node = best_barracks.get_node_or_null("ProductionQueue")
	if pq != null and pq.has_method("add_to_queue"):
		pq.add_to_queue(unit_type)


func _can_train_military() -> bool:
	if _own_barracks.is_empty() or _population_manager == null:
		return false
	var max_mil_ratio: float = float(_config.get("max_military_pop_ratio", 0.50))
	var pop_cap: int = _population_manager.get_population_cap(player_id)
	if pop_cap <= 0:
		return false
	var mil_count: int = _own_military.size()
	if float(mil_count) / float(pop_cap) >= max_mil_ratio:
		return false
	return _check_military_budget()


func _find_best_barracks(unit_type: String) -> Node2D:
	var best: Node2D = null
	var best_queue_size: int = 999
	for barracks in _own_barracks:
		var pq: Node = barracks.get_node_or_null("ProductionQueue")
		if pq == null or not pq.has_method("can_produce"):
			continue
		if not pq.can_produce(unit_type):
			continue
		var queue_size: int = pq.get_queue().size() if pq.has_method("get_queue") else 0
		if queue_size < best_queue_size:
			best_queue_size = queue_size
			best = barracks
	return best


func _check_military_budget() -> bool:
	var budget_ratio: float = float(_config.get("military_budget_ratio", 0.60))
	# Check that we have at least some resources — budget is per-tick cap
	for res_name: String in RESOURCE_NAME_TO_TYPE:
		var res_type: ResourceManager.ResourceType = RESOURCE_NAME_TO_TYPE[res_name]
		var amount: int = ResourceManager.get_amount(player_id, res_type)
		var budget: int = int(float(amount) * budget_ratio)
		if budget > 0:
			return true
	return false


func _evaluate_attack() -> void:
	# Guard: must be age >= 1
	if GameManager.current_age < 1:
		return
	# Guard: min game time
	var min_time: float = float(_config.get("min_attack_game_time", 420.0))
	if _game_time < min_time:
		return
	# Guard: cooldown since last attack
	var cooldown: float = float(_config.get("attack_cooldown", 90.0))
	if _game_time - _last_attack_time < cooldown:
		return
	# Guard: army threshold
	var threshold: int = int(_config.get("army_attack_threshold", 8))
	var idle_military: Array[Node2D] = []
	for unit in _own_military:
		if "hp" in unit and unit.hp <= 0:
			continue
		if unit.has_method("is_idle") and unit.is_idle():
			idle_military.append(unit)
	if idle_military.size() < threshold:
		return
	_launch_attack(idle_military)


func _launch_attack(units: Array[Node2D]) -> void:
	var target_pos: Vector2 = _select_attack_target()
	if target_pos == Vector2.ZERO:
		return
	_attack_in_progress = true
	_last_attack_time = _game_time
	for unit in units:
		if unit.has_method("attack_move_to"):
			unit.attack_move_to(target_pos)


func _select_attack_target() -> Vector2:
	var priority_list: Array = _config.get("target_priority", [])
	for priority: String in priority_list:
		var target: Vector2 = _find_target_by_priority(priority)
		if target != Vector2.ZERO:
			return target
	# Fallback: nearest enemy building
	return _find_nearest_enemy_building_pos()


func _find_target_by_priority(priority: String) -> Vector2:
	match priority:
		"undefended_villagers":
			return _find_undefended_villagers()
		"weakest_building":
			return _find_weakest_building()
		"nearest_building":
			return _find_nearest_enemy_building_pos()
	return Vector2.ZERO


func _find_undefended_villagers() -> Vector2:
	var weakness_radius: float = float(_config.get("weakness_radius", 12)) * TILE_SIZE
	for enemy in _enemy_units:
		if "hp" in enemy and enemy.hp <= 0:
			continue
		var category: String = ""
		if "unit_category" in enemy:
			category = str(enemy.unit_category)
		if category == "military":
			continue
		# Check if there are defenders nearby
		var defended := false
		for other in _enemy_units:
			if other == enemy:
				continue
			if "hp" in other and other.hp <= 0:
				continue
			var other_cat: String = ""
			if "unit_category" in other:
				other_cat = str(other.unit_category)
			if other_cat != "military":
				continue
			if enemy.global_position.distance_to(other.global_position) <= weakness_radius:
				defended = true
				break
		if not defended:
			return enemy.global_position
	return Vector2.ZERO


func _find_weakest_building() -> Vector2:
	var weakest: Node2D = null
	var lowest_hp: int = 999999
	for building in _enemy_buildings:
		if "hp" in building and building.hp <= 0:
			continue
		if "under_construction" in building and building.under_construction:
			continue
		var bhp: int = int(building.hp) if "hp" in building else 0
		if bhp < lowest_hp:
			lowest_hp = bhp
			weakest = building
	if weakest != null:
		return weakest.global_position
	return Vector2.ZERO


func _find_nearest_enemy_building_pos() -> Vector2:
	if _town_center == null:
		return Vector2.ZERO
	var tc_pos: Vector2 = _town_center.global_position
	var best: Node2D = null
	var best_dist: float = INF
	for building in _enemy_buildings:
		if "hp" in building and building.hp <= 0:
			continue
		var dist: float = tc_pos.distance_to(building.global_position)
		if dist < best_dist:
			best_dist = dist
			best = building
	if best != null:
		return best.global_position
	return Vector2.ZERO


func _retreat_damaged_units() -> void:
	if _town_center == null:
		return
	var retreat_ratio: float = float(_config.get("retreat_hp_ratio", 0.25))
	var tc_pos: Vector2 = _town_center.global_position
	for unit in _own_military:
		if "hp" not in unit or "max_hp" not in unit:
			continue
		if unit.max_hp <= 0:
			continue
		var hp_ratio: float = float(unit.hp) / float(unit.max_hp)
		if hp_ratio > retreat_ratio:
			continue
		# Only retreat units that are in combat
		if "_combat_state" in unit and int(unit._combat_state) == 0:
			continue
		if unit.has_method("move_to"):
			unit.move_to(tc_pos)


func _try_garrison_outnumbered() -> void:
	# Garrison system not implemented yet — stub with retreat fallback
	if _own_military.is_empty() or _enemy_units.is_empty():
		return
	if _own_military.size() * 3 < _enemy_units.size():
		push_warning("AIMilitary: Outnumbered — garrison not implemented, retreating instead")
		if _town_center != null:
			var tc_pos: Vector2 = _town_center.global_position
			for unit in _own_military:
				if unit.has_method("move_to"):
					unit.move_to(tc_pos)


func save_state() -> Dictionary:
	return {
		"game_time": _game_time,
		"last_attack_time": _last_attack_time,
		"attack_in_progress": _attack_in_progress,
		"enemy_composition": _enemy_composition.duplicate(),
		"tick_timer": _tick_timer,
		"difficulty": difficulty,
		"player_id": player_id,
	}


func load_state(data: Dictionary) -> void:
	_game_time = float(data.get("game_time", 0.0))
	_last_attack_time = float(data.get("last_attack_time", -9999.0))
	_attack_in_progress = bool(data.get("attack_in_progress", false))
	_tick_timer = float(data.get("tick_timer", 0.0))
	difficulty = str(data.get("difficulty", difficulty))
	player_id = int(data.get("player_id", player_id))
	var ec: Dictionary = data.get("enemy_composition", {})
	_enemy_composition.clear()
	for k: String in ec:
		_enemy_composition[k] = int(ec[k])
	_load_config()
