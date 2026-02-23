class_name RiverTransport
extends Node
## Manages barge dispatching from River Docks and barge movement along rivers.
## Barges are visual + vulnerability — resources enter the stockpile immediately
## when deposited by villagers, but are deducted if a barge is destroyed in transit.

signal barge_dispatched(barge: Node2D)
signal barge_arrived(barge: Node2D)
signal barge_destroyed(barge: Node2D)

const BargeScript := preload("res://scripts/prototype/barge_entity.gd")

# 8-directional neighbors for river tile adjacency search
const NEIGHBORS_8 := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]

# References
var _map_node: Node = null
var _building_placer: Node = null

# Config (loaded from JSON)
var _base_barge_speed: float = 180.0
var _max_downstream_search_depth: int = 200
var _depot_river_proximity: int = 2
var _barge_visual_size: float = 24.0

# Per-dock state
var _dock_data: Dictionary = {}  # Node2D -> DockInfo dict
var _active_barges: Array[Node2D] = []


func _ready() -> void:
	_load_config()


func _load_config() -> void:
	var cfg := _load_settings("river_transport")
	_base_barge_speed = float(cfg.get("base_barge_speed", _base_barge_speed))
	_max_downstream_search_depth = int(cfg.get("max_downstream_search_depth", _max_downstream_search_depth))
	_depot_river_proximity = int(cfg.get("depot_river_proximity", _depot_river_proximity))
	_barge_visual_size = float(cfg.get("barge_visual_size", _barge_visual_size))


func _load_settings(settings_name: String) -> Dictionary:
	if is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_settings"):
			return dl.get_settings(settings_name)
	# Direct file fallback for tests
	var path := "res://data/settings/%s.json" % settings_name
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	if json.data is Dictionary:
		return json.data
	return {}


func _load_building_stats(building_name: String) -> Dictionary:
	if is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_building_stats"):
			return dl.get_building_stats(building_name)
	# Direct file fallback for tests
	var path := "res://data/buildings/%s.json" % building_name
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	if json.data is Dictionary:
		return json.data
	return {}


func setup(map_node: Node, building_placer: Node) -> void:
	_map_node = map_node
	_building_placer = building_placer
	if _building_placer and _building_placer.has_signal("building_placed"):
		_building_placer.building_placed.connect(_on_building_placed)


func _process(delta: float) -> void:
	_update_dock_timers(delta)
	_update_barges(delta)


func register_dock(building: Node2D) -> void:
	if _dock_data.has(building):
		return
	var stats := _load_building_stats("river_dock")
	_dock_data[building] = {
		"queued_resources": {},  # ResourceType (int) -> amount
		"queued_total": 0,
		"time_since_last_dispatch": 0.0,
		"barge_spawn_interval": float(stats.get("barge_spawn_interval", 5.0)),
		"max_barge_capacity": int(stats.get("max_barge_capacity", 30)),
		"barge_hp": int(stats.get("barge_hp", 15)),
		"transport_speed_multiplier": float(stats.get("transport_speed_multiplier", 3.0)),
	}


func unregister_dock(building: Node2D) -> void:
	_dock_data.erase(building)


func notify_resource_deposited(dock: Node2D, resource_type: int, amount: int) -> void:
	if not _dock_data.has(dock):
		return
	var info: Dictionary = _dock_data[dock]
	var queued: Dictionary = info["queued_resources"]
	queued[resource_type] = queued.get(resource_type, 0) + amount
	info["queued_total"] = info.get("queued_total", 0) + amount


func find_dock_river_tile(dock: Node2D) -> Vector2i:
	if _map_node == null:
		return Vector2i(-1, -1)
	var dock_pos: Vector2i = dock.grid_pos
	for offset: Vector2i in NEIGHBORS_8:
		var check := dock_pos + offset
		if _map_node.is_river(check):
			return check
	return Vector2i(-1, -1)


func find_downstream_depot(start_river_tile: Vector2i, owner_id: int, exclude: Node2D = null) -> Node2D:
	if _map_node == null:
		return null
	var current := start_river_tile
	var visited: Dictionary = {}
	for _step in _max_downstream_search_depth:
		if visited.has(current):
			break
		visited[current] = true
		# Check proximity for depots (docks and TCs)
		var depot := _find_depot_near_river(current, owner_id, exclude)
		if depot != null:
			return depot
		# Follow flow direction
		var flow: Vector2i = _map_node.get_flow_direction(current)
		if flow == Vector2i.ZERO:
			break
		var next := current + flow
		if not _map_node.is_river(next):
			# Check last position's neighbors for depot before giving up
			break
		current = next
	# Final check at terminus
	return _find_depot_near_river(current, owner_id, exclude)


