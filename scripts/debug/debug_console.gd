extends CanvasLayer
## In-game debug console overlay. Toggle with backtick/tilde key.
## Routes typed commands through DebugCommandRegistry.
## Only active in debug builds (OS.is_debug_build()).

var _registry: DebugCommandRegistry = null
var _panel: PanelContainer = null
var _input_field: LineEdit = null
var _output: RichTextLabel = null
var _visible: bool = false
var _history: Array[String] = []
var _history_index: int = -1
var _completion_candidates: Array[String] = []
var _completion_index: int = -1


func _ready() -> void:
	if not OS.is_debug_build():
		set_process_input(false)
		return
	layer = 100
	_registry = DebugCommandRegistry.new()
	_register_builtin_commands()
	_build_ui()
	_panel.visible = false


func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_QUOTELEFT:
			_toggle_console()
			get_viewport().set_input_as_handled()


func _toggle_console() -> void:
	_visible = not _visible
	_panel.visible = _visible
	if _visible:
		_input_field.grab_focus()
		_input_field.clear()
		_history_index = -1
	else:
		_input_field.release_focus()


func get_registry() -> DebugCommandRegistry:
	return _registry


func execute_command(command_string: String) -> String:
	## Execute a command string and return the result. Used by tests and DebugAPI.
	if _registry == null:
		return "Console not initialized"
	return _registry.execute(command_string)


func _register_builtin_commands() -> void:
	_register_help_command()
	_register_spawn_commands()
	_register_economy_commands()
	_register_tech_commands()


func _register_help_command() -> void:
	_registry.register_command(
		"help",
		[],
		func(_args: Array) -> String:
			var lines: Array[String] = ["Available commands:"]
			for cmd: Dictionary in _registry.get_commands():
				lines.append("  %s — %s" % [cmd["name"], cmd["help_text"]])
			return "\n".join(lines),
		"Show available commands",
	)


func _register_spawn_commands() -> void:
	_registry.register_command(
		"spawn",
		[
			{"name": "unit_type", "type": "string", "required": true},
			{"name": "owner_id", "type": "int", "required": false, "default": 0},
			{"name": "count", "type": "int", "required": false, "default": 1},
			{"name": "pos", "type": "vector2i", "required": false, "default": null},
		],
		func(args: Array) -> String:
			var unit_type: String = args[0]
			var owner_id: int = args[1] if args[1] != null else 0
			var count: int = args[2] if args[2] != null else 1
			var pos: Variant = args[3]
			var grid_pos: Vector2i
			if pos != null:
				grid_pos = pos as Vector2i
			else:
				grid_pos = _get_cursor_grid_pos()
			var units := DebugAPI.spawn_unit(unit_type, owner_id, grid_pos, count)
			if units.is_empty():
				return "Failed to spawn '%s' — unknown unit type or no scene" % unit_type
			return (
				"Spawned %d %s at (%d, %d) for player %d" % [units.size(), unit_type, grid_pos.x, grid_pos.y, owner_id]
			),
		"Spawn units: spawn <type> [owner] [count] [x,y]",
	)

	_registry.register_command(
		"build",
		[
			{"name": "building_type", "type": "string", "required": true},
			{"name": "owner_id", "type": "int", "required": false, "default": 0},
			{"name": "pos", "type": "vector2i", "required": false, "default": null},
		],
		func(args: Array) -> String:
			var building_type: String = args[0]
			var owner_id: int = args[1] if args[1] != null else 0
			var pos: Variant = args[2]
			var grid_pos: Vector2i
			if pos != null:
				grid_pos = pos as Vector2i
			else:
				grid_pos = _get_cursor_grid_pos()
			var b := DebugAPI.spawn_building(building_type, owner_id, grid_pos)
			if b == null:
				return "Failed to build '%s' — unknown type or no scene" % building_type
			return "Built %s at (%d, %d) for player %d" % [building_type, grid_pos.x, grid_pos.y, owner_id],
		"Place building: build <type> [owner] [x,y]",
	)


func _register_economy_commands() -> void:
	_registry.register_command(
		"give",
		[
			{"name": "resource_type", "type": "string", "required": true},
			{"name": "amount", "type": "int", "required": true},
			{"name": "player_id", "type": "int", "required": false, "default": 0},
		],
		func(args: Array) -> String:
			var res_type: String = args[0]
			var amount: int = args[1]
			var pid: int = args[2] if args[2] != null else 0
			DebugAPI.give_resources(pid, res_type, amount)
			return "Gave %d %s to player %d" % [amount, res_type, pid],
		"Add resources: give <type> <amount> [player_id]",
	)

	_registry.register_command(
		"give-all",
		[
			{"name": "amount", "type": "int", "required": true},
			{"name": "player_id", "type": "int", "required": false, "default": 0},
		],
		func(args: Array) -> String:
			var amount: int = args[0]
			var pid: int = args[1] if args[1] != null else 0
			DebugAPI.give_all_resources(pid, amount)
			return "Set all resources to %d for player %d" % [amount, pid],
		"Set all resources: give-all <amount> [player_id]",
	)


