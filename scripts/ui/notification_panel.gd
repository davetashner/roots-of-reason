extends Control
## Right-side notification panel — displays timed messages with auto-dismiss.
## Config loaded from data/settings/notifications.json.

var _config: Dictionary = {}
var _vbox: VBoxContainer = null
var _active_notifications: Array[Dictionary] = []

# Config values
var _max_visible: int = 5
var _default_duration: float = 4.0
var _fade_duration: float = 0.5
var _font_size: int = 14
var _panel_width: int = 300
var _tier_colors: Dictionary = {
	"info": Color(0.8, 0.8, 0.8, 1.0),
	"warning": Color(1.0, 0.85, 0.3, 1.0),
	"alert": Color(1.0, 0.3, 0.3, 1.0),
}


func _ready() -> void:
	_load_config()
	_build_layout()


func _load_config() -> void:
	var cfg: Dictionary = {}
	if Engine.has_singleton("DataLoader"):
		cfg = DataLoader.get_settings("notifications")
	elif is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_settings"):
			cfg = dl.get_settings("notifications")
	if cfg.is_empty():
		return
	_config = cfg
	_max_visible = int(cfg.get("max_visible", _max_visible))
	_default_duration = float(cfg.get("default_duration", _default_duration))
	_fade_duration = float(cfg.get("fade_duration", _fade_duration))
	_font_size = int(cfg.get("font_size", _font_size))
	_panel_width = int(cfg.get("panel_width", _panel_width))
	var colors: Dictionary = cfg.get("tier_colors", {})
	for tier_name: String in colors:
		var arr: Array = colors[tier_name]
		if arr.size() == 4:
			_tier_colors[tier_name] = Color(arr[0], arr[1], arr[2], arr[3])


func _build_layout() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchor to top-right
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -_panel_width - 10
	offset_right = -10
	offset_top = 50
	offset_bottom = 400
	_vbox = VBoxContainer.new()
	_vbox.name = "NotificationList"
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_theme_constant_override("separation", 4)
	add_child(_vbox)


func notify(message: String, tier: String = "info") -> void:
	# Enforce max visible cap
	while _active_notifications.size() >= _max_visible:
		_remove_oldest()
	var color: Color = _tier_colors.get(tier, _tier_colors.get("info", Color.WHITE))
	var label := Label.new()
	label.text = message
	label.add_theme_font_size_override("font_size", _font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.custom_minimum_size.x = _panel_width
	_vbox.add_child(label)
	var entry: Dictionary = {
		"label": label,
		"timer": _default_duration,
	}
	_active_notifications.append(entry)


func _process(delta: float) -> void:
	var to_remove: Array[int] = []
	for i in _active_notifications.size():
		var entry: Dictionary = _active_notifications[i]
		entry["timer"] = entry["timer"] - delta
		var remaining: float = entry["timer"]
		if remaining <= 0.0:
			to_remove.append(i)
		elif remaining <= _fade_duration:
			var alpha: float = remaining / _fade_duration
			var label: Label = entry["label"]
			if is_instance_valid(label):
				label.modulate.a = alpha
	# Remove expired (iterate backwards to keep indices valid)
	for i in range(to_remove.size() - 1, -1, -1):
		var idx: int = to_remove[i]
		var entry: Dictionary = _active_notifications[idx]
		var label: Label = entry["label"]
		if is_instance_valid(label):
			label.queue_free()
		_active_notifications.remove_at(idx)


func _remove_oldest() -> void:
	if _active_notifications.is_empty():
		return
	var entry: Dictionary = _active_notifications[0]
	var label: Label = entry["label"]
	if is_instance_valid(label):
		label.queue_free()
	_active_notifications.remove_at(0)


func get_notification_count() -> int:
	return _active_notifications.size()


func save_state() -> Dictionary:
	return {}


func load_state(_data: Dictionary) -> void:
	pass
