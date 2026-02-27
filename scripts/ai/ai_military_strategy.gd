class_name AIMilitaryStrategy
extends RefCounted
## AIMilitaryStrategy — decides army composition, training priorities, and
## whether/when to attack. Extracted from AIMilitary to separate strategic
## decision-making from tactical execution.

const RESOURCE_NAME_TO_TYPE: Dictionary = {
	"food": ResourceManager.ResourceType.FOOD,
	"wood": ResourceManager.ResourceType.WOOD,
	"stone": ResourceManager.ResourceType.STONE,
	"gold": ResourceManager.ResourceType.GOLD,
	"knowledge": ResourceManager.ResourceType.KNOWLEDGE,
}

const TILE_SIZE: float = 64.0

var config: Dictionary = {}
var tr_config: Dictionary = {}
var player_id: int = 1
var personality: AIPersonality = null
var tech_loss_boost_timer: float = 0.0
var base_attack_threshold: int = 0
var base_attack_cooldown: float = 0.0

var _tech_manager: Node = null
var _population_manager: Node = null


func setup(
	pop_mgr: Node,
	tech_manager: Node,
	p_config: Dictionary,
	p_tr_config: Dictionary,
) -> void:
	_population_manager = pop_mgr
	_tech_manager = tech_manager
	config = p_config
	tr_config = p_tr_config
	base_attack_threshold = int(config.get("army_attack_threshold", 8))
	base_attack_cooldown = float(config.get("attack_cooldown", 90.0))


func scan_enemy_composition(
	enemy_units: Array[Node2D],
	town_center: Node2D,
) -> Dictionary:
	var composition: Dictionary = {}
	if town_center == null:
		return composition
	var scan_radius: float = float(config.get("scout_scan_radius", 35)) * TILE_SIZE
	var tc_pos: Vector2 = town_center.global_position
	for enemy in enemy_units:
		if "hp" in enemy and enemy.hp <= 0:
			continue
		var dist: float = tc_pos.distance_to(enemy.global_position)
		if dist > scan_radius:
			continue
		var utype: String = _get_unit_type_category(enemy)
		composition[utype] = int(composition.get(utype, 0)) + 1
	return composition


func compute_desired_composition(enemy_composition: Dictionary) -> Dictionary:
	var default_comp: Dictionary = config.get("default_composition", {})
	var counter_weights: Dictionary = config.get("counter_weights", {})
	var counter_bias: float = float(config.get("counter_bias", 0.5))

	# If no enemies seen, use default composition
	var total_enemies: int = 0
	for count: int in enemy_composition.values():
		total_enemies += count
	if total_enemies == 0:
		return default_comp.duplicate()

	# Build counter demand from enemy ratios
	var counter_demand: Dictionary = {}
	for enemy_type: String in enemy_composition:
		var enemy_ratio: float = float(enemy_composition[enemy_type]) / float(total_enemies)
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


func get_training_deficit(
	own_military: Array[Node2D],
	enemy_composition: Dictionary,
) -> String:
	var desired: Dictionary = compute_desired_composition(enemy_composition)
	if desired.is_empty():
		return "infantry"

	# Count own military by type
	var own_counts: Dictionary = {}
	var total_own: int = 0
	for unit in own_military:
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


func can_train_military(
	own_barracks: Array[Node2D],
	own_factories: Array[Node2D],
	own_military: Array[Node2D],
) -> bool:
	if (own_barracks.is_empty() and own_factories.is_empty()) or _population_manager == null:
		return false
	var max_mil_ratio: float = float(config.get("max_military_pop_ratio", 0.50))
	if tech_loss_boost_timer > 0.0:
		var tlr: Dictionary = tr_config.get("tech_loss_response", {})
		max_mil_ratio += float(tlr.get("military_pop_ratio_boost", 0.15))
	var pop_cap: int = _population_manager.get_population_cap(player_id)
	if pop_cap <= 0:
		return false
	var mil_count: int = own_military.size()
	if float(mil_count) / float(pop_cap) >= max_mil_ratio:
		return false
	return check_military_budget()


