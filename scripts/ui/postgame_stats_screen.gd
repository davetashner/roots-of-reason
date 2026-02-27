extends PanelContainer
## Post-game statistics overlay showing cumulative stats with tabs and graphs.

signal closed

const StatsGraphRendererScript := preload("res://scripts/ui/stats_graph_renderer.gd")
const TAB_NAMES: Array[String] = ["Summary", "Economy", "Military", "Technology"]

var _config: Dictionary = {}
var _stats_data: Dictionary = {}
var _game_time: float = 0.0
var _player_colors: Dictionary = {}
var _current_tab: int = 0

var _tab_buttons: Array[Button] = []
var _tab_containers: Array[Control] = []
var _scroll: ScrollContainer = null
var _content_box: VBoxContainer = null


func _ready() -> void:
	visible = false
	_load_config()
	_build_ui()


func _load_config() -> void:
	var json_text := FileAccess.get_file_as_string("res://data/settings/ui/postgame_stats.json")
	if json_text != "":
		var parsed: Variant = JSON.parse_string(json_text)
		if parsed is Dictionary:
			_config = parsed
	var colors_cfg: Dictionary = _config.get("player_colors", {"0": "#4A90D9", "1": "#D94A4A"})
	for key: String in colors_cfg:
		_player_colors[int(key)] = Color.from_string(colors_cfg[key], Color.WHITE)


func show_stats(stats_data: Dictionary, game_time: float) -> void:
	_stats_data = stats_data
	_game_time = game_time
	_rebuild_tabs()
	_switch_tab(0)
	visible = true


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.95)
	add_theme_stylebox_override("panel", style)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.name = "OuterVBox"
	outer_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer_vbox.add_theme_constant_override("separation", 8)
	add_child(outer_vbox)

	# Header row
	var header_row := HBoxContainer.new()
	header_row.name = "HeaderRow"
	outer_vbox.add_child(header_row)

	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "POST-GAME STATISTICS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	header_row.add_child(title)

	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(40, 40)
	close_btn.pressed.connect(_on_close_pressed)
	header_row.add_child(close_btn)

	# Tab bar
	var tab_bar := HBoxContainer.new()
	tab_bar.name = "TabBar"
	tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_bar.add_theme_constant_override("separation", 4)
	outer_vbox.add_child(tab_bar)

	for i in range(TAB_NAMES.size()):
		var btn := Button.new()
		btn.name = "Tab_%s" % TAB_NAMES[i]
		btn.text = TAB_NAMES[i]
		btn.custom_minimum_size = Vector2(120, 36)
		btn.pressed.connect(_on_tab_pressed.bind(i))
		tab_bar.add_child(btn)
		_tab_buttons.append(btn)

	# Scroll area for content
	_scroll = ScrollContainer.new()
	_scroll.name = "ScrollContainer"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(_scroll)

	_content_box = VBoxContainer.new()
	_content_box.name = "ContentBox"
	_content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_box.add_theme_constant_override("separation", 12)
	_scroll.add_child(_content_box)

	# Footer
	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	outer_vbox.add_child(footer)

	var menu_btn := Button.new()
	menu_btn.name = "ReturnToMenuButton"
	menu_btn.text = "Return to Menu"
	menu_btn.custom_minimum_size = Vector2(180, 40)
	menu_btn.pressed.connect(_on_return_to_menu)
	footer.add_child(menu_btn)


func _rebuild_tabs() -> void:
	# Clear existing tab content
	_tab_containers.clear()
	for child in _content_box.get_children():
		child.queue_free()

	for i in range(TAB_NAMES.size()):
		var container := VBoxContainer.new()
		container.name = "TabContent_%s" % TAB_NAMES[i]
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.add_theme_constant_override("separation", 8)
		_content_box.add_child(container)
		_tab_containers.append(container)

	_build_summary_tab()
	_build_economy_tab()
	_build_military_tab()
	_build_technology_tab()


func _switch_tab(index: int) -> void:
	_current_tab = index
	for i in range(_tab_containers.size()):
		_tab_containers[i].visible = (i == index)
	for i in range(_tab_buttons.size()):
		_tab_buttons[i].disabled = (i == index)


