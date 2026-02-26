extends Node
## Dog AI — state machine for domesticated dogs.
## Behaviors: town patrol, hunt assist, danger alert (passive), flee, follow.
## Attached as child of a prototype_unit with entity_category == "dog".

signal danger_alert(alert_position: Vector2, player_id: int)
signal hunt_presence_changed(dog: Node2D, active: bool)

enum DogState { IDLE, TOWN_PATROL, HUNT_ASSIST, FLEE, FOLLOW }

const TILE_SIZE: float = 64.0

var _state: DogState = DogState.IDLE
var _cfg: Dictionary = {}
var _dog: Node2D = null
var _scene_root: Node = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Movement
var _move_target: Vector2 = Vector2.ZERO
var _is_moving: bool = false

# Town patrol
var _patrol_idle_timer: float = 0.0

# Hunt assist
var _hunt_target: Node2D = null
var _pending_hunt_target_name: String = ""

# Danger alert
var _alert_cooldown_timer: float = 0.0
var _alert_buff_targets: Array[Node2D] = []
var _alert_buff_timer: float = 0.0
var _alert_buff_active: bool = false

# Flee
var _flee_destination: Vector2 = Vector2.ZERO

# Follow
var _follow_target: Node2D = null
var _pending_follow_target_name: String = ""

# Scan timer
var _scan_timer: float = 0.0

# LOS bonus tracking
var _los_bonus_buildings: Array[Node2D] = []


func _ready() -> void:
	_dog = get_parent()
	if _dog == null:
		return
	_cfg = _load_config()
	# Suppress prototype_unit's built-in combat
	_dog._stance = _dog.Stance.STAND_GROUND
	_dog._combat_state = _dog.CombatState.NONE
	_dog._cancel_combat()
	if _dog.has_signal("unit_died"):
		_dog.unit_died.connect(_on_dog_died)
	call_deferred("_find_scene_root")


func _load_config() -> Dictionary:
	var id: String = "dog"
	if Engine.has_singleton("DataLoader"):
		return DataLoader.get_unit_stats(id)
	if is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_unit_stats"):
			return dl.get_unit_stats(id)
	return {}


func _find_scene_root() -> void:
	if _dog == null:
		return
	_scene_root = _dog.get_parent()
	_try_enter_patrol()


func _process(delta: float) -> void:
	var game_delta: float = _get_game_delta(delta)
	if game_delta == 0.0:
		return
	if _dog == null or not is_instance_valid(_dog):
		return
	# Keep prototype_unit's combat suppressed
	if _dog._combat_state != _dog.CombatState.NONE:
		_dog._cancel_combat()
	if _dog._moving:
		_dog._moving = false
		_dog._path.clear()
		_dog._path_index = 0

	_scan_timer += game_delta

	# Passive danger alert runs every tick in all states
	_tick_danger_alert(game_delta)

	# Tick alert buff decay
	_tick_alert_buff_decay(game_delta)

	match _state:
		DogState.IDLE:
			_tick_idle(game_delta)
		DogState.TOWN_PATROL:
			_tick_town_patrol(game_delta)
		DogState.HUNT_ASSIST:
			_tick_hunt_assist(game_delta)
		DogState.FLEE:
			_tick_flee(game_delta)
		DogState.FOLLOW:
			_tick_follow(game_delta)


func _get_game_delta(delta: float) -> float:
	if Engine.has_singleton("GameManager"):
		return GameManager.get_game_delta(delta)
	var ml := Engine.get_main_loop() if is_instance_valid(Engine.get_main_loop()) else null
	var gm: Node = ml.root.get_node_or_null("GameManager") if ml else null
	if gm and gm.has_method("get_game_delta"):
		return gm.get_game_delta(delta)
	return delta


# -- IDLE --


func _tick_idle(game_delta: float) -> void:
	_patrol_idle_timer -= game_delta
	if _patrol_idle_timer <= 0.0:
		_try_enter_patrol()


