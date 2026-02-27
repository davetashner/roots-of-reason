class_name HistoricalEventVFX
extends Node
## Visual feedback for historical events: plague dark clouds, renaissance golden
## glow, and phoenix rebirth effect. Mirrors pandemic_vfx.gd pattern.

var _scene_root: Node2D = null
var _camera: Camera2D = null
var _notification_panel: Control = null

# VFX constants
var _flash_duration: float = 0.5
var _circle_duration: float = 2.5
var _circle_max_radius: float = 60.0

# Colors
var _plague_color: Color = Color(0.5, 0.1, 0.15, 0.8)
var _plague_flash_color: Color = Color(0.4, 0.0, 0.1, 0.2)
var _renaissance_color: Color = Color(0.85, 0.75, 0.2, 0.8)
var _renaissance_flash_color: Color = Color(1.0, 0.9, 0.3, 0.15)
var _phoenix_color: Color = Color(1.0, 0.6, 0.0, 0.9)
var _phoenix_flash_color: Color = Color(1.0, 0.5, 0.0, 0.2)


func setup(
	scene_root: Node2D,
	camera: Camera2D,
	notification_panel: Control,
) -> void:
	_scene_root = scene_root
	_camera = camera
	_notification_panel = notification_panel


func play_plague_effect(world_pos: Vector2, player_id: int) -> void:
	_spawn_circle(world_pos, _plague_color)
	if player_id == 0:
		_play_screen_flash(_plague_flash_color)
		_show_notification("The Black Plague has arrived. Pray for your people.")
	# Audio stub for future AudioManager integration
	# _play_plague_audio()


func play_plague_end(player_id: int) -> void:
	if player_id == 0:
		_show_notification("The plague has passed. Survivors grow stronger.")


func play_renaissance_effect(world_pos: Vector2, player_id: int) -> void:
	_spawn_circle(world_pos, _renaissance_color)
	if player_id == 0:
		_play_screen_flash(_renaissance_flash_color)
		_show_notification("A Renaissance dawns! Knowledge and commerce flourish.")
	# Audio stub for future AudioManager integration
	# _play_renaissance_audio()


func play_phoenix_effect(world_pos: Vector2, player_id: int) -> void:
	_spawn_circle(world_pos, _phoenix_color)
	if player_id == 0:
		_play_screen_flash(_phoenix_flash_color)
		_show_notification("From death, rebirth \u2014 the Phoenix rises!")
	# Audio stub for future AudioManager integration
	# _play_phoenix_audio()


func play_renaissance_end(player_id: int) -> void:
	if player_id == 0:
		_show_notification("The Renaissance fades, but its legacy endures.")


func _spawn_circle(world_position: Vector2, color: Color) -> Node2D:
	if _scene_root == null:
		return null
	var glow := _GlowCircle.new()
	glow.position = world_position
	glow.z_index = 95
	glow.glow_color = color
	glow.max_radius = _circle_max_radius
	_scene_root.add_child(glow)
	var tween := glow.create_tween()
	tween.set_parallel(true)
	tween.tween_property(glow, "current_radius", _circle_max_radius, _circle_duration)
	tween.tween_property(glow, "modulate:a", 0.0, _circle_duration)
	tween.set_parallel(false)
	tween.tween_callback(glow.queue_free)
	return glow


func _play_screen_flash(color: Color) -> ColorRect:
	if _scene_root == null:
		return null
	var layer := CanvasLayer.new()
	layer.layer = 100
	_scene_root.add_child(layer)
	var flash := ColorRect.new()
	flash.color = color
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
		_notification_panel.notify_center(message, 5.0)
	elif _notification_panel.has_method("notify"):
		_notification_panel.notify(message, "warning")


# -- Audio stubs for future AudioManager integration --
# func _play_plague_audio() -> void:
#     pass
# func _play_renaissance_audio() -> void:
#     pass
# func _play_phoenix_audio() -> void:
#     pass


func save_state() -> Dictionary:
	return {}


func load_state(_data: Dictionary) -> void:
	pass


class _GlowCircle:
	extends Node2D
	## Expanding circle effect — used for both dark plague clouds and golden glow.

	var max_radius: float = 60.0
	var current_radius: float = 0.0
	var glow_color: Color = Color(0.85, 0.75, 0.2, 0.8)

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if current_radius <= 0.0:
			return
		# Outer expanding ring
		draw_arc(Vector2.ZERO, current_radius, 0, TAU, 32, glow_color, 2.5)
		# Inner translucent filled circles for cloud/glow effect
		var inner_color := Color(glow_color.r, glow_color.g, glow_color.b, 0.12)
		draw_circle(Vector2(-10, -6), current_radius * 0.4, inner_color)
		draw_circle(Vector2(8, 4), current_radius * 0.35, inner_color)
		draw_circle(Vector2(-3, 9), current_radius * 0.3, inner_color)