func _on_tab_pressed(index: int) -> void:
	_switch_tab(index)


func _on_close_pressed() -> void:
	visible = false
	closed.emit()


func _on_return_to_menu() -> void:
	visible = false
	GameManager.reset_game_state()
	ResourceManager.reset()
	CivBonusManager.reset()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


# --- Summary Tab ---


func _build_summary_tab() -> void:
	if _tab_containers.size() < 1:
		return
	var container: VBoxContainer = _tab_containers[0]
	var p0: Dictionary = _stats_data.get(0, _stats_data.get("0", {}))
	var p1: Dictionary = _stats_data.get(1, _stats_data.get("1", {}))

	_add_section_header(container, "Game Duration: %s" % _format_time(_game_time))

	var rows: Array[Dictionary] = [
		{
			"label": "Resources Gathered",
			"p0": _sum_dict(p0.get("resources_gathered", {})),
			"p1": _sum_dict(p1.get("resources_gathered", {}))
		},
		{
			"label": "Resources Spent",
			"p0": _sum_dict(p0.get("resources_spent", {})),
			"p1": _sum_dict(p1.get("resources_spent", {}))
		},
		{
			"label": "Units Produced",
			"p0": _sum_dict(p0.get("units_produced", {})),
			"p1": _sum_dict(p1.get("units_produced", {}))
		},
		{"label": "Units Killed", "p0": int(p0.get("units_killed", 0)), "p1": int(p1.get("units_killed", 0))},
		{"label": "Units Lost", "p0": int(p0.get("units_lost", 0)), "p1": int(p1.get("units_lost", 0))},
		{
			"label": "Buildings Built",
			"p0": _sum_dict(p0.get("buildings_built", {})),
			"p1": _sum_dict(p1.get("buildings_built", {}))
		},
		{"label": "Buildings Lost", "p0": int(p0.get("buildings_lost", 0)), "p1": int(p1.get("buildings_lost", 0))},
		{
			"label": "Techs Researched",
			"p0": p0.get("techs_researched", []).size(),
			"p1": p1.get("techs_researched", []).size()
		},
	]

	for row: Dictionary in rows:
		_add_comparison_row(container, row["label"], int(row["p0"]), int(row["p1"]))


# --- Economy Tab ---


func _build_economy_tab() -> void:
	if _tab_containers.size() < 2:
		return
	var container: VBoxContainer = _tab_containers[1]

	# Line graph: resources over time
	_add_section_header(container, "Resources Over Time")
	var line_graph := _create_graph(container)
	var series: Array = _build_resource_time_series()
	var x_labels: Array = _build_time_labels()
	line_graph.set_data(series, x_labels, "Total Resources")

	# Bar chart: gathered by type
	_add_section_header(container, "Resources Gathered by Type")
	var bar_graph := _create_graph(container)
	var bar_series: Array = _build_resource_type_bars()
	var resource_types: Array = _get_all_resource_types()
	bar_graph.set_data(bar_series, resource_types, "Amount", StatsGraphRendererScript.ChartType.BAR)


# --- Military Tab ---


func _build_military_tab() -> void:
	if _tab_containers.size() < 3:
		return
	var container: VBoxContainer = _tab_containers[2]

	# Line graph: kills over time
	_add_section_header(container, "Kills Over Time")
	var line_graph := _create_graph(container)
	var series: Array = _build_kills_time_series()
	var x_labels: Array = _build_time_labels()
	line_graph.set_data(series, x_labels, "Kills")

	# Bar chart: units produced by type
	_add_section_header(container, "Units Produced by Type")
	var bar_graph := _create_graph(container)
	var bar_series: Array = _build_unit_type_bars()
	var unit_types: Array = _get_all_unit_types()
	bar_graph.set_data(bar_series, unit_types, "Count", StatsGraphRendererScript.ChartType.BAR)


# --- Technology Tab ---


