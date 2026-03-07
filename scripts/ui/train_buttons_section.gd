extends HBoxContainer
## Row of train buttons shown in the info panel when a building with
## producible units is selected.  Each button queues one unit via the
## building's ProductionQueue.

const TRAIN_HOTKEYS: Array = ["Q", "W", "E", "R", "T"]

const RESOURCE_NAME_TO_TYPE: Dictionary = {
	"food": ResourceManager.ResourceType.FOOD,
	"wood": ResourceManager.ResourceType.WOOD,
	"stone": ResourceManager.ResourceType.STONE,
	"gold": ResourceManager.ResourceType.GOLD,
	"knowledge": ResourceManager.ResourceType.KNOWLEDGE,
}

var _building: Node2D = null
var _production_queue: Node = null
var _unit_types: Array = []
var _buttons: Array[Button] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	visible = false


func update_for_building(building: Node2D) -> void:
	if building == null or not is_instance_valid(building):
		_hide()
		return
	if "under_construction" in building and building.under_construction:
		_hide()
		return
	# Only player buildings (owner_id 0) get train buttons
	if "owner_id" in building and building.owner_id != 0:
		_hide()
		return
	var pq: Node = building.get_node_or_null("ProductionQueue")
	if pq == null or not pq.has_method("can_produce"):
		_hide()
		return
	var units_produced: Array = _get_units_produced(building)
	if units_produced.is_empty():
		_hide()
		return
	# Rebuild buttons only when building changes
	if building != _building or units_produced != _unit_types:
		_building = building
		_production_queue = pq
		_unit_types = units_produced
		_rebuild_buttons()
	visible = true
	refresh_button_states()


func refresh_button_states() -> void:
	if _production_queue == null or not is_instance_valid(_production_queue):
		return
	for i in _buttons.size():
		if i >= _unit_types.size():
			break
		var unit_type: String = _unit_types[i]
		_buttons[i].disabled = not _production_queue.can_produce(unit_type)


func try_hotkey(key_char: String) -> bool:
	## Attempts to match key_char to a train hotkey.  Returns true if handled.
	if not visible or _production_queue == null:
		return false
	for i in TRAIN_HOTKEYS.size():
		if i >= _unit_types.size():
			break
		if key_char == TRAIN_HOTKEYS[i]:
			if not _buttons[i].disabled:
				_on_train_pressed(_unit_types[i])
			return true
	return false


func _hide() -> void:
	visible = false
	_building = null
	_production_queue = null
	_unit_types = []


func _rebuild_buttons() -> void:
	_clear_buttons()
	_buttons.clear()
	for i in _unit_types.size():
		var unit_type: String = _unit_types[i]
		var hotkey: String = TRAIN_HOTKEYS[i] if i < TRAIN_HOTKEYS.size() else ""
		var btn := _create_train_button(unit_type, hotkey)
		add_child(btn)
		_buttons.append(btn)


func _clear_buttons() -> void:
	for child in get_children():
		child.queue_free()


func _create_train_button(unit_type: String, hotkey: String) -> Button:
	var display_name: String = unit_type.replace("_", " ").capitalize()
	var btn := Button.new()
	if hotkey != "":
		btn.text = "[%s] %s" % [hotkey, display_name]
	else:
		btn.text = display_name
	btn.custom_minimum_size = Vector2(80, 28)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.add_theme_font_size_override("font_size", 11)
	_apply_btn_style(btn, "normal", Color(0.2, 0.3, 0.2, 0.9))
	_apply_btn_style(btn, "hover", Color(0.3, 0.45, 0.3, 0.9))
	btn.tooltip_text = _build_tooltip(unit_type)
	# Use container to avoid GDScript lambda capture issue
	var ut_arr: Array = [unit_type]
	btn.pressed.connect(func() -> void: _on_train_pressed(ut_arr[0]))
	return btn


func _build_tooltip(unit_type: String) -> String:
	var stats: Dictionary = _get_unit_stats(unit_type)
	if stats.is_empty():
		return unit_type.replace("_", " ").capitalize()
	var display_name: String = str(stats.get("name", unit_type.replace("_", " ").capitalize()))
	var parts: Array[String] = [display_name]
	# Cost
	var train_cost: Dictionary = stats.get("train_cost", {})
	if not train_cost.is_empty():
		var cost_parts: Array[String] = []
		for res_name: String in train_cost:
			cost_parts.append("%s: %d" % [res_name.capitalize(), int(train_cost[res_name])])
		parts.append("Cost: " + ", ".join(cost_parts))
	# Train time
	var train_time: float = float(stats.get("train_time", 0.0))
	if train_time > 0.0:
		parts.append("Time: %ds" % int(train_time))
	return "\n".join(parts)


func _on_train_pressed(unit_type: String) -> void:
	if _production_queue == null or not is_instance_valid(_production_queue):
		return
	_production_queue.add_to_queue(unit_type)


func _get_units_produced(building: Node2D) -> Array:
	if not "building_name" in building:
		return []
	var building_name: String = building.building_name
	var stats: Dictionary = _get_building_stats(building_name)
	return stats.get("units_produced", [])


func _get_building_stats(building_name: String) -> Dictionary:
	if Engine.has_singleton("DataLoader"):
		return DataLoader.get_building_stats(building_name)
	if is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_building_stats"):
			return dl.get_building_stats(building_name)
	return {}


func _get_unit_stats(unit_type: String) -> Dictionary:
	if Engine.has_singleton("DataLoader"):
		return DataLoader.get_unit_stats(unit_type)
	if is_instance_valid(Engine.get_main_loop()):
		var dl: Node = Engine.get_main_loop().root.get_node_or_null("DataLoader")
		if dl and dl.has_method("get_unit_stats"):
			return dl.get_unit_stats(unit_type)
	return {}


func _apply_btn_style(btn: Button, state: String, color: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(3)
	btn.add_theme_stylebox_override(state, s)
