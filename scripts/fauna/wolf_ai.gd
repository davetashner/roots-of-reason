extends BaseFaunaAI
## Wolf AI — state machine driving patrol, aggro, flee behavior for wolf fauna.
## Attached as child of a prototype_unit with owner_id == -1 (Gaia).

signal domesticated(feeder_owner_id: int)

enum WolfState { PATROL, ATTACK, FLEE, BEING_FED, DOMESTICATED }

var pack_id: int = 0

var _state: WolfState = WolfState.PATROL
var _pack_members: Array[Node] = []

# Domestication state
var _domestication_progress: float = 0.0
var _domestication_owner_id: int = -1
var _decay_timer: float = 0.0
var _feed_lockout_timer: float = 0.0
var _current_feeder: Node2D = null
var _pending_feeder: Node2D = null
var _prev_hp: int = -1


func _load_config() -> Dictionary:
	var fauna_cfg: Dictionary = GameUtils.dl_settings("fauna")
	if fauna_cfg.has("wolf"):
		return fauna_cfg["wolf"]
	return {}


func _deferred_init() -> void:
	super()
	if _unit == null:
		return
	spawn_origin = _unit.position
	_find_pack_members()
	# Start with a random idle delay before first patrol move
	_patrol_idle_timer = (
		_rng
		. randf_range(
			float(_cfg.get("patrol_idle_min", 3.0)),
			float(_cfg.get("patrol_idle_max", 5.0)),
		)
	)


func _find_pack_members() -> void:
	_pack_members.clear()
	if _unit == null or _scene_root == null:
		return
	for child in _scene_root.get_children():
		if child == _unit:
			continue
		if not (child is Node2D):
			continue
		var ai := child.get_node_or_null("WolfAI")
		if ai == null:
			continue
		if ai.pack_id == pack_id:
			_pack_members.append(ai)


func _tick(game_delta: float) -> void:
	# Decrement feed lockout timer
	if _feed_lockout_timer > 0.0:
		_feed_lockout_timer -= game_delta

	# Tick domestication decay
	_tick_domestication_decay(game_delta)

	match _state:
		WolfState.PATROL:
			_tick_patrol(game_delta)
		WolfState.ATTACK:
			_tick_attack(game_delta)
		WolfState.FLEE:
			_tick_flee(game_delta)
		WolfState.BEING_FED:
			_tick_being_fed(game_delta)
		WolfState.DOMESTICATED:
			pass  # Terminal state (future story 2hj.7)


# -- PATROL --


func _tick_patrol(game_delta: float) -> void:
	var interval: float = float(_cfg.get("scan_interval", 0.5))
	if _scan_timer >= interval:
		_scan_timer = 0.0
		# Check flee condition first
		if _should_flee_military():
			_enter_flee()
			return
		# Check aggro
		var target := _scan_for_aggro_target()
		if target != null:
			_enter_attack(target)
			return

	if _is_moving:
		_tick_movement(game_delta, float(_cfg.get("patrol_speed_pixels", 96.0)))
	else:
		_patrol_idle_timer -= game_delta
		if _patrol_idle_timer <= 0.0:
			_pick_patrol_target()
			_patrol_idle_timer = (
				_rng
				. randf_range(
					float(_cfg.get("patrol_idle_min", 3.0)),
					float(_cfg.get("patrol_idle_max", 5.0)),
				)
			)


func _pick_patrol_target() -> void:
	var radius: float = float(_cfg.get("patrol_radius_tiles", 8)) * TILE_SIZE
	var target := (
		spawn_origin
		+ Vector2(
			_rng.randf_range(-radius, radius),
			_rng.randf_range(-radius, radius),
		)
	)
	# Pack cohesion: bias toward pack centroid if too far
	var cohesion_max: float = float(_cfg.get("pack_cohesion_max_tiles", 4)) * TILE_SIZE
	var centroid := _get_pack_centroid()
	if centroid != Vector2.ZERO and _unit.position.distance_to(centroid) > cohesion_max:
		target = target.lerp(centroid, 0.5)
	_move_target = target
	_is_moving = true


func _get_pack_centroid() -> Vector2:
	var sum := _unit.position
	var count := 1
	for ai in _pack_members:
		if not is_instance_valid(ai):
			continue
		if ai._unit == null or not is_instance_valid(ai._unit):
			continue
		sum += ai._unit.position
		count += 1
	if count <= 1:
		return Vector2.ZERO
	return sum / float(count)


