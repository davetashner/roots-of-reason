extends VBoxContainer
## Age advancement UI section shown in the info panel when a Town Center
## is selected. Displays advance button, cost, progress, and missing techs.

const RESOURCE_NAME_TO_TYPE: Dictionary = {
	"food": ResourceManager.ResourceType.FOOD,
	"wood": ResourceManager.ResourceType.WOOD,
	"stone": ResourceManager.ResourceType.STONE,
	"gold": ResourceManager.ResourceType.GOLD,
	"knowledge": ResourceManager.ResourceType.KNOWLEDGE,
}

var _age_advancement: Node = null
var _player_id: int = 0

var _button: Button = null
var _progress_bar: ProgressBar = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 2)
	visible = false

	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sep)

	var btn_row := HBoxContainer.new()
	btn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_row.add_theme_constant_override("separation", 6)
	add_child(btn_row)

	_button = Button.new()
	_button.custom_minimum_size = Vector2(180, 28)
	_button.add_theme_font_size_override("font_size", 12)
	_button.pressed.connect(_on_button_pressed)
	btn_row.add_child(_button)

	_progress_bar = ProgressBar.new()
	_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_bar.custom_minimum_size = Vector2(100, 14)
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.show_percentage = true
	_progress_bar.visible = false
	btn_row.add_child(_progress_bar)


func setup(age_advancement: Node, player_id: int = 0) -> void:
	_age_advancement = age_advancement
	_player_id = player_id


func update_display(building: Node2D) -> void:
	if building == null or not is_instance_valid(building):
		visible = false
		return
	if _age_advancement == null:
		visible = false
		return
	if not "building_name" in building or building.building_name != "town_center":
		visible = false
		return
	if building.under_construction:
		visible = false
		return
	if GameManager.current_age >= AgeAdvancement.MAX_AGE:
		visible = false
		return
	var next_age: int = GameManager.current_age + 1
	var age_name: String = GameManager.AGE_NAMES[next_age]
	if _age_advancement.is_advancing():
		visible = true
		_button.text = "Cancel"
		_button.tooltip_text = "Cancel age advancement"
		_button.disabled = false
		_progress_bar.visible = true
		_progress_bar.value = _age_advancement.get_advance_progress() * 100.0
	else:
		visible = true
		_button.text = "Advance to %s" % age_name
		_progress_bar.visible = false
		var missing: Array[String] = _age_advancement.get_missing_techs(_player_id)
		var raw_costs: Dictionary = _age_advancement.get_advance_cost_raw(next_age)
		var can_afford: bool = ResourceManager.can_afford(_player_id, _age_advancement.get_advance_cost(next_age))
		if not missing.is_empty():
			_button.disabled = true
			_button.tooltip_text = _build_locked_tooltip(age_name, missing, raw_costs)
		elif not can_afford:
			_button.disabled = true
			_button.tooltip_text = _build_unaffordable_tooltip(age_name, raw_costs)
		else:
			_button.disabled = false
			_button.tooltip_text = _build_ready_tooltip(age_name, raw_costs)


func _build_locked_tooltip(age_name: String, missing: Array[String], raw_costs: Dictionary) -> String:
	var lines: Array[String] = ["Advance to %s" % age_name, ""]
	lines.append("Missing technologies:")
	for tech_id: String in missing:
		var display_name: String = tech_id.replace("_", " ").capitalize()
		lines.append("  - %s" % display_name)
	if not raw_costs.is_empty():
		lines.append("")
		lines.append("Cost: %s" % _format_costs(raw_costs))
	return "\n".join(lines)


func _build_unaffordable_tooltip(age_name: String, raw_costs: Dictionary) -> String:
	var lines: Array[String] = ["Advance to %s" % age_name, ""]
	lines.append("Insufficient resources:")
	for res_name: String in raw_costs:
		var lower_key := res_name.to_lower()
		if not RESOURCE_NAME_TO_TYPE.has(lower_key):
			continue
		var res_type: ResourceManager.ResourceType = RESOURCE_NAME_TO_TYPE[lower_key]
		var needed: int = int(raw_costs[res_name])
		var have: int = int(ResourceManager.get_amount(_player_id, res_type))
		if have < needed:
			lines.append("  %s: %d / %d" % [res_name.capitalize(), have, needed])
	return "\n".join(lines)


func _build_ready_tooltip(age_name: String, raw_costs: Dictionary) -> String:
	var cost_str: String = _format_costs(raw_costs)
	if cost_str.is_empty():
		return "Advance to %s" % age_name
	return "Advance to %s\nCost: %s" % [age_name, cost_str]


func _format_costs(raw_costs: Dictionary) -> String:
	var cost_parts: Array[String] = []
	for res_name: String in raw_costs:
		cost_parts.append("%s: %d" % [res_name.capitalize(), int(raw_costs[res_name])])
	return ", ".join(cost_parts)


func _on_button_pressed() -> void:
	if _age_advancement == null:
		return
	if _age_advancement.is_advancing():
		_age_advancement.cancel_advancement(_player_id)
	else:
		_age_advancement.start_advancement(_player_id)
