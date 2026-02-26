extends PanelContainer
## In-game tech tree viewer showing all ages, techs, and dependencies.
## Displays a scrollable grid of tech buttons organized by age columns.
## Color-coded: gold (researched), green (available), blue (prereqs met but
## can't afford), gray (locked). Tooltips show cost, time, effects, prereqs.

const COLOR_RESEARCHED := Color("#FFD700")
const COLOR_AVAILABLE := Color("#4CAF50")
const COLOR_UNAFFORDABLE := Color("#2196F3")
const COLOR_LOCKED := Color("#666666")

const AGE_NAMES: Array[String] = [
	"Stone Age",
	"Bronze Age",
	"Iron Age",
	"Medieval",
	"Industrial",
	"Information",
	"Singularity",
]

var _tech_manager: Node = null
var _player_id: int = 0
var _scroll: ScrollContainer = null
var _grid_container: HBoxContainer = null
var _close_btn: Button = null
var _title_label: Label = null
## {tech_id: Button} for quick refresh access
var _tech_buttons: Dictionary = {}
## {tech_id: Dictionary} cached tech data
var _tech_cache: Dictionary = {}
## Ordered list of all tech IDs from tech_tree.json
var _all_tech_ids: Array = []


func _ready() -> void:
	visible = false
	_build_ui()


func setup(tech_manager: Node, player_id: int = 0) -> void:
	_tech_manager = tech_manager
	_player_id = player_id
	_load_tech_data()
	_populate_grid()
	refresh()
	if _tech_manager.has_signal("tech_researched"):
		_tech_manager.tech_researched.connect(_on_tech_researched)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_ESCAPE or key.keycode == KEY_T:
				toggle_visible()
				get_viewport().set_input_as_handled()


func toggle_visible() -> void:
	visible = not visible
	if visible:
		refresh()


func refresh() -> void:
	if _tech_manager == null:
		return
	for tech_id: String in _tech_buttons:
		var btn: Button = _tech_buttons[tech_id]
		var state: String = _get_tech_state(tech_id)
		_apply_button_style(btn, state)
		btn.tooltip_text = _build_tooltip(tech_id, state)


func get_tech_button(tech_id: String) -> Button:
	return _tech_buttons.get(tech_id, null)


func get_tech_button_count() -> int:
	return _tech_buttons.size()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.92)
	add_theme_stylebox_override("panel", style)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.name = "OuterVBox"
	outer_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer_vbox.add_theme_constant_override("separation", 8)
	add_child(outer_vbox)

	# Header row
	var header := HBoxContainer.new()
	header.name = "Header"
	header.custom_minimum_size = Vector2(0, 40)
	outer_vbox.add_child(header)

	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.text = "Technology Tree"
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", Color.WHITE)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	_close_btn = Button.new()
	_close_btn.name = "CloseButton"
	_close_btn.text = "X"
	_close_btn.custom_minimum_size = Vector2(40, 40)
	_close_btn.pressed.connect(_on_close_pressed)
	header.add_child(_close_btn)

	# Scroll area for the tech grid
	_scroll = ScrollContainer.new()
	_scroll.name = "ScrollContainer"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	outer_vbox.add_child(_scroll)

	_grid_container = HBoxContainer.new()
	_grid_container.name = "AgeColumns"
	_grid_container.add_theme_constant_override("separation", 24)
	_scroll.add_child(_grid_container)

	# Legend row
	var legend := HBoxContainer.new()
	legend.name = "Legend"
	legend.custom_minimum_size = Vector2(0, 30)
	legend.add_theme_constant_override("separation", 20)
	outer_vbox.add_child(legend)
	_add_legend_entry(legend, COLOR_RESEARCHED, "Researched")
	_add_legend_entry(legend, COLOR_AVAILABLE, "Available")
	_add_legend_entry(legend, COLOR_UNAFFORDABLE, "Can't Afford")
	_add_legend_entry(legend, COLOR_LOCKED, "Locked")


func _add_legend_entry(parent: HBoxContainer, color: Color, label_text: String) -> void:
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(16, 16)
	swatch.color = color
	parent.add_child(swatch)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	parent.add_child(lbl)


func _load_tech_data() -> void:
	_tech_cache.clear()
	_all_tech_ids.clear()
	var raw: Variant = DataLoader.load_json("res://data/tech/tech_tree.json")
	if raw is Array:
		for entry: Dictionary in raw:
			var tech_id: String = entry.get("id", "")
			if tech_id != "":
				_tech_cache[tech_id] = entry
				_all_tech_ids.append(tech_id)


