extends PanelContainer
## In-game tech tree viewer showing all ages, techs, and dependencies.
## Displays a scrollable grid of tech buttons organized by age columns.
## Color-coded: gold (researched), green (available), blue (prereqs met but
## can't afford), gray (locked), purple (shadowed/undiscovered).
## Supports progressive disclosure: techs are hidden until prereqs are met.

const COLOR_RESEARCHED := Color("#FFD700")
const COLOR_AVAILABLE := Color("#4CAF50")
const COLOR_UNAFFORDABLE := Color("#2196F3")
const COLOR_LOCKED := Color("#666666")
const COLOR_RESEARCHING := Color("#FFA726")
const COLOR_SHADOWED := Color("#9C27B0")

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
## {age_index: VBoxContainer} for column visibility toggling
var _age_columns: Dictionary = {}
## Visibility config loaded from tech_visibility.json
var _visibility_config: Dictionary = {}
## Whether espionage tech has been researched (reveals opponent research)
var _opponent_research_unlocked: bool = false
## Toggle state for opponent intel panel
var _showing_opponent: bool = false
## Header button for toggling opponent intel
var _opponent_toggle_btn: Button = null
## Overlay panel showing opponent's current research
var _opponent_panel: PanelContainer = null
## Tech detail side panel
var _detail_panel: PanelContainer = null
## Currently selected tech in detail panel
var _detail_tech_id: String = ""
## {tech_id: Array[String]} reverse dependency map (what each tech leads to)
var _leads_to_map: Dictionary = {}


func _ready() -> void:
	visible = false
	_build_ui()
	_ensure_fullscreen()


func setup(tech_manager: Node, player_id: int = 0) -> void:
	_tech_manager = tech_manager
	_player_id = player_id
	_load_visibility_config()
	_load_tech_data()
	_build_leads_to_map()
	if _all_tech_ids.is_empty():
		push_warning("TechTreeViewer: No techs loaded from tech_tree.json")
	_populate_grid()
	if _tech_buttons.is_empty():
		push_warning("TechTreeViewer: No tech buttons created (tech count: %d)" % _all_tech_ids.size())
	_check_opponent_unlock()
	refresh()
	if _tech_manager.has_signal("tech_researched"):
		_tech_manager.tech_researched.connect(_on_tech_researched)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_ESCAPE:
				if _detail_panel != null and _detail_panel.visible:
					_hide_detail_panel()
				else:
					toggle_visible()
				get_viewport().set_input_as_handled()
			elif key.keycode == KEY_T:
				toggle_visible()
				get_viewport().set_input_as_handled()


func toggle_visible() -> void:
	visible = not visible
	if visible:
		_ensure_fullscreen()
		refresh()


func refresh() -> void:
	if _tech_manager == null:
		return
	# Update age column visibility
	var max_lookahead: int = int(_visibility_config.get("max_lookahead_ages", 1))
	var max_visible_age: int = GameManager.current_age + max_lookahead
	for age_index: int in _age_columns:
		_age_columns[age_index].visible = age_index <= max_visible_age
	# Update button visibility and styles
	var show_shadowed: bool = bool(_visibility_config.get("show_shadowed_techs", true))
	for tech_id: String in _tech_buttons:
		var btn: Button = _tech_buttons[tech_id]
		var vis: String = _get_tech_visibility(tech_id)
		match vis:
			"visible":
				btn.visible = true
				var state: String = _get_tech_state(tech_id)
				_apply_button_style(btn, state)
				btn.tooltip_text = _build_tooltip(tech_id, state)
			"shadowed":
				btn.visible = show_shadowed
				_apply_button_style(btn, "shadowed")
				btn.tooltip_text = _build_shadowed_tooltip(tech_id)
			"hidden":
				btn.visible = false
				_apply_button_style(btn, "locked")
				btn.tooltip_text = ""
	# Update opponent panel if showing
	if _showing_opponent and _opponent_panel != null:
		_update_opponent_panel()


func get_tech_button(tech_id: String) -> Button:
	return _tech_buttons.get(tech_id, null)


func get_tech_button_count() -> int:
	return _tech_buttons.size()


