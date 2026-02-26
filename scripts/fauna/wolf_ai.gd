extends Node
## Wolf AI — state machine driving patrol, aggro, flee behavior for wolf fauna.
## Attached as child of a prototype_unit with owner_id == -1 (Gaia).

signal domesticated(feeder_owner_id: int)

enum WolfState { PATROL, ATTACK, FLEE, BEING_FED, DOMESTICATED }

const TILE_SIZE: float = 64.0

var pack_id: int = 0
var spawn_origin: Vector2 = Vector2.ZERO

var _state: WolfState = WolfState.PATROL
var _cfg: Dictionary = {}
var _wolf: Node2D = null
var _combat_target: Node2D = null
var _patrol_idle_timer: float = 0.0
var _flee_timer: float = 0.0
var _scan_timer: float = 0.0
var _pack_members: Array[Node] = []
var _scene_root: Node = null
var _move_target: Vector2 = Vector2.ZERO
var _is_moving: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Domestication state
var _domestication_progress: float = 0.0
var _domestication_owner_id: int = -1
var _decay_timer: float = 0.0
var _feed_lockout_timer: float = 0.0
var _current_feeder: Node2D = null
var _pending_feeder: Node2D = null
var _prev_hp: int = -1


func _ready() -> void:
	_wolf = get_parent()
	if _wolf == null:
		return
	_cfg = _load_config()
	spawn_origin = _wolf.position
	# Suppress prototype_unit's built-in combat
	_wolf._stance = _wolf.Stance.STAND_GROUND
	_wolf._combat_state = _wolf.CombatState.NONE
	_wolf._cancel_combat()
	# Connect death signal
	if _wolf.has_signal("unit_died"):
		_wolf.unit_died.connect(_on_wolf_died)
	# Find pack members after all siblings are ready
	call_deferred("_find_pack_members")
	# Start with a random idle delay before first patrol move
	_patrol_idle_timer = (
		_rng
		. randf_range(
			float(_cfg.get("patrol_idle_min", 3.0)),
			float(_cfg.get("patrol_idle_max", 5.0)),
		)
	)


func _load_config() -> Dictionary:
	var fauna_cfg: Dictionary = _dl_settings("fauna")
	if fauna_cfg.has("wolf"):
		return fauna_cfg["wolf"]
	return {}


func _dl_settings(id: String) -> Dictionary:
	if Engine.has_singleton("DataLoader"):
		return DataLoader.get_settings(id)
	if is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_settings"):
			return dl.get_settings(id)
	return {}


func _find_pack_members() -> void:
	_pack_members.clear()
	if _wolf == null:
		return
	var root := _wolf.get_parent()
	if root == null:
		return
	_scene_root = root
	for child in root.get_children():
		if child == _wolf:
			continue
		if not (child is Node2D):
			continue
		var ai := child.get_node_or_null("WolfAI")
		if ai == null:
			continue
		if ai.pack_id == pack_id:
			_pack_members.append(ai)


func _process(delta: float) -> void:
	var game_delta: float = _get_game_delta(delta)
	if game_delta == 0.0:
		return
	if _wolf == null or not is_instance_valid(_wolf):
		return
	# Keep prototype_unit's combat suppressed
	if _wolf._combat_state != _wolf.CombatState.NONE:
		_wolf._cancel_combat()
	if _wolf._moving:
		_wolf._moving = false
		_wolf._path.clear()
		_wolf._path_index = 0

	_scan_timer += game_delta

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


func _get_game_delta(delta: float) -> float:
	if Engine.has_singleton("GameManager"):
		return GameManager.get_game_delta(delta)
	var ml := Engine.get_main_loop() if is_instance_valid(Engine.get_main_loop()) else null
	var gm: Node = ml.root.get_node_or_null("GameManager") if ml else null
	if gm and gm.has_method("get_game_delta"):
		return gm.get_game_delta(delta)
	return delta


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
	if centroid != Vector2.ZERO and _wolf.position.distance_to(centroid) > cohesion_max:
		target = target.lerp(centroid, 0.5)
	_move_target = target
	_is_moving = true


