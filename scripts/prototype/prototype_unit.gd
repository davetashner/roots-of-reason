extends Node2D
## Prototype unit — colored circle with direction indicator, click-to-select,
## right-click-to-move. Villagers can build construction sites and gather resources.
## Military units have combat state machine with attack-move, patrol, and stances.
##
## Delegates gathering to GathererComponent and combat to CombatantComponent.

signal unit_died(unit: Node2D, killer: Node2D)

# Re-export component enums for backward compatibility
enum GatherState { NONE, MOVING_TO_RESOURCE, GATHERING, MOVING_TO_DROP_OFF, DEPOSITING }
enum CombatState { NONE, PURSUING, ATTACKING, ATTACK_MOVING, PATROLLING }
enum Stance { AGGRESSIVE, DEFENSIVE, STAND_GROUND }

const TransportHandlerScript := preload("res://scripts/prototype/transport_handler.gd")
const GathererComponentScript := preload("res://scripts/prototype/gatherer_component.gd")
const CombatantComponentScript := preload("res://scripts/prototype/combatant_component.gd")
const UnitSpriteHandlerScript := preload("res://scripts/prototype/unit_sprite_handler.gd")
const RADIUS: float = 12.0
const MOVE_SPEED: float = 105.0
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
var kill_count: int = 0
var _target_pos: Vector2 = Vector2.ZERO
var _moving: bool = false
var _path: Array[Vector2] = []
var _path_index: int = 0
var _facing: Vector2 = Vector2.RIGHT

var _build_target: Node2D = null
var _build_speed: float = 1.0
var _build_reach: float = 80.0
var _pending_build_target_name: String = ""

var _scene_root: Node = null

# Feed state
var _feed_target: Node2D = null
var _feed_timer: float = 0.0
var _feed_duration: float = 5.0
var _feed_reach: float = 128.0
var _is_feeding: bool = false
var _pending_feed_target_name: String = ""

# Formation speed override — when > 0, caps get_move_speed()
var _formation_speed_override: float = 0.0

var _heal_accumulator: float = 0.0
var _visual_dirty: bool = true  # Start dirty so initial draw happens

var _is_dead: bool = false
var _last_attacker: Node2D = null
var _war_survival: Node = null

# Transport state
var _transport: RefCounted = null  # TransportHandler
var _transport_capacity: int = 0

# Components
var _gatherer: RefCounted = null  # GathererComponent
var _combatant: RefCounted = null  # CombatantComponent
var _sprite_handler: RefCounted = null  # UnitSpriteHandler
var _sprite_variant: String = ""

# -- Forwarding properties for backward compatibility --
# Gather forwarding
var _gather_target: Node2D:
	get:
		return _gatherer.gather_target if _gatherer != null else null
	set(v):
		if _gatherer != null:
			_gatherer.gather_target = v

var _gather_state: int:
	get:
		return _gatherer.gather_state if _gatherer != null else 0
	set(v):
		if _gatherer != null:
			_gatherer.gather_state = v as GathererComponentScript.GatherState

var _gather_type: String:
	get:
		return _gatherer.gather_type if _gatherer != null else ""
	set(v):
		if _gatherer != null:
			_gatherer.gather_type = v

var _carried_amount: int:
	get:
		return _gatherer.carried_amount if _gatherer != null else 0
	set(v):
		if _gatherer != null:
			_gatherer.carried_amount = v

var _carry_capacity: int:
	get:
		return _gatherer.carry_capacity if _gatherer != null else 10
	set(v):
		if _gatherer != null:
			_gatherer.carry_capacity = v

var _gather_rate_multiplier: float:
	get:
		return _gatherer.gather_rate_multiplier if _gatherer != null else 1.0
	set(v):
		if _gatherer != null:
			_gatherer.gather_rate_multiplier = v

var _gather_rates: Dictionary:
	get:
		return _gatherer.gather_rates if _gatherer != null else {}
	set(v):
		if _gatherer != null:
			_gatherer.gather_rates = v

var _gather_reach: float:
	get:
		return _gatherer.gather_reach if _gatherer != null else 80.0
	set(v):
		if _gatherer != null:
			_gatherer.gather_reach = v

var _drop_off_reach: float:
	get:
		return _gatherer.drop_off_reach if _gatherer != null else 80.0
	set(v):
		if _gatherer != null:
			_gatherer.drop_off_reach = v

