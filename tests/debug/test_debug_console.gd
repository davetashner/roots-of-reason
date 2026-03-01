extends GdUnitTestSuite
## Tests for DebugConsole — command execution via the console interface.

const GMGuard := preload("res://tests/helpers/game_manager_guard.gd")
const RMGuard := preload("res://tests/helpers/resource_manager_guard.gd")

var _console: Node = null
var _gm_guard: RefCounted
var _rm_guard: RefCounted


func before_test() -> void:
	_gm_guard = GMGuard.new()
	_rm_guard = RMGuard.new()
	_console = auto_free(preload("res://scripts/debug/debug_console.gd").new())
	add_child(_console)


func after_test() -> void:
	_gm_guard.dispose()
	_rm_guard.dispose()


# --- Registry access ---


func test_get_registry_returns_non_null() -> void:
	assert_object(_console.get_registry()).is_not_null()


func test_registry_has_help_command() -> void:
	assert_bool(_console.get_registry().has_command("help")).is_true()


func test_registry_has_spawn_command() -> void:
	assert_bool(_console.get_registry().has_command("spawn")).is_true()


func test_registry_has_build_command() -> void:
	assert_bool(_console.get_registry().has_command("build")).is_true()


func test_registry_has_give_command() -> void:
	assert_bool(_console.get_registry().has_command("give")).is_true()


func test_registry_has_give_all_command() -> void:
	assert_bool(_console.get_registry().has_command("give-all")).is_true()


func test_registry_has_research_command() -> void:
	assert_bool(_console.get_registry().has_command("research")).is_true()


func test_registry_has_research_all_command() -> void:
	assert_bool(_console.get_registry().has_command("research-all")).is_true()


func test_registry_has_advance_age_command() -> void:
	assert_bool(_console.get_registry().has_command("advance-age")).is_true()


func test_registry_has_set_age_command() -> void:
	assert_bool(_console.get_registry().has_command("set-age")).is_true()


# --- execute_command passthrough ---


func test_execute_help_returns_commands_list() -> void:
	var result := _console.execute_command("help")
	assert_str(result).contains("Available commands")
	assert_str(result).contains("spawn")
	assert_str(result).contains("give")


func test_execute_unknown_command_returns_error() -> void:
	var result := _console.execute_command("nonexistent_cmd")
	assert_str(result).contains("Unknown command")


func test_execute_give_through_console() -> void:
	ResourceManager.init_player(99, {})
	var result := _console.execute_command("give food 500 99")
	assert_str(result).contains("Gave")
	assert_int(ResourceManager.get_amount(99, ResourceManager.ResourceType.FOOD)).is_equal(500)


func test_execute_advance_age_through_console() -> void:
	GameManager.current_age = 0
	var result := _console.execute_command("advance-age")
	assert_str(result).contains("Advanced")
	assert_int(GameManager.current_age).is_equal(1)
