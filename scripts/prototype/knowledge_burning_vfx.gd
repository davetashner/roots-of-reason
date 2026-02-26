class_name KnowledgeBurningVFX
extends Node
## Provides visual and notification feedback when tech regression occurs.
## Creates expanding amber circle at TC position, screen flash, screen shake,
## and center-screen notification for the affected player.

var _config: Dictionary = {}
var _camera: Camera2D = null
var _notification_panel: Control = null
var _scene_root: Node2D = null

# Parsed config values (loaded from knowledge_burning.json vfx block)
var _flash_duration: float = 0.3
var _flash_opacity: float = 0.2
var _shake_amplitude: float = 2.0
var _shake_duration: float = 0.5
var _notification_duration: float = 4.0
var _amber_color: Color = Color(1.0, 0.75, 0.2, 1.0)
var _circle_duration: float = 1.5
var _circle_max_radius: float = 40.0


func setup(
	scene_root: Node2D,
	camera: Camera2D,
	notification_panel: Control,
) -> void:
	_scene_root = scene_root
	_camera = camera
	_notification_panel = notification_panel
	_load_config()


func _load_config() -> void:
	var kb_cfg: Dictionary = DataLoader.get_settings("knowledge_burning")
	if kb_cfg.is_empty():
		return
	_config = kb_cfg.get("vfx", {})
	if _config.is_empty():
		return
	_flash_duration = float(_config.get("screen_flash_duration", _flash_duration))
	_flash_opacity = float(_config.get("screen_flash_opacity", _flash_opacity))
	_shake_amplitude = float(_config.get("screen_shake_amplitude", _shake_amplitude))
	_shake_duration = float(_config.get("screen_shake_duration", _shake_duration))
	_notification_duration = float(_config.get("notification_duration", _notification_duration))
	var color_arr: Array = _config.get("amber_color", [])
	if color_arr.size() == 4:
		_amber_color = Color(color_arr[0], color_arr[1], color_arr[2], color_arr[3])
	_circle_duration = float(_config.get("expand_circle_duration", _circle_duration))
	_circle_max_radius = float(_config.get("expand_circle_max_radius", _circle_max_radius))


func play_burning_effect(
	world_position: Vector2,
	tech_name: String,
	tech_description: String,
	player_id: int,
	attacker_id: int,
) -> void:
	## Main entry point: triggers all VFX for a knowledge burning event.
	_spawn_expanding_circle(world_position)
	if player_id == 0:
		_play_screen_flash()
		_play_screen_shake()
		_show_defender_notification(tech_name)
		_show_event_log_entry(tech_name, tech_description)
	elif attacker_id == 0:
		_show_attacker_notification(tech_name)


func _spawn_expanding_circle(world_position: Vector2) -> Node2D:
	if _scene_root == null:
		return null
	var circle := _AmberCircle.new()
	circle.position = world_position
	circle.z_index = 95
	circle.ring_color = _amber_color
	circle.max_radius = _circle_max_radius
	_scene_root.add_child(circle)
	var tween := circle.create_tween()
	tween.set_parallel(true)
	tween.tween_property(circle, "current_radius", _circle_max_radius, _circle_duration)
	tween.tween_property(circle, "modulate:a", 0.0, _circle_duration)
	tween.set_parallel(false)
	tween.tween_callback(circle.queue_free)
	return circle


func _play_screen_flash() -> ColorRect:
	if _scene_root == null:
		return null
	# Create a CanvasLayer at high layer so it overlays everything
	var layer := CanvasLayer.new()
	layer.layer = 100
	_scene_root.add_child(layer)
	var flash := ColorRect.new()
	flash.color = Color(_amber_color.r, _amber_color.g, _amber_color.b, _flash_opacity)
	flash.anchor_right = 1.0
	flash.anchor_bottom = 1.0
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash)
	var tween := flash.create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, _flash_duration)
	tween.tween_callback(layer.queue_free)
	return flash


func _play_screen_shake() -> void:
	if _camera == null:
		return
	var original_offset := _camera.offset
	var shake_tween := _camera.create_tween()
	var steps: int = int(_shake_duration / 0.05)
	if steps < 1:
		steps = 1
	for i in steps:
		var offset_x: float = randf_range(-_shake_amplitude, _shake_amplitude)
		var offset_y: float = randf_range(-_shake_amplitude, _shake_amplitude)
		shake_tween.tween_property(_camera, "offset", original_offset + Vector2(offset_x, offset_y), 0.05)
	shake_tween.tween_property(_camera, "offset", original_offset, 0.05)


func _show_defender_notification(tech_name: String) -> void:
	if _notification_panel == null:
		return
	if _notification_panel.has_method("notify_center"):
		_notification_panel.notify_center("Knowledge Lost: %s" % tech_name, _notification_duration)
	elif _notification_panel.has_method("notify"):
		_notification_panel.notify("Knowledge Lost: %s" % tech_name, "warning")


func _show_attacker_notification(tech_name: String) -> void:
	if _notification_panel == null:
		return
	if _notification_panel.has_method("notify"):
		_notification_panel.notify("Enemy knowledge destroyed: %s" % tech_name, "info")


func _show_event_log_entry(tech_name: String, tech_description: String) -> void:
	if _notification_panel == null:
		return
	var minutes: int = int(GameManager.game_time) / 60
	var seconds: int = int(GameManager.game_time) % 60
	var timestamp: String = "%02d:%02d" % [minutes, seconds]
	var message: String = "[%s] Your city was sacked! Lost: %s (%s)" % [timestamp, tech_name, tech_description]
	if _notification_panel.has_method("notify"):
		_notification_panel.notify(message, "alert")


func get_amber_color() -> Color:
	return _amber_color


func save_state() -> Dictionary:
	return {}


func load_state(_data: Dictionary) -> void:
	pass


## Expanding amber circle visual effect node.
class _AmberCircle:
	extends Node2D

	var max_radius: float = 40.0
	var current_radius: float = 0.0
	var ring_color: Color = Color(1.0, 0.75, 0.2, 1.0)

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if current_radius > 0.0:
			draw_arc(Vector2.ZERO, current_radius, 0, TAU, 32, ring_color, 2.0)
