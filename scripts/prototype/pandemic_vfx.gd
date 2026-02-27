class_name PandemicVFX
extends Node
## Visual feedback for pandemic events: green expanding circles, screen flash,
## and notification messages. Mirrors knowledge_burning_vfx.gd pattern.

var _scene_root: Node2D = null
var _camera: Camera2D = null
var _notification_panel: Control = null

# VFX constants
var _flash_duration: float = 0.4
var _flash_color: Color = Color(0.0, 0.8, 0.2, 0.15)
var _circle_duration: float = 2.0
var _circle_max_radius: float = 50.0
var _plague_color: Color = Color(0.2, 0.75, 0.1, 0.8)


func setup(
	scene_root: Node2D,
	camera: Camera2D,
	notification_panel: Control,
) -> void:
	_scene_root = scene_root
	_camera = camera
	_notification_panel = notification_panel


func play_outbreak_effect(world_pos: Vector2, player_id: int) -> void:
	_spawn_plague_cloud(world_pos)
	if player_id == 0:
		_play_screen_flash()
		_show_notification("Plague Outbreak! Villager productivity reduced.")


func play_outbreak_end(player_id: int) -> void:
	if player_id == 0:
		_show_notification("The plague has passed.")


func _spawn_plague_cloud(world_position: Vector2) -> Node2D:
	if _scene_root == null:
		return null
	var cloud := _PlagueCloud.new()
	cloud.position = world_position
	cloud.z_index = 95
	cloud.plague_color = _plague_color
	cloud.max_radius = _circle_max_radius
	_scene_root.add_child(cloud)
	var tween := cloud.create_tween()
	tween.set_parallel(true)
	tween.tween_property(cloud, "current_radius", _circle_max_radius, _circle_duration)
	tween.tween_property(cloud, "modulate:a", 0.0, _circle_duration)
	tween.set_parallel(false)
	tween.tween_callback(cloud.queue_free)
	return cloud


func _play_screen_flash() -> ColorRect:
	if _scene_root == null:
		return null
	var layer := CanvasLayer.new()
	layer.layer = 100
	_scene_root.add_child(layer)
	var flash := ColorRect.new()
	flash.color = _flash_color
	flash.anchor_right = 1.0
	flash.anchor_bottom = 1.0
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash)
	var tween := flash.create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, _flash_duration)
	tween.tween_callback(layer.queue_free)
	return flash


func _show_notification(message: String) -> void:
	if _notification_panel == null:
		return
	if _notification_panel.has_method("notify_center"):
		_notification_panel.notify_center(message, 4.0)
	elif _notification_panel.has_method("notify"):
		_notification_panel.notify(message, "warning")


# -- Audio stub for future AudioManager integration --
# func _play_plague_audio() -> void:
#     pass


func save_state() -> Dictionary:
	return {}


func load_state(_data: Dictionary) -> void:
	pass


class _PlagueCloud:
	extends Node2D
	## Green particle cloud effect — multiple translucent circles that expand and fade.

	var max_radius: float = 50.0
	var current_radius: float = 0.0
	var plague_color: Color = Color(0.2, 0.75, 0.1, 0.8)

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if current_radius <= 0.0:
			return
		# Main expanding ring
		draw_arc(Vector2.ZERO, current_radius, 0, TAU, 32, plague_color, 2.0)
		# Inner translucent filled circles for cloud effect
		var inner_color := Color(plague_color.r, plague_color.g, plague_color.b, 0.15)
		draw_circle(Vector2(-8, -5), current_radius * 0.4, inner_color)
		draw_circle(Vector2(6, 3), current_radius * 0.35, inner_color)
		draw_circle(Vector2(-2, 7), current_radius * 0.3, inner_color)
