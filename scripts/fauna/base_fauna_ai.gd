class_name BaseFaunaAI
extends Node
## Base class for fauna AI state machines (wolf, pirate, dog, etc.).
##
## Provides shared movement, combat suppression, scene-root discovery,
## config loading, scan timer, patrol idle timer, and save/load of common
## fields.  Subclasses override [method _load_config],
## [method _on_unit_died], and the per-state tick methods.

const TILE_SIZE: float = 64.0

## Spawn / home position used by patrol logic.
var spawn_origin: Vector2 = Vector2.ZERO

## The parent prototype_unit this AI drives.
var _unit: Node2D = null
var _cfg: Dictionary = {}
var _scene_root: Node = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Movement
var _move_target: Vector2 = Vector2.ZERO
var _is_moving: bool = false

# Shared timers
var _scan_timer: float = 0.0
var _patrol_idle_timer: float = 0.0
var _flee_timer: float = 0.0

# Combat target (used by wolf & pirate; harmless if unused in dog)
var _combat_target: Node2D = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------


func _ready() -> void:
	_unit = get_parent()
	if _unit == null:
		return
	_cfg = _load_config()
	_suppress_combat()
	if _unit.has_signal("unit_died"):
		_unit.unit_died.connect(_on_unit_died)
	call_deferred("_deferred_init")


## Override to load subclass-specific config from DataLoader / GameUtils.
func _load_config() -> Dictionary:
	return {}


## Called after the first frame via [code]call_deferred[/code].
## Subclasses override to find pack members, scene root, etc.
func _deferred_init() -> void:
	if _unit == null:
		return
	var root := _unit.get_parent()
	if root != null:
		_scene_root = root


## Override to clean up subclass resources on death.
func _on_unit_died(_dead_unit: Node2D, _killer: Node2D = null) -> void:
	pass


# ---------------------------------------------------------------------------
# Process — combat suppression + game delta
# ---------------------------------------------------------------------------


func _process(delta: float) -> void:
	var game_delta: float = GameUtils.get_game_delta(delta)
	if game_delta == 0.0:
		return
	if _unit == null or not is_instance_valid(_unit):
		return
	_suppress_combat()
	_scan_timer += game_delta
	_tick(game_delta)


## Subclasses implement state-machine dispatch here.
func _tick(_game_delta: float) -> void:
	pass


func _suppress_combat() -> void:
	if _unit._combat_state != _unit.CombatState.NONE:
		_unit._cancel_combat()
	if _unit._moving:
		_unit._moving = false
		_unit._path.clear()
		_unit._path_index = 0


# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------


func _tick_movement(game_delta: float, speed: float) -> void:
	if not _is_moving:
		return
	var dist := _unit.position.distance_to(_move_target)
	if dist < 2.0:
		_unit.position = _move_target
		_is_moving = false
	else:
		var direction := (_move_target - _unit.position).normalized()
		_unit._facing = direction
		_unit.position = _unit.position.move_toward(_move_target, speed * game_delta)
	_unit.queue_redraw()


# ---------------------------------------------------------------------------
# Patrol helpers
# ---------------------------------------------------------------------------


## Pick a random patrol target within [param radius] of [param center].
func _pick_random_offset_target(center: Vector2, radius: float) -> void:
	_move_target = (
		center
		+ Vector2(
			_rng.randf_range(-radius, radius),
			_rng.randf_range(-radius, radius),
		)
	)
	_is_moving = true


func _reset_patrol_idle(min_sec: float, max_sec: float) -> void:
	_patrol_idle_timer = _rng.randf_range(min_sec, max_sec)


# ---------------------------------------------------------------------------
# Generic target scanning
# ---------------------------------------------------------------------------


## Scan [member _scene_root] children for the nearest [Node2D] that passes
## [param filter].  [param filter] receives [code](child: Node2D) -> bool[/code].
## Returns [code]null[/code] when nothing matches.
func _scan_nearest(radius: float, filter: Callable) -> Node2D:
	if _scene_root == null:
		return null
	var best: Node2D = null
	var best_dist := INF
	for child in _scene_root.get_children():
		if child == _unit:
			continue
		if not (child is Node2D):
			continue
		if not filter.call(child):
			continue
		var dist: float = _unit.position.distance_to(child.global_position)
		if dist > radius:
			continue
		if dist < best_dist:
			best_dist = dist
			best = child
	return best


## Count scene-root children passing [param filter] within [param radius].
func _count_in_radius(radius: float, filter: Callable) -> int:
	if _scene_root == null:
		return 0
	var count := 0
	for child in _scene_root.get_children():
		if child == _unit:
			continue
		if not (child is Node2D):
			continue
		if not filter.call(child):
			continue
		var dist: float = _unit.position.distance_to(child.global_position)
		if dist <= radius:
			count += 1
	return count


## Compute centroid of scene-root children passing [param filter] within
## [param radius].  Returns [constant Vector2.ZERO] when none match.
func _get_centroid(radius: float, filter: Callable) -> Vector2:
	if _scene_root == null:
		return Vector2.ZERO
	var sum := Vector2.ZERO
	var count := 0
	for child in _scene_root.get_children():
		if child == _unit:
			continue
		if not (child is Node2D):
			continue
		if not filter.call(child):
			continue
		var dist: float = _unit.position.distance_to(child.global_position)
		if dist <= radius:
			sum += child.global_position
			count += 1
	if count == 0:
		return Vector2.ZERO
	return sum / float(count)


# ---------------------------------------------------------------------------
# Shared filter helpers
# ---------------------------------------------------------------------------


## Returns true if child is a living player-owned unit (owner_id >= 0, hp > 0).
static func _is_living_player_entity(child: Node2D) -> bool:
	if "owner_id" not in child or child.owner_id < 0:
		return false
	if "hp" in child and child.hp <= 0:
		return false
	return true


## Returns true if the child is a living military unit owned by a player.
static func _is_living_military(child: Node2D) -> bool:
	if not _is_living_player_entity(child):
		return false
	if "unit_category" not in child or child.unit_category != "military":
		return false
	return true


# ---------------------------------------------------------------------------
# Melee / ranged damage helper
# ---------------------------------------------------------------------------


## Use the parent prototype_unit's damage system on [member _combat_target].
func _deal_damage(game_delta: float) -> void:
	if _combat_target == null or not is_instance_valid(_combat_target):
		return
	# Face the target
	var dir := _combat_target.global_position - _unit.position
	if dir.length() > 0.1:
		_unit._facing = dir.normalized()
	if _unit._attack_cooldown <= 0.0:
		_unit._combat_target = _combat_target
		_unit._deal_damage_to_target()
		var cooldown: float = _unit.get_stat("attack_speed")
		if cooldown <= 0.0:
			cooldown = 1.5
		_unit._attack_cooldown = cooldown
	_unit._attack_cooldown -= game_delta


# ---------------------------------------------------------------------------
# Save / Load — base fields
# ---------------------------------------------------------------------------


## Return a dictionary with the shared base-class fields.
## Subclasses call [code]super()[/code] and merge their own keys.
func save_state() -> Dictionary:
	return {
		"spawn_origin_x": spawn_origin.x,
		"spawn_origin_y": spawn_origin.y,
		"patrol_idle_timer": _patrol_idle_timer,
		"flee_timer": _flee_timer,
		"scan_timer": _scan_timer,
		"is_moving": _is_moving,
		"move_target_x": _move_target.x,
		"move_target_y": _move_target.y,
	}


## Restore shared base-class fields.  Subclasses call [code]super()[/code]
## and then restore their own keys.
func load_state(data: Dictionary) -> void:
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
