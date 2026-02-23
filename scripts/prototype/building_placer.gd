extends Node
## Building placement system — manages ghost preview, validation, and construction.
## Uses _unhandled_input with high process_priority to intercept before prototype_input.

signal placement_started(building_name: String)
signal placement_cancelled(building_name: String)
signal placement_confirmed(building_name: String, grid_pos: Vector2i)
signal building_placed(building: Node2D)

const BuildingScript := preload("res://scripts/prototype/prototype_building.gd")
const GhostScript := preload("res://scripts/prototype/building_ghost.gd")

const RESOURCE_NAME_TO_TYPE: Dictionary = {
	"food": ResourceManager.ResourceType.FOOD,
	"wood": ResourceManager.ResourceType.WOOD,
	"stone": ResourceManager.ResourceType.STONE,
	"gold": ResourceManager.ResourceType.GOLD,
	"knowledge": ResourceManager.ResourceType.KNOWLEDGE,
}

var _active: bool = false
var _building_name: String = ""
var _building_stats: Dictionary = {}
var _ghost: Node2D = null
var _current_grid_pos := Vector2i(-1, -1)
var _is_valid: bool = false
var _player_id: int = 0
var _placed_buildings: Array[Dictionary] = []

var _camera: Camera2D = null
var _pathfinder: Node = null
var _map_node: Node = null
var _target_detector: Node = null


func _ready() -> void:
	process_priority = -10


func setup(
	camera: Camera2D,
	pathfinder: Node,
	map_node: Node,
	target_detector: Node,
) -> void:
	_camera = camera
	_pathfinder = pathfinder
	_map_node = map_node
	_target_detector = target_detector


func is_active() -> bool:
	return _active


func start_placement(building_name: String, player_id: int = 0) -> bool:
	if _active:
		cancel_placement()
	_player_id = player_id
	_building_stats = _load_building_stats(building_name)
	if _building_stats.is_empty():
		return false
	var costs := _parse_costs(_building_stats.get("build_cost", {}))
	if not ResourceManager.can_afford(_player_id, costs):
		return false
	_building_name = building_name
	_active = true
	_create_ghost()
	placement_started.emit(_building_name)
	return true


func cancel_placement() -> void:
	if not _active:
		return
	var name_copy := _building_name
	_cleanup_ghost()
	_active = false
	_building_name = ""
	_building_stats = {}
	_current_grid_pos = Vector2i(-1, -1)
	_is_valid = false
	placement_cancelled.emit(name_copy)


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseMotion:
		_update_ghost_position(event as InputEventMouseMotion)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_confirm_placement()
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				cancel_placement()
				get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE:
			cancel_placement()
			get_viewport().set_input_as_handled()


func _update_ghost_position(motion: InputEventMouseMotion) -> void:
	if _ghost == null or _camera == null:
		return
	var world_pos := _screen_to_world(motion.position)
	var grid_pos := IsoUtils.snap_to_grid(world_pos)
	if grid_pos == _current_grid_pos:
		return
	_current_grid_pos = grid_pos
	_ghost.position = IsoUtils.grid_to_screen(Vector2(grid_pos))
	var footprint := _get_footprint()
	var constraint: String = _building_stats.get("placement_constraint", "")
	_is_valid = BuildingValidator.is_placement_valid(grid_pos, footprint, _map_node, _pathfinder, constraint)
	_ghost.set_valid(_is_valid)


func _confirm_placement() -> void:
	if not _is_valid:
		return
	var costs := _parse_costs(_building_stats.get("build_cost", {}))
	if not ResourceManager.spend(_player_id, costs):
		return
	var footprint := _get_footprint()
	var building := _create_building(_building_name, _current_grid_pos, footprint)
	# Mark footprint cells as solid
	if _pathfinder != null:
		var cells := BuildingValidator.get_footprint_cells(_current_grid_pos, footprint)
		for cell in cells:
			_pathfinder.set_cell_solid(cell, true)
	# Register with target detector
	if _target_detector != null:
		_target_detector.register_entity(building)
	# Track for save/load
	(
		_placed_buildings
		. append(
			{
				"building_name": _building_name,
				"grid_pos": [_current_grid_pos.x, _current_grid_pos.y],
				"player_id": _player_id,
				"node": building,
			}
		)
	)
	var placed_name := _building_name
	var placed_pos := _current_grid_pos
	placement_confirmed.emit(placed_name, placed_pos)
	building_placed.emit(building)
	# End placement mode
	_cleanup_ghost()
	_active = false
	_building_name = ""
	_building_stats = {}
	_current_grid_pos = Vector2i(-1, -1)
	_is_valid = false