func _try_enter_patrol() -> void:
	var tc := _find_nearest_tc()
	if tc == null:
		_state = DogState.IDLE
		_patrol_idle_timer = 2.0
		return
	var patrol_radius: float = float(_cfg.get("town_patrol_radius_tiles", 12)) * TILE_SIZE
	if _dog.position.distance_to(tc.global_position) <= patrol_radius:
		_enter_town_patrol()
	else:
		_state = DogState.IDLE
		_patrol_idle_timer = 2.0


# -- TOWN PATROL --


func _enter_town_patrol() -> void:
	_state = DogState.TOWN_PATROL
	_is_moving = false
	_patrol_idle_timer = (
		_rng
		. randf_range(
			float(_cfg.get("town_patrol_idle_min", 2.0)),
			float(_cfg.get("town_patrol_idle_max", 3.0)),
		)
	)


func _tick_town_patrol(game_delta: float) -> void:
	var interval: float = float(_cfg.get("scan_interval", 0.5))
	if _scan_timer >= interval:
		_scan_timer = 0.0
		# Check for nearby hunting villager
		var hunter := _find_hunting_villager()
		if hunter != null:
			_enter_hunt_assist(hunter)
			return

	_update_town_los_bonus()

	if _is_moving:
		_tick_movement(game_delta, float(_cfg.get("patrol_speed_pixels", 96.0)))
	else:
		_patrol_idle_timer -= game_delta
		if _patrol_idle_timer <= 0.0:
			_pick_patrol_target()
			_patrol_idle_timer = (
				_rng
				. randf_range(
					float(_cfg.get("town_patrol_idle_min", 2.0)),
					float(_cfg.get("town_patrol_idle_max", 3.0)),
				)
			)


func _pick_patrol_target() -> void:
	var tc := _find_nearest_tc()
	if tc == null:
		return
	# Pick random building within wander radius of TC
	var wander_radius: float = float(_cfg.get("town_patrol_wander_radius_tiles", 8)) * TILE_SIZE
	var building := _find_random_building_near(tc.global_position, wander_radius)
	if building != null:
		_move_target = building.global_position
	else:
		# Random point near TC
		_move_target = (
			tc.global_position
			+ Vector2(
				_rng.randf_range(-wander_radius, wander_radius),
				_rng.randf_range(-wander_radius, wander_radius),
			)
		)
	_is_moving = true


func _find_random_building_near(center: Vector2, radius: float) -> Node2D:
	if _scene_root == null:
		return null
	var candidates: Array[Node2D] = []
	for child in _scene_root.get_children():
		if not (child is Node2D):
			continue
		if "entity_category" not in child:
			continue
		if child.entity_category != "own_building":
			continue
		if "owner_id" not in child or child.owner_id != _dog.owner_id:
			continue
		if child.global_position.distance_to(center) > radius:
			continue
		candidates.append(child)
	if candidates.is_empty():
		return null
	return candidates[_rng.randi() % candidates.size()]


# -- LOS Bonus --


func _update_town_los_bonus() -> void:
	var los_bonus: int = int(_cfg.get("los_bonus", 2))
	var max_stacks: int = int(_cfg.get("los_bonus_max_stacks", 3))
	var patrol_radius: float = float(_cfg.get("town_patrol_wander_radius_tiles", 8)) * TILE_SIZE
	if _scene_root == null:
		return
	# Clear old bonuses
	_clear_los_bonus()
	# Apply to nearby buildings
	for child in _scene_root.get_children():
		if not (child is Node2D):
			continue
		if not child.has_method("set_dog_los_bonus"):
			continue
		if "owner_id" not in child or child.owner_id != _dog.owner_id:
			continue
		if child.global_position.distance_to(_dog.position) > patrol_radius:
			continue
		var current: int = child.get_los()
		var capped: int = mini(current + los_bonus, max_stacks * los_bonus)
		child.set_dog_los_bonus(capped)
		_los_bonus_buildings.append(child)


