extends BaseFaunaAI
## Pirate AI — state machine driving patrol, hunt, attack, flee behavior for pirate ships.
## Attached as child of a prototype_unit with owner_id == -1 (Gaia).

enum PirateState { PATROL, HUNT, ATTACK, FLEE }

var _state: PirateState = PirateState.PATROL


func _load_config() -> Dictionary:
	return GameUtils.dl_settings("pirates")


func _deferred_init() -> void:
	super()
	if _unit == null:
		return
	spawn_origin = _unit.position
	# Start with a random idle delay before first patrol move
	_patrol_idle_timer = _rng.randf_range(1.0, 3.0)


func _tick(game_delta: float) -> void:
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
	_pick_random_offset_target(spawn_origin, patrol_radius)


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
	if _unit.position.distance_to(_combat_target.global_position) > max_chase:
		_enter_patrol()
		return

	# Move toward target
	_move_target = _combat_target.global_position
	var speed: float = float(_get_stats().get("speed", 3.0)) * TILE_SIZE
	_tick_movement(game_delta, speed)

	# Check if in attack range
	var attack_range: float = float(_get_stats().get("range", 4)) * TILE_SIZE
	var dist := _unit.position.distance_to(_combat_target.global_position)
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
	var dist := _unit.position.distance_to(_combat_target.global_position)
	if dist > attack_range * 1.5:
		_enter_hunt(_combat_target)
		return

	# Chase abandon
	var max_chase: float = float(_get_stats().get("los", 6)) * 2.0 * TILE_SIZE
	if _unit.position.distance_to(_combat_target.global_position) > max_chase:
		_enter_patrol()
		return

	_deal_damage(game_delta)


# -- FLEE --


func _enter_flee() -> void:
	_state = PirateState.FLEE
	_flee_timer = 5.0
	_combat_target = null
	_is_moving = true
	_unit._cancel_combat()
	# Move away from threat centroid
	var threat := _get_threat_centroid()
	if threat != Vector2.ZERO:
		var away := (_unit.position - threat).normalized()
		var flee_dist: float = 10.0 * TILE_SIZE
		_move_target = _unit.position + away * flee_dist
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
	var targets: Array = _cfg.get("targets", [])
	var los: float = float(_get_stats().get("los", 6)) * TILE_SIZE
	return _scan_nearest(
		los,
		func(child: Node2D) -> bool:
			if not BaseFaunaAI._is_living_player_entity(child):
				return false
			if "unit_type" not in child:
				return false
			if child.unit_type not in targets:
				return false
			return true,
	)


func _should_flee() -> bool:
	if _scene_root == null:
		return false
	var avoids: Array = _cfg.get("avoids", [])
	var los: float = float(_get_stats().get("los", 6)) * TILE_SIZE
	for child in _scene_root.get_children():
		if child == _unit:
			continue
		if not (child is Node2D):
			continue
		if "owner_id" not in child or child.owner_id < 0:
			continue
		if "hp" in child and child.hp <= 0:
			continue
		var dist: float = _unit.position.distance_to(child.global_position)
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
		if child == _unit:
			continue
		if not (child is Node2D):
			continue
		if "owner_id" not in child or child.owner_id < 0:
			continue
		if "hp" in child and child.hp <= 0:
			continue
		var dist: float = _unit.position.distance_to(child.global_position)
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


# -- Save / Load --


func save_state() -> Dictionary:
	var data := super()
	data["state"] = _state
	return data


func load_state(data: Dictionary) -> void:
	super(data)
	_state = int(data.get("state", PirateState.PATROL)) as PirateState
