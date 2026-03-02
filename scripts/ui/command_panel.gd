extends PanelContainer
## Command panel — context-sensitive grid of command buttons at bottom-right.
## Shows available actions based on selected unit/building type.
## Villager build menu is dynamically generated from building data with category tabs.

const RESOURCE_NAME_TO_TYPE: Dictionary = {
	"food": ResourceManager.ResourceType.FOOD,
	"wood": ResourceManager.ResourceType.WOOD,
	"stone": ResourceManager.ResourceType.STONE,
	"gold": ResourceManager.ResourceType.GOLD,
	"knowledge": ResourceManager.ResourceType.KNOWLEDGE,
}

const BUILD_CATEGORIES := ["civilian", "military", "economy"]
const MAX_GRID_SLOTS := 12

var _input_handler: Node = null
var _building_placer: Node = null
var _trade_manager: Node = null
var _vbox: VBoxContainer = null
var _tab_bar: HBoxContainer = null
var _grid: GridContainer = null
var _config: Dictionary = {}
var _last_selection_hash: int = -1
var _player_id: int = 0
var _build_tab: String = "civilian"
var _is_villager_mode: bool = false
var _build_page: int = 0


func _ready() -> void:
	_load_config()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setup_layout()


func _load_config() -> void:
	_config = GameUtils.dl_settings("command_panel")
	if _config.is_empty():
		_config = {
			"grid_columns": 3,
			"grid_rows": 4,
			"button_size": 48,
			"button_margin": 4,
			"hotkeys": [["Q", "W", "E"], ["A", "S", "D"], ["Z", "X", "C"], ["R", "F", "V"]],
			"commands": {"default": [], "villager": []},
		}


func _setup_layout() -> void:
	var columns: int = int(_config.get("grid_columns", 3))
	var rows: int = int(_config.get("grid_rows", 4))
	var btn_size: int = int(_config.get("button_size", 48))
	var margin: int = int(_config.get("button_margin", 4))
	var panel_width: int = columns * (btn_size + margin) + margin
	var tab_height := 20
	var panel_height: int = rows * (btn_size + margin) + margin + tab_height
	custom_minimum_size = Vector2(panel_width, panel_height)
	size = Vector2(panel_width, panel_height)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -panel_width
	offset_right = 0.0
	offset_top = -panel_height
	offset_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Add a StyleBoxFlat with transparent background
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.6)
	style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", style)
	# VBox to hold tab bar + grid
	_vbox = VBoxContainer.new()
	_vbox.name = "VBox"
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vbox)
	# Tab bar (hidden by default, shown in villager mode)
	_tab_bar = HBoxContainer.new()
	_tab_bar.name = "TabBar"
	_tab_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_bar.visible = false
	_vbox.add_child(_tab_bar)
	_rebuild_tab_bar()
	# Grid container
	_grid = GridContainer.new()
	_grid.name = "CommandGrid"
	_grid.columns = columns
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(_grid)


func _rebuild_tab_bar() -> void:
	for child in _tab_bar.get_children():
		child.queue_free()
	for cat: String in BUILD_CATEGORIES:
		var tab_btn := Button.new()
		tab_btn.name = "Tab_%s" % cat
		tab_btn.text = cat.capitalize()
		tab_btn.custom_minimum_size = Vector2(50, 18)
		tab_btn.clip_text = true
		tab_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		tab_btn.add_theme_font_size_override("font_size", 9)
		_style_tab_button(tab_btn, cat == _build_tab)
		tab_btn.pressed.connect(_on_tab_pressed.bind(cat))
		_tab_bar.add_child(tab_btn)


func _style_tab_button(btn: Button, active: bool) -> void:
	var style := StyleBoxFlat.new()
	if active:
		style.bg_color = Color(0.3, 0.3, 0.5, 0.9)
	else:
		style.bg_color = Color(0.15, 0.15, 0.2, 0.7)
	style.set_corner_radius_all(2)
	btn.add_theme_stylebox_override("normal", style)
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.35, 0.35, 0.55, 0.9)
	hover_style.set_corner_radius_all(2)
	btn.add_theme_stylebox_override("hover", hover_style)


