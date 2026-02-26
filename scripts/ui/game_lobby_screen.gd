extends PanelContainer
## Pre-game lobby screen — configure difficulty, map size, and pick civilizations.

signal start_game(settings: Dictionary)
signal back_pressed

const CIV_COLORS: Dictionary = {
	"mesopotamia": Color(0.76, 0.65, 0.36),
	"rome": Color(0.72, 0.15, 0.15),
	"polynesia": Color(0.20, 0.60, 0.60),
}
const DEFAULT_CIV_COLOR := Color(0.5, 0.5, 0.5)

var _selected_civ: String = ""
var _cards: Dictionary = {}
var _card_styles: Dictionary = {}
var _start_btn: Button = null
var _back_btn: Button = null
var _difficulty_picker: OptionButton = null
var _map_size_picker: OptionButton = null
var _ai_picker: OptionButton = null
var _civ_ids: Array = []
var _difficulty_keys: Array[String] = []
var _map_size_keys: Array[String] = []


func _ready() -> void:
	visible = false
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.05, 0.05, 0.1, 0.95)
	add_theme_stylebox_override("panel", bg_style)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.name = "OuterVBox"
	outer_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer_vbox.add_theme_constant_override("separation", 16)
	add_child(outer_vbox)

	# Top spacer
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 30)
	outer_vbox.add_child(top_spacer)

	# Title
	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "Game Lobby"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	outer_vbox.add_child(title)

	# Two-column layout
	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.add_theme_constant_override("separation", 40)
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(columns)

	# Left column: game settings
	var left_col := VBoxContainer.new()
	left_col.name = "SettingsColumn"
	left_col.add_theme_constant_override("separation", 16)
	left_col.custom_minimum_size = Vector2(280, 0)
	columns.add_child(left_col)

	_build_settings_column(left_col)

	# Right column: civ selection
	var right_col := VBoxContainer.new()
	right_col.name = "CivColumn"
	right_col.add_theme_constant_override("separation", 12)
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right_col)

	_build_civ_column(right_col)

	# Bottom row: Back + Start buttons
	var bottom_row := HBoxContainer.new()
	bottom_row.name = "BottomRow"
	bottom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_row.add_theme_constant_override("separation", 20)
	outer_vbox.add_child(bottom_row)

	_back_btn = Button.new()
	_back_btn.name = "BackButton"
	_back_btn.text = "Back"
	_back_btn.custom_minimum_size = Vector2(140, 44)
	_back_btn.pressed.connect(_on_back_pressed)
	bottom_row.add_child(_back_btn)

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
	bottom_spacer.custom_minimum_size = Vector2(0, 20)
	outer_vbox.add_child(bottom_spacer)


func _build_settings_column(parent: VBoxContainer) -> void:
	var header := Label.new()
	header.text = "Game Settings"
	header.add_theme_font_size_override("font_size", 24)
	header.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	parent.add_child(header)

	# AI Difficulty
	var diff_label := Label.new()
	diff_label.text = "AI Difficulty:"
	diff_label.add_theme_font_size_override("font_size", 16)
	parent.add_child(diff_label)

	_difficulty_picker = OptionButton.new()
	_difficulty_picker.name = "DifficultyPicker"
	_difficulty_picker.custom_minimum_size = Vector2(200, 36)
	parent.add_child(_difficulty_picker)
	_populate_difficulty_picker()

	# Map Size
	var map_label := Label.new()
	map_label.text = "Map Size:"
	map_label.add_theme_font_size_override("font_size", 16)
	parent.add_child(map_label)

	_map_size_picker = OptionButton.new()
	_map_size_picker.name = "MapSizePicker"
	_map_size_picker.custom_minimum_size = Vector2(200, 36)
	parent.add_child(_map_size_picker)
	_populate_map_size_picker()

	# Opponents
	var opp_label := Label.new()
	opp_label.text = "Opponents:"
	opp_label.add_theme_font_size_override("font_size", 16)
	parent.add_child(opp_label)

	var opp_value := Label.new()
	opp_value.name = "OpponentsValue"
	opp_value.text = "1 AI Opponent"
	opp_value.add_theme_font_size_override("font_size", 14)
	opp_value.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	parent.add_child(opp_value)

	# AI Civ picker
	var ai_label := Label.new()
	ai_label.text = "AI Civilization:"
	ai_label.add_theme_font_size_override("font_size", 16)
	parent.add_child(ai_label)

	_ai_picker = OptionButton.new()
	_ai_picker.name = "AICivPicker"
	_ai_picker.custom_minimum_size = Vector2(200, 36)
	parent.add_child(_ai_picker)
	_populate_ai_picker()


func _build_civ_column(parent: VBoxContainer) -> void:
	var header := Label.new()
	header.text = "Choose Your Civilization"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 24)
	header.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	parent.add_child(header)

	var cards_hbox := HBoxContainer.new()
	cards_hbox.name = "CardsRow"
	cards_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_hbox.add_theme_constant_override("separation", 16)
	cards_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(cards_hbox)

	_civ_ids = DataLoader.get_all_civ_ids()
	for civ_id: String in _civ_ids:
		var card := _build_civ_card(civ_id)
		cards_hbox.add_child(card)


