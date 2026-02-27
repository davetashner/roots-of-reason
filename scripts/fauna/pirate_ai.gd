extends Node
## Pirate AI — state machine driving patrol, hunt, attack, flee behavior for pirate ships.
## Attached as child of a prototype_unit with owner_id == -1 (Gaia).

enum PirateState { PATROL, HUNT, ATTACK, FLEE }

const TILE_SIZE: float = 64.0

var spawn_origin: Vector2 = Vector2.ZERO

var _state: PirateState = PirateState.PATROL
var _cfg: Dictionary = {}
var _pirate: Node2D = null
var _combat_target: Node2D = null
var _patrol_idle_timer: float = 0.0
var _flee_timer: float = 0.0
var _scan_timer: float = 0.0
var _scene_root: Node = null
var _move_target: Vector2 = Vector2.ZERO
var _is_moving: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_pirate = get_parent()
	if _pirate == null:
		return
	_cfg = _load_config()
	spawn_origin = _pirate.position
	# Suppress prototype_unit's built-in combat
	_pirate._stance = _pirate.Stance.STAND_GROUND
	_pirate._combat_state = _pirate.CombatState.NONE
	_pirate._cancel_combat()
	# Find scene root after ready
	call_deferred("_find_scene_root")
	# Start with a random idle delay before first patrol move
	_patrol_idle_timer = _rng.randf_range(1.0, 3.0)


func _load_config() -> Dictionary:
	return GameUtils.dl_settings("pirates")


func _find_scene_root() -> void:
	if _pirate == null:
		return
	var root := _pirate.get_parent()
	if root != null:
		_scene_root = root


func _process(delta: float) -> void:
	var game_delta: float = GameUtils.get_game_delta(delta)
	if game_delta == 0.0:
		return
	if _pirate == null or not is_instance_valid(_pirate):
		return
	# Keep prototype_unit's combat suppressed
	if _pirate._combat_state != _pirate.CombatState.NONE:
		_pirate._cancel_combat()
	if _pirate._moving:
		_pirate._moving = false
		_pirate._path.clear()
		_pirate._path_index = 0

	_scan_timer += game_delta

	match _state:
		PirateState.PATROL:
			_tick_patrol(game_delta)
		PirateState.HUNT:
			_tick_hunt(game_delta)
		PirateState.ATTACK:
			_tick_attack(game_delta)
		PirateState.FLEE:
			_tick_flee(game_delta)


# -- PATROL --


func _tick_patrol(game_delta: float) -> void:
	var scan_interval: float = float(_cfg.get("scan_interval", 0.5))
	if _scan_timer >= scan_interval:
		_scan_timer = 0.0
		# Check flee condition first
		if _should_flee():
			_enter_flee()
			return
		# Check for soft targets
		var target := _scan_for_target()
		if target != null:
			_enter_hunt(target)
			return

	if _is_moving:
		var speed: float = float(_get_stats().get("speed", 3.0)) * TILE_SIZE
		_tick_movement(game_delta, speed)
	else:
		_patrol_idle_timer -= game_delta
		if _patrol_idle_timer <= 0.0:
			_pick_patrol_target()
			_patrol_idle_timer = _rng.randf_range(2.0, 5.0)


func _pick_patrol_target() -> void:
	var patrol_radius: float = 10.0 * TILE_SIZE
	_move_target = (
		spawn_origin
		+ Vector2(
			_rng.randf_range(-patrol_radius, patrol_radius),
			_rng.randf_range(-patrol_radius, patrol_radius),
		)
	)
	_is_moving = true


# -- HUNT --


func _enter_hunt(target: Node2D) -> void:
	_state = PirateState.HUNT
	_combat_target = target
	_is_moving = true
	_move_target = target.global_position