var _gather_accumulator: float:
	get:
		return _gatherer.gather_accumulator if _gatherer != null else 0.0
	set(v):
		if _gatherer != null:
			_gatherer.gather_accumulator = v

var _drop_off_target: Node2D:
	get:
		return _gatherer.drop_off_target if _gatherer != null else null
	set(v):
		if _gatherer != null:
			_gatherer.drop_off_target = v

var _pending_gather_target_name: String:
	get:
		return _gatherer.pending_gather_target_name if _gatherer != null else ""
	set(v):
		if _gatherer != null:
			_gatherer.pending_gather_target_name = v

# Combat forwarding
var _combat_state: int:
	get:
		return _combatant.combat_state if _combatant != null else 0
	set(v):
		if _combatant != null:
			_combatant.combat_state = v as CombatantComponentScript.CombatState

var _stance: int:
	get:
		return _combatant.stance if _combatant != null else 0
	set(v):
		if _combatant != null:
			_combatant.stance = v as CombatantComponentScript.Stance

var _combat_target: Node2D:
	get:
		return _combatant.combat_target if _combatant != null else null
	set(v):
		if _combatant != null:
			_combatant.combat_target = v

var _attack_cooldown: float:
	get:
		return _combatant.attack_cooldown if _combatant != null else 0.0
	set(v):
		if _combatant != null:
			_combatant.attack_cooldown = v

var _scan_timer: float:
	get:
		return _combatant.scan_timer if _combatant != null else 0.0
	set(v):
		if _combatant != null:
			_combatant.scan_timer = v

var _attack_move_destination: Vector2:
	get:
		return _combatant.attack_move_destination if _combatant != null else Vector2.ZERO
	set(v):
		if _combatant != null:
			_combatant.attack_move_destination = v

var _patrol_point_a: Vector2:
	get:
		return _combatant.patrol_point_a if _combatant != null else Vector2.ZERO
	set(v):
		if _combatant != null:
			_combatant.patrol_point_a = v

var _patrol_point_b: Vector2:
	get:
		return _combatant.patrol_point_b if _combatant != null else Vector2.ZERO
	set(v):
		if _combatant != null:
			_combatant.patrol_point_b = v

var _patrol_heading_to_b: bool:
	get:
		return _combatant.patrol_heading_to_b if _combatant != null else true
	set(v):
		if _combatant != null:
			_combatant.patrol_heading_to_b = v

var _leash_origin: Vector2:
	get:
		return _combatant.leash_origin if _combatant != null else Vector2.ZERO
	set(v):
		if _combatant != null:
			_combatant.leash_origin = v

var _combat_config: Dictionary:
	get:
		return _combatant.combat_config if _combatant != null else {}
	set(v):
		if _combatant != null:
			_combatant.combat_config = v

var _pending_combat_target_name: String:
	get:
		return _combatant.pending_combat_target_name if _combatant != null else ""
	set(v):
		if _combatant != null:
			_combatant.pending_combat_target_name = v

var _visibility_manager: Node:
	get:
		return _combatant.visibility_manager if _combatant != null else null
	set(v):
		if _combatant != null:
			_combatant.visibility_manager = v


func _ready() -> void:
	_target_pos = position
	_gatherer = GathererComponentScript.new(self)
	_combatant = CombatantComponentScript.new(self)
	_init_stats()
	_load_build_config()
	_load_gather_config()
	_load_combat_config()
	_init_transport()
	var cbm: Node = GameUtils.get_autoload("CivBonusManager")
	if cbm != null and stats != null:
		cbm.apply_bonus_to_unit(stats, unit_type, owner_id)


func _init_stats() -> void:
	var raw: Dictionary = _dl_unit_stats(unit_type)
	stats = UnitStats.new(unit_type, raw)


func get_stat(stat_name: String) -> float:
	if stats == null:
		return 0.0
	return stats.get_stat(stat_name)


func get_move_speed() -> float:
	var base := MOVE_SPEED
	var speed_stat := get_stat("speed")
	if speed_stat > 0.0:
		base = MOVE_SPEED * speed_stat
	if _formation_speed_override > 0.0:
		return minf(base, _formation_speed_override)
	return base


func set_formation_speed(speed: float) -> void:
	_formation_speed_override = speed


func clear_formation_speed() -> void:
	_formation_speed_override = 0.0


