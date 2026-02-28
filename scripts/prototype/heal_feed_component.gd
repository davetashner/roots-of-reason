extends RefCounted
## HealFeedComponent — handles self-heal regeneration and the wolf-feeding state machine.
## Extracted from prototype_unit.gd to reduce coordinator size.

const TILE_SIZE: float = 64.0

# Feed state
var feed_target: Node2D = null
var feed_timer: float = 0.0
var feed_duration: float = 5.0
var feed_reach: float = 128.0
var is_feeding: bool = false
var pending_feed_target_name: String = ""

# Heal state
var heal_accumulator: float = 0.0

var _unit: Node2D = null


func _init(unit: Node2D = null) -> void:
	_unit = unit


func tick(game_delta: float) -> void:
	_tick_feed(game_delta)
	_tick_heal(game_delta)


func _tick_feed(game_delta: float) -> void:
	if feed_target == null:
		return
	if not is_instance_valid(feed_target):
		_clear_feed_state()
		return
	var wolf_ai: Node = feed_target.get_node_or_null("WolfAI")
	if wolf_ai == null:
		_clear_feed_state()
		return
	var dist: float = _unit.position.distance_to(feed_target.global_position)
	if dist > feed_reach:
		return
	# In range — start feeding if not already
	if not is_feeding:
		_unit._moving = false
		_unit._path.clear()
		_unit._path_index = 0
		if not wolf_ai.begin_feeding(_unit, _unit.owner_id):
			_clear_feed_state()
			return
		is_feeding = true
		feed_timer = 0.0
	# Tick feed timer
	feed_timer += game_delta
	if feed_timer >= feed_duration:
		wolf_ai.complete_feeding()
		_clear_feed_state()


func _tick_heal(game_delta: float) -> void:
	if _unit.hp <= 0 or _unit.hp >= _unit.max_hp:
		return
	# combat_state == 0 means CombatState.NONE — skip heal while in combat
	if _unit._combatant != null and _unit._combatant.combat_state != 0:
		return
	if _unit.stats == null:
		return
	var rate: float = 0.0
	if _unit.stats._base_stats.has("self_heal_rate"):
		rate = float(_unit.stats._base_stats["self_heal_rate"])
	if rate <= 0.0:
		return
	heal_accumulator += rate * game_delta
	if heal_accumulator >= 1.0:
		var whole := int(heal_accumulator)
		_unit.hp = mini(_unit.hp + whole, _unit.max_hp)
		heal_accumulator -= float(whole)
		_unit.mark_visual_dirty()


func assign_feed_target(wolf: Node2D) -> void:
	# Load feed config from fauna settings
	var fauna_cfg: Dictionary = GameUtils.dl_settings("fauna")
	var wolf_cfg: Dictionary = fauna_cfg.get("wolf", {})
	feed_duration = float(wolf_cfg.get("feed_duration", 5.0))
	feed_reach = float(wolf_cfg.get("feed_distance_tiles", 2)) * TILE_SIZE
	# Check food cost
	var cost: int = int(wolf_cfg.get("feed_cost", 25))
	var costs: Dictionary = {ResourceManager.ResourceType.FOOD: cost}
	if not ResourceManager.can_afford(_unit.owner_id, costs):
		return
	ResourceManager.spend(_unit.owner_id, costs)
	feed_target = wolf
	feed_timer = 0.0
	is_feeding = false
	# Register as pending feeder for aggro suppression
	var wolf_ai: Node = wolf.get_node_or_null("WolfAI")
	if wolf_ai != null:
		wolf_ai.register_pending_feeder(_unit)
	_unit.move_to(wolf.global_position)


func cancel() -> void:
	if feed_target == null:
		return
	if is_instance_valid(feed_target):
		var wolf_ai: Node = feed_target.get_node_or_null("WolfAI")
		if wolf_ai != null:
			if is_feeding:
				wolf_ai.cancel_feeding()
			else:
				wolf_ai.unregister_pending_feeder(_unit)
	_clear_feed_state()


func _clear_feed_state() -> void:
	feed_target = null
	feed_timer = 0.0
	is_feeding = false
	pending_feed_target_name = ""


func resolve_target(scene_root: Node) -> void:
	if pending_feed_target_name == "":
		return
	var target := scene_root.get_node_or_null(pending_feed_target_name)
	if target is Node2D:
		feed_target = target
	pending_feed_target_name = ""


func save_state() -> Dictionary:
	var state := {
		"is_feeding": is_feeding,
		"feed_timer": feed_timer,
		"heal_accumulator": heal_accumulator,
	}
	if feed_target != null and is_instance_valid(feed_target):
		state["feed_target_name"] = str(feed_target.name)
	return state


func load_state(data: Dictionary) -> void:
	pending_feed_target_name = str(data.get("feed_target_name", ""))
	is_feeding = bool(data.get("is_feeding", false))
	feed_timer = float(data.get("feed_timer", 0.0))
	heal_accumulator = float(data.get("heal_accumulator", 0.0))
