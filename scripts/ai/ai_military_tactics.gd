class_name AIMilitaryTactics
extends RefCounted
## AIMilitaryTactics — handles unit positioning, target selection, retreat
## decisions, and TC defense allocation. Extracted from AIMilitary to separate
## tactical execution from strategic planning.

const TILE_SIZE: float = 64.0

var config: Dictionary = {}
var tr_config: Dictionary = {}
var player_id: int = 1
var singularity_target_buildings: Array[String] = []

var _tech_manager: Node = null


func setup(
	tech_manager: Node,
	p_config: Dictionary,
	p_tr_config: Dictionary,
) -> void:
	_tech_manager = tech_manager
	config = p_config
	tr_config = p_tr_config


func select_attack_target(
	enemy_buildings: Array[Node2D],
	enemy_units: Array[Node2D],
	enemy_town_centers: Array[Node2D],
	_own_military: Array[Node2D],
	town_center: Node2D,
	prioritize_tc: bool,
) -> Vector2:
	# Priority 0: Singularity-critical buildings
	if not singularity_target_buildings.is_empty():
		var sing_target: Vector2 = _find_singularity_building_target(enemy_buildings)
		if sing_target != Vector2.ZERO:
			return sing_target
	var priority_list: Array = config.get("target_priority", []).duplicate()
	if prioritize_tc:
		priority_list.insert(0, "enemy_town_center")
	for priority: String in priority_list:
		var target: Vector2 = _find_target_by_priority(
			priority, enemy_buildings, enemy_units, enemy_town_centers, town_center
		)
		if target != Vector2.ZERO:
			return target
	# Fallback: nearest enemy building
	return _find_nearest_enemy_building_pos(enemy_buildings, town_center)


func launch_attack(units: Array[Node2D], target_pos: Vector2) -> void:
	if target_pos == Vector2.ZERO:
		return
	for unit in units:
		if unit.has_method("attack_move_to"):
			unit.attack_move_to(target_pos)


func retreat_damaged_units(
	own_military: Array[Node2D],
	town_center: Node2D,
) -> void:
	if town_center == null:
		return
	var retreat_ratio: float = float(config.get("retreat_hp_ratio", 0.25))
	var tc_pos: Vector2 = town_center.global_position
	for unit in own_military:
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


func try_garrison_outnumbered(
	own_military: Array[Node2D],
	enemy_units: Array[Node2D],
	town_center: Node2D,
) -> void:
	if own_military.is_empty() or enemy_units.is_empty():
		return
	if own_military.size() * 3 < enemy_units.size():
		push_warning("AIMilitary: Outnumbered — garrison not implemented, retreating instead")
		if town_center != null:
			var tc_pos: Vector2 = town_center.global_position
			for unit in own_military:
				if unit.has_method("move_to"):
					unit.move_to(tc_pos)


func allocate_tc_defenders(
	town_centers: Array[Node2D],
	own_military: Array[Node2D],
	enemy_units: Array[Node2D],
) -> void:
	if town_centers.is_empty() or _tech_manager == null:
		return
	var defense: Dictionary = tr_config.get("defense", {})
	var base_per_tech: float = float(defense.get("base_garrison_per_tech", 0.15))
	var min_ratio: float = float(defense.get("min_garrison_ratio", 0.05))
	var max_ratio: float = float(defense.get("max_garrison_ratio", 0.40))
	var tech_count: int = _tech_manager.get_researched_techs(player_id).size()
	if tech_count == 0:
		return
	var mil_size: int = own_military.size()
	if mil_size == 0:
		return
	var desired_ratio: float = clampf(base_per_tech * float(tech_count), min_ratio, max_ratio)
	var desired_defenders: int = int(desired_ratio * float(mil_size))
	if desired_defenders <= 0:
		return
	# Find most vulnerable TC
	var most_vulnerable: Node2D = null
	var highest_vuln: float = -1.0
	for tc in town_centers:
		var vuln: float = _compute_tc_vulnerability(tc, own_military, enemy_units)
		if vuln > highest_vuln:
			highest_vuln = vuln
			most_vulnerable = tc
	if most_vulnerable == null:
		return
	var radius_tiles: float = float(defense.get("enemy_proximity_radius_tiles", 20))
	var radius_px: float = radius_tiles * TILE_SIZE
	var tc_pos: Vector2 = most_vulnerable.global_position
	var current_near: int = _count_own_military_near(tc_pos, radius_px, own_military)
	var deficit: int = desired_defenders - current_near
	if deficit <= 0:
		return
	# Move idle military toward most vulnerable TC
	var moved: int = 0
	for unit in own_military:
		if moved >= deficit:
			break
		if not unit.has_method("is_idle") or not unit.is_idle():
			continue
		if tc_pos.distance_to(unit.global_position) <= radius_px:
			continue
		if unit.has_method("move_to"):
			unit.move_to(tc_pos)
			moved += 1