func _get_civ_build_multiplier() -> float:
	var cbm: Node = GameUtils.get_autoload("CivBonusManager")
	if cbm != null:
		return cbm.get_build_speed_multiplier(owner_id)
	return 1.0


func _dl_unit_stats(id: String) -> Dictionary:
	var dl: Node = GameUtils.get_autoload("DataLoader")
	if dl != null and dl.has_method("get_unit_stats"):
		return dl.get_unit_stats(id)
	return {}


func _load_build_config() -> void:
	var unit_cfg := _dl_unit_stats("villager")
	if not unit_cfg.is_empty():
		_build_speed = float(unit_cfg.get("build_speed", _build_speed))
	var con_cfg := GameUtils.dl_settings("construction")
	if not con_cfg.is_empty():
		_build_reach = float(con_cfg.get("build_reach", _build_reach))


func _load_gather_config() -> void:
	var unit_cfg := _dl_unit_stats("villager")
	var gather_cfg := GameUtils.dl_settings("gathering")
	_gatherer.load_config(unit_cfg, gather_cfg)


func _load_combat_config() -> void:
	var cfg := GameUtils.dl_settings("combat")
	_combatant.load_config(cfg)


func _init_transport() -> void:
	var cfg := _dl_unit_stats(unit_type)
	_transport_capacity = int(cfg.get("transport_capacity", 0))
	if _transport_capacity > 0:
		_transport = TransportHandlerScript.new()
		_transport.capacity = _transport_capacity
		_transport.config = GameUtils.dl_settings("transport")


func _init_sprite() -> void:
	if _sprite_variant == "":
		var config_path := "res://data/units/sprites/villager.json"
		var file := FileAccess.open(config_path, FileAccess.READ)
		if file == null:
			return
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed == null or not (parsed is Dictionary):
			return
		var variants: Array = parsed.get("variants", [])
		if variants.is_empty():
			return
		_sprite_variant = variants[randi() % variants.size()]
	_sprite_handler = UnitSpriteHandlerScript.new(self, _sprite_variant, unit_color)


func _get_visual_state() -> String:
	if _is_dead:
		return "death"
	if _build_target != null and not _moving:
		return "build"
	if _gatherer != null and _gatherer.gather_state == GathererComponentScript.GatherState.GATHERING:
		return "gather"
	if _combatant != null and _combatant.combat_state == CombatantComponentScript.CombatState.ATTACKING and not _moving:
		return "attack"
	if _moving:
		return "walk"
	return "idle"


func mark_visual_dirty() -> void:
	_visual_dirty = true


func _process(delta: float) -> void:
	if _is_dead:
		return
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
				clear_formation_speed()
		else:
			var direction := (_target_pos - position).normalized()
			_facing = direction
			position = position.move_toward(_target_pos, get_move_speed() * game_delta)
		_visual_dirty = true
	_tick_build(game_delta)
	_gatherer.tick(game_delta)
	_tick_feed(game_delta)
	_combatant.tick(game_delta)
	_tick_heal(game_delta)
	if _transport != null:
		_transport.tick(game_delta, _moving)
	# Lazy-init sprite handler for villagers (after load_state may have set _sprite_variant)
	if _sprite_handler == null and unit_type == "villager":
		_init_sprite()
	if _sprite_handler != null:
		_sprite_handler.update(_get_visual_state(), _facing, game_delta)
	if _visual_dirty:
		_visual_dirty = false
		queue_redraw()


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
	# Apply build work: build_speed / build_time per second, scaled by civ bonus
	var build_time: float = _build_target._build_time
	var civ_mult: float = _get_civ_build_multiplier()
	var work: float = (_build_speed / build_time) * game_delta * civ_mult
	_build_target.apply_build_work(work)
	# Check if construction completed
	if not _build_target.under_construction:
		_build_target = null


func assign_gather_target(node: Node2D) -> void:
	_build_target = null
	_pending_build_target_name = ""
	_cancel_combat()
	_cancel_feed()
	_gatherer.assign_target(node)


func assign_build_target(building: Node2D) -> void:
	_cancel_gather()
	_cancel_combat()
	_cancel_feed()
	_build_target = building
	move_to(building.global_position)


func is_idle() -> bool:
	return (
		not _moving
		and _build_target == null
		and _gatherer.gather_state == GathererComponentScript.GatherState.NONE
		and _combatant.combat_state == CombatantComponentScript.CombatState.NONE
		and _feed_target == null
	)


