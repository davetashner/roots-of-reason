extends Node2D
## Main prototype scene — assembles map, camera, units, input, and HUD
## programmatically at runtime.

const UnitScript := preload("res://scripts/prototype/prototype_unit.gd")

const UNIT_POSITIONS: Array[Vector2i] = [
	Vector2i(3, 3),
	Vector2i(5, 2),
	Vector2i(4, 6),
	Vector2i(7, 4),
	Vector2i(10, 10),
	Vector2i(8, 12),
	Vector2i(15, 8),
	Vector2i(12, 14),
]

var _camera: Camera2D
var _input_handler: Node
var _map_node: Node2D
var _pathfinder: Node
var _target_detector: Node
var _cursor_overlay: Node
var _building_placer: Node


func _ready() -> void:
	_setup_map()
	_setup_camera()
	_setup_pathfinding()
	_setup_target_detection()
	_setup_input()
	_setup_building_placer()
	_setup_units()
	_setup_demo_entities()
	_setup_hud()


func _setup_map() -> void:
	_map_node = Node2D.new()
	_map_node.name = "Map"
	_map_node.set_script(load("res://scripts/prototype/prototype_map.gd"))
	add_child(_map_node)


func _setup_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera"
	_camera.set_script(load("res://scripts/prototype/prototype_camera.gd"))
	# Center on middle of 20x20 map
	var center := IsoUtils.grid_to_screen(Vector2(10, 10))
	_camera.position = center
	_camera.enabled = true
	add_child(_camera)
	# Compute map bounds from corner grid positions and pass to camera
	var map_size := 20
	var corners: Array[Vector2] = [
		IsoUtils.grid_to_screen(Vector2(0, 0)),
		IsoUtils.grid_to_screen(Vector2(map_size, 0)),
		IsoUtils.grid_to_screen(Vector2(0, map_size)),
		IsoUtils.grid_to_screen(Vector2(map_size, map_size)),
	]
	var min_pos := corners[0]
	var max_pos := corners[0]
	for corner in corners:
		min_pos.x = minf(min_pos.x, corner.x)
		min_pos.y = minf(min_pos.y, corner.y)
		max_pos.x = maxf(max_pos.x, corner.x)
		max_pos.y = maxf(max_pos.y, corner.y)
	var bounds := Rect2(min_pos, max_pos - min_pos)
	_camera.setup(bounds)


func _setup_pathfinding() -> void:
	_pathfinder = Node.new()
	_pathfinder.name = "PathfindingGrid"
	_pathfinder.set_script(load("res://scripts/prototype/pathfinding_grid.gd"))
	add_child(_pathfinder)
	_pathfinder.build(_map_node.get_map_size(), _map_node._tile_grid, {})


func _setup_target_detection() -> void:
	_target_detector = Node.new()
	_target_detector.name = "TargetDetector"
	_target_detector.set_script(load("res://scripts/prototype/target_detector.gd"))
	add_child(_target_detector)


func _setup_input() -> void:
	_input_handler = Node.new()
	_input_handler.name = "InputHandler"
	_input_handler.set_script(load("res://scripts/prototype/prototype_input.gd"))
	add_child(_input_handler)
	if _input_handler.has_method("setup"):
		_input_handler.setup(_camera, _pathfinder, _target_detector)