func _clear_los_bonus() -> void:
	for building in _los_bonus_buildings:
		if is_instance_valid(building) and building.has_method("set_dog_los_bonus"):
			building.set_dog_los_bonus(0)
	_los_bonus_buildings.clear()


# -- HUNT ASSIST --


func _enter_hunt_assist(hunter: Node2D) -> void:
	_state = DogState.HUNT_ASSIST
	_hunt_target = hunter
	_is_moving = true
	# Apply gather bonus
	hunter._gather_rate_multiplier = 1.0 + float(_cfg.get("hunt_gather_bonus", 0.25))
	hunt_presence_changed.emit(_dog, true)


func _tick_hunt_assist(game_delta: float) -> void:
	# Validate hunt target
	if _hunt_target == null or not is_instance_valid(_hunt_target):
		_remove_hunt_bonus()
		_enter_town_patrol()
		return
	# Check if villager stopped gathering food
	if _hunt_target._gather_state == _hunt_target.GatherState.NONE:
		_remove_hunt_bonus()
		_enter_town_patrol()
		return
	if _hunt_target._gather_type != "food":
		_remove_hunt_bonus()
		_enter_town_patrol()
		return
	# Follow at distance
	var follow_dist: float = float(_cfg.get("hunt_follow_distance_tiles", 3)) * TILE_SIZE
	var dist: float = _dog.position.distance_to(_hunt_target.global_position)
	if dist > follow_dist:
		_move_target = _hunt_target.global_position
		_is_moving = true
		_tick_movement(game_delta, float(_cfg.get("patrol_speed_pixels", 96.0)))
	else:
		_is_moving = false


func _remove_hunt_bonus() -> void:
	if _hunt_target != null and is_instance_valid(_hunt_target):
		_hunt_target._gather_rate_multiplier = 1.0
	hunt_presence_changed.emit(_dog, false)
	_hunt_target = null


func _find_hunting_villager() -> Node2D:
	if _scene_root == null:
		return null
	var hunt_radius: float = float(_cfg.get("hunt_assist_radius_tiles", 8)) * TILE_SIZE
	for child in _scene_root.get_children():
		if child == _dog:
			continue
		if not (child is Node2D):
			continue
		if "owner_id" not in child or child.owner_id != _dog.owner_id:
			continue
		if "unit_category" not in child or child.unit_category != "civilian":
			continue
		if "_gather_state" not in child:
			continue
		if child._gather_state == child.GatherState.NONE:
			continue
		if "_gather_type" not in child or child._gather_type != "food":
			continue
		var dist: float = _dog.position.distance_to(child.global_position)
		if dist <= hunt_radius:
			return child
	return null


# -- DANGER ALERT (passive) --


func _tick_danger_alert(game_delta: float) -> void:
	if _alert_cooldown_timer > 0.0:
		_alert_cooldown_timer -= game_delta
		return
	var interval: float = float(_cfg.get("scan_interval", 0.5))
	if _scan_timer < interval:
		return
	var alert_radius: float = float(_cfg.get("alert_radius_tiles", 10)) * TILE_SIZE
	var enemy := _find_enemy_military(alert_radius)
	if enemy == null:
		return
	# Trigger alert
	_alert_cooldown_timer = float(_cfg.get("alert_cooldown", 15.0))
	_apply_alert_buff()
	danger_alert.emit(_dog.global_position, _dog.owner_id)
	# Transition to flee
	_remove_hunt_bonus()
	_clear_los_bonus()
	_enter_flee()