func resolve_build_target(scene_root: Node) -> void:
	if _pending_build_target_name == "":
		return
	var target := scene_root.get_node_or_null(_pending_build_target_name)
	if target is Node2D:
		_build_target = target
	_pending_build_target_name = ""


func resolve_gather_target(scene_root: Node) -> void:
	_gatherer.resolve_target(scene_root)


func _tick_feed(game_delta: float) -> void:
	if _feed_target == null:
		return
	if not is_instance_valid(_feed_target):
		_clear_feed_state()
		return
	var wolf_ai: Node = _feed_target.get_node_or_null("WolfAI")
	if wolf_ai == null:
		_clear_feed_state()
		return
	var dist: float = position.distance_to(_feed_target.global_position)
	if dist > _feed_reach:
		return
	# In range — start feeding if not already
	if not _is_feeding:
		_moving = false
		_path.clear()
		_path_index = 0
		if not wolf_ai.begin_feeding(self, owner_id):
			_clear_feed_state()
			return
		_is_feeding = true
		_feed_timer = 0.0
	# Tick feed timer
	_feed_timer += game_delta
	if _feed_timer >= _feed_duration:
		wolf_ai.complete_feeding()
		_clear_feed_state()


func _cancel_feed() -> void:
	if _feed_target == null:
		return
	if is_instance_valid(_feed_target):
		var wolf_ai: Node = _feed_target.get_node_or_null("WolfAI")
		if wolf_ai != null:
			if _is_feeding:
				wolf_ai.cancel_feeding()
			else:
				wolf_ai.unregister_pending_feeder(self)
	_clear_feed_state()


func _clear_feed_state() -> void:
	_feed_target = null
	_feed_timer = 0.0
	_is_feeding = false
	_pending_feed_target_name = ""


func assign_feed_target(wolf: Node2D) -> void:
	# Cancel other tasks
	_cancel_gather()
	_cancel_combat()
	_build_target = null
	_pending_build_target_name = ""
	# Load feed config from fauna settings
	var fauna_cfg: Dictionary = GameUtils.dl_settings("fauna")
	var wolf_cfg: Dictionary = fauna_cfg.get("wolf", {})
	_feed_duration = float(wolf_cfg.get("feed_duration", 5.0))
	_feed_reach = float(wolf_cfg.get("feed_distance_tiles", 2)) * TILE_SIZE
	# Check food cost
	var cost: int = int(wolf_cfg.get("feed_cost", 25))
	var costs: Dictionary = {ResourceManager.ResourceType.FOOD: cost}
	if not ResourceManager.can_afford(owner_id, costs):
		return
	ResourceManager.spend(owner_id, costs)
	_feed_target = wolf
	_feed_timer = 0.0
	_is_feeding = false
	# Register as pending feeder for aggro suppression
	var wolf_ai: Node = wolf.get_node_or_null("WolfAI")
	if wolf_ai != null:
		wolf_ai.register_pending_feeder(self)
	move_to(wolf.global_position)


func resolve_feed_target(scene_root: Node) -> void:
	if _pending_feed_target_name == "":
		return
	var target := scene_root.get_node_or_null(_pending_feed_target_name)
	if target is Node2D:
		_feed_target = target
	_pending_feed_target_name = ""


func _tick_heal(game_delta: float) -> void:
	if hp <= 0 or hp >= max_hp:
		return
	if _combatant.combat_state != CombatantComponentScript.CombatState.NONE:
		return
	if stats == null:
		return
	var rate: float = 0.0
	if stats._base_stats.has("self_heal_rate"):
		rate = float(stats._base_stats["self_heal_rate"])
	if rate <= 0.0:
		return
	_heal_accumulator += rate * game_delta
	if _heal_accumulator >= 1.0:
		var whole := int(_heal_accumulator)
		hp = mini(hp + whole, max_hp)
		_heal_accumulator -= float(whole)
		_visual_dirty = true


# -- Combat delegation --


func take_damage(amount: int, attacker: Node2D) -> void:
	_combatant.take_damage(amount, attacker)


func assign_attack_target(target: Node2D) -> void:
	_cancel_gather()
	_cancel_feed()
	_build_target = null
	_pending_build_target_name = ""
	_combatant.engage_target(target)


