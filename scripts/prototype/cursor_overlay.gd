extends CanvasLayer
## Cursor overlay — small label near the mouse showing the current command context
## (e.g., [ATK], [GAT], [GAR], [MOV]) with color coding.

var _label: Label


func _ready() -> void:
	layer = 11
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.visible = false
	set_process(false)
	add_child(_label)


func update_command(command: String, cursor_labels: Dictionary) -> void:
	if not cursor_labels.has(command):
		clear()
		return
	var info: Dictionary = cursor_labels[command]
	_label.text = info.get("text", "")
	var c: Array = info.get("color", [1.0, 1.0, 1.0, 1.0])
	_label.add_theme_color_override("font_color", Color(c[0], c[1], c[2], c[3]))
	_label.visible = true
	set_process(true)


func clear() -> void:
	_label.visible = false
	set_process(false)


func _process(_delta: float) -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	_label.position = mouse_pos + Vector2(15, -10)
