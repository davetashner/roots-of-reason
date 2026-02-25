extends Node2D
## Prototype unit — colored circle with direction indicator, click-to-select,
## right-click-to-move. Villagers can build construction sites and gather resources.
## Military units have combat state machine with attack-move, patrol, and stances.

signal unit_died(unit: Node2D)

enum GatherState { NONE, MOVING_TO_RESOURCE, GATHERING, MOVING_TO_DROP_OFF, DEPOSITING }
enum CombatState { NONE, PURSUING, ATTACKING, ATTACK_MOVING, PATROLLING }
enum Stance { AGGRESSIVE, DEFENSIVE, STAND_GROUND }

const RADIUS: float = 12.0
const MOVE_SPEED: float = 150.0
const SELECTION_RING_RADIUS: float = 16.0
const TILE_SIZE: float = 64.0

@export var unit_color: Color = Color(0.2, 0.4, 0.9)
@export var owner_id: int = 0
@export var unit_type: String = "land"
@export var entity_category: String = ""
@export var unit_category: String = ""

var stats: UnitStats = null
var selected: bool = false
var hp: int = 0
var max_hp: int = 0
var _target_pos: Vector2 = Vector2.ZERO
var _moving: bool = false
var _path: Array[Vector2] = []
var _path_index: int = 0
var _facing: Vector2 = Vector2.RIGHT

var _build_target: Node2D = null
var _build_speed: float = 1.0
var _build_reach: float = 80.0
var _pending_build_target_name: String = ""

var _gather_target: Node2D = null
var _gather_state: GatherState = GatherState.NONE
var _gather_type: String = ""
var _carried_amount: int = 0
var _carry_capacity: int = 10
var _gather_rates: Dictionary = {}
var _gather_reach: float = 80.0
var _drop_off_reach: float = 80.0
var _gather_accumulator: float = 0.0
var _drop_off_target: Node2D = null
var _scene_root: Node = null
var _pending_gather_target_name: String = ""

# Combat state
var _combat_state: CombatState = CombatState.NONE
var _stance: Stance = Stance.AGGRESSIVE
var _combat_target: Node2D = null
var _attack_cooldown: float = 0.0
var _scan_timer: float = 0.0
var _attack_move_destination: Vector2 = Vector2.ZERO
var _patrol_point_a: Vector2 = Vector2.ZERO
var _patrol_point_b: Vector2 = Vector2.ZERO
var _patrol_heading_to_b: bool = true
var _leash_origin: Vector2 = Vector2.ZERO
var _combat_config: Dictionary = {}
var _pending_combat_target_name: String = ""
var _visibility_manager: Node = null


func _ready() -> void:
	_target_pos = position
	_init_stats()
	_load_build_config()
	_load_gather_config()
	_load_combat_config()


func _init_stats() -> void:
	var raw: Dictionary = _dl_unit_stats(unit_type)
	stats = UnitStats.new(unit_type, raw)


func get_stat(stat_name: String) -> float:
	if stats == null:
		return 0.0
	return stats.get_stat(stat_name)


func _dl_unit_stats(id: String) -> Dictionary:
	if Engine.has_singleton("DataLoader"):
		return DataLoader.get_unit_stats(id)
	if is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_unit_stats"):
			return dl.get_unit_stats(id)
	return {}


func _dl_settings(id: String) -> Dictionary:
	if Engine.has_singleton("DataLoader"):
		return DataLoader.get_settings(id)
	if is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_settings"):
			return dl.get_settings(id)
	return {}


func _load_build_config() -> void:
	var unit_cfg := _dl_unit_stats("villager")
	if not unit_cfg.is_empty():
		_build_speed = float(unit_cfg.get("build_speed", _build_speed))
	var con_cfg := _dl_settings("construction")
	if not con_cfg.is_empty():
		_build_reach = float(con_cfg.get("build_reach", _build_reach))