func attack_move_to(world_pos: Vector2) -> void:
	_cancel_gather()
	_build_target = null
	_pending_build_target_name = ""
	_combatant.attack_move_to(world_pos)


func patrol_between(point_a: Vector2, point_b: Vector2) -> void:
	_cancel_gather()
	_build_target = null
	_pending_build_target_name = ""
	_combatant.patrol_between(point_a, point_b)


func set_stance(new_stance: Stance) -> void:
	_combatant.set_stance(new_stance as CombatantComponentScript.Stance)


func resolve_combat_target(scene_root: Node) -> void:
	_combatant.resolve_target(scene_root)


func _tick_combat(game_delta: float) -> void:
	_combatant.tick(game_delta)


func _deal_damage_to_target() -> void:
	_combatant._deal_damage_to_target()


func _cancel_combat() -> void:
	_combatant.cancel()


func _tick_gather(game_delta: float) -> void:
	_gatherer.tick(game_delta)


func _find_nearest_drop_off(res_type: String) -> Node2D:
	return _gatherer._find_nearest_drop_off(res_type)


func _cancel_gather() -> void:
	_gatherer.cancel()


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	_cancel_feed()
	_cancel_gather()
	_cancel_combat()
	if _transport != null:
		_transport.kill_passengers()
	var killer: Node2D = _last_attacker
	if killer != null and is_instance_valid(killer) and "kill_count" in killer:
		killer.kill_count += 1
	unit_died.emit(self, killer)
	selected = false
	set_process(false)
	var tween := CombatVisual.play_death_animation(self, _combatant.combat_config)
	if tween != null:
		tween.finished.connect(_enter_corpse_state)
	else:
		_enter_corpse_state()


func _enter_corpse_state() -> void:
	var ca: Array = _combatant.combat_config.get("corpse_modulate", [0.4, 0.4, 0.4, 0.5])
	modulate = Color(ca[0], ca[1], ca[2], ca[3]) if ca.size() == 4 else Color(0.4, 0.4, 0.4, 0.5)
	queue_redraw()
	var corpse_time: float = float(_combatant.combat_config.get("corpse_duration", 30.0))
	var corpse_tween := create_tween()
	corpse_tween.tween_interval(corpse_time)
	corpse_tween.tween_property(self, "modulate:a", 0.0, 1.0)
	corpse_tween.tween_callback(queue_free)


# -- Transport delegation --


func embark_unit(unit: Node2D) -> bool:
	return _transport.embark_unit(unit) if _transport != null else false


func disembark_all(shore_pos: Vector2) -> void:
	if _transport == null or _transport.embarked_units.is_empty():
		return
	_transport.pending_disembark_pos = shore_pos
	_transport.is_unloading = true
	move_to(shore_pos)


func can_embark() -> bool:
	return _transport.can_embark() if _transport != null else false


func get_embarked_count() -> int:
	return _transport.get_count() if _transport != null else 0


func get_transport_capacity() -> int:
	return _transport_capacity


func resolve_embarked(scene_root: Node) -> void:
	if _transport != null:
		_transport.resolve(scene_root)


# -- Drawing --


func _draw() -> void:
	if selected:
		draw_arc(Vector2.ZERO, SELECTION_RING_RADIUS, 0, TAU, 32, Color(0, 1, 0, 0.8), 2.0)
	# Skip circle + arrow when sprite handler is active
	if _sprite_handler == null:
		var draw_radius := RADIUS
		if entity_category == "dog":
			draw_radius = RADIUS * 0.8
			draw_circle(Vector2.ZERO, draw_radius, unit_color)
			var collar_color := Color(0.2, 0.4, 0.9) if owner_id == 0 else Color(0.9, 0.2, 0.2)
			draw_arc(Vector2.ZERO, draw_radius + 1.0, 0.0, PI, 16, collar_color, 2.5)
		else:
			draw_circle(Vector2.ZERO, RADIUS, unit_color)
		var tip := _facing * (draw_radius + 4.0)
		var left := _facing.rotated(2.5) * draw_radius * 0.5
		var right := _facing.rotated(-2.5) * draw_radius * 0.5
		draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(1, 1, 1, 0.9))
		if _moving:
			var lt := _target_pos - position
			draw_circle(lt, 3.0, Color(1, 1, 0, 0.6))
			draw_arc(lt, 6.0, 0, TAU, 16, Color(1, 1, 0, 0.4), 1.0)
	if _gatherer.carried_amount > 0:
		var cr := float(_gatherer.carried_amount) / float(_gatherer.carry_capacity)
		draw_arc(Vector2.ZERO, RADIUS + 2.0, 0, TAU * cr, 16, Color(0.9, 0.8, 0.1, 0.8), 2.0)
	if max_hp > 0 and hp < max_hp:
		var bw: float = RADIUS * 2.5
		var by: float = -RADIUS - 8.0
		var r: float = float(hp) / float(max_hp)
		var hpc := Color(0.2, 0.8, 0.2) if r > 0.5 else Color(0.9, 0.2, 0.2)
		BarDrawer.draw_bar(
			self, Vector2(-bw / 2.0, by), Vector2(bw, 3.0), r, hpc, Color(0.2, 0.2, 0.2, 0.8), Color.TRANSPARENT
		)