func get_tech_visibility(tech_id: String) -> String:
	return _get_tech_visibility(tech_id)


func is_opponent_research_unlocked() -> bool:
	return _opponent_research_unlocked


func is_showing_opponent() -> bool:
	return _showing_opponent


func get_age_column(age_index: int) -> VBoxContainer:
	return _age_columns.get(age_index, null)


func get_detail_panel() -> PanelContainer:
	return _detail_panel


func get_detail_tech_id() -> String:
	return _detail_tech_id


func get_leads_to(tech_id: String) -> Array:
	return _leads_to_map.get(tech_id, [])


func _ensure_fullscreen() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_offsets_preset(Control.PRESET_FULL_RECT)
	set_deferred("size", get_viewport_rect().size)


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

	# Opponent intel toggle button (hidden until espionage researched)
	_opponent_toggle_btn = Button.new()
	_opponent_toggle_btn.name = "OpponentToggle"
	_opponent_toggle_btn.text = "Enemy Intel"
	_opponent_toggle_btn.custom_minimum_size = Vector2(100, 36)
	_opponent_toggle_btn.visible = false
	_opponent_toggle_btn.pressed.connect(_on_opponent_toggle)
	header.add_child(_opponent_toggle_btn)

	_close_btn = Button.new()
	_close_btn.name = "CloseButton"
	_close_btn.text = "X"
	_close_btn.custom_minimum_size = Vector2(40, 40)
	_close_btn.pressed.connect(_on_close_pressed)
	header.add_child(_close_btn)

	# Content area: scroll grid + detail panel side by side
	var content_hbox := HBoxContainer.new()
	content_hbox.name = "ContentHBox"
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 8)
	outer_vbox.add_child(content_hbox)

	# Scroll area for the tech grid
	_scroll = ScrollContainer.new()
	_scroll.name = "ScrollContainer"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content_hbox.add_child(_scroll)

	_grid_container = HBoxContainer.new()
	_grid_container.name = "AgeColumns"
	_grid_container.add_theme_constant_override("separation", 24)
	_scroll.add_child(_grid_container)

	# Detail side panel (hidden by default)
	_build_detail_panel()
	content_hbox.add_child(_detail_panel)

	# Opponent intel panel (hidden by default)
	_build_opponent_panel()
	outer_vbox.add_child(_opponent_panel)

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
	_add_legend_entry(legend, COLOR_SHADOWED, "Undiscovered")


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