func _load_gather_config() -> void:
	var unit_cfg := _dl_unit_stats("villager")
	if not unit_cfg.is_empty():
		_carry_capacity = int(unit_cfg.get("carry_capacity", _carry_capacity))
		var rates: Variant = unit_cfg.get("gather_rates", {})
		if rates is Dictionary:
			_gather_rates = rates
	var gather_cfg := _dl_settings("gathering")
	if not gather_cfg.is_empty():
		_gather_reach = float(gather_cfg.get("gather_reach", _gather_reach))
		_drop_off_reach = float(gather_cfg.get("drop_off_reach", _drop_off_reach))


func _load_combat_config() -> void:
	var cfg := _dl_settings("combat")
	if not cfg.is_empty():
		_combat_config = cfg
	if stats != null:
		var stat_hp: float = stats.get_stat("hp")
		if stat_hp > 0:
			max_hp = int(stat_hp)
			hp = max_hp
	var unit_cfg := _dl_unit_stats(unit_type)
	if not unit_cfg.is_empty():
		var stance_str: String = str(unit_cfg.get("default_stance", "aggressive"))
		_stance = _stance_from_string(stance_str)
		if unit_category == "":
			unit_category = str(unit_cfg.get("unit_category", ""))


func _process(delta: float) -> void:
	var game_delta := GameManager.get_game_delta(delta)
	if game_delta == 0.0:
		return
	if _moving:
		var dist := position.distance_to(_target_pos)
		if dist < 2.0:
			position = _target_pos
			# Advance to next waypoint if following a path
			if _path_index < _path.size() - 1:
				_path_index += 1
				_target_pos = _path[_path_index]
			else:
				_moving = false
				_path.clear()
				_path_index = 0
		else:
			var direction := (_target_pos - position).normalized()
			_facing = direction
			position = position.move_toward(_target_pos, MOVE_SPEED * game_delta)
		queue_redraw()
	_tick_build(game_delta)
	_tick_gather(game_delta)
	_tick_combat(game_delta)


func _tick_build(game_delta: float) -> void:
	if _build_target == null:
		return
	if not is_instance_valid(_build_target):
		_build_target = null
		return
	if not _build_target.under_construction:
		_build_target = null
		return
	var dist: float = position.distance_to(_build_target.global_position)
	if dist > _build_reach:
		return
	# Stop moving — we're in range
	_moving = false
	_path.clear()
	_path_index = 0
	# Apply build work: build_speed / build_time per second
	var build_time: float = _build_target._build_time
	var work: float = (_build_speed / build_time) * game_delta
	_build_target.apply_build_work(work)
	# Check if construction completed
	if not _build_target.under_construction:
		_build_target = null


func _tick_gather(game_delta: float) -> void:
	match _gather_state:
		GatherState.NONE:
			return
		GatherState.MOVING_TO_RESOURCE:
			_tick_moving_to_resource()
		GatherState.GATHERING:
			_tick_gathering(game_delta)
		GatherState.MOVING_TO_DROP_OFF:
			_tick_moving_to_drop_off()
		GatherState.DEPOSITING:
			_tick_depositing()


func _tick_moving_to_resource() -> void:
	if _gather_target == null or not is_instance_valid(_gather_target):
		_cancel_gather()
		return
	if _gather_target.current_yield <= 0:
		_try_find_replacement_resource()
		return
	var dist: float = position.distance_to(_gather_target.global_position)
	if dist <= _gather_reach and not _moving:
		_gather_state = GatherState.GATHERING
		_gather_accumulator = 0.0


func _tick_gathering(game_delta: float) -> void:
	if _gather_target == null or not is_instance_valid(_gather_target):
		if _carried_amount > 0:
			_start_drop_off_trip()
		else:
			_try_find_replacement_resource()
		return
	if _gather_target.current_yield <= 0:
		if _carried_amount > 0:
			_start_drop_off_trip()
		else:
			_try_find_replacement_resource()
		return
	var rate: float = float(_gather_rates.get(_gather_type, 0.0))
	_gather_accumulator += rate * game_delta
	if _gather_accumulator >= 1.0:
		var whole := int(_gather_accumulator)
		var room := _carry_capacity - _carried_amount
		var to_extract := mini(whole, room)
		var gathered: int = _gather_target.apply_gather_work(float(to_extract))
		_carried_amount += gathered
		_gather_accumulator -= float(to_extract)
	if _carried_amount >= _carry_capacity:
		_start_drop_off_trip()