func _populate_grid() -> void:
	_tech_buttons.clear()
	# Remove old children
	for child in _grid_container.get_children():
		child.queue_free()

	# Group techs by age
	var age_groups: Dictionary = {}
	for tech_id: String in _all_tech_ids:
		var data: Dictionary = _tech_cache[tech_id]
		var age: int = int(data.get("age", 0))
		if age not in age_groups:
			age_groups[age] = []
		age_groups[age].append(tech_id)

	# Create a column per age
	for age_index: int in range(AGE_NAMES.size()):
		var column := VBoxContainer.new()
		column.name = "Age_%d" % age_index
		column.custom_minimum_size = Vector2(180, 0)
		column.add_theme_constant_override("separation", 8)
		_grid_container.add_child(column)

		# Age header
		var age_label := Label.new()
		age_label.name = "AgeLabel"
		age_label.text = AGE_NAMES[age_index]
		age_label.add_theme_font_size_override("font_size", 18)
		age_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
		age_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(age_label)

		# Separator
		var sep := HSeparator.new()
		column.add_child(sep)

		# Tech buttons
		var techs: Array = age_groups.get(age_index, [])
		for tech_id: String in techs:
			var data: Dictionary = _tech_cache[tech_id]
			var btn := Button.new()
			btn.name = "Tech_%s" % tech_id
			btn.text = data.get("name", tech_id)
			btn.custom_minimum_size = Vector2(170, 36)
			btn.pressed.connect(_on_tech_button_pressed.bind(tech_id))
			column.add_child(btn)
			_tech_buttons[tech_id] = btn


func _get_tech_state(tech_id: String) -> String:
	## Returns "researched", "available", "unaffordable", or "locked".
	if _tech_manager.is_tech_researched(tech_id, _player_id):
		return "researched"
	# Check prerequisites
	var data: Dictionary = _tech_cache.get(tech_id, {})
	var prereqs: Array = data.get("prerequisites", [])
	for prereq: String in prereqs:
		if not _tech_manager.is_tech_researched(prereq, _player_id):
			return "locked"
	# Check age requirement
	var required_age: int = int(data.get("age", 0))
	if required_age > GameManager.current_age:
		return "locked"
	# Prerequisites met — check affordability
	if _tech_manager.can_research(_player_id, tech_id):
		return "available"
	return "unaffordable"


func _apply_button_style(btn: Button, state: String) -> void:
	var color: Color
	match state:
		"researched":
			color = COLOR_RESEARCHED
		"available":
			color = COLOR_AVAILABLE
		"unaffordable":
			color = COLOR_UNAFFORDABLE
		_:
			color = COLOR_LOCKED

	var normal := StyleBoxFlat.new()
	normal.bg_color = color.darkened(0.6)
	normal.border_color = color
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(4)
	normal.set_content_margin_all(4)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = color.darkened(0.4)
	hover.border_color = color.lightened(0.2)
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(4)
	hover.set_content_margin_all(4)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = color.darkened(0.3)
	pressed_style.border_color = color
	pressed_style.set_border_width_all(2)
	pressed_style.set_corner_radius_all(4)
	pressed_style.set_content_margin_all(4)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)


func _build_tooltip(tech_id: String, state: String) -> String:
	var data: Dictionary = _tech_cache.get(tech_id, {})
	var parts: Array[String] = []

	# Name and status
	var status_text: String
	match state:
		"researched":
			status_text = "RESEARCHED"
		"available":
			status_text = "AVAILABLE"
		"unaffordable":
			status_text = "Need Resources"
		_:
			status_text = "LOCKED"
	parts.append("%s [%s]" % [data.get("name", tech_id), status_text])

	# Cost
	var cost: Dictionary = data.get("cost", {})
	if not cost.is_empty():
		var cost_parts: Array[String] = []
		for resource: String in cost:
			cost_parts.append("%s: %d" % [resource.capitalize(), int(cost[resource])])
		parts.append("Cost: %s" % ", ".join(cost_parts))

	# Research time
	var research_time: int = int(data.get("research_time", 0))
	if research_time > 0:
		parts.append("Time: %ds" % research_time)

	# Prerequisites
	var prereqs: Array = data.get("prerequisites", [])
	if not prereqs.is_empty():
		var prereq_names: Array[String] = []
		for prereq_id: String in prereqs:
			var prereq_data: Dictionary = _tech_cache.get(prereq_id, {})
			prereq_names.append(prereq_data.get("name", prereq_id))
		parts.append("Requires: %s" % ", ".join(prereq_names))

	# Effects
	var effects: Dictionary = data.get("effects", {})
	if not effects.is_empty():
		parts.append("Effects:")
		for key: String in effects:
			var value: Variant = effects[key]
			parts.append("  %s: %s" % [key.replace("_", " ").capitalize(), str(value)])

	# Flavor text
	var flavor: String = data.get("flavor_text", "")
	if flavor != "":
		parts.append('"%s"' % flavor)

	return "\n".join(parts)


func _on_tech_button_pressed(tech_id: String) -> void:
	if _tech_manager == null:
		return
	if _tech_manager.can_research(_player_id, tech_id):
		_tech_manager.start_research(_player_id, tech_id)
		refresh()


func _on_tech_researched(_player_id_arg: int, _tech_id: String, _effects: Dictionary) -> void:
	refresh()


func _on_close_pressed() -> void:
	visible = false
