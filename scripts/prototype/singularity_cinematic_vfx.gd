class_name SingularityCinematicVFX
extends Node
## Plays a dramatic cinematic sequence when AGI Core research completes.
## Creates screen flash, expanding energy wave, white fade overlay, and
## title/subtitle text before emitting cinematic_complete.

signal cinematic_complete

var _config: Dictionary = {}
var _camera: Camera2D = null
var _scene_root: Node2D = null

# Parsed config values (loaded from singularity_cinematic.json)
var _flash_color: Color = Color(0.7, 0.9, 1.0, 0.4)
var _flash_duration: float = 0.5
var _shake_amplitude: float = 4.0
var _shake_duration: float = 0.8
var _wave_color: Color = Color(0.3, 0.8, 1.0, 0.8)
var _wave_duration: float = 2.0
var _wave_max_radius: float = 80.0
var _fade_duration: float = 1.5
var _title_text: String = "The Singularity Has Been Achieved"
var _subtitle_text: String = "The last invention humanity needs to make."
var _title_fade_in: float = 1.0
var _subtitle_delay: float = 1.5
var _subtitle_fade_in: float = 0.8
var _total_duration: float = 6.0

# Track VFX nodes for cleanup
var _vfx_nodes: Array[Node] = []


func setup(scene_root: Node2D, camera: Camera2D) -> void:
	_scene_root = scene_root
	_camera = camera
	_load_config()


func _load_config() -> void:
	_config = DataLoader.get_settings("singularity_cinematic")
	if _config.is_empty():
		return
	_flash_duration = float(_config.get("screen_flash_duration", _flash_duration))
	_shake_amplitude = float(_config.get("screen_shake_amplitude", _shake_amplitude))
	_shake_duration = float(_config.get("screen_shake_duration", _shake_duration))
	_wave_duration = float(_config.get("energy_wave_duration", _wave_duration))
	_wave_max_radius = float(_config.get("energy_wave_max_radius", _wave_max_radius))
	_fade_duration = float(_config.get("fade_to_white_duration", _fade_duration))
	_title_text = str(_config.get("title_text", _title_text))
	_subtitle_text = str(_config.get("subtitle_text", _subtitle_text))
	_title_fade_in = float(_config.get("title_fade_in_duration", _title_fade_in))
	_subtitle_delay = float(_config.get("subtitle_delay", _subtitle_delay))
	_subtitle_fade_in = float(_config.get("subtitle_fade_in_duration", _subtitle_fade_in))
	_total_duration = float(_config.get("total_duration", _total_duration))
	var flash_arr: Array = _config.get("screen_flash_color", [])
	if flash_arr.size() == 4:
		_flash_color = Color(flash_arr[0], flash_arr[1], flash_arr[2], flash_arr[3])
	var wave_arr: Array = _config.get("energy_wave_color", [])
	if wave_arr.size() == 4:
		_wave_color = Color(wave_arr[0], wave_arr[1], wave_arr[2], wave_arr[3])


func play_cinematic() -> void:
	## Main entry point: plays full singularity cinematic sequence.
	var master := create_tween()
	master.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

	# Phase 1 (0s): Screen flash + screen shake (parallel)
	master.tween_callback(_play_screen_flash)
	master.tween_callback(_play_screen_shake)

	# Phase 2 (0.5s): Energy wave from center
	master.tween_interval(0.5)
	master.tween_callback(_spawn_energy_wave)

	# Phase 3 (1.5s): Fade to white overlay
	master.tween_interval(1.0)
	master.tween_callback(_play_fade_overlay)

	# Phase 4 (3.0s): Title text
	master.tween_interval(1.5)
	master.tween_callback(_show_title_text)

	# Phase 5 (4.5s): Subtitle text
	master.tween_interval(_subtitle_delay)
	master.tween_callback(_show_subtitle_text)

	# Phase 6 (6.0s): Complete
	var remaining: float = _total_duration - 4.5 - _subtitle_delay
	if remaining < 0.0:
		remaining = 0.5
	master.tween_interval(remaining)
	master.tween_callback(_on_cinematic_finished)