func _on_tab_pressed(category: String) -> void:
	if _build_tab == category:
		return
	_build_tab = category
	_build_page = 0
	# Update tab button styles
	for child in _tab_bar.get_children():
		if child is Button:
			var cat: String = child.name.replace("Tab_", "")
			_style_tab_button(child, cat == _build_tab)
	# Re-render the build grid
	if _is_villager_mode:
		_render_build_commands()


func setup(
	input_handler: Node,
	building_placer: Node,
	trade_manager: Node = null,
) -> void:
	_input_handler = input_handler
	_building_placer = building_placer
	_trade_manager = trade_manager


func _process(_delta: float) -> void:
	if _input_handler == null:
		return
	var selected: Array = _input_handler._get_selected_units()
	var sel_hash := _compute_selection_hash(selected)
	if sel_hash != _last_selection_hash:
		_last_selection_hash = sel_hash
		update_commands(selected)
	# Update affordability on existing buttons
	_update_button_states()


func _compute_selection_hash(units: Array) -> int:
	if units.is_empty():
		return 0
	var h: int = units.size()
	for unit in units:
		if is_instance_valid(unit):
			h = h * 31 + unit.get_instance_id()
	return h


func update_commands(units: Array) -> void:
	_clear_grid()
	_is_villager_mode = _is_villager_selection(units)
	_tab_bar.visible = _is_villager_mode
	if _is_villager_mode:
		_build_page = 0
		_render_build_commands()
		return
	var commands: Array = _get_commands_for_selection(units)
	if commands.is_empty():
		return
	_render_command_list(commands)


func _is_villager_selection(units: Array) -> bool:
	if units.is_empty():
		return false
	for unit in units:
		if is_instance_valid(unit) and "unit_type" in unit:
			if unit.unit_type == "villager":
				return true
	return false


func _render_build_commands() -> void:
	_clear_grid()
	var commands: Array = _get_dynamic_build_commands()
	_render_command_list(commands)


func _render_command_list(commands: Array) -> void:
	var hotkeys: Array = _config.get("hotkeys", [])
	for i in commands.size():
		var cmd: Dictionary = commands[i]
		var cols: int = int(_config.get("grid_columns", 3))
		var row: int = int(i) / cols
		var col: int = int(i) % cols
		var hotkey: String = ""
		if row < hotkeys.size() and col < hotkeys[row].size():
			hotkey = hotkeys[row][col]
		var btn := _create_button(cmd, hotkey)
		_grid.add_child(btn)


func _get_dynamic_build_commands() -> Array:
	## Build the dynamic list of build commands for the active tab, filtered
	## by unlock state. Only shows buildings the player has unlocked.
	var all_ids: Array = _get_all_building_ids()
	var unlocked: Array = []
	for building_id: String in all_ids:
		# Skip civ-unique buildings not belonging to this player's civ
		if _is_civ_unique_for_other_player(building_id):
			continue
		# Resolve civ replacement (e.g. house -> longhouse for Vikings)
		var resolved: String = _resolve_building_id(building_id)
		var stats: Dictionary = _load_building_stats(resolved)
		if stats.is_empty():
			continue
		var cat: String = str(stats.get("category", ""))
		if cat != _build_tab:
			continue
		if not _is_unlocked(building_id):
			continue
		var cmd := {
			"id": "build_%s" % resolved,
			"label": str(stats.get("name", resolved)),
			"tooltip": _build_tooltip(resolved, stats),
			"action": "build",
			"building": building_id,
		}
		unlocked.append(cmd)
	# Paginate — show up to MAX_GRID_SLOTS per page
	var start: int = _build_page * MAX_GRID_SLOTS
	var end: int = mini(start + MAX_GRID_SLOTS, unlocked.size())
	if start >= unlocked.size():
		return []
	return unlocked.slice(start, end)


func _get_all_building_ids() -> Array:
	if Engine.has_singleton("DataLoader"):
		return DataLoader.get_all_building_ids()
	var dl: Node = null
	if is_instance_valid(Engine.get_main_loop()):
		dl = Engine.get_main_loop().root.get_node_or_null("DataLoader")
	if dl != null and dl.has_method("get_all_building_ids"):
		return dl.get_all_building_ids()
	return []