func _populate_difficulty_picker() -> void:
	var data: Dictionary = DataLoader.load_json("res://data/ai/ai_difficulty.json")
	var tiers: Dictionary = data.get("tiers", {})
	var default_tier: String = data.get("default", "normal")
	var default_idx: int = 0
	var idx: int = 0
	for tier_name: String in tiers:
		_difficulty_keys.append(tier_name)
		_difficulty_picker.add_item(tier_name.capitalize(), idx)
		if tier_name == default_tier:
			default_idx = idx
		idx += 1
	_difficulty_picker.selected = default_idx


func _populate_map_size_picker() -> void:
	var data: Dictionary = DataLoader.load_json("res://data/settings/map_generation.json")
	var sizes: Dictionary = data.get("map_sizes", {})
	var default_size: String = data.get("default_size", "dev")
	var default_idx: int = 0
	var idx: int = 0
	for size_name: String in sizes:
		_map_size_keys.append(size_name)
		var display: String = size_name.capitalize()
		if size_name != "dev":
			display += " (Coming Soon)"
		_map_size_picker.add_item(display, idx)
		if size_name != "dev":
			_map_size_picker.set_item_disabled(idx, true)
		if size_name == default_size:
			default_idx = idx
		idx += 1
	_map_size_picker.selected = default_idx


func _populate_ai_picker() -> void:
	_ai_picker.add_item("Random", 0)
	var civ_ids: Array = DataLoader.get_all_civ_ids()
	for i in civ_ids.size():
		var civ_data: Dictionary = DataLoader.get_civ_data(civ_ids[i])
		var display_name: String = civ_data.get("name", civ_ids[i])
		_ai_picker.add_item(display_name, i + 1)


func _build_civ_card(civ_id: String) -> PanelContainer:
	var civ_data: Dictionary = DataLoader.get_civ_data(civ_id)
	var civ_name: String = civ_data.get("name", civ_id.capitalize())
	var civ_color: Color = CIV_COLORS.get(civ_id, DEFAULT_CIV_COLOR)

	var card := PanelContainer.new()
	card.name = "Card_%s" % civ_id
	card.custom_minimum_size = Vector2(200, 300)

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.12, 0.12, 0.18)
	normal_style.border_color = Color(0.3, 0.3, 0.4)
	normal_style.set_border_width_all(2)
	normal_style.set_corner_radius_all(6)
	normal_style.set_content_margin_all(10)

	var selected_style := StyleBoxFlat.new()
	selected_style.bg_color = Color(0.15, 0.15, 0.25)
	selected_style.border_color = Color(1.0, 0.85, 0.3)
	selected_style.set_border_width_all(3)
	selected_style.set_corner_radius_all(6)
	selected_style.set_content_margin_all(10)

	_card_styles[civ_id] = {"normal": normal_style, "selected": selected_style}
	card.add_theme_stylebox_override("panel", normal_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# Color banner
	var banner := ColorRect.new()
	banner.name = "Banner"
	banner.color = civ_color
	banner.custom_minimum_size = Vector2(0, 50)
	vbox.add_child(banner)

	# Civ name
	var name_label := Label.new()
	name_label.text = civ_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	vbox.add_child(name_label)

	# Description
	var desc_label := Label.new()
	desc_label.name = "DescLabel"
	desc_label.text = civ_data.get("description", "")
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_label)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Bonuses summary
	var bonuses: Dictionary = civ_data.get("bonuses", {})
	if not bonuses.is_empty():
		for key: String in bonuses:
			var value: float = float(bonuses[key])
			var pct: int = int((value - 1.0) * 100.0)
			var bonus_label := Label.new()
			bonus_label.text = "+%d%% %s" % [pct, key.replace("_", " ")]
			bonus_label.add_theme_font_size_override("font_size", 12)
			bonus_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
			vbox.add_child(bonus_label)

	# Unique building
	var unique_bld: Dictionary = civ_data.get("unique_building", {})
	if not unique_bld.is_empty():
		var bld_label := Label.new()
		bld_label.name = "UniqueBuildingLabel"
		bld_label.text = "Building: %s" % unique_bld.get("name", "")
		bld_label.add_theme_font_size_override("font_size", 12)
		bld_label.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
		vbox.add_child(bld_label)

	# Unique unit
	var unique_unit: Dictionary = civ_data.get("unique_unit", {})
	if not unique_unit.is_empty():
		var unit_label := Label.new()
		unit_label.name = "UniqueUnitLabel"
		unit_label.text = "Unit: %s" % unique_unit.get("name", "")
		unit_label.add_theme_font_size_override("font_size", 12)
		unit_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
		vbox.add_child(unit_label)

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
	var settings := {
		"player_civ": _selected_civ,
		"ai_civ": _resolve_ai_civ(),
		"difficulty": _get_selected_difficulty(),
		"map_size": _get_selected_map_size(),
	}
	start_game.emit(settings)
	hide_screen()


func _on_back_pressed() -> void:
	back_pressed.emit()
	hide_screen()


func _get_selected_difficulty() -> String:
	var idx: int = _difficulty_picker.selected
	if idx >= 0 and idx < _difficulty_keys.size():
		return _difficulty_keys[idx]
	return "normal"


func _get_selected_map_size() -> String:
	var idx: int = _map_size_picker.selected
	if idx >= 0 and idx < _map_size_keys.size():
		return _map_size_keys[idx]
	return "dev"


func _resolve_ai_civ() -> String:
	if _ai_picker == null:
		return _pick_random_ai_civ()
	var idx: int = _ai_picker.selected
	if idx <= 0:
		return _pick_random_ai_civ()
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
