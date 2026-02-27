extends PanelContainer
## Pre-game civilization selection screen.
## Shows civ cards with bonuses, unique units/buildings, and AI opponent picker.

signal civ_selected(player_civ: String, ai_civ: String)

## CivCardBuilder uses default options which match this screen's sizing.

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
	var card := CivCardBuilder.build(civ_id, _card_styles, _cards)
	card.gui_input.connect(func(event: InputEvent) -> void: _on_card_input(event, civ_id))
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