func _create_building(bname: String, grid_pos: Vector2i, footprint: Vector2i) -> Node2D:
	var building := Node2D.new()
	building.name = "Building_%s_%d_%d" % [bname, grid_pos.x, grid_pos.y]
	building.set_script(BuildingScript)
	building.position = IsoUtils.grid_to_screen(Vector2(grid_pos))
	building.building_name = bname
	building.footprint = footprint
	building.grid_pos = grid_pos
	building.owner_id = _player_id
	building.max_hp = int(_building_stats.get("hp", 100))
	building.entity_category = "own_building" if _player_id == 0 else "enemy_building"
	# Start under construction
	building.under_construction = true
	building.build_progress = 0.0
	building.hp = 0
	building._build_time = float(_building_stats.get("build_time", 25))
	get_parent().add_child(building)
	return building


func _create_ghost() -> void:
	_cleanup_ghost()
	_ghost = Node2D.new()
	_ghost.set_script(GhostScript)
	_ghost.z_index = 200
	get_parent().add_child(_ghost)
	_ghost.setup(_get_footprint())


func _cleanup_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
		_ghost = null


func _get_footprint() -> Vector2i:
	var fp: Array = _building_stats.get("footprint", [1, 1])
	return Vector2i(int(fp[0]), int(fp[1]))


func _parse_costs(raw_costs: Dictionary) -> Dictionary:
	var costs: Dictionary = {}
	for key: String in raw_costs:
		var lower_key := key.to_lower()
		if RESOURCE_NAME_TO_TYPE.has(lower_key):
			costs[RESOURCE_NAME_TO_TYPE[lower_key]] = int(raw_costs[key])
	return costs


func _load_building_stats(building_name: String) -> Dictionary:
	if Engine.has_singleton("DataLoader"):
		return DataLoader.get_building_stats(building_name)
	var dl: Node = null
	if is_instance_valid(Engine.get_main_loop()):
		dl = Engine.get_main_loop().root.get_node_or_null("DataLoader")
	if dl != null and dl.has_method("get_building_stats"):
		return dl.get_building_stats(building_name)
	return {}


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	if _camera == null:
		return screen_pos
	var vp_size := _camera.get_viewport_rect().size
	var offset := screen_pos - vp_size / 2.0
	return _camera.position + offset / _camera.zoom


func save_state() -> Dictionary:
	var buildings_out: Array[Dictionary] = []
	for entry: Dictionary in _placed_buildings:
		var out := {
			"building_name": entry.get("building_name", ""),
			"grid_pos": entry.get("grid_pos", [0, 0]),
			"player_id": entry.get("player_id", 0),
		}
		var node: Node2D = entry.get("node")
		if is_instance_valid(node):
			out["under_construction"] = node.under_construction
			out["build_progress"] = node.build_progress
		buildings_out.append(out)
	return {"placed_buildings": buildings_out}


func load_state(data: Dictionary) -> void:
	var buildings_data: Array = data.get("placed_buildings", [])
	for entry: Dictionary in buildings_data:
		var bname: String = entry.get("building_name", "")
		var pos_arr: Array = entry.get("grid_pos", [0, 0])
		var pid: int = int(entry.get("player_id", 0))
		var grid_pos := Vector2i(int(pos_arr[0]), int(pos_arr[1]))
		var stats := _load_building_stats(bname)
		if stats.is_empty():
			continue
		var fp: Array = stats.get("footprint", [1, 1])
		var footprint := Vector2i(int(fp[0]), int(fp[1]))
		_player_id = pid
		var building := _create_building(bname, grid_pos, footprint)
		# Restore construction state from saved data
		if entry.has("under_construction"):
			building.under_construction = bool(entry["under_construction"])
		if entry.has("build_progress"):
			building.build_progress = float(entry["build_progress"])
			building.hp = int(building.build_progress * building.max_hp)
		if not building.under_construction:
			building.hp = building.max_hp
		if _pathfinder != null:
			var cells := BuildingValidator.get_footprint_cells(grid_pos, footprint)
			for cell in cells:
				_pathfinder.set_cell_solid(cell, true)
		if _target_detector != null:
			_target_detector.register_entity(building)
		(
			_placed_buildings
			. append(
				{
					"building_name": bname,
					"grid_pos": [grid_pos.x, grid_pos.y],
					"player_id": pid,
					"node": building,
				}
			)
		)