func _tick_moving_to_drop_off() -> void:
	if _drop_off_target == null or not is_instance_valid(_drop_off_target):
		_drop_off_target = _find_nearest_drop_off(_gather_type)
		if _drop_off_target == null:
			_cancel_gather()
			return
		move_to(_drop_off_target.global_position)
		return
	var dist: float = position.distance_to(_drop_off_target.global_position)
	if dist <= _drop_off_reach and not _moving:
		_gather_state = GatherState.DEPOSITING


func _tick_depositing() -> void:
	var res_enum: Variant = _resource_type_to_enum(_gather_type)
	if res_enum != null:
		ResourceManager.add_resource(owner_id, res_enum, _carried_amount)
	_carried_amount = 0
	_drop_off_target = null
	# Return to resource or find replacement
	if _gather_target != null and is_instance_valid(_gather_target) and _gather_target.current_yield > 0:
		_gather_state = GatherState.MOVING_TO_RESOURCE
		move_to(_gather_target.global_position)
	else:
		_try_find_replacement_resource()


func _start_drop_off_trip() -> void:
	_drop_off_target = _find_nearest_drop_off(_gather_type)
	if _drop_off_target == null:
		_cancel_gather()
		return
	_gather_state = GatherState.MOVING_TO_DROP_OFF
	move_to(_drop_off_target.global_position)


func _find_nearest_drop_off(res_type: String) -> Node2D:
	var root := _scene_root if _scene_root != null else get_parent()
	if root == null:
		return null
	var best: Node2D = null
	var best_dist := INF
	for child in root.get_children():
		if not child.has_method("save_state"):
			continue
		if "is_drop_off" not in child or not child.is_drop_off:
			continue
		if "drop_off_types" in child:
			var types: Array = child.drop_off_types
			if not types.has(res_type):
				continue
		var dist: float = position.distance_to(child.global_position)
		if dist < best_dist:
			best_dist = dist
			best = child
	return best


func _try_find_replacement_resource() -> void:
	var root := _scene_root if _scene_root != null else get_parent()
	if root == null:
		_cancel_gather()
		return
	var best: Node2D = null
	var best_dist := INF
	for child in root.get_children():
		if child == _gather_target:
			continue
		if "entity_category" not in child:
			continue
		if child.entity_category != "resource_node":
			continue
		if "resource_type" not in child or child.resource_type != _gather_type:
			continue
		if "current_yield" in child and child.current_yield <= 0:
			continue
		var dist: float = position.distance_to(child.global_position)
		if dist < best_dist:
			best_dist = dist
			best = child
	if best != null:
		_gather_target = best
		_gather_state = GatherState.MOVING_TO_RESOURCE
		_gather_accumulator = 0.0
		move_to(best.global_position)
	elif _carried_amount > 0:
		_start_drop_off_trip()
	else:
		_cancel_gather()


func _cancel_gather() -> void:
	_gather_target = null
	_gather_state = GatherState.NONE
	_gather_type = ""
	_gather_accumulator = 0.0
	_drop_off_target = null


func _resource_type_to_enum(res_type: String) -> Variant:
	match res_type:
		"food":
			return ResourceManager.ResourceType.FOOD
		"wood":
			return ResourceManager.ResourceType.WOOD
		"stone":
			return ResourceManager.ResourceType.STONE
		"gold":
			return ResourceManager.ResourceType.GOLD
	return null


func assign_gather_target(node: Node2D) -> void:
	# Cancel build task
	_build_target = null
	_pending_build_target_name = ""
	# Cancel combat
	_cancel_combat()
	# Set up gather
	_gather_target = node
	_gather_type = node.resource_type if "resource_type" in node else ""
	_gather_state = GatherState.MOVING_TO_RESOURCE
	_gather_accumulator = 0.0
	_carried_amount = 0
	_drop_off_target = null
	move_to(node.global_position)