func _find_depot_near_river(river_tile: Vector2i, owner_id: int, exclude: Node2D = null) -> Node2D:
	## Search for a building (dock or TC) within depot_river_proximity of river_tile.
	if _building_placer == null:
		return null
	var buildings: Array = _building_placer._placed_buildings
	for entry: Dictionary in buildings:
		var node: Node2D = entry.get("node")
		if not is_instance_valid(node):
			continue
		if node == exclude:
			continue
		if node.owner_id != owner_id:
			continue
		# Skip if it's a dock with no queued resources (it's a source, not dest)
		# Actually, any dock or TC is valid as a destination
		var bname: String = entry.get("building_name", "")
		var is_depot: bool = bname == "town_center" or (bool(node.is_drop_off) and bname != "")
		if not is_depot:
			continue
		# Check proximity
		var dist := _grid_distance(node.grid_pos, river_tile)
		if dist <= _depot_river_proximity:
			return node
	return null


func _grid_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _update_dock_timers(delta: float) -> void:
	var docks_to_dispatch: Array[Node2D] = []
	for dock: Node2D in _dock_data:
		if not is_instance_valid(dock):
			continue
		var info: Dictionary = _dock_data[dock]
		info["time_since_last_dispatch"] = info.get("time_since_last_dispatch", 0.0) + delta
		var interval: float = info.get("barge_spawn_interval", 5.0)
		if info.get("queued_total", 0) > 0 and info["time_since_last_dispatch"] >= interval:
			docks_to_dispatch.append(dock)
	for dock: Node2D in docks_to_dispatch:
		_dispatch_barge(dock)


func _dispatch_barge(dock: Node2D) -> void:
	var info: Dictionary = _dock_data.get(dock, {})
	if info.is_empty():
		return
	var queued: Dictionary = info.get("queued_resources", {})
	var queued_total: int = info.get("queued_total", 0)
	if queued_total <= 0:
		return
	# Find river tile and downstream depot
	var river_tile := find_dock_river_tile(dock)
	if river_tile == Vector2i(-1, -1):
		return
	var depot := find_downstream_depot(river_tile, dock.owner_id, dock)
	if depot == null:
		return  # No destination — keep resources queued
	# Build river path
	var path := _build_river_path(river_tile, depot)
	if path.is_empty():
		return
	# Determine how much to load
	var capacity: int = info.get("max_barge_capacity", 30)
	var barge_resources: Dictionary = {}
	var loaded: int = 0
	for res_type: int in queued:
		if loaded >= capacity:
			break
		var available: int = queued[res_type]
		var to_load: int = mini(available, capacity - loaded)
		if to_load > 0:
			barge_resources[res_type] = to_load
			loaded += to_load
	# Deduct from queue
	for res_type: int in barge_resources:
		queued[res_type] -= barge_resources[res_type]
		if queued[res_type] <= 0:
			queued.erase(res_type)
	info["queued_total"] = maxi(0, queued_total - loaded)
	info["time_since_last_dispatch"] = 0.0
	# Create barge
	var barge := Node2D.new()
	barge.set_script(BargeScript)
	barge.carried_resources = barge_resources
	barge.total_carried = loaded
	barge.owner_id = dock.owner_id
	barge.hp = info.get("barge_hp", 15)
	barge.max_hp = barge.hp
	barge.speed = _base_barge_speed * info.get("transport_speed_multiplier", 3.0)
	barge.river_path = path
	barge.path_index = 0
	barge._visual_size = _barge_visual_size
	barge.position = IsoUtils.grid_to_screen(Vector2(river_tile))
	barge.destroyed.connect(_on_barge_destroyed)
	barge.arrived.connect(_on_barge_arrived)
	if is_inside_tree():
		get_parent().add_child(barge)
	_active_barges.append(barge)
	barge_dispatched.emit(barge)


func _build_river_path(start_tile: Vector2i, _depot: Node2D) -> Array[Vector2i]:
	## Trace flow direction from start_tile building a path of river tiles.
	var path: Array[Vector2i] = []
	var current := start_tile
	var visited: Dictionary = {}
	for _step in _max_downstream_search_depth:
		if visited.has(current):
			break
		visited[current] = true
		path.append(current)
		# Check if we're close enough to the depot
		if _depot != null and _grid_distance(current, _depot.grid_pos) <= _depot_river_proximity:
			break
		var flow: Vector2i = _map_node.get_flow_direction(current)
		if flow == Vector2i.ZERO:
			break
		var next := current + flow
		if not _map_node.is_river(next):
			break
		current = next
	return path


