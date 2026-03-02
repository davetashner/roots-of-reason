extends VBoxContainer
## Hotkey remapping UI section for the settings panel.
## Displays all bindable actions, supports click-to-rebind, conflict
## detection with swap, and reset-to-defaults.

signal rebind_started(action: String)
signal rebind_completed(action: String, keycode: int, modifiers: int)
signal rebind_cancelled

## Each entry: { "action": String, "label": String,
##   "default_keycode": int, "default_modifiers": int }
const BINDABLE_ACTIONS: Array[Dictionary] = [
	{
		"action": "camera_pan_up",
		"label": "Camera Pan Up",
		"default_keycode": KEY_W,
		"default_modifiers": 0,
	},
	{
		"action": "camera_pan_left",
		"label": "Camera Pan Left",
		"default_keycode": KEY_A,
		"default_modifiers": 0,
	},
	{
		"action": "camera_pan_down",
		"label": "Camera Pan Down",
		"default_keycode": KEY_S,
		"default_modifiers": 0,
	},
	{
		"action": "camera_pan_right",
		"label": "Camera Pan Right",
		"default_keycode": KEY_D,
		"default_modifiers": 0,
	},
	{
		"action": "select_all_military",
		"label": "Select All Military",
		"default_keycode": KEY_A,
		"default_modifiers": KEY_MASK_CTRL,
	},
	{
		"action": "idle_villager",
		"label": "Idle Villager",
		"default_keycode": KEY_PERIOD,
		"default_modifiers": 0,
	},
	{
		"action": "build_menu",
		"label": "Build Menu",
		"default_keycode": KEY_B,
		"default_modifiers": 0,
	},
	{
		"action": "delete_unit",
		"label": "Delete / Destroy",
		"default_keycode": KEY_DELETE,
		"default_modifiers": 0,
	},
]

var _action_buttons: Dictionary = {}  # action -> Button
var _awaiting_rebind: String = ""
var _conflict_dialog: ConfirmationDialog = null
var _pending_keycode: int = 0
var _pending_modifiers: int = 0
var _pending_conflict_action: String = ""


func build() -> void:
	name = "HotkeyRemapping"
	add_theme_constant_override("separation", 6)

	var header := Label.new()
	header.text = "Hotkeys"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	add_child(header)

	for entry: Dictionary in BINDABLE_ACTIONS:
		_add_hotkey_row(entry)

	# Reset to Defaults button
	var reset_spacer := Control.new()
	reset_spacer.custom_minimum_size = Vector2(0, 4)
	add_child(reset_spacer)

	var reset_btn := Button.new()
	reset_btn.name = "ResetHotkeysButton"
	reset_btn.text = "Reset to Defaults"
	reset_btn.custom_minimum_size = Vector2(200, 32)
	reset_btn.pressed.connect(_on_reset_pressed)
	add_child(reset_btn)

	# Conflict dialog
	_conflict_dialog = ConfirmationDialog.new()
	_conflict_dialog.name = "HotkeyConflictDialog"
	_conflict_dialog.title = "Key Conflict"
	_conflict_dialog.ok_button_text = "Swap"
	_conflict_dialog.cancel_button_text = "Cancel"
	_conflict_dialog.confirmed.connect(_on_conflict_swap)
	_conflict_dialog.canceled.connect(_on_conflict_cancel)
	add_child(_conflict_dialog)


func _add_hotkey_row(entry: Dictionary) -> void:
	var action: String = entry["action"]
	var label_text: String = entry["label"]

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	add_child(hbox)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(180, 0)
	hbox.add_child(label)

	var btn := Button.new()
	btn.name = "HotkeyBtn_" + action
	btn.custom_minimum_size = Vector2(160, 30)
	btn.text = _get_display_text(action)
	btn.pressed.connect(_on_hotkey_btn_pressed.bind(action))
	hbox.add_child(btn)

	_action_buttons[action] = btn


func _on_hotkey_btn_pressed(action: String) -> void:
	if _awaiting_rebind != "":
		# Cancel previous rebind
		_cancel_rebind()
	_awaiting_rebind = action
	_action_buttons[action].text = "Press a key..."
	rebind_started.emit(action)


func _input(event: InputEvent) -> void:
	if _awaiting_rebind == "" or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return

	# Escape cancels rebind
	if key.keycode == KEY_ESCAPE:
		_cancel_rebind()
		get_viewport().set_input_as_handled()
		return

	# Ignore bare modifier keys
	if key.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
		return

	var keycode: int = key.keycode
	var modifiers: int = 0
	if key.ctrl_pressed:
		modifiers |= KEY_MASK_CTRL
	if key.shift_pressed:
		modifiers |= KEY_MASK_SHIFT
	if key.alt_pressed:
		modifiers |= KEY_MASK_ALT

	get_viewport().set_input_as_handled()

	# Check for conflicts
	var conflict_action := _find_conflict(keycode, modifiers, _awaiting_rebind)
	if conflict_action != "":
		_pending_keycode = keycode
		_pending_modifiers = modifiers
		_pending_conflict_action = conflict_action
		var key_text := _keycode_to_string(keycode, modifiers)
		var conflict_label := _get_action_label(conflict_action)
		_conflict_dialog.dialog_text = ("'%s' is already bound to '%s'.\nSwap bindings?" % [key_text, conflict_label])
		_conflict_dialog.popup_centered(Vector2i(340, 140))
		return

	_apply_rebind(_awaiting_rebind, keycode, modifiers)