func assign_build_target(building: Node2D) -> void:
	# Cancel gather task
	_cancel_gather()
	# Cancel combat
	_cancel_combat()
	_build_target = building
	move_to(building.global_position)


func is_idle() -> bool:
	return (
		not _moving
		and _build_target == null
		and _gather_state == GatherState.NONE
		and _combat_state == CombatState.NONE
	)


func resolve_build_target(scene_root: Node) -> void:
	if _pending_build_target_name == "":
		return
	var target := scene_root.get_node_or_null(_pending_build_target_name)
	if target is Node2D:
		_build_target = target
	_pending_build_target_name = ""


func resolve_gather_target(scene_root: Node) -> void:
	if _pending_gather_target_name == "":
		return
	var target := scene_root.get_node_or_null(_pending_gather_target_name)
	if target is Node2D:
		_gather_target = target
	_pending_gather_target_name = ""


# -- Combat --


func _tick_combat(game_delta: float) -> void:
	if hp <= 0:
		return
	# Decrement attack cooldown
	if _attack_cooldown > 0.0:
		_attack_cooldown -= game_delta
	# Increment scan timer
	_scan_timer += game_delta
	# Validate combat target
	if _combat_target != null and not is_instance_valid(_combat_target):
		_combat_target = null
	if _combat_target != null and "hp" in _combat_target and _combat_target.hp <= 0:
		_combat_target = null

	match _combat_state:
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
	var stance_cfg := _get_stance_config()
	if not stance_cfg.get("auto_scan", false):
		return
	var interval: float = float(_combat_config.get("scan_interval", 0.5))
	if _scan_timer < interval:
		return
	_scan_timer = 0.0
	var target := _scan_for_targets()
	if target != null:
		_combat_target = target
		_leash_origin = position
		_combat_state = CombatState.PURSUING
		move_to(target.global_position)


func _tick_combat_pursuing() -> void:
	if _combat_target == null:
		_return_from_combat()
		return
	# Check leash range
	var leash: float = float(_combat_config.get("leash_range", 8)) * TILE_SIZE
	if position.distance_to(_leash_origin) > leash:
		_combat_target = null
		_return_from_combat()
		return
	# Check if in attack range
	var attack_range := _get_attack_range()
	var dist := position.distance_to(_combat_target.global_position)
	var range_pixels: float = maxf(1.0, float(attack_range)) * TILE_SIZE
	if attack_range <= 0:
		range_pixels = TILE_SIZE  # Melee: adjacent tile
	if dist <= range_pixels:
		# Check min range — if target is too close for ranged, disengage
		var min_range := _get_min_range()
		if min_range > 0 and dist < float(min_range) * TILE_SIZE:
			_combat_target = null
			_return_from_combat()
			return
		_moving = false
		_path.clear()
		_path_index = 0
		_combat_state = CombatState.ATTACKING
	else:
		# Keep moving toward target
		if not _moving:
			move_to(_combat_target.global_position)


func _tick_combat_attacking() -> void:
	if _combat_target == null:
		_return_from_combat()
		return
	# Face the target
	var dir := _combat_target.global_position - position
	if dir.length() > 0.1:
		_facing = dir.normalized()
	# Check if target moved out of range
	var attack_range := _get_attack_range()
	var dist := position.distance_to(_combat_target.global_position)
	var range_pixels: float = maxf(1.0, float(attack_range)) * TILE_SIZE
	if attack_range <= 0:
		range_pixels = TILE_SIZE
	if dist > range_pixels * 1.2:
		# Target moved away — pursue if stance allows
		var stance_cfg := _get_stance_config()
		if stance_cfg.get("pursue", false):
			_combat_state = CombatState.PURSUING
			move_to(_combat_target.global_position)
		else:
			_combat_target = null
			_return_from_combat()
		return
	# Check min range — if target is too close for ranged, disengage
	var min_range := _get_min_range()
	if min_range > 0 and dist < float(min_range) * TILE_SIZE:
		_combat_target = null
		_return_from_combat()
		return
	# Apply damage if cooldown ready
	if _attack_cooldown <= 0.0:
		_deal_damage_to_target()
		var cooldown: float = get_stat("attack_speed")
		if cooldown <= 0.0:
			cooldown = float(_combat_config.get("attack_cooldown", 1.0))
		_attack_cooldown = cooldown
		queue_redraw()


