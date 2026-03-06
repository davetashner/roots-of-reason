extends PanelContainer
## Top-of-screen resource bar showing all resource amounts, population, and age.
## Reads configuration from data/settings/ui/hud.json.

const PLAYER_ID: int = 0
const RESOURCE_ORDER: Array[String] = ["Food", "Wood", "Stone", "Gold", "Knowledge"]

var _config: Dictionary = {}
var _resource_labels: Dictionary = {}
var _transit_labels: Dictionary = {}
var _population_label: Label
var _age_label: Label
var _corruption_item: HBoxContainer
var _corruption_label: Label
var _research_item: HBoxContainer
var _research_label: Label
var _research_progress_bar: ProgressBar
var _tech_manager: Node = null
var _river_transport: Node = null


func _ready() -> void:
	_load_config()
	_build_layout()
	_connect_signals()
	_refresh_all_resources()
	_update_age()


func _load_config() -> void:
	var data: Dictionary = DataLoader.get_settings("hud")
	if data.has("resource_bar"):
		_config = data["resource_bar"]


func _build_layout() -> void:
	# Panel styling
	var panel_style := StyleBoxFlat.new()
	var bg: Array = _config.get("background_color", [0.1, 0.1, 0.15, 0.85])
	panel_style.bg_color = Color(bg[0], bg[1], bg[2], bg[3])
	add_theme_stylebox_override("panel", panel_style)

	var bar_height: int = _config.get("height", 32)
	custom_minimum_size.y = bar_height
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Main horizontal container
	var hbox := HBoxContainer.new()
	hbox.name = "MainHBox"
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 16)
	add_child(hbox)

	# Left spacer
	var left_spacer := Control.new()
	left_spacer.custom_minimum_size.x = 8
	left_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(left_spacer)

	# Resource items
	var icon_size: int = _config.get("icon_size", 20)
	var font_size: int = _config.get("font_size", 16)
	var colors: Dictionary = _config.get("resource_colors", {})

	for resource_name in RESOURCE_ORDER:
		var item := HBoxContainer.new()
		item.name = "Res_%s" % resource_name
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_theme_constant_override("separation", 4)

		var icon := ColorRect.new()
		icon.name = "Icon"
		icon.custom_minimum_size = Vector2(icon_size, icon_size)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if colors.has(resource_name):
			var c: Array = colors[resource_name]
			icon.color = Color(c[0], c[1], c[2])
		item.add_child(icon)

		var lbl := Label.new()
		lbl.name = "Amount"
		lbl.text = "0"
		lbl.add_theme_font_size_override("font_size", font_size)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(lbl)

		var transit_size: int = _config.get("in_transit_font_size", 13)
		var transit_color_arr: Array = _config.get("in_transit_color", [0.5, 0.9, 0.5, 1.0])
		var transit_color := Color(
			transit_color_arr[0], transit_color_arr[1], transit_color_arr[2], transit_color_arr[3]
		)
		var transit_lbl := Label.new()
		transit_lbl.name = "Transit"
		transit_lbl.text = ""
		transit_lbl.add_theme_font_size_override("font_size", transit_size)
		transit_lbl.add_theme_color_override("font_color", transit_color)
		transit_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		transit_lbl.visible = false
		item.add_child(transit_lbl)

		hbox.add_child(item)
		_resource_labels[resource_name] = lbl
		_transit_labels[resource_name] = transit_lbl

	# Corruption indicator (hidden by default)
	_corruption_item = HBoxContainer.new()
	_corruption_item.name = "CorruptionItem"
	_corruption_item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_corruption_item.add_theme_constant_override("separation", 4)
	_corruption_item.visible = false

	var corruption_icon := ColorRect.new()
	corruption_icon.name = "Icon"
	corruption_icon.custom_minimum_size = Vector2(icon_size, icon_size)
	corruption_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corruption_icon.color = Color(0.6, 0.1, 0.1)
	_corruption_item.add_child(corruption_icon)

	_corruption_label = Label.new()
	_corruption_label.name = "Amount"
	_corruption_label.text = "-0%"
	_corruption_label.add_theme_font_size_override("font_size", font_size)
	_corruption_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	_corruption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_corruption_item.add_child(_corruption_label)

	hbox.add_child(_corruption_item)

	# Separator
	var sep1 := VSeparator.new()
	sep1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(sep1)

	# Population label
	_population_label = Label.new()
	_population_label.name = "PopulationLabel"
	_population_label.text = "Pop: 0/5"
	_population_label.add_theme_font_size_override("font_size", font_size)
	_population_label.add_theme_color_override("font_color", Color.WHITE)
	_population_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_population_label)

	# Separator
	var sep2 := VSeparator.new()
	sep2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(sep2)

	# Age label
	_age_label = Label.new()
	_age_label.name = "AgeLabel"
	_age_label.text = GameManager.get_age_name()
	_age_label.add_theme_font_size_override("font_size", font_size)
	_age_label.add_theme_color_override("font_color", Color.WHITE)
	_age_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_age_label)

	# Separator before research
	var sep3 := VSeparator.new()
	sep3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(sep3)

	# Research indicator (hidden when idle)
	_research_item = HBoxContainer.new()
	_research_item.name = "ResearchItem"
	_research_item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_research_item.add_theme_constant_override("separation", 4)
	_research_item.visible = false

	var research_icon := ColorRect.new()
	research_icon.name = "Icon"
	research_icon.custom_minimum_size = Vector2(icon_size, icon_size)
	research_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	research_icon.color = Color(0.3, 0.6, 1.0)
	_research_item.add_child(research_icon)

	_research_label = Label.new()
	_research_label.name = "ResearchLabel"
	_research_label.text = ""
	_research_label.add_theme_font_size_override("font_size", font_size)
	_research_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_research_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_research_item.add_child(_research_label)

	_research_progress_bar = ProgressBar.new()
	_research_progress_bar.name = "ResearchProgress"
	_research_progress_bar.custom_minimum_size = Vector2(80, 14)
	_research_progress_bar.min_value = 0.0
	_research_progress_bar.max_value = 1.0
	_research_progress_bar.value = 0.0
	_research_progress_bar.show_percentage = false
	_research_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.15, 0.15, 0.2, 0.8)
	_research_progress_bar.add_theme_stylebox_override("background", bar_bg)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.3, 0.6, 1.0, 0.9)
	_research_progress_bar.add_theme_stylebox_override("fill", bar_fill)
	_research_item.add_child(_research_progress_bar)

	hbox.add_child(_research_item)

	# Right spacer to push content left
	var right_spacer := Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(right_spacer)