func _get_pack_centroid() -> Vector2:
	var sum := _wolf.position
	var count := 1
	for ai in _pack_members:
		if not is_instance_valid(ai):
			continue
		if ai._wolf == null or not is_instance_valid(ai._wolf):
			continue
		sum += ai._wolf.position
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
	if _wolf.position.distance_to(_combat_target.global_position) > abandon:
		_enter_patrol()
		return

	# Move toward target
	_move_target = _combat_target.global_position
	_is_moving = true
	_tick_movement(game_delta, float(_cfg.get("attack_speed_pixels", 192.0)))

	# Deal damage when in melee range
	var dist := _wolf.position.distance_to(_combat_target.global_position)
	if dist <= TILE_SIZE:
		_is_moving = false
		# Face the target
		var dir := _combat_target.global_position - _wolf.position
		if dir.length() > 0.1:
			_wolf._facing = dir.normalized()
		# Use prototype_unit's damage system
		if _wolf._attack_cooldown <= 0.0:
			_wolf._combat_target = _combat_target
			_wolf._deal_damage_to_target()
			var cooldown: float = _wolf.get_stat("attack_speed")
			if cooldown <= 0.0:
				cooldown = 1.5
			_wolf._attack_cooldown = cooldown
		_wolf._attack_cooldown -= game_delta


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
	_wolf._cancel_combat()
	# Cancel feeding if in progress
	if _current_feeder != null:
		cancel_feeding()
	# Pick flee direction: away from nearest military or toward spawn
	var threat := _get_military_centroid()
	if threat != Vector2.ZERO:
		var away := (_wolf.position - threat).normalized()
		var flee_dist: float = float(_cfg.get("flee_distance_tiles", 10)) * TILE_SIZE
		_move_target = _wolf.position + away * flee_dist
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
	if _wolf != null and "hp" in _wolf:
		_prev_hp = _wolf.hp
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
	if _wolf != null and "hp" in _wolf and _prev_hp >= 0:
		if _wolf.hp < _prev_hp:
			cancel_feeding()
			_enter_flee()
			return
		_prev_hp = _wolf.hp
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
	if _scene_root == null:
		return null
	var aggro_radius: float = float(_cfg.get("aggro_radius_tiles", 3)) * TILE_SIZE
	var categories: Array = _cfg.get("aggro_unit_categories", ["civilian"])
	var best: Node2D = null
	var best_dist := INF
	for child in _scene_root.get_children():
		if child == _wolf:
			continue
		if not (child is Node2D):
			continue
		if "owner_id" not in child or child.owner_id < 0:
			continue
		if "hp" in child and child.hp <= 0:
			continue
		if "unit_category" not in child:
			continue
		if child.unit_category not in categories:
			continue
		# Suppress aggro against feeding/approaching villager
		if is_feed_target_of(child):
			continue
		var dist: float = _wolf.position.distance_to(child.global_position)
		if dist > aggro_radius:
			continue
		if dist < best_dist:
			best_dist = dist
			best = child
	return best


func _count_military_in_radius(radius_tiles: float) -> int:
	if _scene_root == null:
		return 0
	var radius: float = radius_tiles * TILE_SIZE
	var count := 0
	for child in _scene_root.get_children():
		if child == _wolf:
			continue
		if not (child is Node2D):
			continue
		if "owner_id" not in child or child.owner_id < 0:
			continue
		if "hp" in child and child.hp <= 0:
			continue
		if "unit_category" not in child or child.unit_category != "military":
			continue
		var dist: float = _wolf.position.distance_to(child.global_position)
		if dist <= radius:
			count += 1
	return count


func _should_flee_military() -> bool:
	var radius: float = float(_cfg.get("flee_military_radius_tiles", 5))
	var threshold: int = int(_cfg.get("flee_military_count_threshold", 3))
	return _count_military_in_radius(radius) >= threshold


func _should_flee_military_during_attack() -> bool:
	var radius: float = float(_cfg.get("flee_military_radius_during_attack_tiles", 4))
	var threshold: int = int(_cfg.get("flee_military_during_attack_count", 2))
	return _count_military_in_radius(radius) >= threshold


func _get_military_centroid() -> Vector2:
	if _scene_root == null:
		return Vector2.ZERO
	var radius: float = float(_cfg.get("flee_military_radius_tiles", 5)) * TILE_SIZE
	var sum := Vector2.ZERO
	var count := 0
	for child in _scene_root.get_children():
		if child == _wolf:
			continue
		if not (child is Node2D):
			continue
		if "owner_id" not in child or child.owner_id < 0:
			continue
		if "unit_category" not in child or child.unit_category != "military":
			continue
		if "hp" in child and child.hp <= 0:
			continue
		var dist: float = _wolf.position.distance_to(child.global_position)
		if dist <= radius:
			sum += child.global_position
			count += 1
	if count == 0:
		return Vector2.ZERO
	return sum / float(count)


# -- Movement --


func _tick_movement(game_delta: float, speed: float) -> void:
	if not _is_moving:
		return
	var dist := _wolf.position.distance_to(_move_target)
	if dist < 2.0:
		_wolf.position = _move_target
		_is_moving = false
	else:
		var direction := (_move_target - _wolf.position).normalized()
		_wolf._facing = direction
		_wolf.position = _wolf.position.move_toward(_move_target, speed * game_delta)
	_wolf.queue_redraw()


# -- Pack death handler --


func _on_wolf_died(_unit: Node2D) -> void:
	# Notify packmates to flee
	for ai in _pack_members:
		if not is_instance_valid(ai):
			continue
		if ai._state != WolfState.FLEE and ai._state != WolfState.DOMESTICATED:
			ai._enter_flee()


# -- Save / Load --


func save_state() -> Dictionary:
	return {
		"state": _state,
		"pack_id": pack_id,
		"spawn_origin_x": spawn_origin.x,
		"spawn_origin_y": spawn_origin.y,
		"patrol_idle_timer": _patrol_idle_timer,
		"flee_timer": _flee_timer,
		"scan_timer": _scan_timer,
		"is_moving": _is_moving,
		"move_target_x": _move_target.x,
		"move_target_y": _move_target.y,
		"domestication_progress": _domestication_progress,
		"domestication_owner_id": _domestication_owner_id,
		"decay_timer": _decay_timer,
		"feed_lockout_timer": _feed_lockout_timer,
	}


func load_state(data: Dictionary) -> void:
	_state = int(data.get("state", WolfState.PATROL)) as WolfState
	pack_id = int(data.get("pack_id", 0))
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
	_domestication_progress = float(data.get("domestication_progress", 0.0))
	_domestication_owner_id = int(data.get("domestication_owner_id", -1))
	_decay_timer = float(data.get("decay_timer", 0.0))
	_feed_lockout_timer = float(data.get("feed_lockout_timer", 0.0))
