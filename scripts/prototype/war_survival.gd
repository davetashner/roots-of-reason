class_name WarSurvival
extends Node
## War survival mechanic — gives units a chance to survive lethal damage
## based on researched medical technologies. Each tech tier replaces the
## previous (not cumulative). Survival has a per-unit cooldown.

signal unit_survived(unit: Node2D, hp_remaining: int)

## Reference to TechManager for checking researched techs
var _tech_manager: Node = null

## Config loaded from data/settings/combat/war_survival.json
var _survival_cooldown: float = 30.0
var _tiers: Array = []
var _flash_color: Color = Color(0.2, 1.0, 0.2, 0.8)
var _flash_duration: float = 0.5

## Per-unit cooldown tracking: {unit instance_id: float (game_time of last survival)}
var _unit_cooldowns: Dictionary = {}


func _ready() -> void:
	_load_config()


func setup(tech_manager: Node) -> void:
	## Store reference to TechManager for tech lookups.
	_tech_manager = tech_manager


func roll_survival(unit: Node2D, damage: int, owner_id: int = -1) -> bool:
	## Returns true if the unit survives a lethal hit. If true, the unit's HP
	## is set to the survival amount and a green flash is played.
	## Only triggers on lethal damage (damage >= unit.hp).
	if not _can_attempt_survival(unit, damage):
		return false

	# Determine player ID
	var pid: int = owner_id
	if pid < 0 and "owner_id" in unit:
		pid = unit.owner_id
	if pid < 0:
		return false

	# Find the highest-tier medical tech the player has researched
	var active_tier: Dictionary = _get_active_tier(pid)
	if active_tier.is_empty():
		return false

	# Roll survival chance
	var chance: float = float(active_tier.get("chance", 0.0))
	if chance <= 0.0 or randf() >= chance:
		return false

	# Survival succeeded — apply it
	_apply_survival(unit, active_tier)
	return true


func _can_attempt_survival(unit: Node2D, damage: int) -> bool:
	## Validates preconditions: tech_manager exists, damage is lethal, not on cooldown.
	if _tech_manager == null:
		return false
	if "hp" not in unit or "max_hp" not in unit:
		return false
	if unit.hp > damage:
		return false
	var uid: int = unit.get_instance_id()
	var last_time: float = _unit_cooldowns.get(uid, -INF)
	return GameManager.game_time - last_time >= _survival_cooldown


func _apply_survival(unit: Node2D, active_tier: Dictionary) -> void:
	## Sets the unit's HP to the survival amount, records cooldown, plays flash.
	var max_hp: int = unit.max_hp
	var hp_percent: float = float(active_tier.get("hp_percent", 0.0))
	var hp_flat: int = int(active_tier.get("hp_flat", 0))
	var survive_hp: int = maxi(1, int(max_hp * hp_percent) + hp_flat)
	unit.hp = survive_hp
	_unit_cooldowns[unit.get_instance_id()] = GameManager.game_time
	_play_survival_flash(unit)
	unit_survived.emit(unit, survive_hp)


func clear_cooldown(unit: Node2D) -> void:
	## Clears the survival cooldown for a specific unit (useful for testing).
	var uid: int = unit.get_instance_id()
	_unit_cooldowns.erase(uid)


func save_state() -> Dictionary:
	return {
		"unit_cooldowns": _unit_cooldowns.duplicate(),
	}


func load_state(data: Dictionary) -> void:
	_unit_cooldowns = {}
	var raw: Dictionary = data.get("unit_cooldowns", {})
	for key: Variant in raw:
		_unit_cooldowns[int(key)] = float(raw[key])


func _get_active_tier(player_id: int) -> Dictionary:
	## Returns the highest-tier medical tech the player has researched.
	## Tiers are ordered lowest to highest in config; last match wins.
	var best: Dictionary = {}
	for tier: Dictionary in _tiers:
		var tech_id: String = str(tier.get("tech_id", ""))
		if tech_id != "" and _tech_manager.is_tech_researched(tech_id, player_id):
			best = tier
	return best


func _play_survival_flash(unit: Node2D) -> void:
	## Brief green flash to indicate survival.
	CombatVisual.play_survival_flash(unit, _flash_color, _flash_duration)


func _load_config() -> void:
	var config: Dictionary = DataLoader.get_settings("war_survival")
	if config.is_empty():
		return
	_survival_cooldown = float(config.get("survival_cooldown", 30.0))
	_flash_duration = float(config.get("flash_duration", 0.5))
	var color_arr: Array = config.get("flash_color", [0.2, 1.0, 0.2, 0.8])
	if color_arr.size() == 4:
		_flash_color = Color(
			float(color_arr[0]),
			float(color_arr[1]),
			float(color_arr[2]),
			float(color_arr[3]),
		)
	var raw_tiers: Array = config.get("tiers", [])
	_tiers = []
	for raw_tier: Variant in raw_tiers:
		if raw_tier is Dictionary:
			_tiers.append(raw_tier)