func _connect_signals() -> void:
	ResourceManager.resources_changed.connect(_on_resources_changed)
	EventBus.age_advanced.connect(_on_age_advanced)


func _refresh_all_resources() -> void:
	for resource_name in RESOURCE_ORDER:
		var res_type: int = _resource_name_to_type(resource_name)
		if res_type >= 0:
			var amount: int = ResourceManager.get_amount(PLAYER_ID, res_type as ResourceManager.ResourceType)
			_update_resource_label(resource_name, amount)


func _on_resources_changed(player_id: int, resource_type: String, _old_amount: int, new_amount: int) -> void:
	if player_id != PLAYER_ID:
		return
	_update_resource_label(resource_type, new_amount)


func _update_resource_label(resource_name: String, amount: int) -> void:
	if resource_name in _resource_labels:
		_resource_labels[resource_name].text = format_amount(amount)


func setup_transit(river_transport: Node) -> void:
	_river_transport = river_transport
	if _river_transport != null:
		if _river_transport.has_signal("barge_dispatched"):
			_river_transport.barge_dispatched.connect(_on_transit_changed)
		if _river_transport.has_signal("barge_arrived"):
			_river_transport.barge_arrived.connect(_on_transit_changed)
		if _river_transport.has_signal("barge_destroyed"):
			_river_transport.barge_destroyed.connect(_on_transit_changed)
		_update_transit_labels()


func _on_transit_changed(_barge: Node2D) -> void:
	_update_transit_labels()


func _update_transit_labels() -> void:
	if _river_transport == null or not _river_transport.has_method("get_in_transit_resources"):
		return
	var in_transit: Dictionary = _river_transport.get_in_transit_resources(PLAYER_ID)
	for resource_name: String in RESOURCE_ORDER:
		var res_type: int = _resource_name_to_type(resource_name)
		if not _transit_labels.has(resource_name):
			continue
		var transit_lbl: Label = _transit_labels[resource_name]
		var amount: int = in_transit.get(res_type, 0)
		if amount > 0:
			transit_lbl.text = "(+%s)" % format_amount(amount)
			transit_lbl.visible = true
		else:
			transit_lbl.text = ""
			transit_lbl.visible = false


