extends RefCounted
## CombatantComponent — handles combat state machine, targeting, damage, and death.
## Extracted from prototype_unit.gd to reduce coordinator size.

enum CombatState { NONE, PURSUING, ATTACKING, ATTACK_MOVING, PATROLLING }
enum Stance { AGGRESSIVE, DEFENSIVE, STAND_GROUND }

const TILE_SIZE: float = 64.0

var combat_state: CombatState = CombatState.NONE
var stance: Stance = Stance.AGGRESSIVE
var combat_target: Node2D = null
var attack_cooldown: float = 0.0
var scan_timer: float = 0.0
var attack_move_destination: Vector2 = Vector2.ZERO
var patrol_point_a: Vector2 = Vector2.ZERO
var patrol_point_b: Vector2 = Vector2.ZERO
var patrol_heading_to_b: bool = true
var leash_origin: Vector2 = Vector2.ZERO
var combat_config: Dictionary = {}
var pending_combat_target_name: String = ""
var visibility_manager: Node = null

var _unit: Node2D = null
var _cached_attacker_stats: Dictionary = {}
var _attacker_stats_dirty: bool = true
var _reusable_target_stats: Dictionary = {
	"defense": 0.0,
	"unit_category": "",
	"unit_type": "",
}


func _init(unit: Node2D = null) -> void:
	_unit = unit


func load_config(combat_cfg: Dictionary) -> void:
	if not combat_cfg.is_empty():
		combat_config = combat_cfg
	if _unit.stats != null:
		var stat_hp: float = _unit.stats.get_stat("hp")
		if stat_hp > 0:
			_unit.max_hp = int(stat_hp)
			_unit.hp = _unit.max_hp
		if not _unit.stats.stats_changed.is_connected(_invalidate_attacker_stats):
			_unit.stats.stats_changed.connect(_invalidate_attacker_stats)
	_attacker_stats_dirty = true
	var unit_cfg := _dl_unit_stats(_unit.unit_type)
	if not unit_cfg.is_empty():
		var stance_str: String = str(unit_cfg.get("default_stance", "aggressive"))
		stance = _stance_from_string(stance_str)
		if _unit.unit_category == "":
			_unit.unit_category = str(unit_cfg.get("unit_category", ""))


func _dl_unit_stats(id: String) -> Dictionary:
	var dl: Node = GameUtils.get_autoload("DataLoader")
	if dl != null and dl.has_method("get_unit_stats"):
		return dl.get_unit_stats(id)
	return {}


func tick(game_delta: float) -> void:
	if _unit.hp <= 0:
		return
	# Decrement attack cooldown
	if attack_cooldown > 0.0:
		attack_cooldown -= game_delta
	# Increment scan timer
	scan_timer += game_delta
	# Validate combat target
	if combat_target != null and not is_instance_valid(combat_target):
		combat_target = null
	if combat_target != null and "hp" in combat_target and combat_target.hp <= 0:
		combat_target = null

	match combat_state:
		CombatState.NONE:
			_tick_combat_none()
		CombatState.PURSUING:
			_tick_combat_pursuing()
		CombatState.ATTACKING:
			_tick_combat_attacking()
		CombatState.ATTACK_MOVING:
			_tick_combat_attack_moving()
		CombatState.PATROLLING:
			_tick_combat_patrolling()


func _tick_combat_none() -> void:
	if _get_stance_config().get("auto_scan", false):
		_try_scan_and_pursue()


func _tick_combat_pursuing() -> void:
	if combat_target == null:
		_return_from_combat()
		return
	var leash: float = float(combat_config.get("leash_range", 8)) * TILE_SIZE
	if _unit.position.distance_to(leash_origin) > leash:
		combat_target = null
		_return_from_combat()
		return
	var dist := _unit.position.distance_to(combat_target.global_position)
	var range_px := _get_attack_range_pixels()
	if dist <= range_px:
		if _is_below_min_range(dist):
			combat_target = null
			_return_from_combat()
			return
		_unit._moving = false
		_unit._path.clear()
		_unit._path_index = 0
		combat_state = CombatState.ATTACKING
	elif not _unit._moving:
		_unit.move_to(combat_target.global_position)


