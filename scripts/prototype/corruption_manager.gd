class_name CorruptionManager
extends Node
## Calculates corruption rates based on building count, age, and tech reductions.
## Corruption reduces resource income as empire sprawl grows.

signal corruption_changed(player_id: int, rate: float)

var _config: Dictionary = {}
var _pop_manager: Node = null
var _tech_manager: Node = null
var _current_rates: Dictionary = {}  # player_id -> float


func _ready() -> void:
	_load_config()


func _load_config() -> void:
	var cfg: Dictionary = {}
	if Engine.has_singleton("DataLoader"):
		cfg = DataLoader.get_settings("corruption")
	elif is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_settings"):
			cfg = dl.get_settings("corruption")
	if cfg.is_empty():
		return
	_config = cfg


func setup(pop_mgr: Node, tech_mgr: Node) -> void:
	_pop_manager = pop_mgr
	_tech_manager = tech_mgr
	if _pop_manager != null:
		if _pop_manager.has_signal("building_count_changed"):
			_pop_manager.building_count_changed.connect(_on_building_count_changed)
	if _tech_manager != null:
		if _tech_manager.has_signal("tech_researched"):
			_tech_manager.tech_researched.connect(_on_tech_changed)
		if _tech_manager.has_signal("tech_regressed"):
			_tech_manager.tech_regressed.connect(_on_tech_changed)
	if GameManager.has_signal("age_advanced"):
		GameManager.age_advanced.connect(_on_age_advanced)


func calculate_corruption(player_id: int) -> float:
	if not _config.get("enabled", true):
		return 0.0
	var active_ages: Array = _config.get("active_ages", [])
	if GameManager.current_age not in active_ages:
		return 0.0
	var threshold: int = int(_config.get("building_threshold", 8))
	var count: int = 0
	if _pop_manager != null and _pop_manager.has_method("get_building_count"):
		count = _pop_manager.get_building_count(player_id)
	if count <= threshold:
		return 0.0
	var base_rate: float = float(_config.get("base_rate_per_building", 0.015))
	var raw: float = float(count - threshold) * base_rate
	var tech_reductions: Dictionary = _config.get("tech_reductions", {})
	for tech_id: String in tech_reductions:
		if _tech_manager != null and _tech_manager.is_tech_researched(tech_id, player_id):
			raw += float(tech_reductions[tech_id])
	var max_corruption: float = float(_config.get("max_corruption", 0.30))
	return clampf(raw, 0.0, max_corruption)


func recalculate(player_id: int) -> void:
	var rate: float = calculate_corruption(player_id)
	var old_rate: float = _current_rates.get(player_id, 0.0)
	_current_rates[player_id] = rate
	ResourceManager.set_corruption_rate(player_id, rate)
	if not is_equal_approx(rate, old_rate):
		corruption_changed.emit(player_id, rate)


func recalculate_all() -> void:
	for player_id: int in _current_rates:
		recalculate(player_id)


func is_resource_affected(resource_key: String) -> bool:
	if _config.get("knowledge_immune", true) and resource_key == "knowledge":
		return false
	var affected: Array = _config.get("affected_resources", [])
	return resource_key in affected


func _on_building_count_changed(player_id: int, _count: int) -> void:
	recalculate(player_id)


func _on_tech_changed(player_id: int, _tech_id: String, _data: Dictionary) -> void:
	recalculate(player_id)


func _on_age_advanced(_new_age: int) -> void:
	recalculate_all()


func save_state() -> Dictionary:
	var rates: Dictionary = {}
	for pid: int in _current_rates:
		rates[str(pid)] = _current_rates[pid]
	return {"current_rates": rates}


func load_state(data: Dictionary) -> void:
	_current_rates.clear()
	var rates: Dictionary = data.get("current_rates", {})
	for pid_str: String in rates:
		var pid: int = int(pid_str)
		_current_rates[pid] = float(rates[pid_str])
		ResourceManager.set_corruption_rate(pid, float(rates[pid_str]))