func flash_resource(resource_name: String) -> void:
	if resource_name not in _resource_labels:
		return
	var lbl: Label = _resource_labels[resource_name]
	var flash_color_arr: Array = _config.get("flash_color", [1.0, 0.2, 0.2, 1.0])
	var flash_color := Color(flash_color_arr[0], flash_color_arr[1], flash_color_arr[2], flash_color_arr[3])
	var duration: float = _config.get("flash_duration", 0.3)

	lbl.add_theme_color_override("font_color", flash_color)
	var tween := create_tween()
	tween.tween_method(
		func(c: Color) -> void: lbl.add_theme_color_override("font_color", c),
		flash_color,
		Color.WHITE,
		duration,
	)


static func format_amount(amount: int) -> String:
	if amount < 0:
		return str(amount)
	if amount < 1000:
		return str(amount)
	@warning_ignore("integer_division")
	var whole: int = amount / 1000
	@warning_ignore("integer_division")
	var frac: int = (amount % 1000) / 100
	if frac > 0:
		return "%d.%dk" % [whole, frac]
	return "%dk" % whole


func update_corruption(rate: float) -> void:
	if _corruption_item == null:
		return
	if rate <= 0.0:
		_corruption_item.visible = false
		return
	_corruption_item.visible = true
	@warning_ignore("narrowing_conversion")
	var pct: int = int(rate * 100.0)
	_corruption_label.text = "-%d%%" % pct


func update_population(current: int, cap: int) -> void:
	if _population_label != null:
		_population_label.text = "Pop: %d/%d" % [current, cap]


func _on_age_advanced(player_id: int, _new_age: int) -> void:
	if player_id == PLAYER_ID:
		_update_age()


func update_age() -> void:
	_update_age()


func _update_age() -> void:
	if _age_label != null:
		_age_label.text = GameManager.get_age_name()


func setup_tech_manager(tech_manager: Node) -> void:
	_tech_manager = tech_manager
	if _tech_manager == null:
		return
	_tech_manager.tech_research_started.connect(_on_research_started)
	_tech_manager.research_progress.connect(_on_research_progress)
	_tech_manager.tech_researched.connect(_on_tech_researched)
	_tech_manager.research_queue_changed.connect(_on_research_queue_changed)
	# Show current research if already in progress
	_refresh_research_indicator()


func _on_research_started(player_id: int, tech_id: String) -> void:
	if player_id != PLAYER_ID:
		return
	_show_research(tech_id, 0.0)


func _on_research_progress(player_id: int, _tech_id: String, progress: float) -> void:
	if player_id != PLAYER_ID:
		return
	if _research_progress_bar != null:
		_research_progress_bar.value = progress


func _on_tech_researched(player_id: int, _tech_id: String, _effects: Dictionary) -> void:
	if player_id != PLAYER_ID:
		return
	_refresh_research_indicator()


func _on_research_queue_changed(player_id: int) -> void:
	if player_id != PLAYER_ID:
		return
	_refresh_research_indicator()


func _refresh_research_indicator() -> void:
	if _tech_manager == null:
		_hide_research()
		return
	var tech_id: String = _tech_manager.get_current_research(PLAYER_ID)
	if tech_id == "":
		_hide_research()
		return
	var progress: float = _tech_manager.get_research_progress(PLAYER_ID)
	_show_research(tech_id, progress)


func _show_research(tech_id: String, progress: float) -> void:
	if _research_item == null:
		return
	var tech_data: Dictionary = _tech_manager.get_tech_data(tech_id)
	var tech_name: String = tech_data.get("name", tech_id)
	_research_label.text = tech_name
	_research_progress_bar.value = progress
	_research_item.visible = true


func _hide_research() -> void:
	if _research_item == null:
		return
	_research_item.visible = false


func _resource_name_to_type(resource_name: String) -> int:
	match resource_name:
		"Food":
			return ResourceManager.ResourceType.FOOD
		"Wood":
			return ResourceManager.ResourceType.WOOD
		"Stone":
			return ResourceManager.ResourceType.STONE
		"Gold":
			return ResourceManager.ResourceType.GOLD
		"Knowledge":
			return ResourceManager.ResourceType.KNOWLEDGE
	return -1