func _tick_combat_attacking() -> void:
	if combat_target == null:
		_return_from_combat()
		return
	var dir := combat_target.global_position - _unit.position
	if dir.length() > 0.1:
		_unit._facing = dir.normalized()
	var dist := _unit.position.distance_to(combat_target.global_position)
	var range_px := _get_attack_range_pixels()
	if dist > range_px * 1.2:
		var stance_cfg := _get_stance_config()
		if stance_cfg.get("pursue", false):
			combat_state = CombatState.PURSUING
			_unit.move_to(combat_target.global_position)
		else:
			combat_target = null
			_return_from_combat()
		return
	if _is_below_min_range(dist):
		combat_target = null
		_return_from_combat()
		return
	# Apply damage if cooldown ready
	if attack_cooldown <= 0.0:
		_deal_damage_to_target()
		var cooldown: float = _unit.get_stat("attack_speed")
		if cooldown <= 0.0:
			cooldown = float(combat_config.get("attack_cooldown", 1.0))
		attack_cooldown = cooldown
		_unit.mark_visual_dirty()


func _tick_combat_attack_moving() -> void:
	if _try_scan_and_pursue():
		return
	if combat_target != null:
		combat_state = CombatState.PURSUING
		leash_origin = _unit.position
		_unit.move_to(combat_target.global_position)
		return
	if not _unit._moving:
		combat_state = CombatState.NONE


func _tick_combat_patrolling() -> void:
	if _try_scan_and_pursue():
		return
	if not _unit._moving:
		if patrol_heading_to_b:
			patrol_heading_to_b = false
			_unit.move_to(patrol_point_a)
		else:
			patrol_heading_to_b = true
			_unit.move_to(patrol_point_b)


func _try_scan_and_pursue() -> bool:
	var interval: float = float(combat_config.get("scan_interval", 0.5))
	if scan_timer < interval:
		return false
	scan_timer = 0.0
	var target := _scan_for_targets()
	if target == null:
		return false
	combat_target = target
	combat_state = CombatState.PURSUING
	leash_origin = _unit.position
	_unit.move_to(target.global_position)
	return true


func _scan_for_targets() -> Node2D:
	var root: Node = _unit._scene_root if _unit._scene_root != null else _unit.get_parent()
	if root == null:
		return null
	var scan_radius: float = float(combat_config.get("aggro_scan_radius", 6)) * TILE_SIZE
	var candidates: Array = []
	for child in root.get_children():
		if child == _unit or not (child is Node2D):
			continue
		if not CombatResolver.is_hostile(_unit, child):
			continue
		if "hp" in child and child.hp <= 0:
			continue
		if _unit.position.distance_to(child.global_position) > scan_radius:
			continue
		if visibility_manager != null and "owner_id" in child and child.owner_id != _unit.owner_id:
			if not visibility_manager.is_visible(_unit.owner_id, _screen_to_grid(child.global_position)):
				continue
		candidates.append(child)
	if candidates.is_empty():
		return null
	var attack_type := _get_attack_type()
	var priority_cfg: Dictionary = combat_config.get("target_priority", {})
	var sorted := CombatResolver.sort_targets_by_priority(candidates, attack_type, priority_cfg)
	var best: Node2D = null
	var best_dist := INF
	for candidate in sorted:
		var dist: float = _unit.position.distance_to(candidate.global_position)
		if dist < best_dist:
			best_dist = dist
			best = candidate
		if best != null:
			if CombatResolver._get_category(candidate) != CombatResolver._get_category(best):
				break
	return best


func _deal_damage_to_target() -> void:
	if combat_target == null or not is_instance_valid(combat_target):
		return
	var attacker_stats := _get_attacker_stats()
	_fill_target_stats(combat_target)
	var damage := CombatResolver.calculate_damage(attacker_stats, _reusable_target_stats, combat_config)
	_play_attack_visuals(damage)
	if combat_target.has_method("take_damage"):
		combat_target.take_damage(damage, _unit)
	elif "hp" in combat_target:
		combat_target.hp -= damage
		if combat_target.hp <= 0:
			combat_target.hp = 0