func _build_detail_panel() -> void:
	_detail_panel = PanelContainer.new()
	_detail_panel.name = "DetailPanel"
	_detail_panel.visible = false
	_detail_panel.custom_minimum_size = Vector2(320, 0)
	_detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.15, 0.95)
	style.border_color = Color(0.4, 0.4, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	_detail_panel.add_theme_stylebox_override("panel", style)

	var scroll := ScrollContainer.new()
	scroll.name = "DetailScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.name = "DetailVBox"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	# Close button row
	var close_row := HBoxContainer.new()
	close_row.name = "DetailCloseRow"
	vbox.add_child(close_row)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_row.add_child(spacer)
	var close_btn := Button.new()
	close_btn.name = "DetailCloseBtn"
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(32, 32)
	close_btn.pressed.connect(_hide_detail_panel)
	close_row.add_child(close_btn)

	# Tech name
	var name_lbl := Label.new()
	name_lbl.name = "DetailName"
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(name_lbl)

	# Status label
	var status_lbl := Label.new()
	status_lbl.name = "DetailStatus"
	status_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(status_lbl)

	vbox.add_child(HSeparator.new())

	# Description
	var desc_lbl := Label.new()
	desc_lbl.name = "DetailDescription"
	desc_lbl.add_theme_font_size_override("font_size", 14)
	desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_lbl)

	# Flavor text
	var flavor_lbl := Label.new()
	flavor_lbl.name = "DetailFlavor"
	flavor_lbl.add_theme_font_size_override("font_size", 13)
	flavor_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.5))
	flavor_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(flavor_lbl)

	vbox.add_child(HSeparator.new())

	# Cost
	var cost_lbl := Label.new()
	cost_lbl.name = "DetailCost"
	cost_lbl.add_theme_font_size_override("font_size", 14)
	cost_lbl.add_theme_color_override("font_color", Color.WHITE)
	cost_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(cost_lbl)

	# Research time
	var time_lbl := Label.new()
	time_lbl.name = "DetailTime"
	time_lbl.add_theme_font_size_override("font_size", 14)
	time_lbl.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(time_lbl)

	vbox.add_child(HSeparator.new())

	# Effects
	var effects_header := Label.new()
	effects_header.name = "DetailEffectsHeader"
	effects_header.text = "Benefits"
	effects_header.add_theme_font_size_override("font_size", 16)
	effects_header.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	vbox.add_child(effects_header)

	var effects_lbl := Label.new()
	effects_lbl.name = "DetailEffects"
	effects_lbl.add_theme_font_size_override("font_size", 13)
	effects_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	effects_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(effects_lbl)

	vbox.add_child(HSeparator.new())

	# Prerequisites
	var prereq_header := Label.new()
	prereq_header.name = "DetailPrereqHeader"
	prereq_header.text = "Requires"
	prereq_header.add_theme_font_size_override("font_size", 16)
	prereq_header.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
	vbox.add_child(prereq_header)

	var prereq_lbl := Label.new()
	prereq_lbl.name = "DetailPrereqs"
	prereq_lbl.add_theme_font_size_override("font_size", 13)
	prereq_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	prereq_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(prereq_lbl)

	# Leads to
	var leads_header := Label.new()
	leads_header.name = "DetailLeadsToHeader"
	leads_header.text = "Leads To"
	leads_header.add_theme_font_size_override("font_size", 16)
	leads_header.add_theme_color_override("font_color", Color(0.9, 0.8, 0.6))
	vbox.add_child(leads_header)

	var leads_lbl := Label.new()
	leads_lbl.name = "DetailLeadsTo"
	leads_lbl.add_theme_font_size_override("font_size", 13)
	leads_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	leads_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(leads_lbl)

	vbox.add_child(HSeparator.new())

	# Research button
	var research_btn := Button.new()
	research_btn.name = "DetailResearchBtn"
	research_btn.text = "Research"
	research_btn.custom_minimum_size = Vector2(0, 40)
	research_btn.pressed.connect(_on_detail_research_pressed)
	vbox.add_child(research_btn)