func _tick_combat_attack_moving() -> void:
	# Scan while moving
	var interval: float = float(_combat_config.get("scan_interval", 0.5))
	if _scan_timer >= interval:
		_scan_timer = 0.0
		if _combat_target == null:
			var target := _scan_for_targets()
			if target != null:
				_combat_target = target
				_combat_state = CombatState.PURSUING
				_leash_origin = position
				move_to(target.global_position)
				return
	# If we have a target, pursue it
	if _combat_target != null:
		_combat_state = CombatState.PURSUING
		_leash_origin = position
		move_to(_combat_target.global_position)
		return
	# If reached destination, done
	if not _moving:
		_combat_state = CombatState.NONE


func _tick_combat_patrolling() -> void:
	# Scan while patrolling
	var interval: float = float(_combat_config.get("scan_interval", 0.5))
	if _scan_timer >= interval:
		_scan_timer = 0.0
		var target := _scan_for_targets()
		if target != null:
			_combat_target = target
			_combat_state = CombatState.PURSUING
			_leash_origin = position
			move_to(target.global_position)
			return
	# Move between patrol points
	if not _moving:
		if _patrol_heading_to_b:
			_patrol_heading_to_b = false
			move_to(_patrol_point_a)
		else:
			_patrol_heading_to_b = true
			move_to(_patrol_point_b)


func _scan_for_targets() -> Node2D:
	var root := _scene_root if _scene_root != null else get_parent()
	if root == null:
		return null
	var scan_radius: float = float(_combat_config.get("aggro_scan_radius", 6)) * TILE_SIZE
	var candidates: Array = []
	for child in root.get_children():
		if child == self:
			continue
		if not (child is Node2D):
			continue
		if not CombatResolver.is_hostile(self, child):
			continue
		if "hp" in child and child.hp <= 0:
			continue
		var dist: float = position.distance_to(child.global_position)
		if dist > scan_radius:
			continue
		# Skip enemies on tiles not visible to this unit's owner
		if _visibility_manager != null and "owner_id" in child and child.owner_id != owner_id:
			var grid_pos := _screen_to_grid(child.global_position)
			if not _visibility_manager.is_visible(owner_id, grid_pos):
				continue
		candidates.append(child)
	if candidates.is_empty():
		return null
	# Sort by priority
	var attack_type := _get_attack_type()
	var priority_cfg: Dictionary = _combat_config.get("target_priority", {})
	var sorted := CombatResolver.sort_targets_by_priority(candidates, attack_type, priority_cfg)
	# Within same priority category, pick nearest
	var best: Node2D = null
	var best_dist := INF
	for candidate in sorted:
		var dist: float = position.distance_to(candidate.global_position)
		if dist < best_dist:
			best_dist = dist
			best = candidate
		# Only check first priority group — break when category changes
		if best != null:
			var best_cat := CombatResolver._get_category(best)
			var cand_cat := CombatResolver._get_category(candidate)
			if cand_cat != best_cat:
				break
	return best


func _deal_damage_to_target() -> void:
	if _combat_target == null or not is_instance_valid(_combat_target):
		return
	var attacker_stats := _build_stats_dict()
	var defender_stats := _build_target_stats_dict(_combat_target)
	var damage := CombatResolver.calculate_damage(attacker_stats, defender_stats, _combat_config)
	_play_attack_visuals(damage)
	if _combat_target.has_method("take_damage"):
		_combat_target.take_damage(damage, self)
	elif "hp" in _combat_target:
		_combat_target.hp -= damage
		if _combat_target.hp <= 0:
			_combat_target.hp = 0