func check_military_budget() -> bool:
	var budget_ratio: float = float(config.get("military_budget_ratio", 0.60))
	for res_name: String in RESOURCE_NAME_TO_TYPE:
		var res_type: ResourceManager.ResourceType = RESOURCE_NAME_TO_TYPE[res_name]
		var amount: int = ResourceManager.get_amount(player_id, res_type)
		var budget: int = int(float(amount) * budget_ratio)
		if budget > 0:
			return true
	return false


func find_best_production_building(
	unit_type: String,
	own_barracks: Array[Node2D],
	own_factories: Array[Node2D],
) -> Node2D:
	var best: Node2D = null
	var best_queue_size: int = 999
	var buildings: Array[Node2D] = []
	buildings.append_array(own_barracks)
	buildings.append_array(own_factories)
	for building in buildings:
		var pq: Node = building.get_node_or_null("ProductionQueue")
		if pq == null or not pq.has_method("can_produce"):
			continue
		if not pq.can_produce(unit_type):
			continue
		var queue_size: int = pq.get_queue().size() if pq.has_method("get_queue") else 0
		if queue_size < best_queue_size:
			best_queue_size = queue_size
			best = building
	return best


func should_attack(
	game_time: float,
	last_attack_time: float,
	own_military: Array[Node2D],
) -> Array[Node2D]:
	## Returns the idle military units to attack with, or empty array if no attack.
	# Guard: must be age >= 1
	if GameManager.current_age < 1:
		return []
	# Guard: min game time
	var min_time: float = float(config.get("min_attack_game_time", 420.0))
	if game_time < min_time:
		return []
	# Guard: cooldown since last attack
	var cooldown: float = float(config.get("attack_cooldown", 90.0))
	if game_time - last_attack_time < cooldown:
		return []
	# Guard: army threshold
	var threshold: int = int(config.get("army_attack_threshold", 8))
	var idle_military: Array[Node2D] = []
	for unit in own_military:
		if "hp" in unit and unit.hp <= 0:
			continue
		if unit.has_method("is_idle") and unit.is_idle():
			idle_military.append(unit)
	if idle_military.size() < threshold:
		return []
	return idle_military


func should_prioritize_tc_snipe(
	enemy_town_centers: Array[Node2D],
	own_military: Array[Node2D],
	enemy_units: Array[Node2D],
) -> bool:
	if enemy_town_centers.is_empty() or _tech_manager == null:
		return false
	var offense: Dictionary = tr_config.get("offense", {})
	var adv_ratio: float = float(offense.get("tc_snipe_military_advantage_ratio", 1.5))
	var tech_lead_threshold: int = int(offense.get("tc_target_tech_lead_threshold", 3))
	# Check military advantage
	if enemy_units.size() > 0:
		var ratio: float = float(own_military.size()) / float(enemy_units.size())
		if ratio >= adv_ratio:
			return true
	elif not own_military.is_empty():
		return true
	# Check if enemy has tech lead
	var own_techs: int = _tech_manager.get_researched_techs(player_id).size()
	var enemy_pid: int = 0 if player_id != 0 else 1
	var enemy_techs: int = _tech_manager.get_researched_techs(enemy_pid).size()
	if enemy_techs - own_techs >= tech_lead_threshold:
		return true
	return false


func set_aggression_override(threshold_mult: float, cooldown_mult: float) -> void:
	config["army_attack_threshold"] = maxi(int(float(base_attack_threshold) / threshold_mult), 1)
	config["attack_cooldown"] = base_attack_cooldown * cooldown_mult


func clear_aggression_override() -> void:
	config["army_attack_threshold"] = base_attack_threshold
	config["attack_cooldown"] = base_attack_cooldown


func on_tech_regressed(p_id: int, _tech_id: String, _tech_data: Dictionary) -> void:
	if p_id != player_id:
		return
	var tlr: Dictionary = tr_config.get("tech_loss_response", {})
	tech_loss_boost_timer = float(tlr.get("military_boost_duration", 120.0))


func _get_unit_type_category(entity: Node2D) -> String:
	if "unit_type" in entity:
		return str(entity.unit_type)
	return "infantry"