func _apply_rebind(action: String, keycode: int, modifiers: int) -> void:
	_store_binding(action, keycode, modifiers)
	_action_buttons[action].text = _keycode_to_string(keycode, modifiers)
	var old_action := _awaiting_rebind
	_awaiting_rebind = ""
	rebind_completed.emit(old_action, keycode, modifiers)


func _cancel_rebind() -> void:
	if _awaiting_rebind == "":
		return
	_action_buttons[_awaiting_rebind].text = _get_display_text(_awaiting_rebind)
	_awaiting_rebind = ""
	rebind_cancelled.emit()


func _on_conflict_swap() -> void:
	# Swap: give the conflicting action the old key of the action being rebound
	var old_binding := _load_binding(_awaiting_rebind)
	var old_keycode: int = old_binding["keycode"]
	var old_modifiers: int = old_binding["modifiers"]

	# Apply new binding to the action being rebound
	_store_binding(_awaiting_rebind, _pending_keycode, _pending_modifiers)
	_action_buttons[_awaiting_rebind].text = _keycode_to_string(_pending_keycode, _pending_modifiers)

	# Apply old binding to the conflicting action
	_store_binding(_pending_conflict_action, old_keycode, old_modifiers)
	if _action_buttons.has(_pending_conflict_action):
		_action_buttons[_pending_conflict_action].text = _keycode_to_string(old_keycode, old_modifiers)

	var completed_action := _awaiting_rebind
	_awaiting_rebind = ""
	rebind_completed.emit(completed_action, _pending_keycode, _pending_modifiers)


func _on_conflict_cancel() -> void:
	_cancel_rebind()


func _on_reset_pressed() -> void:
	for entry: Dictionary in BINDABLE_ACTIONS:
		var action: String = entry["action"]
		var keycode: int = entry["default_keycode"]
		var modifiers: int = entry["default_modifiers"]
		_store_binding(action, keycode, modifiers)
		if _action_buttons.has(action):
			_action_buttons[action].text = _keycode_to_string(keycode, modifiers)


func _find_conflict(keycode: int, modifiers: int, exclude_action: String) -> String:
	for entry: Dictionary in BINDABLE_ACTIONS:
		var action: String = entry["action"]
		if action == exclude_action:
			continue
		var binding := _load_binding(action)
		if binding["keycode"] == keycode and binding["modifiers"] == modifiers:
			return action
	return ""


func _load_binding(action: String) -> Dictionary:
	var bindings := SettingsManager.get_hotkey_bindings()
	if bindings.has(action):
		var stored: Variant = bindings[action]
		if stored is Dictionary:
			return {
				"keycode": int(stored.get("keycode", 0)),
				"modifiers": int(stored.get("modifiers", 0)),
			}
		# Legacy: stored as plain int scancode
		return {"keycode": int(stored), "modifiers": 0}
	# Return default
	for entry: Dictionary in BINDABLE_ACTIONS:
		if entry["action"] == action:
			return {
				"keycode": int(entry["default_keycode"]),
				"modifiers": int(entry["default_modifiers"]),
			}
	return {"keycode": 0, "modifiers": 0}


func _store_binding(action: String, keycode: int, modifiers: int) -> void:
	SettingsManager.set_hotkey_binding(action, {"keycode": keycode, "modifiers": modifiers})


func _get_display_text(action: String) -> String:
	var binding := _load_binding(action)
	return _keycode_to_string(binding["keycode"], binding["modifiers"])


func _get_action_label(action: String) -> String:
	for entry: Dictionary in BINDABLE_ACTIONS:
		if entry["action"] == action:
			return entry["label"]
	return action


static func _keycode_to_string(keycode: int, modifiers: int) -> String:
	var parts: PackedStringArray = []
	if modifiers & KEY_MASK_CTRL:
		parts.append("Ctrl")
	if modifiers & KEY_MASK_SHIFT:
		parts.append("Shift")
	if modifiers & KEY_MASK_ALT:
		parts.append("Alt")
	parts.append(OS.get_keycode_string(keycode))
	return "+".join(parts)


## Returns the current binding for an action as a Dictionary with
## "keycode" and "modifiers" keys. Used by other systems to query
## the player's custom keybinds at runtime.
func get_binding(action: String) -> Dictionary:
	return _load_binding(action)


## Returns true if the remapping UI is currently waiting for a keypress.
func is_awaiting_rebind() -> bool:
	return _awaiting_rebind != ""


## Returns the action currently being rebound, or empty string.
func get_awaiting_action() -> String:
	return _awaiting_rebind