func _is_civ_unique_for_other_player(building_id: String) -> bool:
	## Returns true if building_id is a civ-unique building that belongs to a
	## different civ than this player's. Base buildings are never filtered out.
	var stats: Dictionary = _load_building_stats(building_id)
	if stats.is_empty():
		return false
	# Check if any civ replaces a base building with this building_id
	var all_civs: Array = _get_all_civ_ids()
	for civ_id: String in all_civs:
		var civ_data: Dictionary = _load_civ_data(civ_id)
		var unique: Dictionary = civ_data.get("unique_building", {})
		if unique.is_empty():
			continue
		var unique_name: String = str(unique.get("name", "")).to_lower().replace(" ", "_")
		if unique_name == building_id:
			# This is a civ-unique building — check if it's for this player
			var player_civ: String = CivBonusManager.get_active_civ(_player_id)
			return player_civ != civ_id
	return false


func _get_all_civ_ids() -> Array:
	if Engine.has_singleton("DataLoader"):
		return DataLoader.get_all_civ_ids()
	var dl: Node = null
	if is_instance_valid(Engine.get_main_loop()):
		dl = Engine.get_main_loop().root.get_node_or_null("DataLoader")
	if dl != null and dl.has_method("get_all_civ_ids"):
		return dl.get_all_civ_ids()
	return []


func _load_civ_data(civ_id: String) -> Dictionary:
	if Engine.has_singleton("DataLoader"):
		return DataLoader.get_civ_data(civ_id)
	var dl: Node = null
	if is_instance_valid(Engine.get_main_loop()):
		dl = Engine.get_main_loop().root.get_node_or_null("DataLoader")
	if dl != null and dl.has_method("get_civ_data"):
		return dl.get_civ_data(civ_id)
	return {}


func _resolve_building_id(building_id: String) -> String:
	return CivBonusManager.get_resolved_building_id(_player_id, building_id)


func _is_unlocked(building_id: String) -> bool:
	if _building_placer != null and _building_placer.has_method("is_building_unlocked"):
		return _building_placer.is_building_unlocked(building_id, _player_id)
	return true


func _build_tooltip(building_id: String, stats: Dictionary) -> String:
	var tip: String = "Build %s" % str(stats.get("name", building_id))
	var costs: Dictionary = stats.get("build_cost", {})
	if not costs.is_empty():
		var parts: Array[String] = []
		for res: String in costs:
			parts.append("%d %s" % [int(costs[res]), res.capitalize()])
		tip += " (%s)" % ", ".join(parts)
	return tip


func _get_commands_for_selection(units: Array) -> Array:
	if units.is_empty():
		return []
	var commands_map: Dictionary = _config.get("commands", {})
	# Determine the primary lookup key — buildings use building_name, units use unit_type
	var lookup_key: String = "default"
	for unit in units:
		if is_instance_valid(unit):
			if "building_name" in unit and unit.building_name != "":
				lookup_key = unit.building_name
				break
			if "unit_type" in unit:
				# Villager is handled dynamically, skip static lookup
				if unit.unit_type == "villager":
					lookup_key = "default"
					break
				lookup_key = unit.unit_type
				break
	var result: Array = []
	if commands_map.has(lookup_key):
		result = commands_map[lookup_key].duplicate()
	else:
		result = commands_map.get("default", []).duplicate()
	# Add "Unload" button for transports with passengers
	if _selection_has_embarked(units):
		var unload_cmd := {
			"id": "unload_all",
			"label": "Unload",
			"tooltip": "Unload all embarked units",
			"action": "unload",
		}
		result.append(unload_cmd)
	# Add "Ungarrison" button for buildings with garrisoned units
	if _selection_has_garrisoned(units):
		var ungarrison_cmd := {
			"id": "ungarrison_all",
			"label": "Ungarrison",
			"tooltip": "Eject all garrisoned units",
			"action": "ungarrison",
		}
		result.append(ungarrison_cmd)
	return result


