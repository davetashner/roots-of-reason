extends Node
## Pirate Manager — spawns Gaia pirate ships from deep ocean edges after Compass
## is researched. Manages pirate lifecycle, bounties, and spawn timing.

signal pirate_destroyed(pirate: Node2D, killer: Node2D)

const PirateAIScript := preload("res://scripts/fauna/pirate_ai.gd")
const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")
const TILE_SIZE: float = 64.0

var _enabled: bool = false
var _active_pirates: Array[Node2D] = []
var _spawn_timer: float = 0.0
var _config: Dictionary = {}
var _scene_root: Node = null
var _map_node: Node = null
var _target_detector: Node = null
var _tech_manager: Node = null
var _edge_tiles_cache: Array[Vector2i] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func setup(scene_root: Node, map_node: Node, target_detector: Node, tech_manager: Node) -> void:
	_scene_root = scene_root
	_map_node = map_node
	_target_detector = target_detector
	_tech_manager = tech_manager
	_config = _load_config()
	if _tech_manager != null and _tech_manager.has_signal("tech_researched"):
		_tech_manager.tech_researched.connect(_on_tech_researched)


func _load_config() -> Dictionary:
	if Engine.has_singleton("DataLoader"):
		return DataLoader.get_settings("pirates")
	if is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_settings"):
			return dl.get_settings("pirates")
	return {}


func _on_tech_researched(_player_id: int, tech_id: String, _effects: Dictionary) -> void:
	var trigger: String = str(_config.get("trigger_tech", "compass"))
	if tech_id == trigger:
		_enabled = true


func _process(delta: float) -> void:
	var game_delta: float = _get_game_delta(delta)
	if game_delta == 0.0:
		return
	# Clean dead pirates
	_clean_dead_pirates()
	if not _enabled:
		return
	# Tick spawn timer
	var base_interval: float = float(_config.get("spawn_interval_seconds", 90))
	var age_rate: float = _get_age_spawn_rate()
	var interval: float = base_interval / age_rate if age_rate > 0.0 else base_interval
	_spawn_timer += game_delta
	if _spawn_timer >= interval:
		_spawn_timer = 0.0
		var max_pirates: int = int(_config.get("max_active_pirates", 8))
		if _active_pirates.size() < max_pirates:
			_spawn_pirate()


func _clean_dead_pirates() -> void:
	var cleaned: Array[Node2D] = []
	for pirate in _active_pirates:
		if is_instance_valid(pirate) and "hp" in pirate and pirate.hp > 0:
			cleaned.append(pirate)
	_active_pirates = cleaned


func _find_deep_ocean_edge_tiles() -> Array[Vector2i]:
	if not _edge_tiles_cache.is_empty():
		return _edge_tiles_cache
	if _map_node == null or not _map_node.has_method("get_terrain_at"):
		return []
	if not _map_node.has_method("get_map_dimensions"):
		return []
	var dims: Vector2i = _map_node.get_map_dimensions()
	var result: Array[Vector2i] = []
	# Scan all four edges
	for x in dims.x:
		# Top edge
		if _map_node.get_terrain_at(Vector2i(x, 0)) == "deep_water":
			result.append(Vector2i(x, 0))
		# Bottom edge
		if _map_node.get_terrain_at(Vector2i(x, dims.y - 1)) == "deep_water":
			result.append(Vector2i(x, dims.y - 1))
	for y in range(1, dims.y - 1):
		# Left edge
		if _map_node.get_terrain_at(Vector2i(0, y)) == "deep_water":
			result.append(Vector2i(0, y))
		# Right edge
		if _map_node.get_terrain_at(Vector2i(dims.x - 1, y)) == "deep_water":
			result.append(Vector2i(dims.x - 1, y))
	_edge_tiles_cache = result
	return result


