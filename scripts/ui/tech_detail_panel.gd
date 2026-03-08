extends PanelContainer
## Tech detail overlay panel showing illustration, name, status, description,
## cost, effects, prerequisites, leads-to, and a research button.
## Slides in from the left with a dimming backdrop behind it.
## Extracted from tech_tree_viewer.gd to keep files under 1000 lines.

signal research_requested(tech_id: String)
signal close_requested

const COLOR_RESEARCHED := Color("#FFD700")
const COLOR_AVAILABLE := Color("#4CAF50")
const COLOR_UNAFFORDABLE := Color("#2196F3")
const COLOR_LOCKED := Color("#666666")
const COLOR_RESEARCHING := Color("#FFA726")

const DETAIL_IMAGE_SIZE := Vector2(180, 180)
const TECH_SPRITE_PATH := "res://assets/sprites/tech/%s.png"
const PANEL_WIDTH: float = 420.0
const SLIDE_DURATION: float = 0.3

var slide_target_x: float = -1.0

var _tech_textures: Dictionary = {}
var _current_tech_id: String = ""
var _slide_tween: Tween = null


func _init() -> void:
	name = "DetailPanel"
	visible = false
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.15, 0.95)
	style.border_color = Color(0.4, 0.4, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(20)
	add_theme_stylebox_override("panel", style)


func _ready() -> void:
	_build_contents()


func get_current_tech_id() -> String:
	return _current_tech_id


func get_tech_texture(tech_id: String) -> Texture2D:
	if tech_id in _tech_textures:
		return _tech_textures[tech_id]
	var path: String = TECH_SPRITE_PATH % tech_id
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		_tech_textures[tech_id] = tex
		return tex
	_tech_textures[tech_id] = null
	return null


func show_tech(
	tech_id: String,
	data: Dictionary,
	state: String,
	prereq_info: Array,
	leads_to_info: Array,
	progress: float = 0.0,
) -> void:
	_current_tech_id = tech_id
	var vbox: VBoxContainer = get_node("DetailVBox")

	# Name
	var name_lbl: Label = vbox.get_node("DetailName")
	name_lbl.text = data.get("name", tech_id)

	# Illustration image
	var image_rect: TextureRect = vbox.get_node("DetailImageContainer/DetailImageBg/DetailImage")
	var image_container: CenterContainer = vbox.get_node("DetailImageContainer")
	var tex: Texture2D = get_tech_texture(tech_id)
	if tex != null:
		image_rect.texture = tex
		image_rect.visible = true
		image_container.visible = true
	else:
		image_rect.texture = null
		image_rect.visible = false
		image_container.visible = false

	# Status
	var status_lbl: Label = vbox.get_node("DetailStatus")
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
		"busy":
			status_text = "RESEARCH IN PROGRESS"
			status_color = COLOR_UNAFFORDABLE
		_:
			status_text = "LOCKED"
			status_color = COLOR_LOCKED
	status_lbl.text = status_text
	status_lbl.add_theme_color_override("font_color", status_color)

	# Progress bar (visible only when researching)
	var progress_bar: ProgressBar = vbox.get_node("DetailProgressBar")
	if state == "researching":
		progress_bar.value = progress * 100.0
		progress_bar.visible = true
	else:
		progress_bar.value = 0.0
		progress_bar.visible = false

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
	var effects_lbl: Label = vbox.get_node("DetailEffectsMargin/DetailEffects")
	var effects_header: Label = vbox.get_node("DetailEffectsHeader")
	var formatted_effects: String = _format_effects(effects)
	if formatted_effects != "":
		effects_lbl.text = formatted_effects
		effects_header.visible = true
		effects_lbl.visible = true
		effects_lbl.get_parent().visible = true
	else:
		effects_header.visible = false
		effects_lbl.visible = false
		effects_lbl.get_parent().visible = false

	# Buildings unlocked
	var unlock_buildings: Array = effects.get("unlock_buildings", [])
	var unlocks_header: Label = vbox.get_node("DetailUnlocksHeader")
	var unlocks_lbl: Label = vbox.get_node("DetailUnlocksMargin/DetailUnlocks")
	var unlock_parts: Array[String] = []
	for bldg_name: Variant in unlock_buildings:
		unlock_parts.append(str(bldg_name).replace("_", " ").capitalize())
	# Units unlocked
	var unlock_units: Array = effects.get("unlock_units", [])
	for unit_name: Variant in unlock_units:
		unlock_parts.append(str(unit_name).replace("_", " ").capitalize())
	if not unlock_parts.is_empty():
		unlocks_lbl.text = "\n".join(unlock_parts)
		unlocks_header.visible = true
		unlocks_lbl.visible = true
		unlocks_lbl.get_parent().visible = true
	else:
		unlocks_header.visible = false
		unlocks_lbl.visible = false
		unlocks_lbl.get_parent().visible = false

	# Prerequisites
	var prereq_header: Label = vbox.get_node("DetailPrereqHeader")
	var prereq_lbl: Label = vbox.get_node("DetailPrereqsMargin/DetailPrereqs")
	if not prereq_info.is_empty():
		prereq_lbl.text = "\n".join(prereq_info)
		prereq_header.visible = true
		prereq_lbl.visible = true
		prereq_lbl.get_parent().visible = true
	else:
		prereq_header.visible = false
		prereq_lbl.visible = false
		prereq_lbl.get_parent().visible = false

	# Leads to
	var leads_header: Label = vbox.get_node("DetailLeadsToHeader")
	var leads_lbl: Label = vbox.get_node("DetailLeadsToMargin/DetailLeadsTo")
	if not leads_to_info.is_empty():
		leads_lbl.text = "\n".join(leads_to_info)
		leads_header.visible = true
		leads_lbl.visible = true
		leads_lbl.get_parent().visible = true
	else:
		leads_header.visible = false
		leads_lbl.visible = false
		leads_lbl.get_parent().visible = false

	# Research button
	var research_btn: Button = vbox.get_node("DetailResearchBtn")
	research_btn.visible = state == "available"

	slide_in(slide_target_x)


func update_progress(ratio: float) -> void:
	var vbox: VBoxContainer = get_node("DetailVBox")
	var progress_bar: ProgressBar = vbox.get_node("DetailProgressBar")
	progress_bar.value = ratio * 100.0


func hide_panel() -> void:
	_current_tech_id = ""
	visible = false
	_kill_slide_tween()


func slide_in(target_x: float = -1.0) -> void:
	## Animate the panel sliding in from the left to target_x.
	## If target_x is negative, defaults to viewport center.
	_kill_slide_tween()
	visible = true
	if target_x < 0.0:
		var viewport_size := get_viewport_rect().size
		target_x = (viewport_size.x - size.x) / 2.0
	position.x = -size.x
	_slide_tween = create_tween()
	_slide_tween.set_ease(Tween.EASE_OUT)
	_slide_tween.set_trans(Tween.TRANS_CUBIC)
	_slide_tween.tween_property(self, "position:x", target_x, SLIDE_DURATION)


func slide_out() -> void:
	## Animate the panel sliding out to the left, then hide.
	_kill_slide_tween()
	if not visible:
		return
	_slide_tween = create_tween()
	_slide_tween.set_ease(Tween.EASE_IN)
	_slide_tween.set_trans(Tween.TRANS_CUBIC)
	_slide_tween.tween_property(self, "position:x", -size.x, SLIDE_DURATION)
	_slide_tween.tween_callback(func() -> void: visible = false)


func _kill_slide_tween() -> void:
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	_slide_tween = null


func play_image_reveal() -> void:
	var vbox: VBoxContainer = get_node("DetailVBox")
	var image_rect: TextureRect = vbox.get_node("DetailImageContainer/DetailImageBg/DetailImage")
	if not image_rect.visible or image_rect.texture == null:
		return
	image_rect.modulate = Color(0.3, 0.3, 0.3, 1.0)
	var tween := create_tween()
	tween.tween_property(image_rect, "modulate", Color(1.8, 1.6, 0.8, 1.0), 0.5).set_ease(Tween.EASE_IN)
	tween.tween_property(image_rect, "modulate", Color.WHITE, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _build_contents() -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "DetailVBox"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

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
	close_btn.pressed.connect(func() -> void: close_requested.emit())
	_style_close_button(close_btn)
	close_row.add_child(close_btn)

	# Tech name
	var name_lbl := Label.new()
	name_lbl.name = "DetailName"
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)

	# Tech illustration image with dark background to blend white-bg art
	var image_container := CenterContainer.new()
	image_container.name = "DetailImageContainer"
	vbox.add_child(image_container)
	var image_bg := PanelContainer.new()
	image_bg.name = "DetailImageBg"
	var img_style := StyleBoxFlat.new()
	img_style.bg_color = Color(0.12, 0.12, 0.18, 1.0)
	img_style.set_corner_radius_all(8)
	img_style.set_content_margin_all(8)
	image_bg.add_theme_stylebox_override("panel", img_style)
	image_container.add_child(image_bg)
	var image_rect := TextureRect.new()
	image_rect.name = "DetailImage"
	image_rect.custom_minimum_size = DETAIL_IMAGE_SIZE
	image_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image_rect.visible = false
	image_bg.add_child(image_rect)

	# Status label
	var status_lbl := Label.new()
	status_lbl.name = "DetailStatus"
	status_lbl.add_theme_font_size_override("font_size", 14)
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_lbl)

	# Progress bar (shown when researching)
	var progress_bar := ProgressBar.new()
	progress_bar.name = "DetailProgressBar"
	progress_bar.custom_minimum_size = Vector2(0, 16)
	progress_bar.value = 0.0
	progress_bar.visible = false
	vbox.add_child(progress_bar)

	vbox.add_child(HSeparator.new())

	_add_label(vbox, "DetailDescription", 14, Color(0.85, 0.85, 0.85))
	_add_label(vbox, "DetailFlavor", 13, Color(0.6, 0.6, 0.5))
	vbox.add_child(HSeparator.new())
	_add_label(vbox, "DetailCost", 14, Color.WHITE)
	_add_label(vbox, "DetailTime", 14, Color.WHITE)
	vbox.add_child(HSeparator.new())
	_add_section_header(vbox, "DetailEffectsHeader", "Benefits", Color(0.7, 0.9, 0.7))
	_add_indented_label(vbox, "DetailEffects", 13, Color(0.8, 0.8, 0.8))
	_add_section_header(vbox, "DetailUnlocksHeader", "Unlocks", Color(0.9, 0.75, 0.5))
	_add_indented_label(vbox, "DetailUnlocks", 13, Color(0.8, 0.8, 0.8))
	vbox.add_child(HSeparator.new())
	_add_section_header(vbox, "DetailPrereqHeader", "Requires", Color(0.7, 0.7, 0.9))
	_add_indented_label(vbox, "DetailPrereqs", 13, Color(0.8, 0.8, 0.8))
	_add_section_header(vbox, "DetailLeadsToHeader", "Leads To", Color(0.9, 0.8, 0.6))
	_add_indented_label(vbox, "DetailLeadsTo", 13, Color(0.8, 0.8, 0.8))
	vbox.add_child(HSeparator.new())

	# Research button
	var research_btn := Button.new()
	research_btn.name = "DetailResearchBtn"
	research_btn.text = "Research"
	research_btn.custom_minimum_size = Vector2(0, 44)
	research_btn.pressed.connect(func() -> void: research_requested.emit(_current_tech_id))
	_style_research_button(research_btn)
	vbox.add_child(research_btn)


