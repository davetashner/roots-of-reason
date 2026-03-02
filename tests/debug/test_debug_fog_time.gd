extends GdUnitTestSuite
## Tests for debug fog of war toggle and time control commands.

const VisManagerScript := preload("res://scripts/prototype/visibility_manager.gd")
const DebugConsoleScript := preload("res://scripts/debug/debug_console.gd")


## Minimal mock root that exposes _visibility_manager for DebugAPI fog commands.
static func _make_mock_root(vm: Node) -> Node2D:
	var root: Node2D = Node2D.new()
	var script_text := "extends Node2D\nvar _visibility_manager: Node = null\nvar _fog_layer: Node = null\n"
	var s := GDScript.new()
	s.source_code = script_text
	s.reload()
	root.set_script(s)
	root._visibility_manager = vm
	root.add_child(vm)
	return root


# -- VisibilityManager.reveal_all tests --


func test_reveal_all_marks_all_tiles_visible() -> void:
	var vm: Node = auto_free(Node.new())
	vm.set_script(VisManagerScript)
	var no_block: Callable = func(_pos: Vector2i) -> bool: return false
	vm.setup(4, 4, no_block)
	vm.reveal_all(0)
	for y: int in range(4):
		for x: int in range(4):
			assert_bool(vm.is_visible(0, Vector2i(x, y))).is_true()
			assert_bool(vm.is_explored(0, Vector2i(x, y))).is_true()


func test_reveal_all_marks_all_tiles_explored() -> void:
	var vm: Node = auto_free(Node.new())
	vm.set_script(VisManagerScript)
	var no_block: Callable = func(_pos: Vector2i) -> bool: return false
	vm.setup(3, 3, no_block)
	vm.reveal_all(0)
	assert_int(vm.get_explored_tiles(0).size()).is_equal(9)


func test_reveal_all_emits_visibility_changed() -> void:
	var vm: Node = auto_free(Node.new())
	vm.set_script(VisManagerScript)
	var no_block: Callable = func(_pos: Vector2i) -> bool: return false
	vm.setup(2, 2, no_block)
	var emitted: Array = [false]
	vm.visibility_changed.connect(func(_pid: int) -> void: emitted[0] = true)
	vm.reveal_all(0)
	assert_bool(emitted[0]).is_true()


# -- VisibilityManager.set_fog_enabled tests --


func test_set_fog_enabled_toggles_state() -> void:
	var vm: Node = auto_free(Node.new())
	vm.set_script(VisManagerScript)
	var no_block: Callable = func(_pos: Vector2i) -> bool: return false
	vm.setup(2, 2, no_block)
	assert_bool(vm.is_fog_enabled()).is_true()
	vm.set_fog_enabled(false)
	assert_bool(vm.is_fog_enabled()).is_false()
	vm.set_fog_enabled(true)
	assert_bool(vm.is_fog_enabled()).is_true()


# -- DebugAPI.set_speed tests --


func test_set_speed_changes_time_scale() -> void:
	var prev: float = Engine.time_scale
	var result: String = DebugAPI.set_speed(2.0)
	assert_float(Engine.time_scale).is_equal(2.0)
	assert_str(result).contains("2.0x")
	Engine.time_scale = prev


func test_set_speed_rejects_negative() -> void:
	var prev: float = Engine.time_scale
	var result: String = DebugAPI.set_speed(-1.0)
	assert_str(result).contains("Error")
	assert_float(Engine.time_scale).is_equal(prev)


# -- DebugAPI.pause_game tests --


func test_pause_sets_time_scale_zero() -> void:
	var prev: float = Engine.time_scale
	var result: String = DebugAPI.pause_game()
	assert_float(Engine.time_scale).is_equal(0.0)
	assert_str(result).contains("paused")
	Engine.time_scale = prev


# -- DebugAPI.unpause_game tests --


func test_unpause_restores_time_scale() -> void:
	Engine.time_scale = 0.0
	var result: String = DebugAPI.unpause_game()
	assert_float(Engine.time_scale).is_equal(1.0)
	assert_str(result).contains("resumed")


# -- DebugAPI.reveal_map tests --


func test_reveal_map_without_scene_returns_error() -> void:
	var root: Node = auto_free(Node.new())
	var result: String = DebugAPI.reveal_map(root)
	assert_str(result).contains("Error")


func test_reveal_map_with_mock_scene() -> void:
	var vm: Node = Node.new()
	vm.set_script(VisManagerScript)
	var no_block: Callable = func(_pos: Vector2i) -> bool: return false
	vm.setup(4, 4, no_block)
	var root: Node2D = auto_free(_make_mock_root(vm))
	var result: String = DebugAPI.reveal_map(root)
	assert_str(result).contains("revealed")
	assert_bool(vm.is_fog_enabled()).is_false()
	for y: int in range(4):
		for x: int in range(4):
			assert_bool(vm.is_visible(0, Vector2i(x, y))).is_true()


# -- DebugAPI.set_fog tests --


func test_set_fog_off_disables() -> void:
	var vm: Node = Node.new()
	vm.set_script(VisManagerScript)
	var no_block: Callable = func(_pos: Vector2i) -> bool: return false
	vm.setup(2, 2, no_block)
	var root: Node2D = auto_free(_make_mock_root(vm))
	var result: String = DebugAPI.set_fog(false, root)
	assert_str(result).contains("disabled")
	assert_bool(vm.is_fog_enabled()).is_false()


func test_set_fog_on_enables() -> void:
	var vm: Node = Node.new()
	vm.set_script(VisManagerScript)
	var no_block: Callable = func(_pos: Vector2i) -> bool: return false
	vm.setup(2, 2, no_block)
	var root: Node2D = auto_free(_make_mock_root(vm))
	vm.set_fog_enabled(false)
	var result: String = DebugAPI.set_fog(true, root)
	assert_str(result).contains("enabled")
	assert_bool(vm.is_fog_enabled()).is_true()


# -- Console command registration --


func test_console_registers_reveal_map() -> void:
	var console: Node = auto_free(DebugConsoleScript.new())
	add_child(console)
	assert_bool(console.get_registry().has_command("reveal-map")).is_true()


func test_console_registers_fog() -> void:
	var console: Node = auto_free(DebugConsoleScript.new())
	add_child(console)
	assert_bool(console.get_registry().has_command("fog")).is_true()


func test_console_registers_show_ai() -> void:
	var console: Node = auto_free(DebugConsoleScript.new())
	add_child(console)
	assert_bool(console.get_registry().has_command("show-ai")).is_true()


func test_console_registers_speed() -> void:
	var console: Node = auto_free(DebugConsoleScript.new())
	add_child(console)
	assert_bool(console.get_registry().has_command("speed")).is_true()


func test_console_registers_pause() -> void:
	var console: Node = auto_free(DebugConsoleScript.new())
	add_child(console)
	assert_bool(console.get_registry().has_command("pause")).is_true()


func test_console_registers_unpause() -> void:
	var console: Node = auto_free(DebugConsoleScript.new())
	add_child(console)
	assert_bool(console.get_registry().has_command("unpause")).is_true()


func test_console_registers_step() -> void:
	var console: Node = auto_free(DebugConsoleScript.new())
	add_child(console)
	assert_bool(console.get_registry().has_command("step")).is_true()


func test_console_registers_skip() -> void:
	var console: Node = auto_free(DebugConsoleScript.new())
	add_child(console)
	assert_bool(console.get_registry().has_command("skip")).is_true()