func _spawn_pirate() -> void:
	var edge_tiles := _find_deep_ocean_edge_tiles()
	if edge_tiles.is_empty():
		return
	var tile: Vector2i = edge_tiles[_rng.randi() % edge_tiles.size()]
	var unit := Node2D.new()
	var idx := _active_pirates.size()
	unit.name = "Pirate_%d" % idx
	unit.set_script(UnitScript)
	unit.position = IsoUtils.grid_to_screen(Vector2(tile))
	unit.unit_type = "pirate_ship"
	unit.owner_id = -1
	unit.entity_category = "pirate"
	unit.unit_color = Color(0.1, 0.1, 0.1)  # Dark / black
	_scene_root.add_child(unit)
	unit._scene_root = _scene_root
	# Apply stats from config (not from unit JSON)
	var pirate_stats: Dictionary = _config.get("stats", {})
	unit.hp = int(pirate_stats.get("hp", 80))
	unit.max_hp = int(pirate_stats.get("hp", 80))
	if unit.stats != null:
		unit.stats.set_base_stat("attack", float(pirate_stats.get("attack", 12)))
		unit.stats.set_base_stat("defense", float(pirate_stats.get("defense", 3)))
		unit.stats.set_base_stat("speed", float(pirate_stats.get("speed", 3.0)))
		unit.stats.set_base_stat("range", float(pirate_stats.get("range", 4)))
		unit.stats.set_base_stat("los", float(pirate_stats.get("los", 6)))
		unit.stats.set_base_stat("attack_speed", 1.5)
	# Register with target detector
	if _target_detector != null:
		_target_detector.register_entity(unit)
	# Attach PirateAI child
	var pirate_ai := Node.new()
	pirate_ai.name = "PirateAI"
	pirate_ai.set_script(PirateAIScript)
	unit.add_child(pirate_ai)
	pirate_ai._cfg = _config
	pirate_ai._scene_root = _scene_root
	# Connect death signal
	if unit.has_signal("unit_died"):
		unit.unit_died.connect(_on_pirate_died)
	_active_pirates.append(unit)


func _on_pirate_died(unit: Node2D, killer: Node2D) -> void:
	# Remove from active list
	var idx := _active_pirates.find(unit)
	if idx >= 0:
		_active_pirates.remove_at(idx)
	# Award bounty to killer's owner
	if killer != null and is_instance_valid(killer) and "owner_id" in killer:
		var killer_owner: int = killer.owner_id
		if killer_owner >= 0:
			_award_bounty(killer_owner)
	# Unregister from target detector
	if _target_detector != null:
		_target_detector.unregister_entity(unit)
	pirate_destroyed.emit(unit, killer)


func _award_bounty(player_id: int) -> void:
	var bounty_cfg: Dictionary = _config.get("bounty", {})
	var min_gold: int = int(bounty_cfg.get("min_gold", 30))
	var max_gold: int = int(bounty_cfg.get("max_gold", 120))
	var base_amount: int = _rng.randi_range(min_gold, max_gold)
	var scale: float = _get_age_bounty_scale()
	var final_amount: int = int(float(base_amount) * scale)
	if final_amount < 1:
		final_amount = 1
	var rm: Node = _get_resource_manager()
	if rm != null and rm.has_method("add_resource"):
		rm.add_resource(player_id, rm.ResourceType.GOLD, final_amount)


func _get_resource_manager() -> Node:
	if Engine.has_singleton("ResourceManager"):
		return ResourceManager
	if is_instance_valid(Engine.get_main_loop()):
		return Engine.get_main_loop().root.get_node_or_null("ResourceManager")
	return null


func _get_age_spawn_rate() -> float:
	var rates: Dictionary = _config.get("spawn_rate_by_age", {})
	var age: int = _get_current_age()
	return float(rates.get(str(age), 1.0))


func _get_age_bounty_scale() -> float:
	var bounty_cfg: Dictionary = _config.get("bounty", {})
	var scales: Dictionary = bounty_cfg.get("scaling_by_age", {})
	var age: int = _get_current_age()
	return float(scales.get(str(age), 1.0))


func _get_current_age() -> int:
	if Engine.has_singleton("GameManager"):
		return GameManager.current_age
	if is_instance_valid(Engine.get_main_loop()):
		var gm: Node = Engine.get_main_loop().root.get_node_or_null("GameManager")
		if gm and "current_age" in gm:
			return gm.current_age
	return 3  # Default to Medieval


func _get_game_delta(delta: float) -> float:
	if Engine.has_singleton("GameManager"):
		return GameManager.get_game_delta(delta)
	var ml := Engine.get_main_loop() if is_instance_valid(Engine.get_main_loop()) else null
	var gm: Node = ml.root.get_node_or_null("GameManager") if ml else null
	if gm and gm.has_method("get_game_delta"):
		return gm.get_game_delta(delta)
	return delta


func get_active_pirate_count() -> int:
	return _active_pirates.size()


func is_enabled() -> bool:
	return _enabled


# -- Save / Load --


func save_state() -> Dictionary:
	return {
		"enabled": _enabled,
		"spawn_timer": _spawn_timer,
		"active_pirate_count": _active_pirates.size(),
	}


func load_state(data: Dictionary) -> void:
	_enabled = bool(data.get("enabled", false))
	_spawn_timer = float(data.get("spawn_timer", 0.0))