func _add_label(parent: VBoxContainer, lbl_name: String, font_size: int, color: Color) -> void:
	var lbl := Label.new()
	lbl.name = lbl_name
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(lbl)


func _add_indented_label(parent: VBoxContainer, lbl_name: String, font_size: int, color: Color) -> void:
	var margin := MarginContainer.new()
	margin.name = lbl_name + "Margin"
	margin.add_theme_constant_override("margin_left", 12)
	parent.add_child(margin)
	var lbl := Label.new()
	lbl.name = lbl_name
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	margin.add_child(lbl)


func _add_section_header(parent: VBoxContainer, lbl_name: String, text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.name = lbl_name
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", color)
	parent.add_child(lbl)


func _style_research_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = COLOR_AVAILABLE.darkened(0.5)
	normal.border_color = COLOR_AVAILABLE
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(6)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = COLOR_AVAILABLE.darkened(0.3)
	hover.border_color = COLOR_AVAILABLE.lightened(0.2)
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(6)
	hover.set_content_margin_all(6)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = COLOR_AVAILABLE.darkened(0.2)
	pressed_style.border_color = COLOR_AVAILABLE
	pressed_style.set_border_width_all(2)
	pressed_style.set_corner_radius_all(6)
	pressed_style.set_content_margin_all(6)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 16)


