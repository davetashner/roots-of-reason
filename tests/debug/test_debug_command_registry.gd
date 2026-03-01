extends GdUnitTestSuite
## Tests for DebugCommandRegistry — command registration, parsing, and execution.

var _registry: DebugCommandRegistry


func before_test() -> void:
	_registry = DebugCommandRegistry.new()


func after_test() -> void:
	_registry = null


# --- Registration tests ---


func test_register_command_adds_to_registry() -> void:
	_registry.register_command(
		"test_cmd",
		[],
		func(_args: Array) -> String: return "ok",
		"A test command",
	)
	assert_bool(_registry.has_command("test_cmd")).is_true()


func test_has_command_returns_false_for_unregistered() -> void:
	assert_bool(_registry.has_command("nonexistent")).is_false()


func test_get_commands_returns_all_registered() -> void:
	_registry.register_command("cmd_a", [], func(_a: Array) -> String: return "", "Help A")
	_registry.register_command("cmd_b", [], func(_a: Array) -> String: return "", "Help B")
	var cmds := _registry.get_commands()
	assert_int(cmds.size()).is_equal(2)


# --- Execution tests ---


func test_execute_unknown_command_returns_error() -> void:
	var result := _registry.execute("foobar")
	assert_str(result).contains("Unknown command")


func test_execute_empty_string_returns_empty() -> void:
	var result := _registry.execute("")
	assert_str(result).is_equal("")


func test_execute_calls_handler() -> void:
	var called := [false]
	_registry.register_command(
		"ping",
		[],
		func(_args: Array) -> String:
			called[0] = true
			return "pong",
		"Ping test",
	)
	var result := _registry.execute("ping")
	assert_str(result).is_equal("pong")
	assert_bool(called[0]).is_true()


func test_execute_with_string_arg() -> void:
	_registry.register_command(
		"echo",
		[{"name": "message", "type": "string", "required": true}],
		func(args: Array) -> String: return str(args[0]),
		"Echo message",
	)
	var result := _registry.execute("echo hello")
	assert_str(result).is_equal("hello")


func test_execute_with_int_arg() -> void:
	_registry.register_command(
		"count",
		[{"name": "n", "type": "int", "required": true}],
		func(args: Array) -> String: return "count=%d" % args[0],
		"Count test",
	)
	var result := _registry.execute("count 42")
	assert_str(result).is_equal("count=42")


func test_execute_with_optional_arg_uses_default() -> void:
	_registry.register_command(
		"greet",
		[{"name": "name", "type": "string", "required": false, "default": "world"}],
		func(args: Array) -> String: return "hello %s" % args[0],
		"Greet",
	)
	var result := _registry.execute("greet")
	assert_str(result).is_equal("hello world")


func test_execute_missing_required_arg_returns_error() -> void:
	_registry.register_command(
		"need_arg",
		[{"name": "val", "type": "int", "required": true}],
		func(args: Array) -> String: return str(args[0]),
		"Needs arg",
	)
	var result := _registry.execute("need_arg")
	assert_str(result).contains("Missing required argument")


func test_execute_invalid_int_arg_returns_error() -> void:
	_registry.register_command(
		"intcmd",
		[{"name": "n", "type": "int", "required": true}],
		func(args: Array) -> String: return str(args[0]),
		"Int cmd",
	)
	var result := _registry.execute("intcmd abc")
	assert_str(result).contains("Expected integer")


func test_execute_vector2i_arg() -> void:
	_registry.register_command(
		"pos",
		[{"name": "xy", "type": "vector2i", "required": true}],
		func(args: Array) -> String:
			var v: Vector2i = args[0]
			return "%d,%d" % [v.x, v.y],
		"Position",
	)
	var result := _registry.execute("pos 10,20")
	assert_str(result).is_equal("10,20")


func test_execute_case_insensitive_command_name() -> void:
	_registry.register_command(
		"hello",
		[],
		func(_args: Array) -> String: return "hi",
		"Hello",
	)
	assert_str(_registry.execute("HELLO")).is_equal("hi")
	assert_str(_registry.execute("Hello")).is_equal("hi")


# --- Completion tests ---


func test_get_completions_returns_matching() -> void:
	_registry.register_command("spawn", [], func(_a: Array) -> String: return "", "Spawn")
	_registry.register_command("speed", [], func(_a: Array) -> String: return "", "Speed")
	_registry.register_command("help", [], func(_a: Array) -> String: return "", "Help")
	var completions := _registry.get_completions("sp")
	assert_int(completions.size()).is_equal(2)
	assert_bool("spawn" in completions).is_true()
	assert_bool("speed" in completions).is_true()


func test_get_completions_empty_for_no_match() -> void:
	_registry.register_command("spawn", [], func(_a: Array) -> String: return "", "Spawn")
	var completions := _registry.get_completions("xyz")
	assert_int(completions.size()).is_equal(0)