func _play_attack_visuals(damage: int) -> void:
	CombatVisual.play_attack_flash(_unit, combat_config)
	var vfx_parent: Node = _unit._scene_root if _unit._scene_root != null else _unit.get_parent()
	if vfx_parent == null:
		return
	var src := _unit.global_position
	var dst := combat_target.global_position
	if _get_attack_type() == "ranged":
		CombatVisual.spawn_projectile(vfx_parent, src, dst, combat_config)
	if combat_config.get("show_damage_numbers", true):
		var num_pos := dst + Vector2(0, -20)
		CombatVisual.spawn_damage_number(vfx_parent, num_pos, damage, combat_config)


func _invalidate_attacker_stats() -> void:
	_attacker_stats_dirty = true


func _get_attacker_stats() -> Dictionary:
	if not _attacker_stats_dirty:
		return _cached_attacker_stats
	_cached_attacker_stats["attack"] = _unit.get_stat("attack")
	_cached_attacker_stats["defense"] = _unit.get_stat("defense")
	_cached_attacker_stats["unit_category"] = _unit.unit_category
	_cached_attacker_stats["unit_type"] = _unit.unit_type
	_cached_attacker_stats["attack_type"] = _get_attack_type()
	# Remove stale optional keys before potentially re-adding
	_cached_attacker_stats.erase("bonus_vs")
	_cached_attacker_stats.erase("building_damage_ignore_reduction")
	if _unit.stats != null:
		var raw: Dictionary = _unit.stats._base_stats
		if raw.has("bonus_vs"):
			_cached_attacker_stats["bonus_vs"] = raw["bonus_vs"]
		if raw.has("building_damage_ignore_reduction"):
			_cached_attacker_stats["building_damage_ignore_reduction"] = raw["building_damage_ignore_reduction"]
	_attacker_stats_dirty = false
	return _cached_attacker_stats


func _fill_target_stats(target: Node2D) -> void:
	_reusable_target_stats["defense"] = 0.0
	_reusable_target_stats["unit_category"] = ""
	_reusable_target_stats["unit_type"] = ""
	_reusable_target_stats.erase("armor_type")
	if target.has_method("get_stat"):
		_reusable_target_stats["defense"] = target.get_stat("defense")
	elif "defense" in target:
		_reusable_target_stats["defense"] = float(target.defense)
	if "unit_category" in target:
		_reusable_target_stats["unit_category"] = target.unit_category
	elif "entity_category" in target:
		_reusable_target_stats["unit_category"] = target.entity_category
	if "unit_type" in target:
		_reusable_target_stats["unit_type"] = target.unit_type
	if "stats" in target and target.stats and target.stats._base_stats.has("armor_type"):
		_reusable_target_stats["armor_type"] = target.stats._base_stats["armor_type"]


func take_damage(amount: int, attacker: Node2D) -> void:
	if _unit._is_dead:
		return
	_unit._last_attacker = attacker
	# Check war survival before applying lethal damage
	if _unit.hp > 0 and amount >= _unit.hp and _unit._war_survival != null:
		if _unit._war_survival.roll_survival(_unit, amount):
			_unit.mark_visual_dirty()
			_try_retaliate(attacker)
			return
	_unit.hp = maxi(0, _unit.hp - amount)
	_unit.mark_visual_dirty()
	_try_retaliate(attacker)
	if _unit.hp <= 0:
		_unit._die()


func _try_retaliate(attacker: Node2D) -> void:
	var stance_cfg := _get_stance_config()
	if (
		stance_cfg.get("retaliate", false)
		and combat_state == CombatState.NONE
		and attacker != null
		and is_instance_valid(attacker)
	):
		combat_target = attacker
		leash_origin = _unit.position
		combat_state = CombatState.PURSUING
		_unit.move_to(attacker.global_position)


func attack_move_to(world_pos: Vector2) -> void:
	combat_state = CombatState.ATTACK_MOVING
	attack_move_destination = world_pos
	leash_origin = _unit.position
	combat_target = null
	_unit.move_to(world_pos)


func patrol_between(point_a: Vector2, point_b: Vector2) -> void:
	combat_state = CombatState.PATROLLING
	patrol_point_a = point_a
	patrol_point_b = point_b
	patrol_heading_to_b = true
	combat_target = null
	_unit.move_to(point_b)


func set_stance(new_stance: Stance) -> void:
	stance = new_stance
	if new_stance == Stance.STAND_GROUND and combat_state == CombatState.PURSUING:
		combat_target = null
		combat_state = CombatState.NONE
		_unit._moving = false
		_unit._path.clear()
		_unit._path_index = 0