func _play_attack_visuals(damage: int) -> void:
	CombatVisual.play_attack_flash(self, _combat_config)
	var vfx_parent := _scene_root if _scene_root != null else get_parent()
	if vfx_parent == null:
		return
	if _get_attack_type() == "ranged":
		CombatVisual.spawn_projectile(vfx_parent, global_position, _combat_target.global_position, _combat_config)
	if _combat_config.get("show_damage_numbers", true):
		CombatVisual.spawn_damage_number(
			vfx_parent, _combat_target.global_position + Vector2(0, -20), damage, _combat_config
		)


func _build_stats_dict() -> Dictionary:
	var result: Dictionary = {
		"attack": get_stat("attack"),
		"defense": get_stat("defense"),
		"unit_category": unit_category,
		"unit_type": unit_type,
		"attack_type": _get_attack_type(),
	}
	# Include bonus_vs and building_damage_ignore_reduction from base stats
	if stats != null:
		var raw: Dictionary = stats._base_stats
		if raw.has("bonus_vs"):
			result["bonus_vs"] = raw["bonus_vs"]
		if raw.has("building_damage_ignore_reduction"):
			result["building_damage_ignore_reduction"] = raw["building_damage_ignore_reduction"]
	return result


func _build_target_stats_dict(target: Node2D) -> Dictionary:
	var result: Dictionary = {
		"defense": 0.0,
		"unit_category": "",
		"unit_type": "",
	}
	if target.has_method("get_stat"):
		result["defense"] = target.get_stat("defense")
	elif "defense" in target:
		result["defense"] = float(target.defense)
	if "unit_category" in target:
		result["unit_category"] = target.unit_category
	elif "entity_category" in target:
		result["unit_category"] = target.entity_category
	if "unit_type" in target:
		result["unit_type"] = target.unit_type
	return result


func take_damage(amount: int, attacker: Node2D) -> void:
	hp -= amount
	if hp < 0:
		hp = 0
	queue_redraw()
	# Retaliate if defensive stance and idle
	var stance_cfg := _get_stance_config()
	if (
		stance_cfg.get("retaliate", false)
		and _combat_state == CombatState.NONE
		and attacker != null
		and is_instance_valid(attacker)
	):
		_combat_target = attacker
		_leash_origin = position
		_combat_state = CombatState.PURSUING
		move_to(attacker.global_position)
	# Die if HP depleted
	if hp <= 0:
		_die()


func _die() -> void:
	unit_died.emit(self)
	set_process(false)
	var tween := CombatVisual.play_death_animation(self, _combat_config)
	if tween != null:
		tween.finished.connect(queue_free)
	else:
		queue_free()


func attack_move_to(world_pos: Vector2) -> void:
	# Cancel gather and build
	_cancel_gather()
	_build_target = null
	_pending_build_target_name = ""
	# Set combat state
	_combat_state = CombatState.ATTACK_MOVING
	_attack_move_destination = world_pos
	_leash_origin = position
	_combat_target = null
	move_to(world_pos)


func patrol_between(point_a: Vector2, point_b: Vector2) -> void:
	# Cancel gather and build
	_cancel_gather()
	_build_target = null
	_pending_build_target_name = ""
	# Set combat state
	_combat_state = CombatState.PATROLLING
	_patrol_point_a = point_a
	_patrol_point_b = point_b
	_patrol_heading_to_b = true
	_combat_target = null
	move_to(point_b)


func set_stance(new_stance: Stance) -> void:
	_stance = new_stance
	# Stand ground cancels pursuit
	if new_stance == Stance.STAND_GROUND:
		if _combat_state == CombatState.PURSUING:
			_combat_target = null
			_combat_state = CombatState.NONE
			_moving = false
			_path.clear()
			_path_index = 0


func _cancel_combat() -> void:
	_combat_state = CombatState.NONE
	_combat_target = null
	_attack_cooldown = 0.0
	_scan_timer = 0.0