# -- Movement --


func move_to(world_pos: Vector2) -> void:
	# Reject moves to impassable terrain (mountain, canyon, deep water, etc.)
	var grid_pos := Vector2i(IsoUtils.screen_to_grid(world_pos))
	var pf: Node = get_node_or_null("/root/PrototypeMain/PathfindingGrid")
	if pf and pf.has_method("is_cell_solid") and pf.is_cell_solid(grid_pos):
		return
	_path.clear()
	_path_index = 0
	_target_pos = world_pos
	_moving = true
	mark_visual_dirty()


func follow_path(waypoints: Array[Vector2]) -> void:
	if waypoints.is_empty():
		return
	_path = waypoints
	_path_index = 0
	_target_pos = _path[0]
	_moving = true
	mark_visual_dirty()


func select() -> void:
	if _is_dead:
		return
	selected = true
	mark_visual_dirty()


func deselect() -> void:
	selected = false
	mark_visual_dirty()


func is_point_inside(point: Vector2) -> bool:
	if _is_dead:
		return false
	return point.distance_to(global_position) <= RADIUS * 1.5


func get_entity_category() -> String:
	if entity_category != "":
		return entity_category
	if _transport_capacity > 0 and owner_id == 0:
		return "own_transport"
	return "enemy_unit" if owner_id != 0 else ""


# -- Save / Load --


func save_state() -> Dictionary:
	var state := {
		"position_x": position.x,
		"position_y": position.y,
		"unit_type": unit_type,
		"hp": hp,
		"max_hp": max_hp,
		"is_feeding": _is_feeding,
		"feed_timer": _feed_timer,
		"formation_speed_override": _formation_speed_override,
		"kill_count": kill_count,
		"heal_accumulator": _heal_accumulator,
	}
	if _sprite_variant != "":
		state["sprite_variant"] = _sprite_variant
	if _build_target != null and is_instance_valid(_build_target):
		state["build_target_name"] = str(_build_target.name)
	if _feed_target != null and is_instance_valid(_feed_target):
		state["feed_target_name"] = str(_feed_target.name)
	if stats != null:
		state["stats"] = stats.save_state()
	# Merge component states (flat dict — backward compatible)
	state.merge(_gatherer.save_state())
	state.merge(_combatant.save_state())
	if _transport != null:
		state.merge(_transport.save_state())
	return state


func load_state(data: Dictionary) -> void:
	position = Vector2(
		float(data.get("position_x", 0)),
		float(data.get("position_y", 0)),
	)
	unit_type = str(data.get("unit_type", "land"))
	_pending_build_target_name = str(data.get("build_target_name", ""))
	hp = int(data.get("hp", max_hp))
	max_hp = int(data.get("max_hp", max_hp))
	# Restore feed state
	_pending_feed_target_name = str(data.get("feed_target_name", ""))
	_is_feeding = bool(data.get("is_feeding", false))
	_feed_timer = float(data.get("feed_timer", 0.0))
	_formation_speed_override = float(data.get("formation_speed_override", 0.0))
	kill_count = int(data.get("kill_count", 0))
	_heal_accumulator = float(data.get("heal_accumulator", 0.0))
	_sprite_variant = str(data.get("sprite_variant", ""))
	if data.has("stats"):
		if stats == null:
			stats = UnitStats.new()
		stats.load_state(data["stats"])
	# Delegate to components
	_gatherer.load_state(data)
	_combatant.load_state(data)
	if _transport != null and data.has("embarked_unit_names"):
		_transport.load_state(data)
