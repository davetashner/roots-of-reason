class_name DebugCommandRegistry
extends RefCounted
## Shared command backend for the debug console and DebugAPI.
## Commands are registered as dictionaries with name, args_spec, handler, help_text.
## Parses command strings, validates arguments, and dispatches to handlers.

## Each registered command: {name: String, args_spec: Array, handler: Callable, help_text: String}
## args_spec entries: {name: String, type: String, required: bool, default: Variant}
var _commands: Dictionary = {}


func register_command(cmd_name: String, args_spec: Array, handler: Callable, help_text: String) -> void:
	_commands[cmd_name] = {
		"name": cmd_name,
		"args_spec": args_spec,
		"handler": handler,
		"help_text": help_text,
	}


func execute(command_string: String) -> String:
	## Parses a command string and dispatches to the registered handler.
	## Returns the result string or an error message.
	var parts := _split_command(command_string.strip_edges())
	if parts.is_empty():
		return ""
	var cmd_name: String = parts[0].to_lower()
	if cmd_name not in _commands:
		return "Unknown command: '%s'. Type 'help' for available commands." % cmd_name
	var cmd: Dictionary = _commands[cmd_name]
	var raw_args: Array = parts.slice(1)
	var parsed := _parse_args(raw_args, cmd["args_spec"])
	if parsed.has("error"):
		return "Error: %s\nUsage: %s %s" % [parsed["error"], cmd_name, _usage_string(cmd)]
	return cmd["handler"].call(parsed["args"])


func get_commands() -> Array[Dictionary]:
	## Returns all registered commands for listing/help.
	var result: Array[Dictionary] = []
	for cmd_name: String in _commands:
		result.append(_commands[cmd_name])
	return result


func get_completions(partial: String) -> Array[String]:
	## Returns command names that start with the given partial string.
	var result: Array[String] = []
	var lower := partial.to_lower()
	for cmd_name: String in _commands:
		if cmd_name.begins_with(lower):
			result.append(cmd_name)
	result.sort()
	return result


func has_command(cmd_name: String) -> bool:
	return cmd_name in _commands


func _split_command(text: String) -> Array:
	## Splits command string respecting quoted arguments.
	var result: Array = []
	var current := ""
	var in_quotes := false
	for ch in text:
		if ch == '"':
			in_quotes = not in_quotes
		elif ch == " " and not in_quotes:
			if not current.is_empty():
				result.append(current)
				current = ""
		else:
			current += ch
	if not current.is_empty():
		result.append(current)
	return result


func _parse_args(raw_args: Array, args_spec: Array) -> Dictionary:
	## Parses raw argument strings against the spec.
	## Returns {"args": Array} on success or {"error": String} on failure.
	var parsed: Array = []
	for i: int in range(args_spec.size()):
		var spec: Dictionary = args_spec[i]
		if i < raw_args.size():
			var converted := _convert_arg(raw_args[i], spec.get("type", "string"))
			if converted.has("error"):
				return {"error": "Argument '%s': %s" % [spec["name"], converted["error"]]}
			parsed.append(converted["value"])
		elif spec.get("required", false):
			return {"error": "Missing required argument '%s'" % spec["name"]}
		else:
			parsed.append(spec.get("default", null))
	return {"args": parsed}


func _convert_arg(raw: String, type: String) -> Dictionary:
	## Converts a raw string argument to the specified type.
	if type == "int":
		if not raw.is_valid_int():
			return {"error": "Expected integer, got '%s'" % raw}
		return {"value": int(raw)}
	if type == "float":
		if not raw.is_valid_float():
			return {"error": "Expected number, got '%s'" % raw}
		return {"value": float(raw)}
	if type == "vector2i":
		return _parse_vector2i(raw)
	return {"value": raw}


func _parse_vector2i(raw: String) -> Dictionary:
	## Parses "x,y" format into a Vector2i result dictionary.
	var parts := raw.split(",")
	if parts.size() != 2:
		return {"error": "Expected x,y format, got '%s'" % raw}
	if not parts[0].strip_edges().is_valid_int():
		return {"error": "Expected integer x, got '%s'" % parts[0]}
	if not parts[1].strip_edges().is_valid_int():
		return {"error": "Expected integer y, got '%s'" % parts[1]}
	return {"value": Vector2i(int(parts[0].strip_edges()), int(parts[1].strip_edges()))}


func _usage_string(cmd: Dictionary) -> String:
	var parts: Array[String] = []
	for spec: Dictionary in cmd["args_spec"]:
		if spec.get("required", false):
			parts.append("<%s>" % spec["name"])
		else:
			parts.append("[%s]" % spec["name"])
	return " ".join(parts)