func _build_technology_tab() -> void:
	if _tab_containers.size() < 4:
		return
	var container: VBoxContainer = _tab_containers[3]

	# Bar chart: time per age
	_add_section_header(container, "Time Per Age")
	var age_graph := _create_graph(container)
	var age_series: Array = _build_age_time_bars()
	var age_labels: Array = _get_age_labels()
	age_graph.set_data(age_series, age_labels, "Seconds", StatsGraphRendererScript.ChartType.BAR)

	# Tech research list
	_add_section_header(container, "Technologies Researched")
	for pid in [0, 1]:
		var pdata: Dictionary = _stats_data.get(pid, _stats_data.get(str(pid), {}))
		var techs: Array = pdata.get("techs_researched", [])
		var player_label := "Player" if pid == 0 else "AI"
		var color: Color = _player_colors.get(pid, Color.WHITE)
		var label := Label.new()
		label.text = (
			"%s (%d techs): %s" % [player_label, techs.size(), ", ".join(techs) if not techs.is_empty() else "None"]
		)
		label.add_theme_color_override("font_color", color)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		container.add_child(label)


# --- Helper methods ---


func _add_section_header(container: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	container.add_child(label)


func _add_comparison_row(container: VBoxContainer, label_text: String, p0_val: int, p1_val: int) -> void:
	var row := HBoxContainer.new()
	row.name = "Row_%s" % label_text.replace(" ", "")
	row.add_theme_constant_override("separation", 8)
	container.add_child(row)

	var max_val := maxi(maxi(p0_val, p1_val), 1)
	var bar_cfg: Dictionary = _config.get("comparison_bar", {})
	var bar_max_width: float = bar_cfg.get("max_width", 200.0)
	var bar_height: float = bar_cfg.get("height", 20.0)

	# Player bar (right-aligned)
	var p0_color: Color = _player_colors.get(0, Color(0.29, 0.56, 0.85))
	var p0_bar := ColorRect.new()
	p0_bar.color = p0_color
	p0_bar.custom_minimum_size = Vector2(bar_max_width * p0_val / max_val, bar_height)
	row.add_child(p0_bar)

	# Player value
	var p0_label := Label.new()
	p0_label.text = str(p0_val)
	p0_label.custom_minimum_size = Vector2(60, 0)
	p0_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(p0_label)

	# Stat label (center)
	var stat_label := Label.new()
	stat_label.text = label_text
	stat_label.custom_minimum_size = Vector2(160, 0)
	stat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(stat_label)

	# AI value
	var p1_label := Label.new()
	p1_label.text = str(p1_val)
	p1_label.custom_minimum_size = Vector2(60, 0)
	p1_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(p1_label)

	# AI bar (left-aligned)
	var p1_color: Color = _player_colors.get(1, Color(0.85, 0.29, 0.29))
	var p1_bar := ColorRect.new()
	p1_bar.color = p1_color
	p1_bar.custom_minimum_size = Vector2(bar_max_width * p1_val / max_val, bar_height)
	row.add_child(p1_bar)


func _create_graph(container: VBoxContainer) -> Control:
	var graph := Control.new()
	graph.name = "Graph_%d" % container.get_child_count()
	graph.set_script(StatsGraphRendererScript)
	var graph_cfg: Dictionary = _config.get("graph", {})
	graph.custom_minimum_size = Vector2(
		graph_cfg.get("width", 600.0),
		graph_cfg.get("height", 250.0),
	)
	if graph_cfg.has("grid_line_color"):
		graph.set_grid_color(Color.from_string(graph_cfg["grid_line_color"], Color(0.2, 0.2, 0.2)))
	if graph_cfg.has("axis_color"):
		graph.set_axis_color(Color.from_string(graph_cfg["axis_color"], Color(0.53, 0.53, 0.53)))
	if graph_cfg.has("line_width"):
		graph.set_line_width(float(graph_cfg["line_width"]))
	container.add_child(graph)
	return graph


func _build_resource_time_series() -> Array:
	return _build_time_series_for_field("resources_gathered_total")


func _build_kills_time_series() -> Array:
	return _build_time_series_for_field("units_killed")


func _build_time_series_for_field(snapshot_field: String) -> Array:
	var result: Array = []
	for pid in [0, 1]:
		var pdata: Dictionary = _stats_data.get(pid, _stats_data.get(str(pid), {}))
		var snapshots: Array = pdata.get("time_snapshots", [])
		var values: Array = []
		for snap: Dictionary in snapshots:
			values.append(float(snap.get(snapshot_field, 0)))
		var label := "Player" if pid == 0 else "AI"
		var color: Color = _player_colors.get(pid, Color.WHITE)
		result.append({"label": label, "color": color, "values": values})
	return result


func _build_time_labels() -> Array:
	# Use player 0 snapshots for time labels
	var p0: Dictionary = _stats_data.get(0, _stats_data.get("0", {}))
	var snapshots: Array = p0.get("time_snapshots", [])
	var labels: Array = []
	for snap: Dictionary in snapshots:
		labels.append(_format_time(float(snap.get("time", 0))))
	return labels


func _build_resource_type_bars() -> Array:
	return _build_type_bars("resources_gathered", _get_all_resource_types())


func _build_unit_type_bars() -> Array:
	return _build_type_bars("units_produced", _get_all_unit_types())


func _build_type_bars(stat_field: String, types: Array) -> Array:
	var result: Array = []
	for pid in [0, 1]:
		var pdata: Dictionary = _stats_data.get(pid, _stats_data.get(str(pid), {}))
		var field_data: Dictionary = pdata.get(stat_field, {})
		var values: Array = []
		for t: String in types:
			values.append(float(field_data.get(t, 0)))
		var label := "Player" if pid == 0 else "AI"
		var color: Color = _player_colors.get(pid, Color.WHITE)
		result.append({"label": label, "color": color, "values": values})
	return result


func _build_age_time_bars() -> Array:
	var result: Array = []
	for pid in [0, 1]:
		var pdata: Dictionary = _stats_data.get(pid, _stats_data.get(str(pid), {}))
		var timestamps: Dictionary = pdata.get("age_timestamps", {})
		var sorted_ages: Array = timestamps.keys()
		sorted_ages.sort()
		var values: Array = []
		for i in range(sorted_ages.size()):
			var age_key: Variant = sorted_ages[i]
			var start_time: float = float(timestamps[age_key])
			var end_time: float = _game_time
			if i + 1 < sorted_ages.size():
				end_time = float(timestamps[sorted_ages[i + 1]])
			values.append(end_time - start_time)
		var label := "Player" if pid == 0 else "AI"
		var color: Color = _player_colors.get(pid, Color.WHITE)
		result.append({"label": label, "color": color, "values": values})
	return result


func _get_all_resource_types() -> Array:
	var types: Dictionary = {}
	for pid_key: Variant in _stats_data:
		var pdata: Dictionary = _stats_data[pid_key]
		for t: String in pdata.get("resources_gathered", {}):
			types[t] = true
	var result: Array = types.keys()
	result.sort()
	return result


func _get_all_unit_types() -> Array:
	var types: Dictionary = {}
	for pid_key: Variant in _stats_data:
		var pdata: Dictionary = _stats_data[pid_key]
		for t: String in pdata.get("units_produced", {}):
			types[t] = true
	var result: Array = types.keys()
	result.sort()
	return result


func _get_age_labels() -> Array:
	# Collect all age indices across players
	var ages: Dictionary = {}
	for pid_key: Variant in _stats_data:
		var pdata: Dictionary = _stats_data[pid_key]
		for age_key: Variant in pdata.get("age_timestamps", {}):
			ages[age_key] = true
	var sorted_ages: Array = ages.keys()
	sorted_ages.sort()
	var labels: Array = []
	var age_names: Array[String] = ["Stone", "Bronze", "Iron", "Medieval", "Renaissance", "Industrial", "Singularity"]
	for age: Variant in sorted_ages:
		var idx := int(age)
		if idx >= 0 and idx < age_names.size():
			labels.append(age_names[idx])
		else:
			labels.append("Age %d" % idx)
	return labels


func _sum_dict(d: Dictionary) -> int:
	var total := 0
	for val: Variant in d.values():
		total += int(val)
	return total


func _format_time(seconds: float) -> String:
	var mins := int(seconds) / 60
	var secs := int(seconds) % 60
	return "%d:%02d" % [mins, secs]