func _return_from_combat() -> void:
	# Return to previous task based on combat state
	var prev_state := _combat_state
	_combat_target = null
	if prev_state == CombatState.ATTACK_MOVING:
		_combat_state = CombatState.ATTACK_MOVING
		move_to(_attack_move_destination)
	elif prev_state == CombatState.PATROLLING:
		_combat_state = CombatState.PATROLLING
		if _patrol_heading_to_b:
			move_to(_patrol_point_b)
		else:
			move_to(_patrol_point_a)
	else:
		_combat_state = CombatState.NONE


func _get_attack_type() -> String:
	if stats != null and stats._base_stats.has("attack_type"):
		return str(stats._base_stats["attack_type"])
	return "melee"


func _get_attack_range() -> int:
	if stats != null:
		return int(stats.get_stat("range"))
	return 0


func _screen_to_grid(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x / 128.0 + p.y / 64.0), roundi(p.y / 64.0 - p.x / 128.0))


func _get_min_range() -> int:
	if stats != null and stats._base_stats.has("min_range"):
		return int(stats._base_stats["min_range"])
	return 0


func _get_stance_config() -> Dictionary:
	var stance_name := _stance_to_string(_stance)
	var stances: Dictionary = _combat_config.get("stances", {})
	if stances.has(stance_name):
		return stances[stance_name]
	# Default: aggressive
	return {"auto_scan": true, "pursue": true, "retaliate": true}


func _stance_to_string(s: Stance) -> String:
	if s == Stance.DEFENSIVE:
		return "defensive"
	if s == Stance.STAND_GROUND:
		return "stand_ground"
	return "aggressive"


func _stance_from_string(s: String) -> Stance:
	if s == "defensive":
		return Stance.DEFENSIVE
	if s == "stand_ground":
		return Stance.STAND_GROUND
	return Stance.AGGRESSIVE


func resolve_combat_target(scene_root: Node) -> void:
	if _pending_combat_target_name == "":
		return
	var target := scene_root.get_node_or_null(_pending_combat_target_name)
	if target is Node2D:
		_combat_target = target
	_pending_combat_target_name = ""


func _draw() -> void:
	# Selection ring
	if selected:
		draw_arc(
			Vector2.ZERO,
			SELECTION_RING_RADIUS,
			0,
			TAU,
			32,
			Color(0.0, 1.0, 0.0, 0.8),
			2.0,
		)

	# Unit body
	draw_circle(Vector2.ZERO, RADIUS, unit_color)

	# Direction triangle (points toward facing direction)
	var dir := _facing
	var tip := dir * (RADIUS + 4.0)
	var left := dir.rotated(2.5) * RADIUS * 0.5
	var right := dir.rotated(-2.5) * RADIUS * 0.5
	draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(1, 1, 1, 0.9))

	# Movement target indicator
	if _moving:
		var local_target := _target_pos - position
		draw_circle(local_target, 3.0, Color(1, 1, 0, 0.6))
		draw_arc(local_target, 6.0, 0, TAU, 16, Color(1, 1, 0, 0.4), 1.0)

	# Carry indicator
	if _carried_amount > 0:
		var carry_color := Color(0.9, 0.8, 0.1, 0.8)
		var ratio := float(_carried_amount) / float(_carry_capacity)
		draw_arc(Vector2.ZERO, RADIUS + 2.0, 0, TAU * ratio, 16, carry_color, 2.0)

	# HP bar (only if damaged)
	if max_hp > 0 and hp < max_hp:
		var bar_width: float = RADIUS * 2.5
		var bar_height: float = 3.0
		var bar_y: float = -RADIUS - 8.0
		var ratio: float = float(hp) / float(max_hp)
		var bg_rect := Rect2(-bar_width / 2.0, bar_y, bar_width, bar_height)
		draw_rect(bg_rect, Color(0.2, 0.2, 0.2, 0.8))
		var fg_rect := Rect2(-bar_width / 2.0, bar_y, bar_width * ratio, bar_height)
		var hp_color: Color
		if ratio > 0.5:
			hp_color = Color(0.2, 0.8, 0.2)
		else:
			hp_color = Color(0.9, 0.2, 0.2)
		draw_rect(fg_rect, hp_color)