func _apply_alert_buff() -> void:
	if _scene_root == null:
		return
	var buff_radius: float = float(_cfg.get("alert_buff_radius_tiles", 8)) * TILE_SIZE
	var buff_amount: float = float(_cfg.get("alert_speed_buff", 0.10))
	_alert_buff_targets.clear()
	for child in _scene_root.get_children():
		if child == _dog:
			continue
		if not (child is Node2D):
			continue
		if "owner_id" not in child or child.owner_id != _dog.owner_id:
			continue
		if "hp" in child and child.hp <= 0:
			continue
		if not child.has_method("get_stat"):
			continue
		var dist: float = _dog.position.distance_to(child.global_position)
		if dist > buff_radius:
			continue
		# Apply speed modifier via UnitStats
		if "stats" in child and child.stats != null and child.stats.has_method("add_modifier"):
			child.stats.add_modifier("speed", "dog_alert", buff_amount, "percent")
			_alert_buff_targets.append(child)
	_alert_buff_active = true
	_alert_buff_timer = float(_cfg.get("alert_buff_duration", 5.0))


func _tick_alert_buff_decay(game_delta: float) -> void:
	if not _alert_buff_active:
		return
	_alert_buff_timer -= game_delta
	if _alert_buff_timer <= 0.0:
		_remove_alert_buff()


func _remove_alert_buff() -> void:
	for unit in _alert_buff_targets:
		if is_instance_valid(unit) and "stats" in unit and unit.stats != null:
			if unit.stats.has_method("remove_modifier"):
				unit.stats.remove_modifier("speed", "dog_alert")
	_alert_buff_targets.clear()
	_alert_buff_active = false
	_alert_buff_timer = 0.0


func _find_enemy_military(radius: float) -> Node2D:
	if _scene_root == null:
		return null
	for child in _scene_root.get_children():
		if child == _dog:
			continue
		if not (child is Node2D):
			continue
		if "owner_id" not in child:
			continue
		if child.owner_id == _dog.owner_id or child.owner_id < 0:
			continue
		if "unit_category" not in child or child.unit_category != "military":
			continue
		if "hp" in child and child.hp <= 0:
			continue
		var dist: float = _dog.position.distance_to(child.global_position)
		if dist <= radius:
			return child
	return null


# -- FLEE --


func _enter_flee() -> void:
	_state = DogState.FLEE
	_is_moving = true
	# Move toward nearest friendly TC or military unit
	var tc := _find_nearest_tc()
	var military := _find_nearest_friendly_military()
	if tc != null:
		_flee_destination = tc.global_position
	elif military != null:
		_flee_destination = military.global_position
	else:
		# Flee away from enemies
		_flee_destination = _dog.position + Vector2(_rng.randf_range(-200, 200), _rng.randf_range(-200, 200))
	_move_target = _flee_destination


func _tick_flee(game_delta: float) -> void:
	_tick_movement(game_delta, float(_cfg.get("flee_speed_pixels", 192.0)))
	if not _is_moving:
		# Check if safe
		var alert_radius: float = float(_cfg.get("alert_radius_tiles", 10)) * TILE_SIZE
		var enemy := _find_enemy_military(alert_radius)
		if enemy == null:
			_try_enter_patrol()
		else:
			# Keep fleeing
			_enter_flee()


func _find_nearest_tc() -> Node2D:
	if _scene_root == null:
		return null
	var best: Node2D = null
	var best_dist := INF
	for child in _scene_root.get_children():
		if not (child is Node2D):
			continue
		if "owner_id" not in child or child.owner_id != _dog.owner_id:
			continue
		if "building_name" not in child:
			continue
		if child.building_name != "town_center":
			continue
		if "hp" in child and child.hp <= 0:
			continue
		var dist: float = _dog.position.distance_to(child.global_position)
		if dist < best_dist:
			best_dist = dist
			best = child
	return best


func _find_nearest_friendly_military() -> Node2D:
	if _scene_root == null:
		return null
	var best: Node2D = null
	var best_dist := INF
	for child in _scene_root.get_children():
		if child == _dog:
			continue
		if not (child is Node2D):
			continue
		if "owner_id" not in child or child.owner_id != _dog.owner_id:
			continue
		if "unit_category" not in child or child.unit_category != "military":
			continue
		if "hp" in child and child.hp <= 0:
			continue
		var dist: float = _dog.position.distance_to(child.global_position)
		if dist < best_dist:
			best_dist = dist
			best = child
	return best