func _play_screen_flash() -> void:
	if _scene_root == null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	_scene_root.add_child(layer)
	_vfx_nodes.append(layer)
	var flash := ColorRect.new()
	flash.color = _flash_color
	flash.anchor_right = 1.0
	flash.anchor_bottom = 1.0
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash)
	var tween := flash.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(flash, "modulate:a", 0.0, _flash_duration)


func _play_screen_shake() -> void:
	if _camera == null:
		return
	var original_offset := _camera.offset
	var shake_tween := _camera.create_tween()
	shake_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var steps: int = int(_shake_duration / 0.05)
	if steps < 1:
		steps = 1
	for i in steps:
		var offset_x: float = randf_range(-_shake_amplitude, _shake_amplitude)
		var offset_y: float = randf_range(-_shake_amplitude, _shake_amplitude)
		shake_tween.tween_property(_camera, "offset", original_offset + Vector2(offset_x, offset_y), 0.05)
	shake_tween.tween_property(_camera, "offset", original_offset, 0.05)


func _spawn_energy_wave() -> void:
	if _scene_root == null:
		return
	var wave := _EnergyWave.new()
	wave.z_index = 95
	wave.ring_color = _wave_color
	wave.max_radius = _wave_max_radius
	# Position at screen center via camera
	if _camera != null:
		wave.position = _camera.global_position
	_scene_root.add_child(wave)
	_vfx_nodes.append(wave)
	var tween := wave.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(wave, "current_radius", _wave_max_radius, _wave_duration)
	tween.tween_property(wave, "modulate:a", 0.0, _wave_duration)


func _play_fade_overlay() -> void:
	if _scene_root == null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	_scene_root.add_child(layer)
	_vfx_nodes.append(layer)
	var overlay := ColorRect.new()
	overlay.name = "FadeOverlay"
	overlay.color = Color(1.0, 1.0, 1.0, 0.8)
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.modulate.a = 0.0
	layer.add_child(overlay)
	var tween := overlay.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(overlay, "modulate:a", 1.0, _fade_duration)


func _show_title_text() -> void:
	if _scene_root == null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 101
	_scene_root.add_child(layer)
	_vfx_nodes.append(layer)
	var label := Label.new()
	label.name = "CinematicTitle"
	label.text = _title_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 0.4
	label.anchor_bottom = 0.5
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", Color(0.2, 0.8, 1.0))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.modulate.a = 0.0
	layer.add_child(label)
	var tween := label.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(label, "modulate:a", 1.0, _title_fade_in)


func _show_subtitle_text() -> void:
	if _scene_root == null:
		return
	# Find existing text layer or create new one
	var layer: CanvasLayer = null
	for node in _vfx_nodes:
		if node is CanvasLayer and is_instance_valid(node):
			var title := node.get_node_or_null("CinematicTitle")
			if title != null:
				layer = node
				break
	if layer == null:
		layer = CanvasLayer.new()
		layer.layer = 101
		_scene_root.add_child(layer)
		_vfx_nodes.append(layer)
	var label := Label.new()
	label.name = "CinematicSubtitle"
	label.text = _subtitle_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 0.5
	label.anchor_bottom = 0.6
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.modulate.a = 0.0
	layer.add_child(label)
	var tween := label.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(label, "modulate:a", 1.0, _subtitle_fade_in)


func _on_cinematic_finished() -> void:
	_cleanup_vfx()
	cinematic_complete.emit()


func _cleanup_vfx() -> void:
	for node in _vfx_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_vfx_nodes.clear()


func save_state() -> Dictionary:
	return {}


func load_state(_data: Dictionary) -> void:
	pass


## Expanding cyan energy wave visual effect node.
class _EnergyWave:
	extends Node2D

	var max_radius: float = 80.0
	var current_radius: float = 0.0
	var ring_color: Color = Color(0.3, 0.8, 1.0, 0.8)

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if current_radius > 0.0:
			draw_arc(Vector2.ZERO, current_radius, 0, TAU, 64, ring_color, 3.0)
