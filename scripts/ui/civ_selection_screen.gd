extends PanelContainer
## Pre-game civilization selection screen.
## Shows civ cards with bonuses, unique units/buildings, and AI opponent picker.

signal civ_selected(player_civ: String, ai_civ: String)

const CIV_COLORS: Dictionary = {
	"mesopotamia": Color(0.76, 0.65, 0.36),
	"rome": Color(0.72, 0.15, 0.15),
	"polynesia": Color(0.20, 0.60, 0.60),
}

const DEFAULT_CIV_COLOR := Color(0.5, 0.5, 0.5)

var _selected_civ: String = ""
var _cards: Dictionary = {}  # {civ_id: PanelContainer}
var _card_styles: Dictionary = {}  # {civ_id: {normal: StyleBox, selected: StyleBox}}
var _start_btn: Button = null
var _ai_picker: OptionButton = null
var _civ_ids: Array = []


func _ready() -> void:
	visible = false
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.05, 0.05, 0.1, 0.92)
	add_theme_stylebox_override("panel", bg_style)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.name = "OuterVBox"
	outer_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer_vbox.add_theme_constant_override("separation", 20)
	add_child(outer_vbox)

	# Top spacer
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 40)
	outer_vbox.add_child(top_spacer)

	# Title
	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "Choose Your Civilization"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	outer_vbox.add_child(title)

	# Cards row
	var cards_hbox := HBoxContainer.new()
	cards_hbox.name = "CardsRow"
	cards_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_hbox.add_theme_constant_override("separation", 24)
	cards_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(cards_hbox)

	_civ_ids = DataLoader.get_all_civ_ids()
	for civ_id: String in _civ_ids:
		var card := _build_civ_card(civ_id)
		cards_hbox.add_child(card)

	# Bottom row: AI picker + Start button
	var bottom_row := HBoxContainer.new()
	bottom_row.name = "BottomRow"
	bottom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_row.add_theme_constant_override("separation", 20)
	outer_vbox.add_child(bottom_row)

	var ai_label := Label.new()
	ai_label.text = "AI Opponent:"
	ai_label.add_theme_font_size_override("font_size", 18)
	bottom_row.add_child(ai_label)

	_ai_picker = OptionButton.new()
	_ai_picker.name = "AIPicker"
	_ai_picker.custom_minimum_size = Vector2(160, 36)
	_ai_picker.add_item("Random", 0)
	for i in _civ_ids.size():
		var civ_data: Dictionary = DataLoader.get_civ_data(_civ_ids[i])
		var display_name: String = civ_data.get("name", _civ_ids[i])
		_ai_picker.add_item(display_name, i + 1)
	bottom_row.add_child(_ai_picker)

	var btn_spacer := Control.new()
	btn_spacer.custom_minimum_size = Vector2(40, 0)
	bottom_row.add_child(btn_spacer)

	_start_btn = Button.new()
	_start_btn.name = "StartButton"
	_start_btn.text = "Start Game"
	_start_btn.custom_minimum_size = Vector2(160, 44)
	_start_btn.disabled = true
	_start_btn.pressed.connect(_on_start_pressed)
	bottom_row.add_child(_start_btn)

	# Bottom spacer
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = Vector2(0, 30)
	outer_vbox.add_child(bottom_spacer)