func _show_detail_panel(tech_id: String) -> void:
	_detail_tech_id = tech_id
	if _detail_panel == null:
		return
	var data: Dictionary = _tech_cache.get(tech_id, {})
	var vbox: VBoxContainer = _detail_panel.get_node("DetailScroll/DetailVBox")

	# Name
	var name_lbl: Label = vbox.get_node("DetailName")
	name_lbl.text = data.get("name", tech_id)

	# Status
	var status_lbl: Label = vbox.get_node("DetailStatus")
	var state: String = _get_tech_state(tech_id) if _tech_manager != null else "locked"
	var status_color: Color
	var status_text: String
	match state:
		"researched":
			status_text = "RESEARCHED"
			status_color = COLOR_RESEARCHED
		"researching":
			status_text = "RESEARCHING"
			status_color = COLOR_RESEARCHING
		"available":
			status_text = "AVAILABLE"
			status_color = COLOR_AVAILABLE
		"unaffordable":
			status_text = "NEED RESOURCES"
			status_color = COLOR_UNAFFORDABLE
		_:
			status_text = "LOCKED"
			status_color = COLOR_LOCKED
	status_lbl.text = status_text
	status_lbl.add_theme_color_override("font_color", status_color)

	# Description
	var desc_lbl: Label = vbox.get_node("DetailDescription")
	desc_lbl.text = data.get("description", "")
	desc_lbl.visible = desc_lbl.text != ""

	# Flavor
	var flavor_lbl: Label = vbox.get_node("DetailFlavor")
	var flavor: String = data.get("flavor_text", "")
	flavor_lbl.text = '"%s"' % flavor if flavor != "" else ""
	flavor_lbl.visible = flavor != ""

	# Cost
	var cost_lbl: Label = vbox.get_node("DetailCost")
	var cost: Dictionary = data.get("cost", {})
	if not cost.is_empty():
		var cost_parts: Array[String] = []
		for resource: String in cost:
			cost_parts.append("%s: %d" % [resource.capitalize(), int(cost[resource])])
		cost_lbl.text = "Cost: %s" % ", ".join(cost_parts)
		cost_lbl.visible = true
	else:
		cost_lbl.visible = false

	# Time
	var time_lbl: Label = vbox.get_node("DetailTime")
	var research_time: int = int(data.get("research_time", 0))
	time_lbl.text = "Research Time: %ds" % research_time if research_time > 0 else ""
	time_lbl.visible = research_time > 0

	# Effects
	var effects: Dictionary = data.get("effects", {})
	var effects_lbl: Label = vbox.get_node("DetailEffects")
	var effects_header: Label = vbox.get_node("DetailEffectsHeader")
	if not effects.is_empty():
		effects_lbl.text = _format_effects(effects)
		effects_header.visible = true
		effects_lbl.visible = true
	else:
		effects_header.visible = false
		effects_lbl.visible = false

	# Prerequisites
	var prereqs: Array = data.get("prerequisites", [])
	var prereq_header: Label = vbox.get_node("DetailPrereqHeader")
	var prereq_lbl: Label = vbox.get_node("DetailPrereqs")
	if not prereqs.is_empty():
		var prereq_parts: Array[String] = []
		for prereq_id: String in prereqs:
			var prereq_data: Dictionary = _tech_cache.get(prereq_id, {})
			var prereq_name: String = prereq_data.get("name", prereq_id)
			var done: bool = _tech_manager != null and _tech_manager.is_tech_researched(prereq_id, _player_id)
			prereq_parts.append("%s %s" % [prereq_name, "(done)" if done else "(needed)"])
		prereq_lbl.text = "\n".join(prereq_parts)
		prereq_header.visible = true
		prereq_lbl.visible = true
	else:
		prereq_header.visible = false
		prereq_lbl.visible = false

	# Leads to
	var leads_to: Array = _leads_to_map.get(tech_id, [])
	var leads_header: Label = vbox.get_node("DetailLeadsToHeader")
	var leads_lbl: Label = vbox.get_node("DetailLeadsTo")
	if not leads_to.is_empty():
		var leads_parts: Array[String] = []
		for next_id: String in leads_to:
			var next_data: Dictionary = _tech_cache.get(next_id, {})
			leads_parts.append(next_data.get("name", next_id))
		leads_lbl.text = "\n".join(leads_parts)
		leads_header.visible = true
		leads_lbl.visible = true
	else:
		leads_header.visible = false
		leads_lbl.visible = false

	# Research button
	var research_btn: Button = vbox.get_node("DetailResearchBtn")
	research_btn.visible = state == "available"

	_detail_panel.visible = true


func _hide_detail_panel() -> void:
	_detail_tech_id = ""
	if _detail_panel != null:
		_detail_panel.visible = false


func _format_effects(effects: Dictionary) -> String:
	var parts: Array[String] = []
	for key: String in effects:
		var value: Variant = effects[key]
		var label: String = key.replace("_", " ").capitalize()
		if value is Dictionary:
			var sub_parts: Array[String] = []
			for sub_key: String in value:
				var sub_label: String = sub_key.replace("_", " ").capitalize()
				sub_parts.append("%s: %s" % [sub_label, str(value[sub_key])])
			parts.append("%s: %s" % [label, ", ".join(sub_parts)])
		elif value is Array:
			var names: Array[String] = []
			for item: Variant in value:
				names.append(str(item).replace("_", " ").capitalize())
			parts.append("%s: %s" % [label, ", ".join(names)])
		else:
			parts.append("%s: %s" % [label, str(value)])
	return "\n".join(parts)


func _on_detail_research_pressed() -> void:
	if _tech_manager == null or _detail_tech_id == "":
		return
	if _tech_manager.can_research(_player_id, _detail_tech_id):
		_tech_manager.start_research(_player_id, _detail_tech_id)
		refresh()
		_show_detail_panel(_detail_tech_id)