func _create_button(command: Dictionary, hotkey: String) -> Button:
	var btn := Button.new()
	var btn_size: int = int(_config.get("button_size", 48))
	btn.custom_minimum_size = Vector2(btn_size, btn_size)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	# Build label text with hotkey indicator
	var label_text: String = command.get("label", "?")
	if hotkey != "":
		label_text = "[%s] %s" % [hotkey, label_text]
	btn.text = label_text
	# Tooltip with hotkey
	var tip: String = command.get("tooltip", "")
	if hotkey != "":
		tip += " (%s)" % hotkey
	btn.tooltip_text = tip
	# Clip text for small buttons
	btn.clip_text = true
	# Style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.3, 0.9)
	style.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", style)
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.3, 0.3, 0.5, 0.9)
	hover_style.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("hover", hover_style)
	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.15, 0.15, 0.25, 0.9)
	pressed_style.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	var disabled_style := StyleBoxFlat.new()
	disabled_style.bg_color = Color(0.15, 0.15, 0.15, 0.5)
	disabled_style.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("disabled", disabled_style)
	btn.add_theme_font_size_override("font_size", 10)
	# Affordability check
	if not _check_affordability(command):
		btn.disabled = true
	# Connect press
	btn.pressed.connect(_on_command_pressed.bind(command))
	# Store command data for later affordability updates
	btn.set_meta("command", command)
	return btn


func _on_command_pressed(command: Dictionary) -> void:
	var action: String = command.get("action", "")
	match action:
		"build":
			var building_name: String = command.get("building", "")
			if building_name != "" and _building_placer != null:
				_building_placer.start_placement(building_name, _player_id)
		"trade":
			_execute_trade(command)
		"stop":
			_issue_stop()
		"hold":
			_issue_hold()
		"unload":
			_issue_unload()
		"ungarrison":
			_issue_ungarrison()
		"produce":
			_execute_production(command)


func _issue_stop() -> void:
	if _input_handler == null:
		return
	var selected: Array = _input_handler._get_selected_units()
	for unit in selected:
		if is_instance_valid(unit) and unit.has_method("stop"):
			unit.stop()


func _issue_hold() -> void:
	if _input_handler == null:
		return
	var selected: Array = _input_handler._get_selected_units()
	for unit in selected:
		if is_instance_valid(unit) and unit.has_method("hold_position"):
			unit.hold_position()


func _issue_unload() -> void:
	if _input_handler == null:
		return
	var selected: Array = _input_handler._get_selected_units()
	for unit in selected:
		if is_instance_valid(unit) and unit.has_method("disembark_all"):
			if unit.get_embarked_count() > 0:
				unit.disembark_all(unit.global_position)


func _selection_has_embarked(units: Array) -> bool:
	for unit in units:
		if is_instance_valid(unit) and unit.has_method("get_embarked_count"):
			if unit.get_embarked_count() > 0:
				return true
	return false


func _selection_has_garrisoned(units: Array) -> bool:
	for unit in units:
		if is_instance_valid(unit) and unit.has_method("get_garrisoned_count"):
			if unit.get_garrisoned_count() > 0:
				return true
	return false


func _issue_ungarrison() -> void:
	if _input_handler == null:
		return
	var selected: Array = _input_handler._get_selected_units()
	for unit in selected:
		if is_instance_valid(unit) and unit.has_method("ungarrison_all"):
			if unit.has_method("get_garrisoned_count") and unit.get_garrisoned_count() > 0:
				unit.ungarrison_all()


func _execute_trade(command: Dictionary) -> void:
	if _trade_manager == null:
		return
	var sell_resource: String = command.get("sell_resource", "")
	var sell_amount: int = int(command.get("sell_amount", 0))
	if sell_resource == "" or sell_amount <= 0:
		return
	_trade_manager.execute_exchange(_player_id, sell_resource, sell_amount)


func _execute_production(command: Dictionary) -> void:
	if _input_handler == null:
		return
	var unit_type: String = command.get("unit", "")
	if unit_type == "":
		return
	var selected: Array = _input_handler._get_selected_units()
	for building in selected:
		if not is_instance_valid(building):
			continue
		var pq: Node = building.get_node_or_null("ProductionQueue")
		if pq != null and pq.has_method("add_to_queue"):
			pq.add_to_queue(unit_type)