# -- ATTACK --


func _enter_attack(target: Node2D) -> void:
	_state = WolfState.ATTACK
	_combat_target = target
	_is_moving = true
	_move_target = target.global_position
	_alert_pack(target)


func _tick_attack(game_delta: float) -> void:
	# Validate target
	if _combat_target == null or not is_instance_valid(_combat_target):
		_enter_patrol()
		return
	if "hp" in _combat_target and _combat_target.hp <= 0:
		_enter_patrol()
		return

	# Check flee from military during attack
	var interval: float = float(_cfg.get("scan_interval", 0.5))
	if _scan_timer >= interval:
		_scan_timer = 0.0
		if _should_flee_military_during_attack():
			_enter_flee()
			return

	# Check chase abandon distance
	var abandon: float = float(_cfg.get("chase_abandon_distance_tiles", 6)) * TILE_SIZE
	if _unit.position.distance_to(_combat_target.global_position) > abandon:
		_enter_patrol()
		return

	# Move toward target
	_move_target = _combat_target.global_position
	_is_moving = true
	_tick_movement(game_delta, float(_cfg.get("attack_speed_pixels", 192.0)))

	# Deal damage when in melee range
	var dist := _unit.position.distance_to(_combat_target.global_position)
	if dist <= TILE_SIZE:
		_is_moving = false
		_deal_damage(game_delta)


func _alert_pack(target: Node2D) -> void:
	for ai in _pack_members:
		if not is_instance_valid(ai):
			continue
		if ai._state == WolfState.PATROL:
			ai._enter_attack(target)


# -- FLEE --


func _enter_flee() -> void:
	_state = WolfState.FLEE
	_flee_timer = float(_cfg.get("flee_duration", 5.0))
	_combat_target = null
	_is_moving = true
	# Cancel any proto-unit combat state
	_unit._cancel_combat()
	# Cancel feeding if in progress
	if _current_feeder != null:
		cancel_feeding()
	# Pick flee direction: away from nearest military or toward spawn
	var threat := _get_military_centroid()
	if threat != Vector2.ZERO:
		var away := (_unit.position - threat).normalized()
		var flee_dist: float = float(_cfg.get("flee_distance_tiles", 10)) * TILE_SIZE
		_move_target = _unit.position + away * flee_dist
	else:
		_move_target = spawn_origin


func _tick_flee(game_delta: float) -> void:
	_flee_timer -= game_delta
	if _flee_timer <= 0.0:
		_enter_patrol()
		return
	_tick_movement(game_delta, float(_cfg.get("attack_speed_pixels", 192.0)))
	if not _is_moving:
		_enter_patrol()


func _enter_patrol() -> void:
	_state = WolfState.PATROL
	_combat_target = null
	_is_moving = false
	_scan_timer = 0.0
	_patrol_idle_timer = (
		_rng
		. randf_range(
			float(_cfg.get("patrol_idle_min", 3.0)),
			float(_cfg.get("patrol_idle_max", 5.0)),
		)
	)


# -- BEING_FED --


func begin_feeding(feeder: Node2D, feeder_owner_id: int) -> bool:
	if _state == WolfState.DOMESTICATED:
		return false
	if _feed_lockout_timer > 0.0:
		return false
	# Contested domestication: different player resets progress
	if _domestication_owner_id >= 0 and feeder_owner_id != _domestication_owner_id:
		_domestication_progress = 0.0
	_domestication_owner_id = feeder_owner_id
	_current_feeder = feeder
	_pending_feeder = null
	_state = WolfState.BEING_FED
	_is_moving = false
	_combat_target = null
	# Track HP for damage detection
	if _unit != null and "hp" in _unit:
		_prev_hp = _unit.hp
	return true


func complete_feeding() -> void:
	var feeds_required: int = int(_cfg.get("feeds_required", 3))
	_domestication_progress += 1.0 / float(feeds_required)
	_current_feeder = null
	_feed_lockout_timer = float(_cfg.get("feed_cooldown_per_wolf", 5.0))
	if _domestication_progress >= 1.0:
		_domestication_progress = 1.0
		_state = WolfState.DOMESTICATED
		domesticated.emit(_domestication_owner_id)
	else:
		_enter_patrol()


func cancel_feeding() -> void:
	_current_feeder = null
	_pending_feeder = null
	_feed_lockout_timer = float(_cfg.get("feed_cooldown_per_wolf", 5.0))
	if _state == WolfState.BEING_FED:
		_enter_patrol()


