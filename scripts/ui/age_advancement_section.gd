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
var _cost_label: Label = null
var _missing_label: Label = null


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

	_cost_label = Label.new()
	_cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cost_label.add_theme_font_size_override("font_size", 11)
	add_child(_cost_label)

	_missing_label = Label.new()
	_missing_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_missing_label.add_theme_font_size_override("font_size", 10)
	_missing_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.3))
	add_child(_missing_label)


func setup(age_advancement: Node, player_id: int = 0) -> void:
	_age_advancement = age_advancement
	_player_id = player_id


func update_display(building: Node2D) -> void:
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
	visible = true
	var next_age: int = GameManager.current_age + 1
	var age_name: String = GameManager.AGE_NAMES[next_age]
	if _age_advancement.is_advancing():
		_button.text = "Cancel"
		_button.disabled = false
		_progress_bar.visible = true
		_progress_bar.value = _age_advancement.get_advance_progress() * 100.0
		_cost_label.text = "Advancing to %s..." % age_name
		_missing_label.text = ""
	else:
		_button.text = "Advance to %s" % age_name
		_progress_bar.visible = false
		var raw_costs: Dictionary = _age_advancement.get_advance_cost_raw(next_age)
		var cost_parts: Array[String] = []
		for res_name: String in raw_costs:
			cost_parts.append("%s: %d" % [res_name.capitalize(), int(raw_costs[res_name])])
		_cost_label.text = "Cost: " + ", ".join(cost_parts) if not cost_parts.is_empty() else ""
		var missing: Array[String] = _age_advancement.get_missing_techs(_player_id)
		if not missing.is_empty():
			var names: Array[String] = []
			for tid: String in missing:
				names.append(tid.replace("_", " ").capitalize())
			_missing_label.text = "Need: " + ", ".join(names)
			_button.disabled = true
		elif not ResourceManager.can_afford(_player_id, _age_advancement.get_advance_cost(next_age)):
			_missing_label.text = "Not enough resources"
			_button.disabled = true
		else:
			_missing_label.text = ""
			_button.disabled = false


func _on_button_pressed() -> void:
	if _age_advancement == null:
		return
	if _age_advancement.is_advancing():
		_age_advancement.cancel_advancement(_player_id)
	else:
		_age_advancement.start_advancement(_player_id)