func _check_produce_affordability(command: Dictionary) -> bool:
	var unit_type: String = command.get("unit", "")
	if unit_type == "":
		return true
	var stats: Dictionary = _load_unit_stats(unit_type)
	if stats.is_empty():
		return true
	var raw_costs: Dictionary = stats.get("train_cost", {})
	var costs: Dictionary = _parse_costs(raw_costs)
	return ResourceManager.can_afford(_player_id, costs)


func _load_unit_stats(unit_type: String) -> Dictionary:
	if Engine.has_singleton("DataLoader"):
		return DataLoader.get_unit_stats(unit_type)
	var dl: Node = null
	if is_instance_valid(Engine.get_main_loop()):
		dl = Engine.get_main_loop().root.get_node_or_null("DataLoader")
	if dl != null and dl.has_method("get_unit_stats"):
		return dl.get_unit_stats(unit_type)
	return {}


func _check_affordability(command: Dictionary) -> bool:
	var action: String = command.get("action", "")
	if action == "build":
		return _check_build_affordability(command)
	if action == "trade":
		return _check_trade_affordability(command)
	if action == "produce":
		return _check_produce_affordability(command)
	return true


func _check_build_affordability(command: Dictionary) -> bool:
	var building_name: String = command.get("building", "")
	if building_name == "":
		return true
	var stats: Dictionary = _load_building_stats(building_name)
	if stats.is_empty():
		return true
	var raw_costs: Dictionary = stats.get("build_cost", {})
	var costs: Dictionary = _parse_costs(raw_costs)
	return ResourceManager.can_afford(_player_id, costs)


func _check_trade_affordability(command: Dictionary) -> bool:
	var sell_resource: String = command.get("sell_resource", "")
	var sell_amount: int = int(command.get("sell_amount", 0))
	if sell_resource == "" or sell_amount <= 0:
		return true
	if not RESOURCE_NAME_TO_TYPE.has(sell_resource):
		return true
	var res_type: int = RESOURCE_NAME_TO_TYPE[sell_resource]
	var current: int = ResourceManager.get_amount(_player_id, res_type)
	return current >= sell_amount


func _update_button_states() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		if child is Button and child.has_meta("command"):
			var cmd: Dictionary = child.get_meta("command")
			var affordable := _check_affordability(cmd)
			child.disabled = not affordable


func _clear_grid() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		child.queue_free()


func _parse_costs(raw_costs: Dictionary) -> Dictionary:
	var multiplier: float = 1.0
	if _building_placer != null and _building_placer.has_method("get_building_cost_multiplier"):
		multiplier = _building_placer.get_building_cost_multiplier()
	var costs: Dictionary = {}
	for key: String in raw_costs:
		var lower_key := key.to_lower()
		if RESOURCE_NAME_TO_TYPE.has(lower_key):
			costs[RESOURCE_NAME_TO_TYPE[lower_key]] = int(int(raw_costs[key]) * multiplier)
	return costs


func _load_building_stats(building_name: String) -> Dictionary:
	if Engine.has_singleton("DataLoader"):
		return DataLoader.get_building_stats(building_name)
	var dl: Node = null
	if is_instance_valid(Engine.get_main_loop()):
		dl = Engine.get_main_loop().root.get_node_or_null("DataLoader")
	if dl != null and dl.has_method("get_building_stats"):
		return dl.get_building_stats(building_name)
	return {}


func _unhandled_input(event: InputEvent) -> void:
	if _grid == null or _grid.get_child_count() == 0:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		var key_char := char(key.keycode).to_upper()
		var hotkeys: Array = _config.get("hotkeys", [])
		for row_idx in hotkeys.size():
			var row: Array = hotkeys[row_idx]
			for col_idx in row.size():
				if row[col_idx] == key_char:
					var btn_index: int = row_idx * int(_config.get("grid_columns", 3)) + col_idx
					if btn_index < _grid.get_child_count():
						var btn: Button = _grid.get_child(btn_index) as Button
						if btn != null and not btn.disabled:
							btn.emit_signal("pressed")
							get_viewport().set_input_as_handled()
					return


func save_state() -> Dictionary:
	return {"player_id": _player_id, "build_tab": _build_tab}


func load_state(data: Dictionary) -> void:
	_player_id = int(data.get("player_id", 0))
	_build_tab = str(data.get("build_tab", "civilian"))