func _update_barges(_delta: float) -> void:
	# Barges update themselves in _process; we just clean up dead/arrived ones
	var to_remove: Array[Node2D] = []
	for barge: Node2D in _active_barges:
		if not is_instance_valid(barge):
			to_remove.append(barge)
	for barge: Node2D in to_remove:
		_active_barges.erase(barge)


func _on_barge_destroyed(barge: Node2D) -> void:
	# Deduct resources from stockpile since the barge was destroyed
	var rm: Node = null
	if is_instance_valid(Engine.get_main_loop()):
		rm = Engine.get_main_loop().root.get_node_or_null("ResourceManager")
	if rm != null:
		for res_type: int in barge.carried_resources:
			var amount: int = barge.carried_resources[res_type]
			rm.add_resource(barge.owner_id, res_type, -amount)
	_active_barges.erase(barge)
	barge_destroyed.emit(barge)
	if is_instance_valid(barge):
		barge.queue_free()


func _on_barge_arrived(barge: Node2D) -> void:
	# Resources are already in stockpile — just clean up
	_active_barges.erase(barge)
	barge_arrived.emit(barge)
	if is_instance_valid(barge):
		barge.queue_free()


func _on_building_placed(building: Node2D) -> void:
	if not is_instance_valid(building):
		return
	if building.building_name == "river_dock":
		# Wait for construction to complete before registering
		if building.under_construction:
			building.construction_complete.connect(_on_dock_construction_complete)
		else:
			register_dock(building)


func _on_dock_construction_complete(building: Node2D) -> void:
	register_dock(building)


func get_active_barges() -> Array[Node2D]:
	return _active_barges.duplicate()


func get_dock_data() -> Dictionary:
	return _dock_data


func save_state() -> Dictionary:
	var docks_out: Array[Dictionary] = []
	for dock: Node2D in _dock_data:
		if not is_instance_valid(dock):
			continue
		var info: Dictionary = _dock_data[dock]
		var queued_out: Dictionary = {}
		var queued: Dictionary = info.get("queued_resources", {})
		for res_type: int in queued:
			queued_out[str(res_type)] = queued[res_type]
		(
			docks_out
			. append(
				{
					"grid_pos": [dock.grid_pos.x, dock.grid_pos.y],
					"owner_id": dock.owner_id,
					"queued_resources": queued_out,
					"queued_total": info.get("queued_total", 0),
					"time_since_last_dispatch": info.get("time_since_last_dispatch", 0.0),
				}
			)
		)
	var barges_out: Array[Dictionary] = []
	for barge: Node2D in _active_barges:
		if is_instance_valid(barge) and barge.has_method("save_state"):
			barges_out.append(barge.save_state())
	return {
		"docks": docks_out,
		"barges": barges_out,
	}


func load_state(data: Dictionary) -> void:
	# Dock state is restored by matching grid positions to placed buildings
	var docks_data: Array = data.get("docks", [])
	for entry: Dictionary in docks_data:
		var pos_arr: Array = entry.get("grid_pos", [0, 0])
		var grid_pos := Vector2i(int(pos_arr[0]), int(pos_arr[1]))
		var dock := _find_dock_at(grid_pos)
		if dock == null:
			continue
		register_dock(dock)
		var info: Dictionary = _dock_data[dock]
		var queued_in: Dictionary = entry.get("queued_resources", {})
		var queued: Dictionary = {}
		for key: String in queued_in:
			queued[int(key)] = int(queued_in[key])
		info["queued_resources"] = queued
		info["queued_total"] = int(entry.get("queued_total", 0))
		info["time_since_last_dispatch"] = float(entry.get("time_since_last_dispatch", 0.0))
	# Restore barges
	var barges_data: Array = data.get("barges", [])
	for barge_data: Dictionary in barges_data:
		var barge := Node2D.new()
		barge.set_script(BargeScript)
		barge.load_state(barge_data)
		barge.destroyed.connect(_on_barge_destroyed)
		barge.arrived.connect(_on_barge_arrived)
		if is_inside_tree():
			get_parent().add_child(barge)
		_active_barges.append(barge)


func _find_dock_at(grid_pos: Vector2i) -> Node2D:
	if _building_placer == null:
		return null
	for entry: Dictionary in _building_placer._placed_buildings:
		var node: Node2D = entry.get("node")
		if is_instance_valid(node) and node.grid_pos == grid_pos:
			if entry.get("building_name", "") == "river_dock":
				return node
	return null
