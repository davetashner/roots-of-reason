class_name CombatLogger
extends RefCounted
## Static ring buffer for combat damage events. No autoload needed — combat code
## calls static methods to record events; the debug server reads the buffer.

const DEFAULT_CAPACITY: int = 200

static var _events: Array[Dictionary] = []
static var _capacity: int = DEFAULT_CAPACITY
static var _total_logged: int = 0


static func log_damage(
	attacker: Node2D,
	defender: Node2D,
	damage: int,
	attacker_stats: Dictionary,
	defender_stats: Dictionary,
	extras: Dictionary = {},
) -> void:
	var hp_before: int = int(extras.get("hp_before", 0))
	var hp_after: int = int(extras.get("hp_after", 0))
	var max_hp: int = int(extras.get("max_hp", 0))
	var overkill: int = maxi(0, damage - hp_before)
	var outcome: String = "hit"
	if extras.get("war_survived", false):
		outcome = "survived"
	elif hp_after <= 0:
		outcome = "lethal"

	var event: Dictionary = {
		"timestamp": _get_game_time(),
		"attacker":
		{
			"name": attacker.name if attacker != null else "",
			"owner_id": int(attacker.owner_id) if attacker != null and "owner_id" in attacker else -1,
			"unit_type": str(attacker_stats.get("unit_type", "")),
			"attack": float(attacker_stats.get("attack", 0)),
			"attack_type": str(attacker_stats.get("attack_type", "melee")),
			"position": _pos_dict(attacker),
		},
		"defender":
		{
			"name": defender.name if defender != null else "",
			"owner_id": int(defender.owner_id) if defender != null and "owner_id" in defender else -1,
			"unit_type": str(defender_stats.get("unit_type", "")),
			"defense": float(defender_stats.get("defense", 0)),
			"armor_type": str(defender_stats.get("armor_type", "")),
			"hp_before": hp_before,
			"hp_after": hp_after,
			"max_hp": max_hp,
			"position": _pos_dict(defender),
		},
		"damage":
		{
			"final": damage,
			"raw_attack": float(attacker_stats.get("attack", 0)),
			"raw_defense": float(defender_stats.get("defense", 0)),
			"overkill": overkill,
		},
		"outcome": outcome,
	}

	if _events.size() >= _capacity:
		_events.remove_at(0)
	_events.append(event)
	_total_logged += 1


static func get_events(limit: int = 50) -> Array[Dictionary]:
	if limit <= 0 or limit >= _events.size():
		return _events.duplicate()
	return _events.slice(_events.size() - limit) as Array[Dictionary]


static func clear() -> void:
	_events.clear()
	_total_logged = 0


static func get_capacity() -> int:
	return _capacity


static func get_total_logged() -> int:
	return _total_logged


static func _get_game_time() -> float:
	if Engine.has_singleton("GameManager"):
		return float(GameManager.game_time)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		var gm: Node = tree.root.get_node_or_null("GameManager")
		if gm != null and "game_time" in gm:
			return float(gm.game_time)
	return 0.0


static func _pos_dict(entity: Node2D) -> Dictionary:
	if entity == null:
		return {"x": 0.0, "y": 0.0}
	return {"x": entity.global_position.x, "y": entity.global_position.y}