func _load_visibility_config() -> void:
	_visibility_config = DataLoader.get_settings("tech_visibility")


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


func _build_leads_to_map() -> void:
	_leads_to_map.clear()
	for tech_id: String in _all_tech_ids:
		var data: Dictionary = _tech_cache[tech_id]
		for prereq_id: String in data.get("prerequisites", []):
			if prereq_id not in _leads_to_map:
				_leads_to_map[prereq_id] = []
			_leads_to_map[prereq_id].append(tech_id)


func _populate_grid() -> void:
	_tech_buttons.clear()
	_age_columns.clear()
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
		_age_columns[age_index] = column

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


func _get_tech_visibility(tech_id: String) -> String:
	## Returns "visible", "shadowed", or "hidden" based on disclosure rules.
	var data: Dictionary = _tech_cache.get(tech_id, {})
	var prereqs: Array = data.get("prerequisites", [])

	# Researched techs are always visible
	if _tech_manager != null and _tech_manager.is_tech_researched(tech_id, _player_id):
		return "visible"

	# Civ-exclusive techs: completely hidden unless correct civ + all prereqs met
	var civ_exclusive: String = data.get("civ_exclusive", "")
	if civ_exclusive != "":
		return _get_civ_exclusive_visibility(prereqs, civ_exclusive)

	# Root techs (no prereqs) are always visible
	if prereqs.is_empty():
		return "visible"

	return _classify_by_prereqs(prereqs)


func _get_civ_exclusive_visibility(prereqs: Array, civ_exclusive: String) -> String:
	var player_civ: String = GameManager.get_player_civilization(_player_id)
	if player_civ != civ_exclusive:
		return "hidden"
	if _visibility_config.get("civ_exclusive_require_all_prereqs", true):
		for prereq: String in prereqs:
			if not _tech_manager.is_tech_researched(prereq, _player_id):
				return "hidden"
	return "visible"


func _classify_by_prereqs(prereqs: Array) -> String:
	## Classifies as visible/shadowed/hidden based on how many prereqs are done.
	var researched_count: int = 0
	for prereq: String in prereqs:
		if _tech_manager != null and _tech_manager.is_tech_researched(prereq, _player_id):
			researched_count += 1
	if researched_count == prereqs.size():
		return "visible"
	if researched_count > 0:
		return "shadowed"
	return "hidden"


func _get_tech_state(tech_id: String) -> String:
	## Returns "researched", "researching", "available", "unaffordable", or "locked".
	if _tech_manager.is_tech_researched(tech_id, _player_id):
		return "researched"
	# Check if currently in the research queue
	var queue: Array = _tech_manager.get_research_queue(_player_id)
	if tech_id in queue:
		return "researching"
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
		"researching":
			color = COLOR_RESEARCHING
		"available":
			color = COLOR_AVAILABLE
		"unaffordable":
			color = COLOR_UNAFFORDABLE
		"shadowed":
			color = COLOR_SHADOWED
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
		"researching":
			status_text = "RESEARCHING"
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


func _build_shadowed_tooltip(tech_id: String) -> String:
	## Tooltip for shadowed techs: shows name + UNDISCOVERED + prereq progress.
	var data: Dictionary = _tech_cache.get(tech_id, {})
	var parts: Array[String] = []
	parts.append("%s [UNDISCOVERED]" % data.get("name", tech_id))
	# Show prerequisite progress
	var prereqs: Array = data.get("prerequisites", [])
	if not prereqs.is_empty():
		var prereq_parts: Array[String] = []
		for prereq_id: String in prereqs:
			var prereq_data: Dictionary = _tech_cache.get(prereq_id, {})
			var prereq_name: String = prereq_data.get("name", prereq_id)
			var done: bool = _tech_manager != null and _tech_manager.is_tech_researched(prereq_id, _player_id)
			var marker: String = "done" if done else "needed"
			prereq_parts.append("  %s (%s)" % [prereq_name, marker])
		parts.append("Prerequisites:")
		parts.append_array(prereq_parts)
	return "\n".join(parts)


