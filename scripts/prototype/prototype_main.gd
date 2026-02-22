extends Node2D
## Main prototype scene — assembles map, camera, units, input, and HUD
## programmatically at runtime.

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


func _ready() -> void:
	_setup_map()
	_setup_camera()
	_setup_input()
	_setup_units()
	_setup_hud()


func _setup_map() -> void:
	var map_node := Node2D.new()
	map_node.name = "Map"
	map_node.set_script(load("res://scripts/prototype/prototype_map.gd"))
	add_child(map_node)


func _setup_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera"
	_camera.set_script(load("res://scripts/prototype/prototype_camera.gd"))
	# Center on middle of 20x20 map
	var center := IsoUtils.grid_to_screen(Vector2(10, 10))
	_camera.position = center
	_camera.enabled = true
	add_child(_camera)


func _setup_input() -> void:
	_input_handler = Node.new()
	_input_handler.name = "InputHandler"
	_input_handler.set_script(load("res://scripts/prototype/prototype_input.gd"))
	add_child(_input_handler)


func _setup_units() -> void:
	for i in UNIT_POSITIONS.size():
		var unit := Node2D.new()
		unit.name = "Unit_%d" % i
		unit.set_script(load("res://scripts/prototype/prototype_unit.gd"))
		unit.position = IsoUtils.grid_to_screen(Vector2(UNIT_POSITIONS[i]))
		add_child(unit)
		# Register with input handler after both are in tree
		if _input_handler.has_method("register_unit"):
			_input_handler.register_unit(unit)


func _setup_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.set_script(load("res://scripts/prototype/prototype_hud.gd"))
	add_child(hud)
	# Connect camera and input handler
	if hud.has_method("setup"):
		hud.setup(_camera, _input_handler)
