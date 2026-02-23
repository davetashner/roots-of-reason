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


func _ready() -> void:
	_setup_map()
	_setup_camera()
	_setup_pathfinding()
	_setup_target_detection()
	_setup_input()
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


func _setup_units() -> void:
	for i in UNIT_POSITIONS.size():
		var unit := Node2D.new()
		unit.name = "Unit_%d" % i
		unit.set_script(UnitScript)
		unit.position = IsoUtils.grid_to_screen(Vector2(UNIT_POSITIONS[i]))
		add_child(unit)
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
	# Resource nodes (green diamonds)
	var resource_positions: Array[Vector2i] = [Vector2i(6, 9), Vector2i(8, 11)]
	for i in resource_positions.size():
		var res_node := Node2D.new()
		res_node.name = "Resource_%d" % i
		res_node.set_script(load("res://scripts/prototype/prototype_resource_node.gd"))
		res_node.position = IsoUtils.grid_to_screen(Vector2(resource_positions[i]))
		add_child(res_node)
		_target_detector.register_entity(res_node)
	# Own building (blue square)
	var building := Node2D.new()
	building.name = "Building_0"
	building.set_script(load("res://scripts/prototype/prototype_building.gd"))
	building.position = IsoUtils.grid_to_screen(Vector2(Vector2i(4, 4)))
	building.owner_id = 0
	add_child(building)
	_target_detector.register_entity(building)


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
