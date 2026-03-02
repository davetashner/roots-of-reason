extends CanvasLayer
## Simple HUD showing zoom level, cursor tile coords, and selection count.
## Also provides an idle villager finder button with count badge.

const IdleVillagerFinderScript := preload("res://scripts/prototype/idle_villager_finder.gd")

var _label: Label
var _camera: Camera2D = null
var _input_handler: Node = null

var _idle_button: Button = null
var _idle_finder: RefCounted = null
var _update_timer: float = 0.0
var _update_interval: float = 0.5
var _badge_color: Color = Color(0.9, 0.8, 0.1, 1.0)
var _badge_zero_color: Color = Color(0.5, 0.5, 0.5, 0.7)
var _hotkey_label: String = "(.)"


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
	_idle_finder = IdleVillagerFinderScript.new()
	_load_config()
	_create_idle_button()


func _load_config() -> void:
	var cfg: Dictionary = GameUtils.dl_settings("idle_villager_finder")
	if cfg.is_empty():
		return
	_update_interval = float(cfg.get("update_interval", _update_interval))
	_hotkey_label = str(cfg.get("hotkey_label", _hotkey_label))
	var bc: Array = cfg.get("badge_color", [])
	if bc.size() == 4:
		_badge_color = Color(bc[0], bc[1], bc[2], bc[3])
	var bzc: Array = cfg.get("badge_zero_color", [])
	if bzc.size() == 4:
		_badge_zero_color = Color(bzc[0], bzc[1], bzc[2], bzc[3])


func _create_idle_button() -> void:
	_idle_button = Button.new()
	_idle_button.text = "Idle: 0 %s" % _hotkey_label
	var cfg: Dictionary = GameUtils.dl_settings("idle_villager_finder")
	var font_size: int = int(cfg.get("button_font_size", 14))
	var pos: Array = cfg.get("button_position", [10, 60])
	var min_size: Array = cfg.get("button_min_size", [120, 32])
	_idle_button.add_theme_font_size_override("font_size", font_size)
	_idle_button.position = Vector2(float(pos[0]), float(pos[1]))
	_idle_button.custom_minimum_size = Vector2(float(min_size[0]), float(min_size[1]))
	_idle_button.pressed.connect(_on_idle_button_pressed)
	add_child(_idle_button)


func setup(camera: Camera2D, input_handler: Node) -> void:
	_camera = camera
	_input_handler = input_handler
	if _input_handler != null and "_units" in _input_handler:
		_idle_finder.setup(_input_handler._units)


func get_idle_finder() -> RefCounted:
	return _idle_finder


func cycle_to_idle_villager() -> void:
	var unit: Node = _idle_finder.cycle_next()
	if unit == null:
		return
	# Center camera on the idle villager
	if _camera != null:
		_camera.position = unit.global_position
	# Select the villager
	if _input_handler != null and _input_handler.has_method("_deselect_all"):
		_input_handler._deselect_all()
	if unit.has_method("select"):
		unit.select()


func _on_idle_button_pressed() -> void:
	cycle_to_idle_villager()


func _process(delta: float) -> void:
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

	var line1 := "Zoom: %.1fx | Tile: (%d, %d) | Selected: %d" % [zoom_level, grid_pos.x, grid_pos.y, selected_count]
	var clock := GameManager.get_clock_display()
	var speed := GameManager.get_speed_display()
	var line2 := "Time: %s | Speed: %s" % [clock, speed]
	if GameManager.is_paused:
		line2 += " [PAUSED]"
	_label.text = line1 + "\n" + line2

	# Update idle count periodically
	_update_timer += delta
	if _update_timer >= _update_interval:
		_update_timer = 0.0
		_refresh_idle_count()


func _refresh_idle_count() -> void:
	var count := _idle_finder.get_idle_count()
	_idle_button.text = "Idle: %d %s" % [count, _hotkey_label]
	if count > 0:
		_idle_button.add_theme_color_override("font_color", _badge_color)
	else:
		_idle_button.add_theme_color_override("font_color", _badge_zero_color)
