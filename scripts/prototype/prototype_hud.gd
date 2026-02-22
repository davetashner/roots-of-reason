extends CanvasLayer
## Simple HUD showing zoom level, cursor tile coords, and selection count.

var _label: Label
var _camera: Camera2D = null
var _input_handler: Node = null


func _ready() -> void:
	layer = 10
	_label = Label.new()
	_label.position = Vector2(10, 10)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)


func setup(camera: Camera2D, input_handler: Node) -> void:
	_camera = camera
	_input_handler = input_handler


func _process(_delta: float) -> void:
	if _camera == null:
		return

	var zoom_level := _camera.zoom.x
	var mouse_screen := get_viewport().get_mouse_position()
	var vp_size := get_viewport().get_visible_rect().size
	var world_pos := _camera.position + (mouse_screen - vp_size / 2.0) / _camera.zoom
	var grid_pos := IsoUtils.snap_to_grid(world_pos)

	var selected_count := 0
	if _input_handler != null and _input_handler.has_method("get_selected_count"):
		selected_count = _input_handler.get_selected_count()

	_label.text = "Zoom: %.1fx | Tile: (%d, %d) | Selected: %d" % [zoom_level, grid_pos.x, grid_pos.y, selected_count]