func _check_opponent_unlock() -> void:
	## Scans researched techs for the espionage reveal effect.
	_opponent_research_unlocked = false
	if _tech_manager == null:
		return
	var effect_key: String = str(_visibility_config.get("opponent_reveal_effect_key", "reveals_opponent_research"))
	var researched: Array = _tech_manager.get_researched_techs(_player_id)
	for tech_id: String in researched:
		var data: Dictionary = _tech_cache.get(tech_id, {})
		var effects: Dictionary = data.get("effects", {})
		if effects.get(effect_key, false):
			_opponent_research_unlocked = true
			break
	if _opponent_toggle_btn != null:
		_opponent_toggle_btn.visible = _opponent_research_unlocked
	if not _opponent_research_unlocked and _opponent_panel != null:
		_opponent_panel.visible = false
		_showing_opponent = false


func _build_opponent_panel() -> void:
	## Creates the small overlay panel for enemy intel.
	_opponent_panel = PanelContainer.new()
	_opponent_panel.name = "OpponentPanel"
	_opponent_panel.visible = false
	_opponent_panel.custom_minimum_size = Vector2(300, 60)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.05, 0.2, 0.9)
	panel_style.border_color = COLOR_SHADOWED
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(6)
	panel_style.set_content_margin_all(8)
	_opponent_panel.add_theme_stylebox_override("panel", panel_style)

	var vbox := VBoxContainer.new()
	vbox.name = "OpponentVBox"
	_opponent_panel.add_child(vbox)

	var header_lbl := Label.new()
	header_lbl.name = "OpponentHeader"
	header_lbl.text = "Enemy Research Intel"
	header_lbl.add_theme_font_size_override("font_size", 16)
	header_lbl.add_theme_color_override("font_color", Color(0.9, 0.7, 1.0))
	vbox.add_child(header_lbl)

	var research_lbl := Label.new()
	research_lbl.name = "OpponentResearch"
	research_lbl.text = "No active research"
	research_lbl.add_theme_font_size_override("font_size", 14)
	research_lbl.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(research_lbl)

	var progress_bar := ProgressBar.new()
	progress_bar.name = "OpponentProgress"
	progress_bar.custom_minimum_size = Vector2(280, 16)
	progress_bar.value = 0.0
	progress_bar.visible = false
	vbox.add_child(progress_bar)


func _update_opponent_panel() -> void:
	## Queries TechManager for the AI opponent's current research + progress.
	if _opponent_panel == null or _tech_manager == null:
		return
	# Opponent is player_id 1 by convention
	var opponent_id: int = 1
	var vbox: VBoxContainer = _opponent_panel.get_node("OpponentVBox")
	var research_lbl: Label = vbox.get_node("OpponentResearch")
	var progress_bar: ProgressBar = vbox.get_node("OpponentProgress")

	var current_tech: String = _tech_manager.get_current_research(opponent_id)
	if current_tech == "":
		research_lbl.text = "No active research"
		progress_bar.visible = false
		return
	var tech_data: Dictionary = _tech_cache.get(current_tech, {})
	var tech_name: String = tech_data.get("name", current_tech)
	research_lbl.text = "Researching: %s" % tech_name
	var ratio: float = _tech_manager.get_research_progress(opponent_id)
	progress_bar.value = ratio * 100.0
	progress_bar.visible = true


func _on_opponent_toggle() -> void:
	_showing_opponent = not _showing_opponent
	if _opponent_panel != null:
		_opponent_panel.visible = _showing_opponent
	if _showing_opponent:
		_update_opponent_panel()


func _on_tech_button_pressed(tech_id: String) -> void:
	if _tech_manager == null:
		return
	var vis: String = _get_tech_visibility(tech_id)
	if vis == "hidden":
		return
	if _showing_opponent:
		return
	_show_detail_panel(tech_id)


func _on_tech_researched(_player_id_arg: int, _tech_id: String, _effects: Dictionary) -> void:
	_check_opponent_unlock()
	refresh()


func _on_close_pressed() -> void:
	visible = false