func _setup_building_placer() -> void:
	_building_placer = Node.new()
	_building_placer.name = "BuildingPlacer"
	_building_placer.set_script(load("res://scripts/prototype/building_placer.gd"))
	add_child(_building_placer)
	_building_placer.setup(_camera, _pathfinder, _map_node, _target_detector)
	_building_placer.building_placed.connect(_on_building_placed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_B:
			if _building_placer != null and not _building_placer.is_active():
				_building_placer.start_placement("house", 0)


func _setup_units() -> void:
	for i in UNIT_POSITIONS.size():
		var unit := Node2D.new()
		unit.name = "Unit_%d" % i
		unit.set_script(UnitScript)
		unit.position = IsoUtils.grid_to_screen(Vector2(UNIT_POSITIONS[i]))
		unit.unit_type = "villager"
		add_child(unit)
		unit._scene_root = self
		# Register with input handler after both are in tree
		if _input_handler.has_method("register_unit"):
			_input_handler.register_unit(unit)
		if _target_detector != null:
			_target_detector.register_entity(unit)


func _setup_demo_entities() -> void:
	# Enemy units (red, owner_id = 1)
	var enemy_positions: Array[Vector2i] = [Vector2i(16, 3), Vector2i(17, 5)]
	for i in enemy_positions.size():
		var enemy := Node2D.new()
		enemy.name = "Enemy_%d" % i
		enemy.set_script(UnitScript)
		enemy.position = IsoUtils.grid_to_screen(Vector2(enemy_positions[i]))
		enemy.unit_color = Color(0.9, 0.2, 0.2)
		enemy.owner_id = 1
		add_child(enemy)
		_target_detector.register_entity(enemy)
	# Resource nodes — typed and depletable
	var ResourceNodeScript: GDScript = load("res://scripts/prototype/prototype_resource_node.gd")
	var berry_positions: Array[Vector2i] = [Vector2i(6, 9), Vector2i(8, 11)]
	for i in berry_positions.size():
		var res_node := Node2D.new()
		res_node.name = "Resource_berry_%d" % i
		res_node.set_script(ResourceNodeScript)
		res_node.position = IsoUtils.grid_to_screen(Vector2(berry_positions[i]))
		add_child(res_node)
		res_node.setup("berry_bush")
		res_node.depleted.connect(_on_resource_depleted)
		_target_detector.register_entity(res_node)
	var tree_positions: Array[Vector2i] = [Vector2i(12, 6), Vector2i(13, 7), Vector2i(14, 6)]
	for i in tree_positions.size():
		var res_node := Node2D.new()
		res_node.name = "Resource_tree_%d" % i
		res_node.set_script(ResourceNodeScript)
		res_node.position = IsoUtils.grid_to_screen(Vector2(tree_positions[i]))
		add_child(res_node)
		res_node.setup("tree")
		res_node.depleted.connect(_on_resource_depleted)
		_target_detector.register_entity(res_node)
	# Own building (blue, 3x3 town center) — fully built
	var building := Node2D.new()
	building.name = "Building_0"
	building.set_script(load("res://scripts/prototype/prototype_building.gd"))
	var bld_pos := Vector2i(4, 4)
	building.position = IsoUtils.grid_to_screen(Vector2(bld_pos))
	building.owner_id = 0
	building.building_name = "town_center"
	building.footprint = Vector2i(3, 3)
	building.grid_pos = bld_pos
	building.hp = 2400
	building.max_hp = 2400
	building.under_construction = false
	building.build_progress = 1.0
	add_child(building)
	_target_detector.register_entity(building)
	# Mark footprint cells solid
	var cells := BuildingValidator.get_footprint_cells(bld_pos, Vector2i(3, 3))
	for cell in cells:
		_pathfinder.set_cell_solid(cell, true)


func _on_building_placed(building: Node2D) -> void:
	var idle_unit := _find_nearest_idle_unit(building.global_position)
	if idle_unit != null and idle_unit.has_method("assign_build_target"):
		idle_unit.assign_build_target(building)


func _find_nearest_idle_unit(target_pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for child in get_children():
		if not child.has_method("is_idle"):
			continue
		if "owner_id" in child and child.owner_id != 0:
			continue
		if not child.is_idle():
			continue
		var dist: float = child.global_position.distance_to(target_pos)
		if dist < best_dist:
			best_dist = dist
			best = child
	return best


func _on_resource_depleted(node: Node2D) -> void:
	if _target_detector != null and _target_detector.has_method("unregister_entity"):
		_target_detector.unregister_entity(node)


func _setup_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.set_script(load("res://scripts/prototype/prototype_hud.gd"))
	add_child(hud)
	# Connect camera and input handler
	if hud.has_method("setup"):
		hud.setup(_camera, _input_handler)
	# Cursor overlay for command context labels
	_cursor_overlay = CanvasLayer.new()
	_cursor_overlay.name = "CursorOverlay"
	_cursor_overlay.set_script(load("res://scripts/prototype/cursor_overlay.gd"))
	add_child(_cursor_overlay)
	_input_handler._cursor_overlay = _cursor_overlay
	# Resource bar HUD
	_setup_resource_bar()


func _setup_resource_bar() -> void:
	(
		ResourceManager
		. init_player(
			0,
			{
				ResourceManager.ResourceType.FOOD: 200,
				ResourceManager.ResourceType.WOOD: 200,
				ResourceManager.ResourceType.STONE: 100,
				ResourceManager.ResourceType.GOLD: 100,
				ResourceManager.ResourceType.KNOWLEDGE: 0,
			}
		)
	)
	var resource_bar_layer := CanvasLayer.new()
	resource_bar_layer.name = "ResourceBar"
	resource_bar_layer.layer = 10
	add_child(resource_bar_layer)
	var resource_bar := PanelContainer.new()
	resource_bar.name = "ResourceBarPanel"
	resource_bar.set_script(load("res://scripts/ui/resource_bar.gd"))
	resource_bar_layer.add_child(resource_bar)