func register_pending_feeder(feeder: Node2D) -> void:
	_pending_feeder = feeder


func unregister_pending_feeder(feeder: Node2D) -> void:
	if _pending_feeder == feeder:
		_pending_feeder = null


func get_domestication_progress() -> float:
	return _domestication_progress


func get_domestication_owner() -> int:
	return _domestication_owner_id


func is_being_fed_by(unit: Node2D) -> bool:
	return _current_feeder == unit


func is_feed_target_of(unit: Node2D) -> bool:
	return _current_feeder == unit or _pending_feeder == unit


func _tick_being_fed(game_delta: float) -> void:
	# Validate feeder
	if _current_feeder == null or not is_instance_valid(_current_feeder):
		cancel_feeding()
		return
	# Check if wolf took damage — flee
	if _unit != null and "hp" in _unit and _prev_hp >= 0:
		if _unit.hp < _prev_hp:
			cancel_feeding()
			_enter_flee()
			return
		_prev_hp = _unit.hp
	# Stay inert — villager drives the timer
	game_delta = game_delta  # Suppress unused warning


func _tick_domestication_decay(game_delta: float) -> void:
	if _state == WolfState.BEING_FED or _state == WolfState.DOMESTICATED:
		return
	if _domestication_progress <= 0.0:
		return
	var decay_interval: float = float(_cfg.get("decay_interval", 10.0))
	_decay_timer += game_delta
	if _decay_timer >= decay_interval:
		_decay_timer = 0.0
		var decay_rate: float = float(_cfg.get("decay_rate", 0.1))
		_domestication_progress = maxf(0.0, _domestication_progress - decay_rate)


# -- Scanning helpers --


func _scan_for_aggro_target() -> Node2D:
	var aggro_radius: float = float(_cfg.get("aggro_radius_tiles", 3)) * TILE_SIZE
	var categories: Array = _cfg.get("aggro_unit_categories", ["civilian"])
	return _scan_nearest(
		aggro_radius,
		func(child: Node2D) -> bool:
			if not BaseFaunaAI._is_living_player_entity(child):
				return false
			if "unit_category" not in child:
				return false
			if child.unit_category not in categories:
				return false
			# Suppress aggro against feeding/approaching villager
			if is_feed_target_of(child):
				return false
			return true,
	)


func _should_flee_military() -> bool:
	var radius: float = float(_cfg.get("flee_military_radius_tiles", 5)) * TILE_SIZE
	var threshold: int = int(_cfg.get("flee_military_count_threshold", 3))
	return _count_in_radius(radius, BaseFaunaAI._is_living_military) >= threshold


func _should_flee_military_during_attack() -> bool:
	var radius: float = float(_cfg.get("flee_military_radius_during_attack_tiles", 4)) * TILE_SIZE
	var threshold: int = int(_cfg.get("flee_military_during_attack_count", 2))
	return _count_in_radius(radius, BaseFaunaAI._is_living_military) >= threshold


func _get_military_centroid() -> Vector2:
	var radius: float = float(_cfg.get("flee_military_radius_tiles", 5)) * TILE_SIZE
	return _get_centroid(radius, BaseFaunaAI._is_living_military)


# -- Pack death handler --


func _on_unit_died(_dead_unit: Node2D, _killer: Node2D = null) -> void:
	# Notify packmates to flee
	for ai in _pack_members:
		if not is_instance_valid(ai):
			continue
		if ai._state != WolfState.FLEE and ai._state != WolfState.DOMESTICATED:
			ai._enter_flee()


# -- Save / Load --


func save_state() -> Dictionary:
	var data := super()
	data["state"] = _state
	data["pack_id"] = pack_id
	data["domestication_progress"] = _domestication_progress
	data["domestication_owner_id"] = _domestication_owner_id
	data["decay_timer"] = _decay_timer
	data["feed_lockout_timer"] = _feed_lockout_timer
	return data


func load_state(data: Dictionary) -> void:
	super(data)
	_state = int(data.get("state", WolfState.PATROL)) as WolfState
	pack_id = int(data.get("pack_id", 0))
	_domestication_progress = float(data.get("domestication_progress", 0.0))
	_domestication_owner_id = int(data.get("domestication_owner_id", -1))
	_decay_timer = float(data.get("decay_timer", 0.0))
	_feed_lockout_timer = float(data.get("feed_lockout_timer", 0.0))
