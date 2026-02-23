class_name CombatResolver
extends RefCounted
## Pure-function combat resolver: damage calculation, target priority sorting,
## and range checking. No side effects.


## Calculate damage dealt. Formula: max(1, (attack - defense) * bonus_multiplier)
## Buildings take building_damage_reduction unless attacker has
## building_damage_ignore_reduction.
static func calculate_damage(
	attacker_stats: Dictionary,
	defender_stats: Dictionary,
	combat_config: Dictionary,
) -> int:
	var attack: float = float(attacker_stats.get("attack", 0))
	var defense: float = float(defender_stats.get("defense", 0))
	var raw: float = attack - defense

	# Apply bonus_vs multiplier
	var bonus_vs: Dictionary = attacker_stats.get("bonus_vs", {})
	var defender_category: String = str(defender_stats.get("unit_category", ""))
	var defender_type: String = str(defender_stats.get("unit_type", ""))
	var bonus: float = 1.0
	if bonus_vs.has(defender_type):
		bonus = float(bonus_vs[defender_type])
	elif bonus_vs.has(defender_category):
		bonus = float(bonus_vs[defender_category])

	raw *= bonus

	# Building damage reduction
	if defender_category == "building":
		var reduction: float = float(combat_config.get("building_damage_reduction", 0.80))
		var ignore: float = float(attacker_stats.get("building_damage_ignore_reduction", 0.0))
		raw *= (1.0 - reduction + ignore)

	return maxi(1, int(raw))


## Check if target is in attack range. Uses Chebyshev grid distance.
static func is_in_range(
	attacker_pos: Vector2i,
	target_pos: Vector2i,
	attack_range: int,
) -> bool:
	var dist := maxi(
		absi(attacker_pos.x - target_pos.x),
		absi(attacker_pos.y - target_pos.y),
	)
	if attack_range <= 0:
		# Melee: must be adjacent (dist <= 1)
		return dist <= 1
	return dist <= attack_range


## Check if target is beyond min_range (for ranged units).
static func is_beyond_min_range(
	attacker_pos: Vector2i,
	target_pos: Vector2i,
	min_range: int,
) -> bool:
	if min_range <= 0:
		return true
	var dist := maxi(
		absi(attacker_pos.x - target_pos.x),
		absi(attacker_pos.y - target_pos.y),
	)
	return dist >= min_range


## Sort potential targets by priority order. Returns sorted array of nodes.
static func sort_targets_by_priority(
	targets: Array,
	attacker_category: String,
	priority_config: Dictionary,
) -> Array:
	var priority_order: Array = priority_config.get(attacker_category, ["military", "civilian", "building"])
	var sorted: Array = targets.duplicate()
	sorted.sort_custom(
		func(a: Node, b: Node) -> bool:
			var cat_a: String = _get_category(a)
			var cat_b: String = _get_category(b)
			var idx_a: int = priority_order.find(cat_a)
			var idx_b: int = priority_order.find(cat_b)
			if idx_a < 0:
				idx_a = 999
			if idx_b < 0:
				idx_b = 999
			return idx_a < idx_b
	)
	return sorted


## Get the combat-relevant category of an entity.
static func _get_category(entity: Node) -> String:
	if "unit_category" in entity:
		return entity.unit_category
	if "entity_category" in entity:
		var cat: String = entity.entity_category
		if cat == "resource_node":
			return "resource"
		if cat.begins_with("enemy"):
			return "military"
		return cat
	if entity.has_method("get_entity_category"):
		var cat: String = entity.get_entity_category()
		if cat.begins_with("enemy"):
			return "military"
		return cat
	return "unknown"


## Check if two entities are hostile to each other.
static func is_hostile(entity_a: Node, entity_b: Node) -> bool:
	var owner_a: int = entity_a.owner_id if "owner_id" in entity_a else -1
	var owner_b: int = entity_b.owner_id if "owner_id" in entity_b else -1
	if owner_a < 0 or owner_b < 0:
		return false
	return owner_a != owner_b