func move_to(world_pos: Vector2) -> void:
	_path.clear()
	_path_index = 0
	_target_pos = world_pos
	_moving = true
	queue_redraw()


func follow_path(waypoints: Array[Vector2]) -> void:
	if waypoints.is_empty():
		return
	_path = waypoints
	_path_index = 0
	_target_pos = _path[0]
	_moving = true
	queue_redraw()


func select() -> void:
	selected = true
	queue_redraw()


func deselect() -> void:
	selected = false
	queue_redraw()


func is_point_inside(point: Vector2) -> bool:
	return point.distance_to(global_position) <= RADIUS * 1.5


func get_entity_category() -> String:
	if entity_category != "":
		return entity_category
	return "enemy_unit" if owner_id != 0 else ""


func save_state() -> Dictionary:
	var state := {
		"position_x": position.x,
		"position_y": position.y,
		"unit_type": unit_type,
		"gather_state": _gather_state,
		"gather_type": _gather_type,
		"carried_amount": _carried_amount,
		"gather_accumulator": _gather_accumulator,
		"hp": hp,
		"max_hp": max_hp,
		"combat_state": _combat_state,
		"stance": _stance,
		"attack_move_destination_x": _attack_move_destination.x,
		"attack_move_destination_y": _attack_move_destination.y,
		"patrol_point_a_x": _patrol_point_a.x,
		"patrol_point_a_y": _patrol_point_a.y,
		"patrol_point_b_x": _patrol_point_b.x,
		"patrol_point_b_y": _patrol_point_b.y,
		"patrol_heading_to_b": _patrol_heading_to_b,
		"attack_cooldown": _attack_cooldown,
	}
	if _build_target != null and is_instance_valid(_build_target):
		state["build_target_name"] = str(_build_target.name)
	if _gather_target != null and is_instance_valid(_gather_target):
		state["gather_target_name"] = str(_gather_target.name)
	if _combat_target != null and is_instance_valid(_combat_target):
		state["combat_target_name"] = str(_combat_target.name)
	if stats != null:
		state["stats"] = stats.save_state()
	return state


func load_state(data: Dictionary) -> void:
	position = Vector2(
		float(data.get("position_x", 0)),
		float(data.get("position_y", 0)),
	)
	unit_type = str(data.get("unit_type", "land"))
	_pending_build_target_name = str(data.get("build_target_name", ""))
	_pending_gather_target_name = str(data.get("gather_target_name", ""))
	_gather_state = int(data.get("gather_state", GatherState.NONE)) as GatherState
	_gather_type = str(data.get("gather_type", ""))
	_carried_amount = int(data.get("carried_amount", 0))
	_gather_accumulator = float(data.get("gather_accumulator", 0.0))
	# Restore combat state
	hp = int(data.get("hp", max_hp))
	max_hp = int(data.get("max_hp", max_hp))
	_combat_state = int(data.get("combat_state", CombatState.NONE)) as CombatState
	_stance = int(data.get("stance", Stance.AGGRESSIVE)) as Stance
	_attack_move_destination = Vector2(
		float(data.get("attack_move_destination_x", 0)),
		float(data.get("attack_move_destination_y", 0)),
	)
	_patrol_point_a = Vector2(
		float(data.get("patrol_point_a_x", 0)),
		float(data.get("patrol_point_a_y", 0)),
	)
	_patrol_point_b = Vector2(
		float(data.get("patrol_point_b_x", 0)),
		float(data.get("patrol_point_b_y", 0)),
	)
	_patrol_heading_to_b = bool(data.get("patrol_heading_to_b", true))
	_attack_cooldown = float(data.get("attack_cooldown", 0.0))
	_pending_combat_target_name = str(data.get("combat_target_name", ""))
	if data.has("stats"):
		if stats == null:
			stats = UnitStats.new()
		stats.load_state(data["stats"])