func cancel() -> void:
	combat_state = CombatState.NONE
	combat_target = null
	attack_cooldown = 0.0
	scan_timer = 0.0


func _return_from_combat() -> void:
	var prev_state := combat_state
	combat_target = null
	if prev_state == CombatState.ATTACK_MOVING:
		combat_state = CombatState.ATTACK_MOVING
		_unit.move_to(attack_move_destination)
	elif prev_state == CombatState.PATROLLING:
		combat_state = CombatState.PATROLLING
		if patrol_heading_to_b:
			_unit.move_to(patrol_point_b)
		else:
			_unit.move_to(patrol_point_a)
	else:
		combat_state = CombatState.NONE


func _get_attack_type() -> String:
	if _unit.stats != null and _unit.stats._base_stats.has("attack_type"):
		return str(_unit.stats._base_stats["attack_type"])
	return "melee"


func _get_attack_range() -> int:
	return int(_unit.stats.get_stat("range")) if _unit.stats != null else 0


func _get_min_range() -> int:
	if _unit.stats != null and _unit.stats._base_stats.has("min_range"):
		return int(_unit.stats._base_stats["min_range"])
	return 0


func _get_attack_range_pixels() -> float:
	var r := _get_attack_range()
	return TILE_SIZE if r <= 0 else maxf(1.0, float(r)) * TILE_SIZE


func _is_below_min_range(dist: float) -> bool:
	var mr := _get_min_range()
	return mr > 0 and dist < float(mr) * TILE_SIZE


func _get_stance_config() -> Dictionary:
	var stance_name := _stance_to_string(stance)
	var stances: Dictionary = combat_config.get("stances", {})
	if stances.has(stance_name):
		return stances[stance_name]
	# Default: aggressive
	return {"auto_scan": true, "pursue": true, "retaliate": true}


func _stance_to_string(s: Stance) -> String:
	match s:
		Stance.DEFENSIVE:
			return "defensive"
		Stance.STAND_GROUND:
			return "stand_ground"
		_:
			return "aggressive"


func _stance_from_string(s: String) -> Stance:
	match s:
		"defensive":
			return Stance.DEFENSIVE
		"stand_ground":
			return Stance.STAND_GROUND
		_:
			return Stance.AGGRESSIVE


func _screen_to_grid(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x / 128.0 + p.y / 64.0), roundi(p.y / 64.0 - p.x / 128.0))


func resolve_target(scene_root: Node) -> void:
	if pending_combat_target_name == "":
		return
	var target := scene_root.get_node_or_null(pending_combat_target_name)
	if target is Node2D:
		combat_target = target
	pending_combat_target_name = ""


func save_state() -> Dictionary:
	var state := {
		"combat_state": combat_state,
		"stance": stance,
		"attack_move_destination_x": attack_move_destination.x,
		"attack_move_destination_y": attack_move_destination.y,
		"patrol_point_a_x": patrol_point_a.x,
		"patrol_point_a_y": patrol_point_a.y,
		"patrol_point_b_x": patrol_point_b.x,
		"patrol_point_b_y": patrol_point_b.y,
		"patrol_heading_to_b": patrol_heading_to_b,
		"attack_cooldown": attack_cooldown,
	}
	if combat_target != null and is_instance_valid(combat_target):
		state["combat_target_name"] = str(combat_target.name)
	return state


func load_state(data: Dictionary) -> void:
	combat_state = int(data.get("combat_state", CombatState.NONE)) as CombatState
	stance = int(data.get("stance", Stance.AGGRESSIVE)) as Stance
	attack_move_destination = Vector2(
		float(data.get("attack_move_destination_x", 0)),
		float(data.get("attack_move_destination_y", 0)),
	)
	patrol_point_a = Vector2(
		float(data.get("patrol_point_a_x", 0)),
		float(data.get("patrol_point_a_y", 0)),
	)
	patrol_point_b = Vector2(
		float(data.get("patrol_point_b_x", 0)),
		float(data.get("patrol_point_b_y", 0)),
	)
	patrol_heading_to_b = bool(data.get("patrol_heading_to_b", true))
	attack_cooldown = float(data.get("attack_cooldown", 0.0))
	pending_combat_target_name = str(data.get("combat_target_name", ""))