func _compute_tc_vulnerability(
	tc: Node2D,
	own_military: Array[Node2D],
	enemy_units: Array[Node2D],
) -> float:
	var defense: Dictionary = tr_config.get("defense", {})
	var weights: Dictionary = defense.get("scoring_weights", {})
	var w_tech: float = float(weights.get("tech_count", 0.5))
	var w_prox: float = float(weights.get("enemy_proximity", 0.3))
	var w_gap: float = float(weights.get("garrison_gap", 0.2))
	var radius_tiles: float = float(defense.get("enemy_proximity_radius_tiles", 20))
	var radius_px: float = radius_tiles * TILE_SIZE
	# Tech count score (normalized to 40 max)
	var tech_count: int = 0
	if _tech_manager != null:
		tech_count = _tech_manager.get_researched_techs(player_id).size()
	var tech_score: float = clampf(float(tech_count) / 40.0, 0.0, 1.0)
	# Enemy proximity score
	var tc_pos: Vector2 = tc.global_position
	var nearby_enemies: int = 0
	for enemy in enemy_units:
		if "hp" in enemy and enemy.hp <= 0:
			continue
		if tc_pos.distance_to(enemy.global_position) <= radius_px:
			nearby_enemies += 1
	var prox_score: float = clampf(float(nearby_enemies) / 5.0, 0.0, 1.0)
	# Garrison gap score
	var nearby_defenders: int = _count_own_military_near(tc_pos, radius_px, own_military)
	var gap_score: float = clampf(1.0 - float(nearby_defenders) / 6.0, 0.0, 1.0)
	var raw_score: float = w_tech * tech_score + w_prox * prox_score + w_gap * gap_score
	# Scale by age defense multiplier
	var age_mults: Array = defense.get("age_defense_multiplier", [1.0])
	var age: int = clampi(GameManager.current_age, 0, age_mults.size() - 1)
	var age_mult: float = float(age_mults[age])
	return clampf(raw_score * age_mult, 0.0, 1.0)


func _count_own_military_near(
	pos: Vector2,
	radius: float,
	own_military: Array[Node2D],
) -> int:
	var count: int = 0
	for unit in own_military:
		if "hp" in unit and unit.hp <= 0:
			continue
		if pos.distance_to(unit.global_position) <= radius:
			count += 1
	return count


func _find_singularity_building_target(enemy_buildings: Array[Node2D]) -> Vector2:
	for target_name: String in singularity_target_buildings:
		for building in enemy_buildings:
			if "building_name" not in building:
				continue
			if building.building_name != target_name:
				continue
			if "hp" in building and building.hp <= 0:
				continue
			return building.global_position
	return Vector2.ZERO


func _find_target_by_priority(
	priority: String,
	enemy_buildings: Array[Node2D],
	enemy_units: Array[Node2D],
	enemy_town_centers: Array[Node2D],
	town_center: Node2D,
) -> Vector2:
	match priority:
		"undefended_villagers":
			return _find_undefended_villagers(enemy_units)
		"weakest_building":
			return _find_weakest_building(enemy_buildings)
		"nearest_building":
			return _find_nearest_enemy_building_pos(enemy_buildings, town_center)
		"enemy_town_center":
			return _find_best_enemy_tc_target(enemy_town_centers, town_center)
	return Vector2.ZERO


func _find_undefended_villagers(enemy_units: Array[Node2D]) -> Vector2:
	var weakness_radius: float = float(config.get("weakness_radius", 12)) * TILE_SIZE
	for enemy in enemy_units:
		if "hp" in enemy and enemy.hp <= 0:
			continue
		var category: String = ""
		if "unit_category" in enemy:
			category = str(enemy.unit_category)
		if category == "military":
			continue
		# Check if there are defenders nearby
		var defended := false
		for other in enemy_units:
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


func _find_weakest_building(enemy_buildings: Array[Node2D]) -> Vector2:
	var weakest: Node2D = null
	var lowest_hp: int = 999999
	for building in enemy_buildings:
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


func _find_nearest_enemy_building_pos(
	enemy_buildings: Array[Node2D],
	town_center: Node2D,
) -> Vector2:
	if town_center == null:
		return Vector2.ZERO
	var tc_pos: Vector2 = town_center.global_position
	var best: Node2D = null
	var best_dist: float = INF
	for building in enemy_buildings:
		if "hp" in building and building.hp <= 0:
			continue
		var dist: float = tc_pos.distance_to(building.global_position)
		if dist < best_dist:
			best_dist = dist
			best = building
	if best != null:
		return best.global_position
	return Vector2.ZERO


func _find_best_enemy_tc_target(
	enemy_town_centers: Array[Node2D],
	town_center: Node2D,
) -> Vector2:
	if town_center == null or enemy_town_centers.is_empty():
		return Vector2.ZERO
	var tc_pos: Vector2 = town_center.global_position
	var best: Node2D = null
	var best_dist: float = INF
	for etc in enemy_town_centers:
		if "hp" in etc and etc.hp <= 0:
			continue
		var dist: float = tc_pos.distance_to(etc.global_position)
		if dist < best_dist:
			best_dist = dist
			best = etc
	if best != null:
		return best.global_position
	return Vector2.ZERO