func _build_civ_card(civ_id: String) -> PanelContainer:
	var civ_data: Dictionary = DataLoader.get_civ_data(civ_id)
	var civ_name: String = civ_data.get("name", civ_id.capitalize())
	var civ_color: Color = CIV_COLORS.get(civ_id, DEFAULT_CIV_COLOR)

	var card := PanelContainer.new()
	card.name = "Card_%s" % civ_id
	card.custom_minimum_size = Vector2(220, 340)

	# Normal style
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.12, 0.12, 0.18)
	normal_style.border_color = Color(0.3, 0.3, 0.4)
	normal_style.set_border_width_all(2)
	normal_style.set_corner_radius_all(6)
	normal_style.set_content_margin_all(12)

	# Selected style
	var selected_style := StyleBoxFlat.new()
	selected_style.bg_color = Color(0.15, 0.15, 0.25)
	selected_style.border_color = Color(1.0, 0.85, 0.3)
	selected_style.set_border_width_all(3)
	selected_style.set_corner_radius_all(6)
	selected_style.set_content_margin_all(12)

	_card_styles[civ_id] = {"normal": normal_style, "selected": selected_style}
	card.add_theme_stylebox_override("panel", normal_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	# Color banner
	var banner := ColorRect.new()
	banner.name = "Banner"
	banner.color = civ_color
	banner.custom_minimum_size = Vector2(0, 60)
	vbox.add_child(banner)

	# Civ name
	var name_label := Label.new()
	name_label.text = civ_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	vbox.add_child(name_label)

	# Description
	var desc_label := Label.new()
	desc_label.name = "DescLabel"
	desc_label.text = civ_data.get("description", "")
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_label)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Bonuses
	var bonuses: Dictionary = civ_data.get("bonuses", {})
	if not bonuses.is_empty():
		var bonus_header := Label.new()
		bonus_header.text = "Bonuses:"
		bonus_header.add_theme_font_size_override("font_size", 14)
		bonus_header.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
		vbox.add_child(bonus_header)
		for key: String in bonuses:
			var value: float = float(bonuses[key])
			var pct: int = int((value - 1.0) * 100.0)
			var bonus_label := Label.new()
			bonus_label.text = "  +%d%% %s" % [pct, key.replace("_", " ")]
			bonus_label.add_theme_font_size_override("font_size", 13)
			vbox.add_child(bonus_label)

	# Unique building
	var unique_bld: Dictionary = civ_data.get("unique_building", {})
	if not unique_bld.is_empty():
		var bld_label := Label.new()
		bld_label.name = "UniqueBuildingLabel"
		bld_label.text = "Building: %s" % unique_bld.get("name", "")
		bld_label.add_theme_font_size_override("font_size", 13)
		bld_label.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
		vbox.add_child(bld_label)

	# Unique unit
	var unique_unit: Dictionary = civ_data.get("unique_unit", {})
	if not unique_unit.is_empty():
		var unit_label := Label.new()
		unit_label.name = "UniqueUnitLabel"
		unit_label.text = "Unit: %s" % unique_unit.get("name", "")
		unit_label.add_theme_font_size_override("font_size", 13)
		unit_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
		vbox.add_child(unit_label)

	# Unique techs
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
		tech_label.add_theme_font_size_override("font_size", 12)
		tech_label.add_theme_color_override("font_color", Color(0.9, 0.7, 1.0))
		tech_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(tech_label)

	# Click detection
	card.gui_input.connect(func(event: InputEvent) -> void: _on_card_input(event, civ_id))

	_cards[civ_id] = card
	return card


func _on_card_input(event: InputEvent, civ_id: String) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_select_civ(civ_id)


func _select_civ(civ_id: String) -> void:
	_selected_civ = civ_id
	for id: String in _cards:
		var styles: Dictionary = _card_styles[id]
		if id == civ_id:
			_cards[id].add_theme_stylebox_override("panel", styles["selected"])
		else:
			_cards[id].add_theme_stylebox_override("panel", styles["normal"])
	if _start_btn != null:
		_start_btn.disabled = false


func _on_start_pressed() -> void:
	if _selected_civ == "":
		return
	var ai_civ := _resolve_ai_civ()
	civ_selected.emit(_selected_civ, ai_civ)
	hide_screen()


func _resolve_ai_civ() -> String:
	if _ai_picker == null:
		return _pick_random_ai_civ()
	var idx: int = _ai_picker.selected
	if idx <= 0:
		return _pick_random_ai_civ()
	# idx 1..N maps to _civ_ids[idx-1]
	var picked_id: String = _civ_ids[idx - 1]
	if picked_id == _selected_civ:
		return _pick_random_ai_civ()
	return picked_id


func _pick_random_ai_civ() -> String:
	var candidates: Array = []
	for civ_id: String in _civ_ids:
		if civ_id != _selected_civ:
			candidates.append(civ_id)
	if candidates.is_empty():
		return _civ_ids[0] if not _civ_ids.is_empty() else ""
	return candidates[randi() % candidates.size()]


func show_screen() -> void:
	visible = true


func hide_screen() -> void:
	visible = false


func get_selected_civ() -> String:
	return _selected_civ