func _style_close_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.15, 0.15, 0.25, 0.8)
	normal.border_color = Color(0.4, 0.4, 0.6, 0.6)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.set_content_margin_all(4)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.3, 0.15, 0.15, 0.9)
	hover.border_color = Color(0.8, 0.3, 0.3)
	hover.set_border_width_all(1)
	hover.set_corner_radius_all(4)
	hover.set_content_margin_all(4)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.4, 0.4))


func _format_effects(effects: Dictionary) -> String:
	const SKIP_KEYS: Array[String] = ["unlock_buildings", "unlock_units"]
	var parts: Array[String] = []
	for key: String in effects:
		if key in SKIP_KEYS:
			continue
		var value: Variant = effects[key]
		var label: String = key.replace("_", " ").capitalize()
		if value is Dictionary:
			var sub_parts: Array[String] = []
			for sub_key: String in value:
				var sub_label: String = sub_key.replace("_", " ").capitalize()
				sub_parts.append("%s: %s" % [sub_label, _format_value(value[sub_key])])
			parts.append("%s: %s" % [label, ", ".join(sub_parts)])
		elif value is Array:
			var names: Array[String] = []
			for item: Variant in value:
				names.append(str(item).replace("_", " ").capitalize())
			parts.append("%s: %s" % [label, ", ".join(names)])
		else:
			parts.append("%s: %s" % [label, _format_value(value)])
	return "\n".join(parts)


func _format_value(value: Variant) -> String:
	## Formats a numeric value as a percentage if it is a decimal fraction,
	## otherwise returns the value as a string.
	if value is float or value is int:
		var f: float = float(value)
		if f != 0.0 and f > -1.0 and f < 1.0:
			return "%d%%" % int(f * 100.0)
	return str(value)
