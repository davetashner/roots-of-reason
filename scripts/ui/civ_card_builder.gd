class_name CivCardBuilder
## Shared utility for building civilization selection cards.
## Used by both game_lobby_screen.gd and civ_selection_screen.gd.

const CIV_COLORS: Dictionary = {
	"mesopotamia": Color(0.76, 0.65, 0.36),
	"rome": Color(0.72, 0.15, 0.15),
	"polynesia": Color(0.20, 0.60, 0.60),
}
const DEFAULT_CIV_COLOR := Color(0.5, 0.5, 0.5)

## Default sizing options. Override individual keys for different contexts.
const DEFAULT_OPTIONS: Dictionary = {
	"card_size": Vector2(220, 340),
	"content_margin": 12,
	"banner_height": 60,
	"name_font_size": 24,
	"desc_font_size": 12,
	"bonus_font_size": 13,
	"detail_font_size": 13,
	"separation": 6,
	"show_bonus_header": true,
	"indent_bonuses": true,
	"show_unique_techs": true,
}


static func build(
	civ_id: String,
	card_styles: Dictionary,
	cards: Dictionary,
	options: Dictionary = {},
) -> PanelContainer:
	var opts := _merge_options(options)
	var civ_data: Dictionary = DataLoader.get_civ_data(civ_id)
	var civ_name: String = civ_data.get("name", civ_id.capitalize())
	var civ_color: Color = CIV_COLORS.get(civ_id, DEFAULT_CIV_COLOR)

	var card := PanelContainer.new()
	card.name = "Card_%s" % civ_id
	card.custom_minimum_size = opts["card_size"]

	var margin: int = int(opts["content_margin"])

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.12, 0.12, 0.18)
	normal_style.border_color = Color(0.3, 0.3, 0.4)
	normal_style.set_border_width_all(2)
	normal_style.set_corner_radius_all(6)
	normal_style.set_content_margin_all(margin)

	var selected_style := StyleBoxFlat.new()
	selected_style.bg_color = Color(0.15, 0.15, 0.25)
	selected_style.border_color = Color(1.0, 0.85, 0.3)
	selected_style.set_border_width_all(3)
	selected_style.set_corner_radius_all(6)
	selected_style.set_content_margin_all(margin)

	card_styles[civ_id] = {"normal": normal_style, "selected": selected_style}
	card.add_theme_stylebox_override("panel", normal_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(opts["separation"]))
	card.add_child(vbox)

	# Color banner
	var banner := ColorRect.new()
	banner.name = "Banner"
	banner.color = civ_color
	banner.custom_minimum_size = Vector2(0, float(opts["banner_height"]))
	vbox.add_child(banner)

	# Civ name
	var name_label := Label.new()
	name_label.text = civ_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", int(opts["name_font_size"]))
	name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	vbox.add_child(name_label)

	# Description
	var desc_label := Label.new()
	desc_label.name = "DescLabel"
	desc_label.text = civ_data.get("description", "")
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.add_theme_font_size_override("font_size", int(opts["desc_font_size"]))
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_label)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Bonuses
	var bonuses: Dictionary = civ_data.get("bonuses", {})
	if not bonuses.is_empty():
		if opts["show_bonus_header"]:
			var bonus_header := Label.new()
			bonus_header.text = "Bonuses:"
			bonus_header.add_theme_font_size_override("font_size", int(opts["bonus_font_size"]) + 1)
			bonus_header.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
			vbox.add_child(bonus_header)
		var indent: String = "  " if opts["indent_bonuses"] else ""
		for key: String in bonuses:
			var value: float = float(bonuses[key])
			var pct: int = int((value - 1.0) * 100.0)
			var bonus_label := Label.new()
			bonus_label.text = "%s+%d%% %s" % [indent, pct, key.replace("_", " ")]
			bonus_label.add_theme_font_size_override("font_size", int(opts["bonus_font_size"]))
			bonus_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
			vbox.add_child(bonus_label)

	# Unique building
	var unique_bld: Dictionary = civ_data.get("unique_building", {})
	if not unique_bld.is_empty():
		var bld_label := Label.new()
		bld_label.name = "UniqueBuildingLabel"
		bld_label.text = "Building: %s" % unique_bld.get("name", "")
		bld_label.add_theme_font_size_override("font_size", int(opts["detail_font_size"]))
		bld_label.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
		vbox.add_child(bld_label)

	# Unique unit
	var unique_unit: Dictionary = civ_data.get("unique_unit", {})
	if not unique_unit.is_empty():
		var unit_label := Label.new()
		unit_label.name = "UniqueUnitLabel"
		unit_label.text = "Unit: %s" % unique_unit.get("name", "")
		unit_label.add_theme_font_size_override("font_size", int(opts["detail_font_size"]))
		unit_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
		vbox.add_child(unit_label)

	# Unique techs (optional)
	if opts["show_unique_techs"]:
		var unique_techs: Array = civ_data.get("unique_techs", [])
		if not unique_techs.is_empty():
			var tech_names: Array[String] = []
			for tech_id: String in unique_techs:
				var tech_data: Dictionary = DataLoader.get_tech_data(tech_id)
				var tname: String = tech_data.get("name", tech_id.replace("_", " ").capitalize())
				tech_names.append(tname)
			var tech_label := Label.new()
			tech_label.name = "UniqueTechsLabel"
			tech_label.text = "Techs: %s" % ", ".join(tech_names)
			tech_label.add_theme_font_size_override("font_size", int(opts["desc_font_size"]))
			tech_label.add_theme_color_override("font_color", Color(0.9, 0.7, 1.0))
			tech_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vbox.add_child(tech_label)

	cards[civ_id] = card
	return card


static func _merge_options(overrides: Dictionary) -> Dictionary:
	var result := DEFAULT_OPTIONS.duplicate()
	for key: String in overrides:
		result[key] = overrides[key]
	return result
