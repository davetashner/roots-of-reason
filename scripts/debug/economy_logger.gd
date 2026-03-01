class_name EconomyLogger
extends RefCounted
## Static ring buffer for economy deposit events. No autoload needed — gather
## code calls static methods to record deposits; the debug server reads the buffer
## and computes rolling gather rates.

const DEFAULT_CAPACITY: int = 200
const RATE_WINDOW: float = 10.0

static var _events: Array[Dictionary] = []
static var _capacity: int = DEFAULT_CAPACITY
static var _total_logged: int = 0


static func log_deposit(
	unit: Node2D,
	player_id: int,
	resource_type: String,
	amount: int,
	extras: Dictionary = {},
) -> void:
	var event: Dictionary = {
		"timestamp": _get_game_time(),
		"player_id": player_id,
		"resource_type": resource_type,
		"amount": amount,
		"unit_name": unit.name if unit != null else "",
		"drop_off_building": str(extras.get("drop_off_building", "")),
		"carry_capacity": int(extras.get("carry_capacity", 0)),
		"gather_rate": float(extras.get("gather_rate", 0.0)),
		"gather_multiplier": float(extras.get("gather_multiplier", 1.0)),
	}
	if _events.size() >= _capacity:
		_events.remove_at(0)
	_events.append(event)
	_total_logged += 1


static func get_events(limit: int = 50) -> Array[Dictionary]:
	if limit <= 0 or limit >= _events.size():
		return _events.duplicate()
	return _events.slice(_events.size() - limit) as Array[Dictionary]


static func clear() -> void:
	_events.clear()
	_total_logged = 0


static func get_capacity() -> int:
	return _capacity


static func get_total_logged() -> int:
	return _total_logged


static func get_gather_rates(player_id: int, window: float = RATE_WINDOW) -> Dictionary:
	## Compute per-resource gather rate (units/sec) over a rolling window.
	var now: float = _get_game_time()
	var cutoff: float = now - window
	var totals: Dictionary = {}
	for event: Dictionary in _events:
		if float(event.get("timestamp", 0.0)) < cutoff:
			continue
		if int(event.get("player_id", -1)) != player_id:
			continue
		var res_type: String = str(event.get("resource_type", ""))
		if res_type == "":
			continue
		totals[res_type] = int(totals.get(res_type, 0)) + int(event.get("amount", 0))
	var rates: Dictionary = {}
	var elapsed: float = minf(now, window)
	if elapsed <= 0.0:
		return rates
	for res_type: String in totals:
		rates[res_type] = float(totals[res_type]) / elapsed
	return rates


static func get_deposits_per_second(player_id: int, window: float = RATE_WINDOW) -> float:
	## Count deposit events per second over a rolling window.
	var now: float = _get_game_time()
	var cutoff: float = now - window
	var count: int = 0
	for event: Dictionary in _events:
		if float(event.get("timestamp", 0.0)) < cutoff:
			continue
		if int(event.get("player_id", -1)) != player_id:
			continue
		count += 1
	var elapsed: float = minf(now, window)
	if elapsed <= 0.0:
		return 0.0
	return float(count) / elapsed


static func get_villager_allocation(scene_root: Node, player_id: int) -> Dictionary:
	## Scan scene tree for villagers and compute allocation breakdown.
	var allocation: Dictionary = {"idle": 0, "building": 0}
	var idle_count: int = 0
	var total: int = 0
	if scene_root == null:
		return {"allocation": allocation, "idle_count": 0, "total": 0}
	for child: Node in scene_root.get_children():
		if not (child is Node2D):
			continue
		if "owner_id" not in child or int(child.owner_id) != player_id:
			continue
		if "unit_category" not in child:
			continue
		var cat: String = str(child.unit_category)
		if cat != "villager" and cat != "civilian":
			continue
		total += 1
		if child.has_method("is_idle") and child.is_idle():
			idle_count += 1
			allocation["idle"] = int(allocation.get("idle", 0)) + 1
			continue
		if "_build_target" in child and child._build_target != null:
			allocation["building"] = int(allocation.get("building", 0)) + 1
			continue
		var gather_type: String = ""
		if "_gather_type" in child:
			gather_type = str(child._gather_type)
		if gather_type != "":
			allocation[gather_type] = int(allocation.get(gather_type, 0)) + 1
		else:
			allocation["other"] = int(allocation.get("other", 0)) + 1
	return {"allocation": allocation, "idle_count": idle_count, "total": total}


static func _get_game_time() -> float:
	if Engine.has_singleton("GameManager"):
		return float(GameManager.game_time)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		var gm: Node = tree.root.get_node_or_null("GameManager")
		if gm != null and "game_time" in gm:
			return float(gm.game_time)
	return 0.0