# -- FOLLOW --


func command_follow(target: Node2D) -> void:
	_remove_hunt_bonus()
	_clear_los_bonus()
	_state = DogState.FOLLOW
	_follow_target = target
	_is_moving = true
	_move_target = target.global_position


func _tick_follow(game_delta: float) -> void:
	if _follow_target == null or not is_instance_valid(_follow_target):
		_follow_target = null
		_try_enter_patrol()
		return
	if "hp" in _follow_target and _follow_target.hp <= 0:
		_follow_target = null
		_try_enter_patrol()
		return
	var follow_dist: float = float(_cfg.get("follow_distance_tiles", 3)) * TILE_SIZE
	var dist: float = _dog.position.distance_to(_follow_target.global_position)
	if dist > follow_dist:
		_move_target = _follow_target.global_position
		_is_moving = true
		_tick_movement(game_delta, float(_cfg.get("patrol_speed_pixels", 96.0)))
	else:
		_is_moving = false


# -- Movement --


func _tick_movement(game_delta: float, speed: float) -> void:
	if not _is_moving:
		return
	var dist := _dog.position.distance_to(_move_target)
	if dist < 2.0:
		_dog.position = _move_target
		_is_moving = false
	else:
		var direction := (_move_target - _dog.position).normalized()
		_dog._facing = direction
		_dog.position = _dog.position.move_toward(_move_target, speed * game_delta)
	_dog.queue_redraw()


# -- Death handler --


func _on_dog_died(_unit: Node2D) -> void:
	_remove_hunt_bonus()
	_remove_alert_buff()
	_clear_los_bonus()


# -- Save / Load --


func _get_target_name(target: Node2D) -> String:
	if target != null and is_instance_valid(target):
		return str(target.name)
	return ""


func save_state() -> Dictionary:
	return {
		"state": _state,
		"move_target_x": _move_target.x,
		"move_target_y": _move_target.y,
		"is_moving": _is_moving,
		"patrol_idle_timer": _patrol_idle_timer,
		"alert_cooldown_timer": _alert_cooldown_timer,
		"alert_buff_timer": _alert_buff_timer,
		"alert_buff_active": _alert_buff_active,
		"flee_destination_x": _flee_destination.x,
		"flee_destination_y": _flee_destination.y,
		"scan_timer": _scan_timer,
		"follow_target_name": _get_target_name(_follow_target),
		"hunt_target_name": _get_target_name(_hunt_target),
	}


func load_state(data: Dictionary) -> void:
	_state = int(data.get("state", DogState.IDLE)) as DogState
	_move_target = Vector2(
		float(data.get("move_target_x", 0.0)),
		float(data.get("move_target_y", 0.0)),
	)
	_is_moving = bool(data.get("is_moving", false))
	_patrol_idle_timer = float(data.get("patrol_idle_timer", 0.0))
	_alert_cooldown_timer = float(data.get("alert_cooldown_timer", 0.0))
	_alert_buff_timer = float(data.get("alert_buff_timer", 0.0))
	_alert_buff_active = bool(data.get("alert_buff_active", false))
	_flee_destination = Vector2(
		float(data.get("flee_destination_x", 0.0)),
		float(data.get("flee_destination_y", 0.0)),
	)
	_scan_timer = float(data.get("scan_timer", 0.0))
	_pending_follow_target_name = str(data.get("follow_target_name", ""))
	_pending_hunt_target_name = str(data.get("hunt_target_name", ""))


func resolve_targets(scene_root: Node) -> void:
	if _pending_follow_target_name != "":
		var target := scene_root.get_node_or_null(_pending_follow_target_name)
		if target is Node2D:
			_follow_target = target
		_pending_follow_target_name = ""
	if _pending_hunt_target_name != "":
		var target := scene_root.get_node_or_null(_pending_hunt_target_name)
		if target is Node2D:
			_hunt_target = target
		_pending_hunt_target_name = ""