func _tick_hunt(game_delta: float) -> void:
	# Validate target
	if _combat_target == null or not is_instance_valid(_combat_target):
		_enter_patrol()
		return
	if "hp" in _combat_target and _combat_target.hp <= 0:
		_enter_patrol()
		return

	# Check flee during hunt
	var scan_interval: float = float(_cfg.get("scan_interval", 0.5))
	if _scan_timer >= scan_interval:
		_scan_timer = 0.0
		if _should_flee():
			_enter_flee()
			return

	# Check chase abandon distance
	var max_chase: float = float(_get_stats().get("los", 6)) * 2.0 * TILE_SIZE
	if _pirate.position.distance_to(_combat_target.global_position) > max_chase:
		_enter_patrol()
		return

	# Move toward target
	_move_target = _combat_target.global_position
	var speed: float = float(_get_stats().get("speed", 3.0)) * TILE_SIZE
	_tick_movement(game_delta, speed)

	# Check if in attack range
	var attack_range: float = float(_get_stats().get("range", 4)) * TILE_SIZE
	var dist := _pirate.position.distance_to(_combat_target.global_position)
	if dist <= attack_range:
		_enter_attack(_combat_target)


# -- ATTACK --


func _enter_attack(target: Node2D) -> void:
	_state = PirateState.ATTACK
	_combat_target = target
	_is_moving = false


func _tick_attack(game_delta: float) -> void:
	# Validate target
	if _combat_target == null or not is_instance_valid(_combat_target):
		_enter_patrol()
		return
	if "hp" in _combat_target and _combat_target.hp <= 0:
		_enter_patrol()
		return

	# Check flee during attack
	var scan_interval: float = float(_cfg.get("scan_interval", 0.5))
	if _scan_timer >= scan_interval:
		_scan_timer = 0.0
		if _should_flee():
			_enter_flee()
			return

	# Check range — if target moved out of range, go back to HUNT
	var attack_range: float = float(_get_stats().get("range", 4)) * TILE_SIZE
	var dist := _pirate.position.distance_to(_combat_target.global_position)
	if dist > attack_range * 1.5:
		_enter_hunt(_combat_target)
		return

	# Chase abandon
	var max_chase: float = float(_get_stats().get("los", 6)) * 2.0 * TILE_SIZE
	if _pirate.position.distance_to(_combat_target.global_position) > max_chase:
		_enter_patrol()
		return

	# Face the target
	var dir := _combat_target.global_position - _pirate.position
	if dir.length() > 0.1:
		_pirate._facing = dir.normalized()

	# Deal damage when cooldown expires
	if _pirate._attack_cooldown <= 0.0:
		_pirate._combat_target = _combat_target
		_pirate._deal_damage_to_target()
		var cooldown: float = _pirate.get_stat("attack_speed")
		if cooldown <= 0.0:
			cooldown = 1.5
		_pirate._attack_cooldown = cooldown
	_pirate._attack_cooldown -= game_delta


# -- FLEE --


func _enter_flee() -> void:
	_state = PirateState.FLEE
	_flee_timer = 5.0
	_combat_target = null
	_is_moving = true
	_pirate._cancel_combat()
	# Move away from threat centroid
	var threat := _get_threat_centroid()
	if threat != Vector2.ZERO:
		var away := (_pirate.position - threat).normalized()
		var flee_dist: float = 10.0 * TILE_SIZE
		_move_target = _pirate.position + away * flee_dist
	else:
		_move_target = spawn_origin


func _tick_flee(game_delta: float) -> void:
	_flee_timer -= game_delta
	if _flee_timer <= 0.0:
		_enter_patrol()
		return
	var speed: float = float(_get_stats().get("speed", 3.0)) * TILE_SIZE * 1.5
	_tick_movement(game_delta, speed)
	if not _is_moving:
		_enter_patrol()


func _enter_patrol() -> void:
	_state = PirateState.PATROL
	_combat_target = null
	_is_moving = false
	_scan_timer = 0.0
	_patrol_idle_timer = _rng.randf_range(2.0, 5.0)


# -- Scanning helpers --