func _register_tech_commands() -> void:
	_registry.register_command(
		"research",
		[
			{"name": "tech_id", "type": "string", "required": true},
			{"name": "player_id", "type": "int", "required": false, "default": 0},
		],
		func(args: Array) -> String:
			var tech_id: String = args[0]
			var pid: int = args[1] if args[1] != null else 0
			var ok := DebugAPI.research_tech(tech_id, pid)
			if ok:
				return "Researched '%s' for player %d" % [tech_id, pid]
			return "Failed to research '%s' — not found or already researched" % tech_id,
		"Research tech: research <tech_id> [player_id]",
	)

	_registry.register_command(
		"research-all",
		[
			{"name": "player_id", "type": "int", "required": false, "default": 0},
		],
		func(args: Array) -> String:
			var pid: int = args[0] if args[0] != null else 0
			DebugAPI.research_all(pid)
			return "Researched all techs for player %d" % pid,
		"Research all techs: research-all [player_id]",
	)

	_registry.register_command(
		"advance-age",
		[
			{"name": "player_id", "type": "int", "required": false, "default": 0},
		],
		func(args: Array) -> String:
			var pid: int = args[0] if args[0] != null else 0
			DebugAPI.advance_age(pid)
			return "Advanced to %s" % GameManager.get_age_name(),
		"Advance to next age: advance-age [player_id]",
	)

	_registry.register_command(
		"set-age",
		[
			{"name": "age_name", "type": "string", "required": true},
			{"name": "player_id", "type": "int", "required": false, "default": 0},
		],
		func(args: Array) -> String:
			var age_name: String = args[0]
			var pid: int = args[1] if args[1] != null else 0
			DebugAPI.set_age(age_name, pid)
			return "Set age to %s" % GameManager.get_age_name(),
		"Jump to age: set-age <age_name> [player_id]",
	)


func _build_ui() -> void:
	## Constructs the console UI programmatically.
	_panel = PanelContainer.new()
	_panel.name = "DebugConsolePanel"
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.4
	_panel.offset_bottom = 0.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.85)
	style.border_color = Color(0.3, 0.3, 0.5, 0.8)
	style.border_width_bottom = 2
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	_panel.add_child(vbox)

	_output = RichTextLabel.new()
	_output.name = "Output"
	_output.bbcode_enabled = true
	_output.scroll_following = true
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.add_theme_color_override("default_color", Color(0.8, 0.9, 0.8))
	vbox.add_child(_output)

	_input_field = LineEdit.new()
	_input_field.name = "Input"
	_input_field.placeholder_text = "Type a command... (Tab to complete, Up/Down for history)"
	_input_field.caret_blink = true
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	input_style.border_color = Color(0.4, 0.4, 0.6)
	input_style.border_width_bottom = 1
	input_style.border_width_top = 1
	input_style.content_margin_left = 6
	input_style.content_margin_right = 6
	_input_field.add_theme_stylebox_override("normal", input_style)
	_input_field.add_theme_color_override("font_color", Color(0.9, 1.0, 0.9))
	vbox.add_child(_input_field)

	_input_field.text_submitted.connect(_on_command_submitted)
	_input_field.gui_input.connect(_on_input_gui_event)

	add_child(_panel)
	_append_output("[color=cyan]Debug Console ready. Type 'help' for commands.[/color]")


func _on_command_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	_history.append(text)
	_history_index = -1
	_append_output("[color=gray]> %s[/color]" % text)
	var result := _registry.execute(text)
	if not result.is_empty():
		_append_output(result)
	_input_field.clear()
	_completion_candidates.clear()
	_completion_index = -1


func _on_input_gui_event(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	var key_event := event as InputEventKey
	if key_event.keycode == KEY_UP:
		_navigate_history(-1)
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_DOWN:
		_navigate_history(1)
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_TAB:
		_tab_complete()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_QUOTELEFT:
		get_viewport().set_input_as_handled()


func _navigate_history(direction: int) -> void:
	if _history.is_empty():
		return
	if _history_index == -1:
		if direction < 0:
			_history_index = _history.size() - 1
		else:
			return
	else:
		_history_index += direction
	_history_index = clampi(_history_index, 0, _history.size() - 1)
	_input_field.text = _history[_history_index]
	_input_field.caret_column = _input_field.text.length()


func _tab_complete() -> void:
	var text := _input_field.text
	if text.is_empty():
		return
	var completions := _registry.get_completions(text)
	if completions.size() == 1:
		_input_field.text = completions[0] + " "
		_input_field.caret_column = _input_field.text.length()
	elif completions.size() > 1:
		_append_output("[color=yellow]%s[/color]" % " | ".join(completions))


func _get_cursor_grid_pos() -> Vector2i:
	## Gets the current mouse cursor position in grid coordinates.
	var viewport := get_viewport()
	if viewport == null:
		return Vector2i.ZERO
	var mouse_pos := viewport.get_mouse_position()
	# Try to account for camera offset
	var cam := viewport.get_camera_2d()
	if cam != null:
		var world_pos := mouse_pos + cam.global_position - viewport.get_visible_rect().size / 2.0
		return Vector2i(IsoUtils.screen_to_grid(world_pos))
	return Vector2i(IsoUtils.screen_to_grid(mouse_pos))


func _append_output(text: String) -> void:
	if _output != null:
		_output.append_text(text + "\n")