func _scan_for_target() -> Node2D:
	if _scene_root == null:
		return null
	var targets: Array = _cfg.get("targets", [])
	var los: float = float(_get_stats().get("los", 6)) * TILE_SIZE
	var best: Node2D = null
	var best_dist := INF
	for child in _scene_root.get_children():
		if child == _pirate:
			continue
		if not (child is Node2D):
			continue
		if "owner_id" not in child or child.owner_id < 0:
			continue
		if "hp" in child and child.hp <= 0:
			continue
		if "unit_type" not in child:
			continue
		if child.unit_type not in targets:
			continue
		var dist: float = _pirate.position.distance_to(child.global_position)
		if dist > los:
			continue
		if dist < best_dist:
			best_dist = dist
			best = child
	return best


func _should_flee() -> bool:
	if _scene_root == null:
		return false
	var avoids: Array = _cfg.get("avoids", [])
	var los: float = float(_get_stats().get("los", 6)) * TILE_SIZE
	for child in _scene_root.get_children():
		if child == _pirate:
			continue
		if not (child is Node2D):
			continue
		if "owner_id" not in child or child.owner_id < 0:
			continue
		if "hp" in child and child.hp <= 0:
			continue
		var dist: float = _pirate.position.distance_to(child.global_position)
		if dist > los:
			continue
		# Check unit_type against avoids list (excluding dock_with_garrison)
		if "unit_type" in child and child.unit_type in avoids:
			return true
		# Check for dock_with_garrison — simplified: all docks avoided
		if "dock_with_garrison" in avoids:
			if "building_name" in child and child.building_name == "dock":
				return true
	return false


func _get_threat_centroid() -> Vector2:
	if _scene_root == null:
		return Vector2.ZERO
	var avoids: Array = _cfg.get("avoids", [])
	var los: float = float(_get_stats().get("los", 6)) * TILE_SIZE
	var sum := Vector2.ZERO
	var count := 0
	for child in _scene_root.get_children():
		if child == _pirate:
			continue
		if not (child is Node2D):
			continue
		if "owner_id" not in child or child.owner_id < 0:
			continue
		if "hp" in child and child.hp <= 0:
			continue
		var dist: float = _pirate.position.distance_to(child.global_position)
		if dist > los:
			continue
		var is_threat := false
		if "unit_type" in child and child.unit_type in avoids:
			is_threat = true
		if "building_name" in child and child.building_name == "dock":
			if "dock_with_garrison" in avoids:
				is_threat = true
		if is_threat:
			sum += child.global_position
			count += 1
	if count == 0:
		return Vector2.ZERO
	return sum / float(count)


func _get_stats() -> Dictionary:
	return _cfg.get("stats", {})


# -- Movement --


func _tick_movement(game_delta: float, speed: float) -> void:
	if not _is_moving:
		return
	var dist := _pirate.position.distance_to(_move_target)
	if dist < 2.0:
		_pirate.position = _move_target
		_is_moving = false
	else:
		var direction := (_move_target - _pirate.position).normalized()
		_pirate._facing = direction
		_pirate.position = _pirate.position.move_toward(_move_target, speed * game_delta)
	_pirate.queue_redraw()


# -- Save / Load --


func save_state() -> Dictionary:
	return {
		"state": _state,
		"spawn_origin_x": spawn_origin.x,
		"spawn_origin_y": spawn_origin.y,
		"patrol_idle_timer": _patrol_idle_timer,
		"flee_timer": _flee_timer,
		"scan_timer": _scan_timer,
		"is_moving": _is_moving,
		"move_target_x": _move_target.x,
		"move_target_y": _move_target.y,
	}


func load_state(data: Dictionary) -> void:
	_state = int(data.get("state", PirateState.PATROL)) as PirateState
	spawn_origin = Vector2(
		float(data.get("spawn_origin_x", 0.0)),
		float(data.get("spawn_origin_y", 0.0)),
	)
	_patrol_idle_timer = float(data.get("patrol_idle_timer", 0.0))
	_flee_timer = float(data.get("flee_timer", 0.0))
	_scan_timer = float(data.get("scan_timer", 0.0))
	_is_moving = bool(data.get("is_moving", false))
	_move_target = Vector2(
		float(data.get("move_target_x", 0.0)),
		float(data.get("move_target_y", 0.0)),
	)
